# SPDX-License-Identifier: Apache-2.0

from binascii import crc_hqx

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, Timer


class SpiHost:
    """Mode-0 host on ui[2:0], with eight core clocks per SPI half-period."""

    def __init__(self, dut):
        self.dut = dut

    async def wait_cycles(self, count):
        for _ in range(count):
            await FallingEdge(self.dut.clk)

    async def transfer(self, outgoing):
        await self.wait_cycles(1)
        self.dut.ui_in.value = 0
        await self.wait_cycles(8)

        incoming = bytearray()
        for byte in outgoing:
            received = 0
            for bit in range(7, -1, -1):
                mosi = ((byte >> bit) & 1) << 2
                self.dut.ui_in.value = mosi
                await self.wait_cycles(8)
                self.dut.ui_in.value = mosi | 1
                await Timer(1, unit="ns")
                received = (received << 1) | ((int(self.dut.uo_out.value) >> 7) & 1)
                await self.wait_cycles(8)
                self.dut.ui_in.value = mosi
            incoming.append(received)

        await self.wait_cycles(8)
        self.dut.ui_in.value = 2
        await self.wait_cycles(8)
        return bytes(incoming)

    async def write(self, address, data):
        response = await self.transfer(bytes([0x02]) + address.to_bytes(2, "big") + data)
        assert response == bytes(len(response))

    async def read(self, address, count):
        response = await self.transfer(bytes([0x03]) + address.to_bytes(2, "big") + bytes(1 + count))
        assert response[:4] == bytes(4)
        return response[4:]


@cocotb.test()
async def test_host_and_pin_safety(dut):
    dut.ena.value = 1
    dut.ui_in.value = 2
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())

    host = SpiHost(dut)
    await host.wait_cycles(4)
    assert int(dut.uio_oe.value) == 0
    dut.rst_n.value = 1

    assert await host.transfer(b"\x9f" + bytes(5)) == b"\x00PVM!\x00"
    assert await host.read(0x0F01, 1) == b"\x00"

    # A valid entry word plus P5 push-pull with idle high and P12 bidir push-pull.
    program = b"\x00\x00"
    config_p5 = b"\x29"
    config_p12 = b"\x09"
    await host.write(0x0000, program)
    await host.write(0x0405, config_p5)
    await host.write(0x040C, config_p12)
    assert await host.read(0x0000, 2) == program
    assert await host.read(0x0405, 1) == config_p5
    assert int(dut.uo_out.value) & 0x7F == 1
    assert int(dut.uio_oe.value) == 0

    expected_crc = crc_hqx(program + config_p5 + config_p12, 0xFFFF).to_bytes(2, "little")
    await host.write(0x0F08, expected_crc)
    await host.write(0x0F00, b"\x02")
    assert await host.read(0x0F01, 1) == b"\x42"
    assert await host.read(0x0F20, 3) == expected_crc + b"\x00"
    assert int(dut.uo_out.value) & 0x7F == 1
    assert int(dut.uio_oe.value) == 0

    await host.write(0x0F00, b"\x03")
    # JMP 0 keeps the program in RUN after engine integration.
    assert (await host.read(0x0F01, 1))[0] & 7 == 3
    assert int(dut.uo_out.value) & 0x7F == 0
    await host.write(0x0F00, b"\x01")
    assert (await host.read(0x0F01, 1))[0] & 0x3F == 0
    assert int(dut.uo_out.value) & 0x7F == 1
    assert int(dut.uio_oe.value) == 0
