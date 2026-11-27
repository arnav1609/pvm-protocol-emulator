"""PC bridge framing and demo-policy checks with no attached hardware."""

from dataclasses import replace
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock
from zipfile import ZipFile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "host"))

from pc_host import SerialSPI
from pvm_host import PVMError, PVMHost
from pvm_wire import crc16_ccitt_false
from run_demos import DMX_IDLE_SECONDS, HANDOFF, read_demo_cases, run_demo


class SerialStub:
    def __init__(self, make_reply=lambda request: b"", *, write_limit=400, read_limit=400):
        self.wire = bytearray()
        self.responses = bytearray()
        self.request = bytearray()
        self.make_reply = make_reply
        self.write_limit = write_limit
        self.read_limit = read_limit

    def write(self, data):
        chunk = data[:self.write_limit]
        self.wire.extend(chunk)
        self.request.extend(chunk)
        if self.request[:1] == b"\x02":
            self.responses.extend(self.make_reply(bytes(self.request)))
            self.request.clear()
        elif len(self.request) >= 3 and len(self.request) == 3 + int.from_bytes(self.request[1:3], "big"):
            self.responses.extend(self.make_reply(bytes(self.request)))
            self.request.clear()
        return len(chunk)

    def read(self, count):
        count = min(count, self.read_limit)
        data = bytes(self.responses[:count])
        del self.responses[:count]
        return data


class DemoTarget:
    """Small register model used to observe the loader's SPI operations."""

    def __init__(self):
        self.events = []
        self.reset()

    def reset(self):
        self.registers = {}
        self.writes = []
        self.image_id = bytes(3)
        self.status = 0
        self.pc = 0
        self.events.append("reset")

    def reply(self, request):
        if request == b"\x02":
            self.reset()
            return b"\x00"
        frame = request[3:]
        self.events.append(frame)
        if frame == b"\x9f\x00\x00\x00\x00":
            return b"\x00\x00PVM!"
        address = int.from_bytes(frame[1:3], "big")
        if frame[0] == 2:
            for i, byte in enumerate(frame[3:]):
                loc = address + i
                if loc == 0x0F00:
                    if byte == 1:
                        self.reset()
                    elif byte == 4:
                        self.events.append("clear")
                    elif byte == 2:
                        check = (self.registers[0x0F08] | self.registers[0x0F09] << 8)
                        if check != crc16_ccitt_false(value for _, value in self.writes):
                            raise ValueError("model CRC mismatch")
                        self.image_id = check.to_bytes(2, "little") + bytes((self.registers[0x0F0A],))
                        self.status = 0x42
                        self.events.append(("ready", list(self.writes)))
                    elif byte == 3:
                        self.status = 0x44
                        self.events.append("enable")
                    continue
                self.registers[loc] = byte
                if loc < 0x0F00 or loc == 0x0F0A:
                    self.writes.append((loc, byte))
            return bytes(len(frame) + 1)
        if frame[0] != 3:
            raise ValueError(f"Unexpected SPI frame {frame!r}")
        crc = crc16_ccitt_false(value for _, value in self.writes)
        readback = {
            0x0F01: self.status,
            0x0F02: int(self.status == 0x44),
            0x0F03: self.pc if self.status == 0x44 else 0,
            0x0F04: 0xFE,
            0x0F05: 0xCA,
            0x0F06: crc & 0xFF,
            0x0F07: crc >> 8,
            **{0x0F20 + i: byte for i, byte in enumerate(self.image_id)},
        }
        return b"\x00" * 5 + bytes(readback.get(address + i, 0) for i in range(len(frame) - 4))


def fake_clock():
    ticks = iter(i * 0.01 for i in range(1000))
    return lambda: next(ticks)


