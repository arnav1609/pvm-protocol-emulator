"""Image-author checks. Independent target-model acceptance is a separate gate."""
import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.task import bridge
from cocotb.triggers import FallingEdge, Timer

from demo_replay import I2CReplay
from test_toolchain import SimTransport
from tools.pvm_asm import assemble
from tools.pvm_host import PVMHost
from tools.pvm_image import build_image, _config_from_json

MATRIX = Path(__file__).resolve().parents[3] / "tools" / "examples" / "matrix"
PRELOAD = {
    "i2c_400k": (0xa0, 0x3c),
    "i2c_100k": (0xa0, 0x3c),
    "ws2812b_tx": (0x96, 0x3c, 0xa5),
    "ps2_rx": (),
}
MUTATIONS = {
    "spi_mode1": ("out pins, 1 side 1", "out pins, 1 side 1 [1]", "SPI_ACTIVE_WIDTH"),
    "spi_mode2": ("jmp x--, next_bit side 1", "jmp x--, next_bit side 1 [1]", "SPI_ACTIVE_WIDTH"),
    "spi_mode3": ("out pins, 1 side 1", "out pins, 1 side 1 [1]", "SPI_ACTIVE_WIDTH"),
    "i2c_400k": ("out pins, 1 side 0 [2]", "out pins, 1 side 0 [1]", "I2C_DATA_PERIOD"),
    "i2c_100k": ("out pins, 1 side 0 [2]", "out pins, 1 side 0 [1]", "I2C_DATA_PERIOD"),
    "ws2812b_tx": ("set y, 7 side 0", "set y, 0 side 0", "WS_LATCH_MIN"),
    "ps2_rx": ("jmp !y, bad", "mov y, y", "PS2_BAD_PARITY"),
}


def image_for(name, mutate):
    program = "i2c_400k" if name == "i2c_100k" else name
    source = (MATRIX / f"{program}.pvm").read_text()
    if mutate:
        old, new, _ = MUTATIONS[name]
        assert source.count(old) == 1
        source = source.replace(old, new)
    config = _config_from_json(MATRIX / f"{name}.json")
    words = assemble(source, side_count=config.get(0x0108, 0))
    return build_image(words, config=config, tx_preload=PRELOAD.get(name, (0xa6, 0xc9)))


async def capture(dut, name):
    top = dut.user_project.pvm
    while not int(top.enable_pulse.value):
        await FallingEdge(dut.clk)
    await FallingEdge(dut.clk)
    rows = []
    i2c = I2CReplay(dut) if name.startswith("i2c_") else None
    for _ in range(30_000):
        if i2c is not None:
            i2c.sample()
        pad = int(dut.uo_out.value) if i2c is None else i2c.prev[1]
        rows.append(pad)
        if int(top.eng_done_req.value):
            if i2c is not None:
                i2c.verify()
            return rows
        await FallingEdge(dut.clk)
    raise AssertionError(f"{name} capture timed out")


def check_spi(rows, mode):
    cpol = mode >> 1
    sck = [(pad >> 1) & 1 for pad in rows]
    edges = [at for at in range(1, len(rows)) if sck[at - 1] != sck[at]]
    assert sck[0] == sck[-1] == cpol and len(edges) == 32, "SPI_EDGE_COUNT"
    for index, (leading, trailing) in enumerate(zip(edges[::2], edges[1::2])):
        assert trailing - leading == 32, "SPI_ACTIVE_WIDTH"
        sample = trailing if mode & 1 else leading
        wanted = (0xa6c9 >> (15 - index)) & 1
        assert all((rows[at] >> 2) & 1 == wanted for at in (sample - 1, sample)), "SPI_DATA"
    return f"mode={mode} samples=16 active_half_cycles=32 MOSI=a6c9"


