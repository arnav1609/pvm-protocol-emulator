"""Observe physical demo pins and compare the ISS at the engine boundary."""

import csv
from pathlib import Path

from cocotb.triggers import FallingEdge

from tb_rtl.pvm_trace_jobs import FIELDS
from tools.pvm_iss import Engine, Fault, Inputs, State


class I2CReplay:
    """Replay S14b's two ACKs and first-ACK stretch with ideal pull-ups."""

    def __init__(self, dut):
        self.dut = dut
        dut.uio_in.value = 3
        self.prev = (1, 1)
        self.started = self.stopped = False
        self.pending_ack = self.acking = self.ack_clock = False
        self.bits = []
        self.acks = 0
        self.stretch = 0

    def sample(self):
        oe = int(self.dut.uio_oe.value) & 3
        out = int(self.dut.uio_out.value)
        assert not oe & out, "open-drain pins drove high"
        prev_sda, prev_scl = self.prev
        if self.pending_ack and oe & 2:
            self.pending_ack = False
            self.acking = True

        stretch_clock = self.acking and self.acks == 0 and self.stretch < 331
        if stretch_clock and not oe & 2:
            assert not oe & 1, "controller drove SDA during stretched ACK"
            self.stretch += 1
        scl = int(not (oe & 2 or stretch_clock))
        if self.ack_clock and not scl:
            self.acking = self.ack_clock = False
        sda = int(not (oe & 1 or self.acking))

        if scl and prev_scl and sda != prev_sda:
            if sda == 0:
                assert not self.started, "unexpected repeated START"
                self.started = True
            else:
                assert self.acks == 2, "STOP before two ACKs"
                self.stopped = True
        if scl and not prev_scl and self.started and not self.stopped:
            if self.acking:
                assert sda == 0 and not oe & 1, "controller must release SDA for ACK"
                self.acks += 1
                self.ack_clock = True
            elif len(self.bits) < 16:
                assert bool(oe & 1) == (sda == 0), "incorrect open-drain data drive"
                self.bits.append(sda)
                self.pending_ack = len(self.bits) % 8 == 0
            else:
                assert sda == 0, "STOP requires SDA low when SCL rises"
        self.prev = sda, scl
        self.dut.uio_in.value = sda | (scl << 1)

    def verify(self):
        assert self.bits == [int(bit) for bit in f"{0xA03C:016b}"], self.bits
        assert self.started and self.stopped and self.acks == 2 and self.stretch == 331
        assert self.prev == (1, 1)
        assert int(self.dut.uio_oe.value) & 3 == 0


def verify_uart(pads):
    tx = [value & 1 for value in pads]
    idle = tx.index(1)
    start = tx.index(0, idle)
    bits = [0, *((0x35 >> b) & 1 for b in range(8)), 1]
    expected = [bit for bit in bits for _ in range(434)]
    assert tx[start:start + len(expected)] == expected, "UART frame or bit duration"
    assert all(tx[start + len(expected):]), "UART pin left idle low"


def verify_spi(pads):
    sck = [(value >> 1) & 1 for value in pads]
    mosi = [(value >> 2) & 1 for value in pads]
    edges = [(cycle, level) for cycle, level in enumerate(sck[1:], start=1)
             if sck[cycle - 1] != level]
    assert sck[0] == 0 and [level for _, level in edges] == [1, 0] * 16
    last_fall = None
    for index in range(16):
        rise = edges[2 * index][0]
        fall = edges[2 * index + 1][0]
        bit = (0xA6C9 >> (15 - index)) & 1
        assert fall - rise == 32 and mosi[rise - 1:fall] == [bit] * 33
        if last_fall is not None:
            assert rise - last_fall == (128 if index == 8 else 32)
        last_fall = fall


def trace_values(top):
    return (
        int(top.state.value), int(top.engine_pc.value), int(top.instr_valid.value),
        int(top.engine_out.value), int(top.engine_oe.value), int(top.fab_ctrl.value),
        int(top.fab_wr.value), int(top.engine_tx_pop.value), int(top.engine_rx_push.value),
        int(top.engine_rx_data.value) if int(top.engine_rx_push.value) else 0,
        int(top.eng_fault_req.value), int(top.eng_fault_code.value),
    )


def write_row(writer, cycle, values):
    run, pc, valid, out, oe, fab, wr, pop, push, byte, req, code = values
    writer.writerow((cycle, int(run), pc, valid, f"{out:05x}", f"{oe:05x}", f"{fab:x}",
                     wr, pop, push, f"{byte:02x}", req, f"{code:x}"))


async def replay_demo(dut, name, image):
    top = dut.user_project.pvm
    engine = Engine.from_image(image)
    i2c = I2CReplay(dut) if name == "i2c_write" else None
    pads = []
    while True:
        await FallingEdge(dut.clk)
        if int(top.enable_pulse.value):
            break
    # The next rising edge initializes the engine and restarts CLKDIV.
    await FallingEdge(dut.clk)

    output = Path("output") / name
    output.mkdir(parents=True, exist_ok=True)
    last_fab_write = False
    with (output / "iss.csv").open("w", newline="") as model_stream, \
         (output / "rtl.csv").open("w", newline="") as rtl_stream:
        iss, rtl = [csv.writer(stream, lineterminator="\n") for stream in (model_stream, rtl_stream)]
        for writer in (iss, rtl):
            writer.writerow(FIELDS)
        for cycle in range(10_000):
            if i2c is not None:
                i2c.sample()
            pads.append(int(dut.uo_out.value))
            inputs = Inputs(pins=int(top.pin_in.value))
            before = (engine.state, engine.pc, int(engine.pc in engine.words),
                      engine.out_val, engine.oe_val, engine.fab_ctrl, int(last_fab_write))
            effects = engine.step(inputs)
            last_fab_write = effects.fab_write
            expected = (*before, int(effects.tx_pop), int(effects.rx_byte is not None),
                        effects.rx_byte or 0, 0, Fault.NONE)
            actual = trace_values(top)
            write_row(iss, cycle, expected)
            write_row(rtl, cycle, actual)
            differences = [(field, exp, got) for field, exp, got in zip(FIELDS[1:], expected, actual)
                           if exp != got]
            assert not differences, f"{name}, cycle {cycle}, pins 0x{inputs.pins:05x}: {differences}"
            await FallingEdge(dut.clk)
            if engine.state != State.RUN:
                assert engine.state == State.DONE and int(top.eng_done_req.value)
                break
        else:
            raise AssertionError(f"{name}: demo did not finish in 10000 core cycles")

    if i2c is not None:
        i2c.sample()
        i2c.verify()
    else:
        pads.append(int(dut.uo_out.value))
        (verify_uart if name == "uart_tx" else verify_spi)(pads)
    return engine.cycle
