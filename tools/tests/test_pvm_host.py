import binascii
import unittest

from tools.pvm_host import DONE, READY, DemoBoardSPI, PVMError, PVMHost
from tools.pvm_wire import CONFIG_ADDRESSES, IMAGE_FORMAT, IMAGE_VER, crc16_ccitt_false


def image():
    writes = [[0, 0xC0], [1, 0xC0]]
    writes += [[address, 8 if address == 0x0405 else 0] for address in CONFIG_ADDRESSES]
    writes.append([IMAGE_VER, 7])
    return {
        "format": IMAGE_FORMAT,
        "writes": writes,
        "image_version": 7,
        "crc16": binascii.crc_hqx(bytes(byte for _, byte in writes), 0xFFFF),
        "tx_preload": [0x35, 0xA6],
    }


class SpiDevice:
    """Independent register model for host transaction tests."""

    def __init__(self):
        self.frames = []
        self.regs = {address: 0xFF for address in CONFIG_ADDRESSES}
        self.regs[7] = 0xFF  # Previous instruction image.
        self.crc = 0xFFFF
        self.tx = []
        self.rx = []
        self.state = DONE
        self.reject_validation = False
        self.id = b"PVM!"

    def exchange(self, frame):
        self.frames.append(frame)
        if frame[0] == 0x9F:
            return b"\x00" + self.id
        command, high, low = frame[:3]
        address = high << 8 | low
        if command == 2:
            for offset, value in enumerate(frame[3:]):
                self._write((address + offset) & 0xFFFF, value)
            return bytes(len(frame))
        if command != 3 or frame[3]:
            raise AssertionError("bad SPI command or dummy byte")
        return bytes(4) + bytes(self._read((address + offset) & 0xFFFF)
                                for offset in range(len(frame) - 4))

    def _write(self, address, value):
        if address == 0x0F00:
            if value == 1:
                self.state, self.crc = 0, 0xFFFF
                self.tx.clear()
                self.rx.clear()
            elif value == 4:
                self.regs = {addr: byte for addr, byte in self.regs.items() if addr >= 64}
            elif value == 2:
                expected = self.regs[0x0F08] | self.regs[0x0F09] << 8
                self.state = READY if self.crc == expected and not self.reject_validation else 5
                if self.state == READY:
                    self.regs[0x0F20] = expected & 0xFF
                    self.regs[0x0F21] = expected >> 8
                    self.regs[0x0F22] = self.regs[IMAGE_VER]
            elif value == 3:
                self.state = DONE
            else:
                raise AssertionError("unexpected control command")
        elif address == 0x0F10:
            self.tx.append(value)
        else:
            self.regs[address] = value
            if address not in (0x0F08, 0x0F09):
                self.crc = binascii.crc_hqx(bytes((value,)), self.crc)

    def _read(self, address):
        if address == 0x0F01:
            return self.state | (0x40 if self.state == READY else 0)
        if address == 0x0F06:
            return self.crc & 0xFF
        if address == 0x0F07:
            return self.crc >> 8
        if address == 0x0F12:
            return len(self.tx) | len(self.rx) << 4
        if address == 0x0F11:
            return self.rx.pop(0)
        return self.regs.get(address, 0)


class BoardInputs(list):
    def __init__(self):
        super().__init__([0, 1, 0, 0, 0, 0, 1, 0])
        self.tx_bits = []
        self.edges = []
        self.time_us = 0

    def __setitem__(self, index, value):
        if index == 0 and value != self[0]:
            self.edges.append(self.time_us)
        if index == 0 and value == 1:
            if self[1] != 0:
                raise AssertionError("clock rose while CS was inactive")
            self.tx_bits.append(self[2])
        super().__setitem__(index, value)


class BoardOutputs:
    def __init__(self, bits):
        self._bits = iter(bits)

    def __getitem__(self, pin):
        if pin != 7:
            raise AssertionError("wrong MISO pin")
        return next(self._bits)


class FakeBoard:
    def __init__(self, bits):
        self.ui_in = BoardInputs()
        self.uo_out = BoardOutputs(bits)

    def wait(self, us):
        self.ui_in.time_us += us


