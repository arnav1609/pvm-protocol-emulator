"""Pre-freeze program-fit checks at PVM's configured protocol pads."""

from collections import deque
import json
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.task import bridge
from cocotb.triggers import FallingEdge, ValueChange, with_timeout
from cocotb.utils import get_sim_time

from test_toolchain import SimTransport
from tools.pvm_asm import assemble
from tools.pvm_host import PVMHost
from tools.pvm_image import build_image

FIT = Path(__file__).resolve().parents[1] / "tools" / "examples" / "fit"
CORE_NS = 20


class FitFailure(AssertionError):
    def __init__(self, check, detail):
        self.check = check
        super().__init__(f"{check}: {detail}")


def require(ok, check, detail):
    if not ok:
        raise FitFailure(check, detail)


class Pads:
    """Resolve P12 with a pull-up or a target driver; observe SWCLK on P5."""

    def __init__(self, dut, open_drain):
        self.dut = dut
        self.open_drain = open_drain
        self.events = deque()
        self.target = None
        self.target_since = 0
        self.now = 0
        self.driven = False
        self.data = 1
        self.swclk = 0

    async def step(self):
        await FallingEdge(self.dut.clk)
        self.now = int(get_sim_time(unit="ns"))
        while self.events and self.events[0][0] <= self.now:
            _, self.target = self.events.popleft()
            self.target_since = self.now
        self.driven = bool(int(self.dut.uio_oe.value) & 1)
        out = int(self.dut.uio_out.value) & 1
        self.swclk = int(self.dut.uo_out.value) & 1
        if self.open_drain:
            require(not self.driven or out == 0, "OPEN_DRAIN", "PVM drove high")
            self.data = int(not (self.driven or self.target == 0))
        else:
            require(not self.driven or self.target is None, "SWD_CONTENTION",
                    "PVM and the target both drove SWDIO")
            self.data = out if self.driven else (1 if self.target is None else self.target)
        self.dut.uio_in.value = self.data
        return self.now

    async def drive_edge(self, enabled, limit_ns):
        start = self.now
        while self.now - start <= limit_ns:
            await self.step()
            if self.driven == enabled:
                return self.now
        raise FitFailure("PVM_DRIVE_EDGE", f"missing drive state {enabled} after {limit_ns} ns")


async def setup(dut, protocol, preload, mutation=None):
    transport = SimTransport(dut)
    host = PVMHost(transport)
    cfg = {int(addr, 0): int(byte, 0) if isinstance(byte, str) else byte
           for addr, byte in json.loads((FIT / f"{protocol}.json").read_text()).items()}
    source = (FIT / f"{protocol}.pvm").read_text()
    if mutation:
        old, new = mutation
        assert source.count(old) == 1
        source = source.replace(old, new)
    words = assemble(source, side_count=cfg[0x0108])
    image = build_image(words, config=cfg, tx_preload=preload)
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 2
    dut.uio_in.value = 1
    await transport.wait_cycles(4)
    dut.rst_n.value = 1
    await transport.wait_cycles(4)
    await bridge(host.load_image)(image)
    return host, len(words)


async def one_wire_target(pads, presence, result_bit):
    await pads.step()
    reset_start = await pads.drive_edge(True, 40_000)
    reset_end = await pads.drive_edge(False, 960_000)
    reset_low = reset_end - reset_start
    require(480_000 <= reset_low <= 960_000, "RESET_LOW", reset_low)
    if presence is None:
        while pads.now - reset_end <= 150_000:
            await pads.step()
            require(not pads.driven, "ABSENT_TARGET", "unexpected slot")
        return {"reset_low_ns": reset_low}

    onset, width = presence
    pads.events.extend(((reset_end + onset, 0), (reset_end + onset + width, None)))
    previous_end = reset_end
    previous_start = None
    lows = {0: [], 1: []}
    recoveries = []
    reset_high = 0
    for command in (0xCC, 0xB4):
        for bit_number in range(8):
            bit = (command >> bit_number) & 1
            start = await pads.drive_edge(True, 700_000)
            if not reset_high:
                reset_high = start - reset_end
                require(reset_high >= 480_000, "RESET_HIGH", reset_high)
            else:
                recoveries.append(start - previous_end)
            if previous_start is not None:
                require(60_000 <= start - previous_start <= 120_000, "WRITE_SLOT", start - previous_start)
            end = await pads.drive_edge(False, 140_000)
            low = end - start
            if bit:
                require(1_000 <= low <= 15_000, "WRITE_ONE_LOW", low)
            else:
                require(60_000 <= low <= 120_000, "WRITE_ZERO_LOW", low)
            lows[bit].append(low)
            previous_start, previous_end = start, end

    read_start = await pads.drive_edge(True, 120_000)
    recoveries.append(read_start - previous_end)
    require(min(recoveries) >= 1_000, "RECOVERY", min(recoveries))
    require(60_000 <= read_start - previous_start <= 120_000, "WRITE_SLOT", read_start - previous_start)
    if result_bit == 0:
        pads.events.extend(((read_start + 8_000, 0), (read_start + 55_000, None)))
    read_end = await pads.drive_edge(False, 15_000)
    require(1_000 <= read_end - read_start < 15_000, "READ_INIT", read_end - read_start)
    while pads.now - read_start <= 90_000:
        await pads.step()
        require(not pads.driven, "READ_SLOT", "master drove again during the read slot")
    return {"reset_low_ns": reset_low, "reset_high_ns": reset_high,
            "write_zero_ns": min(lows[0]), "write_one_ns": max(lows[1]),
            "recovery_ns": min(recoveries), "read_init_ns": read_end - read_start}