class TransportTests(unittest.TestCase):
    def test_exchange_exact_bytes_across_partial_io(self):
        serial = SerialStub(lambda req: b"\x00\x00PVM!", write_limit=2, read_limit=1)
        self.assertEqual(SerialSPI(serial).exchange(b"\x9f\x00\x00\x00\x00"), b"\x00PVM!")
        self.assertEqual(serial.wire, b"\x01\x00\x05\x9f\x00\x00\x00\x00")

    def test_reset_opcode(self):
        serial = SerialStub(lambda req: b"\x00")
        SerialSPI(serial).reset_target()
        self.assertEqual(serial.wire, b"\x02")

    def test_max_frame_count_big_endian(self):
        serial = SerialStub(lambda req: b"\x00" + req[3:])
        payload = bytes(range(256)) + b"\x01\x02\x03\x04"
        self.assertEqual(SerialSPI(serial).exchange(payload), payload)
        self.assertEqual(serial.wire[:3], b"\x01\x01\x04")

    def test_empty_and_oversized_frames_send_nothing(self):
        serial = SerialStub()
        transport = SerialSPI(serial)
        self.assertEqual(transport.exchange(b""), b"")
        with self.assertRaises(ValueError):
            transport.exchange(bytes(261))
        self.assertEqual(serial.wire, b"")

    def test_missing_reply_poisoned_stream(self):
        serial = SerialStub()
        transport = SerialSPI(serial, timeout=0.08, clock=fake_clock())
        with self.assertRaisesRegex(PVMError, "response timed out"):
            transport.reset_target()
        with self.assertRaisesRegex(PVMError, "lost synchronization"):
            transport.reset_target()
        self.assertEqual(serial.wire, b"\x02")

    def test_partial_reply_times_out(self):
        serial = SerialStub(lambda req: b"\x00\x12")
        with self.assertRaisesRegex(PVMError, r"1/2 bytes"):
            SerialSPI(serial, timeout=0.08, clock=fake_clock()).exchange(b"\x01\x02")

    def test_invalid_status_rejected(self):
        for status, message in ((b"\xff", "rejected"), (b"\x7f", "Unexpected")):
            with self.subTest(status=status):
                with self.assertRaisesRegex(PVMError, message):
                    SerialSPI(SerialStub(lambda req: status)).reset_target()

    def test_zero_progress_write_stops(self):
        serial = SerialStub(write_limit=0)
        with self.assertRaisesRegex(PVMError, "write did not complete"):
            SerialSPI(serial).reset_target()

    def test_timeout_argument_bounds(self):
        for timeout in (0, -1, float("inf"), float("nan")):
            with self.subTest(timeout=timeout), self.assertRaises(ValueError):
                SerialSPI(SerialStub(), timeout=timeout)


class DemoTests(unittest.TestCase):
    def test_all_archived_runs_through_framed_host(self):
        cases = read_demo_cases(HANDOFF)
        target = DemoTarget()
        transport = SerialSPI(SerialStub(target.reply, read_limit=2))
        transport.reset_target()
        host = PVMHost(transport)
        results = []
        for case in cases:
            # The modeled reset only occurs on HALT. Use the archived PC for execution.
            begin = len(target.events)

            def arm(armed_case):
                target.pc = armed_case.expected["status"]["fault_pc"]
                target.events.append("arm")

            def wait(seconds):
                self.assertEqual(seconds, DMX_IDLE_SECONDS)
                self.assertEqual(target.events[-1], "enable")
                target.events.append("quiet")

            results.append(run_demo(host, case, before_start=arm, wait=wait))
            events = target.events[begin:]
            ordered_image = [tuple(pair) for pair in case.image["writes"]]
            self.assertIn(("ready", ordered_image), events)
            self.assertLess(events.index("arm"), events.index("enable"))
            self.assertEqual("quiet" in events, case.name == "dmx512_tx")
        self.assertEqual([(r["demo"], r["run"]) for r in results],
                         [("uart_tx", 1), ("spi_mode0", 1), ("i2c_write", 1),
                          ("dmx512_tx", 1), ("dmx512_tx", 2)])
        self.assertEqual(results[0]["status"]["fault_time"], 0xCAFE)

    def test_wrong_ready_prevents_enable(self):
        case = read_demo_cases(HANDOFF, ("uart_tx",))[0]
        host = Mock()
        host.load_image.return_value = {"status": 2}
        with self.assertRaisesRegex(PVMError, "exact READY"):
            run_demo(host, case)
        host.enable.assert_not_called()
        host.command.assert_not_called()

    def test_terminal_image_id_mismatch_rejected(self):
        case = read_demo_cases(HANDOFF, ("uart_tx",))[0]
        case = replace(case, expected={**case.expected, "image_id": "a51a02"})
        target = DemoTarget()
        host = PVMHost(SerialSPI(SerialStub(target.reply)))

        def arm(armed_case):
            target.pc = armed_case.expected["status"]["fault_pc"]

        with self.assertRaisesRegex(PVMError, "image_id"):
            run_demo(host, case, before_start=arm)

    def test_corrupted_image_fails_handoff_validation(self):
        member = "images/uart_tx/image.json"
        with tempfile.TemporaryDirectory() as folder:
            copy = Path(folder) / "bad.zip"
            with ZipFile(HANDOFF) as source, ZipFile(copy, "w") as dest:
                dest.writestr("SHA256SUMS.txt", source.read("SHA256SUMS.txt"))
                dest.writestr(member, source.read(member) + b" ")
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                read_demo_cases(copy, ("uart_tx",))


if __name__ == "__main__":
    unittest.main()