def check_i2c(rows, period):
    rises = [at for at in range(1, len(rows)) if rows[at - 1] == 0 and rows[at] == 1]
    assert len(rises) == 19, f"I2C_RISE_COUNT {rises}"
    observed = [rises[at + 1] - rises[at] for at in (*range(7), *range(9, 16))]
    assert observed == [period] * 14, f"I2C_DATA_PERIOD {observed}"
    return f"SDA=a03c ACKs=2 stretch_core_cycles=331 data_period_core_cycles={period}"


def check_ws(rows):
    line = [pad & 1 for pad in rows]
    edges = [at for at in range(1, len(line)) if line[at - 1] != line[at]]
    assert line[0] == line[-1] == 0 and len(edges) == 48, "WS_EDGE_COUNT"
    for idx, (rise, fall) in enumerate(zip(edges[::2], edges[1::2])):
        bit = (0x963ca5 >> (23 - idx)) & 1
        assert fall - rise == (36 if bit else 16), "WS_HIGH_WIDTH"
        if idx:
            assert rise - edges[2 * idx - 2] == 64, "WS_BIT_CELL"
    assert len(line) - 1 - edges[-1] >= 15_000, "WS_LATCH_MIN"
    return f"GRB=963ca5 bits=24 final_low_core_cycles={len(line) - 1 - edges[-1]}"


async def ps2_frame(dut, data, parity):
    # An ideal digital device controls P0 and P1 through the wrapper inputs.
    await Timer(40, unit="us")
    for bit in (0, *((data >> b) & 1 for b in range(8)), parity, 1):
        dut.ui_in.value = (int(dut.ui_in.value) & 7) | (bit << 4) | 8
        await Timer(35, unit="us")
        dut.ui_in.value = (int(dut.ui_in.value) & 7) | (bit << 4)
        await Timer(35, unit="us")
    dut.ui_in.value = (int(dut.ui_in.value) & 7) | 24


async def check_ps2_frame(host, dut, image, parity, valid):
    dut.ui_in.value = (int(dut.ui_in.value) & 7) | 24
    await bridge(host.load_image)(image, enable=True)
    await ps2_frame(dut, 0x96, parity)
    await bridge(host.wait_done)(polls=32)
    flags = (await bridge(host.read)(0x0f0b))[0]
    level = ((await bridge(host.read)(0x0f12))[0] >> 4) & 7
    if valid:
        assert flags == 4 and level == 1 and await bridge(host.pop_rx)() == b"\x96", "PS2_VALID"
    else:
        assert flags == 8 and level == 0, "PS2_BAD_PARITY"


@cocotb.test()
async def author_replay(dut):
    dut.ena.value = 1
    dut.ui_in.value = 2
    dut.uio_in.value = 3
    dut.rst_n.value = 0
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    transport = SimTransport(dut)
    host = PVMHost(transport)
    await transport.wait_cycles(4)
    dut.rst_n.value = 1
    await transport.wait_cycles(4)
    selected = os.environ.get("PVM_MATRIX_CASE")
    cases = (selected,) if selected else MUTATIONS
    for name in cases:
        expected = MUTATIONS[name][2]
        for mutate in (False, True):
            image = image_for(name, mutate)
            try:
                if name == "ps2_rx":
                    await check_ps2_frame(host, dut, image, 1, True)
                    await check_ps2_frame(host, dut, image, 0, False)
                    summary = "valid byte=96, invalid parity selected FLAG3 and left RX empty"
                else:
                    await bridge(host.load_image)(image)
                    recording = cocotb.start_soon(capture(dut, name))
                    await bridge(host.enable)()
                    rows = await recording
                    await bridge(host.wait_done)(polls=32)
                    if name.startswith("spi"):
                        summary = check_spi(rows, int(name[-1]))
                    elif name.startswith("i2c_"):
                        summary = check_i2c(rows, 125 if name == "i2c_400k" else 500)
                    else:
                        summary = check_ws(rows)
            except AssertionError as exc:
                if not mutate or not str(exc).startswith(expected):
                    raise
                dut._log.info("NEG_KILLED %s %s", name, exc)
            else:
                assert not mutate, f"{name}: mutation survived {expected}"
                dut._log.info("PASS %s %s", name, summary)