class HostTests(unittest.TestCase):
    def test_spi_mode_zero_and_clock_limit(self):
        board = FakeBoard([1, 0, 1, 0, 1, 1, 0, 0])
        with self.assertRaises(ValueError):
            DemoBoardSPI(board, 4_000_000, 250_001, board.wait)
        transport = DemoBoardSPI(board, 4_000_000, 250_000, board.wait)
        self.assertEqual(transport.exchange(b"\x53"), b"\xAC")
        self.assertEqual(board.ui_in.tx_bits, [0, 1, 0, 1, 0, 0, 1, 1])
        self.assertTrue(all(b - a >= 2 for a, b in zip(board.ui_in.edges, board.ui_in.edges[1:])))
        self.assertEqual(board.ui_in[:2], [0, 1])
        self.assertEqual(board.ui_in[6], 1)
        with self.assertRaises(StopIteration):
            transport.exchange(b"\x00")
        self.assertEqual(board.ui_in[:2], [0, 1])

    def test_load_replaces_config_clears_old_words_and_preloads_fifo(self):
        device = SpiDevice()
        host = PVMHost(device)
        self.assertEqual(host.load_image(image())["state"], READY)
        self.assertNotIn(7, device.regs)
        self.assertEqual(device.regs[0x0406], 0)
        self.assertEqual(device.regs[0x0405], 8)
        self.assertEqual(device.tx, [0x35, 0xA6])
        self.assertIn(b"\x03\x0F\x20\x00\x00\x00\x00", device.frames)
        self.assertEqual([f for f in device.frames if f[:3] == b"\x02\x0F\x10"],
                         [b"\x02\x0F\x10\x35", b"\x02\x0F\x10\xA6"])
        self.assertEqual(host.enable(), DONE)
        self.assertEqual(host.wait_done()["state"], DONE)

    def test_bad_image_is_rejected_before_any_spi_transaction(self):
        device = SpiDevice()
        host = PVMHost(device)
        broken = image()
        broken["writes"][0][1] ^= 1
        with self.assertRaisesRegex(ValueError, "CRC"):
            host.load_image(broken)
        broken = image()
        broken["writes"].pop(3)
        with self.assertRaisesRegex(ValueError, "all configuration"):
            host.load_image(broken)
        self.assertEqual(device.frames, [])
        self.assertEqual(crc16_ccitt_false(b"123456789"), 0x29B1)

    def test_wrong_target_and_rejected_validation_hold_enable(self):
        device = SpiDevice()
        host = PVMHost(device)
        device.id = b"TEST"
        with self.assertRaisesRegex(PVMError, "ID"):
            host.load_image(image(), enable=True)
        self.assertEqual(device.frames, [b"\x9F\x00\x00\x00\x00"])
        device.id = b"PVM!"
        device.reject_validation = True
        with self.assertRaisesRegex(PVMError, "validate failed"):
            host.load_image(image(), enable=True)
        self.assertNotIn(b"\x02\x0F\x00\x03", device.frames)
        self.assertEqual(device.tx, [])

    def test_fifo_reads_use_one_acknowledged_byte_per_frame(self):
        device = SpiDevice()
        host = PVMHost(device)
        device.rx = [3, 7]
        self.assertEqual(host.pop_rx(2), b"\x03\x07")
        self.assertEqual(device.rx, [])
        self.assertEqual(device.frames.count(b"\x03\x0F\x11\x00\x00"), 2)

    def test_monitor_ring_returns_oldest_slot_first(self):
        device = SpiDevice()
        host = PVMHost(device)
        device.regs[0x0330] = 9
        device.regs[0x0FA0] = 63 << 2 | 1
        for slot in range(4):
            base = 0x0F80 + 8 * slot
            device.regs[base] = slot | 1 << 3
            device.regs[base + 1] = 10 + slot
        report = host.read_monitor()
        self.assertEqual(report["log_total"], 63)
        self.assertEqual(report["pass"], 9)
        self.assertEqual([entry["rule"] for entry in report["entries"]], [1, 2, 3, 0])
        self.assertEqual([entry["interval"] for entry in report["entries"]], [11, 12, 13, 10])


if __name__ == "__main__":
    unittest.main()