async def one_wire(dut, presence, result_bit, mutation=None):
    host, words = await setup(dut, "one_wire", (0xCC, 0xB4), mutation)
    target = cocotb.start_soon(one_wire_target(Pads(dut, open_drain=True), presence, result_bit))
    diagnostic = None
    if presence is not None and mutation is None:
        diagnostic = cocotb.start_soon(with_timeout(observe_read_slot(dut), 4, "ms"))
    await bridge(host.command)(3)
    timing = await target
    if diagnostic is not None:
        timing.update(await diagnostic)
    await bridge(host.wait_done)()
    level = (await bridge(host.read)(0x0F12))[0] >> 4
    require(level == (0 if presence is None else 1), "ONE_WIRE_RX_LEVEL", level)
    if presence is not None:
        result = await bridge(host.pop_rx)(1)
        require(result == bytes((result_bit,)), "ONE_WIRE_READ_BIT", result.hex())
    return words, timing


async def observe_read_slot(dut):
    """Timestamp the RTL sample and slot exit while the pin model runs."""
    async def observe(signal, value, mask):
        while (int(signal.value) & mask) != value:
            await ValueChange(signal)
        return int(get_sim_time(unit="ns"))

    # Skip reset and the sixteen write slots. The next open-drain OE
    # assertion is the read slot's falling edge.
    for _ in range(17):
        await observe(dut.uio_oe, 1, 1)
        await observe(dut.uio_oe, 0, 1)
    read_edge = await observe(dut.uio_oe, 1, 1)
    pvm = dut.user_project.pvm
    sampled = await observe(pvm.engine.isr_cnt_q, 1, 0x1F)
    pushed = await observe(pvm.rx_level, 1, 7)
    done = await observe(pvm.state, 4, 7)
    sample_ns = sampled - read_edge
    slot_ns = pushed - read_edge
    require(0 < sample_ns <= 15_000 and 60_000 <= slot_ns <= 120_000,
            "READ_SLOT", (sample_ns, slot_ns))
    return {"read_sample_ns": sample_ns, "read_slot_to_push_ns": slot_ns,
            "read_fall_to_done_ns": done - read_edge}


def lsb_first(value, width):
    return [(value >> n) & 1 for n in range(width)]


