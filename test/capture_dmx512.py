"""Capture P5 transitions for the owner to decode independently."""

import csv
import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.task import bridge
from cocotb.triggers import FallingEdge, Timer
from cocotb.utils import get_sim_time

from test_toolchain import SimTransport
from tools.pvm_host import DONE, PVMHost, read_image


async def capture_edges(dut, edges):
    prior = None
    origin = None
    while True:
        await FallingEdge(dut.clk)
        cycle = int(get_sim_time(unit="ns")) // 20
        if origin is None:
            origin = cycle
        level = int(dut.uo_out.value) & 1
        if level != prior:
            prior = level
            edges.append((cycle - origin, level))


@cocotb.test()
async def capture_and_reload(dut):
    examples = Path(__file__).resolve().parents[1] / "tools" / "examples"
    image_path = Path(os.environ.get("PVM_DMX_IMAGE", examples / "dmx512_tx.image.json"))
    output = Path(os.environ.get("PVM_DMX_CAPTURE", "output/dmx512_tx"))
    output.mkdir(parents=True, exist_ok=True)
    image = read_image(image_path)
    dut.ena.value = 1
    dut.ui_in.value = 2
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    transport = SimTransport(dut)
    host = PVMHost(transport)

    await transport.wait_cycles(4)
    dut.rst_n.value = 1
    await transport.wait_cycles(4)
    for run in (1, 2):
        ready = await bridge(host.load_image)(image)
        assert ready["status"] == 0x42
        assert int(dut.uo_out.value) & 1 == 1
        edges = []
        capture = cocotb.start_soon(capture_edges(dut, edges))
        await bridge(host.command)(0x03)
        enable_frame_end_ns = int(get_sim_time(unit="ns"))
        # Leave SPI idle during transmission. STATUS is read afterwards.
        await Timer(2900, unit="us")
        capture.cancel()
        status = await bridge(host.status)()
        status_end_ns = int(get_sim_time(unit="ns"))
        assert status["state"] == DONE and status["fault_code"] == 1
        assert (status["status"] & 0x38) == 0, status
        assert int(dut.uo_out.value) & 1 == 1
        with (output / f"run_{run}_p5.csv").open("w", newline="") as stream:
            writer = csv.writer(stream, lineterminator="\n")
            writer.writerow(("core_cycle", "p5"))
            writer.writerows(edges)
        dut._log.info(
            "DMX run %d, %d P5 samples, DONE status %dns after ENABLE frame end",
            run, len(edges), status_end_ns - enable_frame_end_ns,
        )
