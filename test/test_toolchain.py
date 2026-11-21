"""Replay assembled images through the production host loader and RTL SPI pins."""

from pathlib import Path
from tempfile import TemporaryDirectory

import cocotb
from cocotb.clock import Clock
from cocotb.task import bridge, resume

from test import SpiHost
from tools.pvm_host import PVMHost, read_image
from tools.pvm_image import main as build_image_file


class SimTransport(SpiHost):
    @resume
    async def exchange(self, frame):
        return await self.transfer(frame)


@cocotb.test()
async def load_generated_images_over_spi(dut):
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

    examples = Path(__file__).resolve().parents[1] / "tools" / "examples"
    with TemporaryDirectory() as work:
        for version, (name, preload) in enumerate((
            ("uart_tx", (0x35,)),
            ("spi_mode0", (0xA6, 0xC9)),
            ("i2c_write", (0xA0, 0x3C)),
        ), start=1):
            output = Path(work) / f"{name}.json"
            args = [str(examples / f"{name}.pvm"), str(output),
                    "--config", str(examples / f"{name}.json"), "--image-version", str(version)]
            for byte in preload:
                args.extend(("--tx", str(byte)))
            build_image_file(args)
            image = read_image(output)

            status = await bridge(host.load_image)(image)
            assert status == {"state": 2, "status": 0x42, "fault_code": 0,
                              "fault_pc": 0, "fault_time": 0}, name
            assert await bridge(host.read)(0x0F20, 3) == (
                image["crc16"].to_bytes(2, "little") + bytes((version,))
            ), name
            assert await bridge(host.read)(0x0F12) == bytes((len(preload),)), name
            expected = dict(image["writes"])
            for begin, end in ((0x0000, 0x0040), (0x0100, 0x0113), (0x0400, 0x0414)):
                actual = await bridge(host.read)(begin, end - begin)
                assert actual == bytes(expected.get(addr, 0) for addr in range(begin, end)), name