async def swd_target(pads, request, ack, data, parity):
    # Entries describe the independent target's expected wire transaction.
    packet = [("request", bit) for bit in lsb_first(request, 8)]
    packet += [("turn", None), *(("target", bit) for bit in lsb_first(ack, 3))]
    if ack == 1:
        packet += [("target", bit) for bit in (*lsb_first(data, 32), parity)]
    packet += [("turn", None)] + [("idle", 0)] * 8
    index = 0
    high_ns, low_ns, setup_ns = [], [], []
    last_low = last_rise = None
    previous = pads.swclk
    await pads.step()
    end = pads.now + 300_000
    while pads.now < end:
        now = await pads.step()
        if pads.swclk and not previous:
            require(index < len(packet), "SWD_EXTRA_CLOCK", index)
            kind, bit = packet[index]
            if kind in ("request", "idle"):
                require(pads.driven and pads.data == bit, "SWD_HOST_BIT", (index, kind, pads.data))
            elif kind == "turn":
                require(not pads.driven and pads.target is None, "SWD_TURNAROUND", index)
            else:
                require(not pads.driven and pads.target == bit, "SWD_TARGET_BIT", index)
                # `step` observes registered SWCLK half a core cycle
                # after the pad edge. Target updates occur at `target_since`.
                setup_ns.append(now - CORE_NS // 2 - pads.target_since)
            if last_low is not None:
                low_ns.append(now - last_low)
            last_rise = now
            index += 1
            if index < len(packet):
                # ADIv5 B4.3.1: launch or release after the rising edge
                # that just sampled the previous bit.
                kind, bit = packet[index]
                pads.events.append((now + 100, bit if kind == "target" else None))
        elif not pads.swclk and previous:
            high_ns.append(now - last_rise)
            if index == len(packet):
                break
            last_low = now
        previous = pads.swclk
    require(index == len(packet), "SWD_CLOCK_COUNT", (index, len(packet)))
    require(min(high_ns) >= 400 and min(low_ns) >= 400, "SWD_CLOCK_PHASE",
            (min(high_ns), min(low_ns)))
    require(min(setup_ns) >= 260, "SWD_SETUP", min(setup_ns))
    # One extra idle observation interval catches clocks beyond the expected tail.
    for _ in range(100):
        await pads.step()
        require(pads.swclk == 0, "SWD_EXTRA_CLOCK", index)
    return {"swclk_rises": index, "min_high_ns": min(high_ns), "min_low_ns": min(low_ns),
            "target_setup_ns": min(setup_ns)}


def reverse_byte(value):
    return sum(((value >> bit) & 1) << (7 - bit) for bit in range(8))


async def swd(dut, request, ack, data, parity, mutation=None, check_reload=False):
    host, words = await setup(dut, "swd", (request,), mutation)
    target = cocotb.start_soon(swd_target(Pads(dut, open_drain=False), request, ack, data, parity))
    await bridge(host.command)(3)
    timing = await target
    await bridge(host.wait_done)()
    level = (await bridge(host.read)(0x0F12))[0] >> 4
    require(level == (4 if ack == 1 else 0), "SWD_RX_LEVEL", (ack, level))
    if ack == 1:
        fifo = await bridge(host.pop_rx)(4)
        observed = int.from_bytes(bytes(map(reverse_byte, fifo)), "little")
        require(observed == data, "SWD_READ_DATA", hex(observed))
    flags = (await bridge(host.read)(0x0F0B))[0]
    accepted = ack == 1 and parity == (data.bit_count() & 1)
    require(bool(flags & 4) == accepted, "SWD_PARITY_FLAG", (ack, parity, flags))
    if check_reload:
        await observe_swd_reload(dut, host)
    return words, timing


async def observe_swd_reload(dut, host):
    async def monitor_clock():
        while True:
            require(int(dut.uo_out.value) & 1 == 0, "SWD_RELOAD_IDLE", "SWCLK rose")
            await ValueChange(dut.uo_out)

    require(await bridge(host.read)(0x0405) == b"\x0a", "SWD_RELOAD_CONFIG", "P5 settings")
    spare_words = assemble("evt done side 0", side_count=1)
    image = build_image(spare_words, config={0x0107: 5, 0x0108: 1, 0x0405: 0x0A})
    clock_monitor = cocotb.start_soon(monitor_clock())
    try:
        await bridge(host.load_image)(image)
    finally:
        clock_monitor.cancel()
    dut._log.info("OBSERVE SWD_RELOAD_IDLE P5=0 from DONE through HALT, reload, and READY")


@cocotb.test()
async def fit_one_wire(dut):
    cocotb.start_soon(Clock(dut.clk, CORE_NS, unit="ns").start())
    scenarios = [((15_000, 60_000), 0), ((60_000, 240_000), 1), (None, None)]
    for presence, bit in scenarios:
        words, timing = await one_wire(dut, presence, bit)
        dut._log.info("FIT one_wire words=%d presence=%s bit=%s %s", words, presence, bit, timing)
    dut._log.info("CHECK PASS ONE_WIRE_PIN_TRANSACTION")


@cocotb.test()
async def fit_one_wire_neg_short_zero(dut):
    cocotb.start_soon(Clock(dut.clk, CORE_NS, unit="ns").start())
    mutation = ("jmp write_end side 0 [14]", "jmp write_end side 0 [5]")
    try:
        await one_wire(dut, (15_000, 60_000), 0, mutation)
    except FitFailure as fail:
        assert fail.check == "WRITE_ZERO_LOW", str(fail)
        dut._log.info("MUTANT KILLED ONE_WIRE_PIN_TRANSACTION %s", fail)
    else:
        raise AssertionError("short write-zero mutant survived")


@cocotb.test()
async def fit_swd(dut):
    cocotb.start_soon(Clock(dut.clk, CORE_NS, unit="ns").start())
    even = 0x2BA01477
    odd = even ^ (1 << 28)
    # DPIDR reads exercise data. AP reads can elicit WAIT or FAULT.
    scenarios = ((0xA5, 1, even, 0), (0xA5, 1, odd, 1),
                 (0xA5, 1, even, 1), (0xA5, 1, odd, 0),
                 (0x87, 2, 0, 0), (0x87, 4, 0, 0))
    for index, (request, ack, reply, parity) in enumerate(scenarios):
        words, timing = await swd(dut, request, ack, reply, parity, check_reload=index == 0)
        dut._log.info("FIT swd words=%d request=%02x ack=%d reply=%08x parity=%d %s",
                      words, request, ack, reply, parity, timing)
    dut._log.info("CHECK PASS SWD_DPIDR_PIN_TRANSACTION")


@cocotb.test()
async def fit_swd_neg_accept_bad_parity(dut):
    cocotb.start_soon(Clock(dut.clk, CORE_NS, unit="ns").start())
    mutation = ("jmp !y, turn_low side 1", "jmp good side 1")
    try:
        await swd(dut, 0xA5, 1, 0x2BA01477, 1, mutation)
    except FitFailure as fail:
        assert fail.check == "SWD_PARITY_FLAG", str(fail)
        dut._log.info("MUTANT KILLED SWD_DPIDR_PIN_TRANSACTION %s", fail)
    else:
        raise AssertionError("bad parity acceptance mutant survived")
