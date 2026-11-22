"""PVM image loader for the Tiny Tapeout RP2350 MicroPython SDK."""

try:
    from .pvm_wire import (
        CONFIG_ADDRESSES, IMAGE_FORMAT, IMAGE_VER, config_write_mask, crc16_ccitt_false,
    )
except ImportError:  # MicroPython deployment copies these two modules to the board.
    from pvm_wire import (
        CONFIG_ADDRESSES, IMAGE_FORMAT, IMAGE_VER, config_write_mask, crc16_ccitt_false,
    )

CTRL = 0x0F00
STATUS = 0x0F01
CRC_CALC = 0x0F06
CRC_EXPECT = 0x0F08
TX_FIFO = 0x0F10
RX_FIFO = 0x0F11
FIFO_STAT = 0x0F12
IMAGE_ID = 0x0F20

HALT, VALIDATING, READY, RUN, DONE, FAULT = range(6)
CLR_IMEM = 0x04
WR_REJ, CRC_OK = 0x08, 0x40
FIFO_DEPTH = 4


class PVMError(RuntimeError):
    """A transport, validation, or execution failure reported by the host."""


def read_image(path):
    """Read the JSON artifact produced on the desktop."""
    import json

    with open(path) as stream:
        return json.load(stream)


def _bounded_int(value, maximum):
    return type(value) is int and 0 <= value <= maximum


def _image_fields(image):
    if not isinstance(image, dict) or image.get("format") != IMAGE_FORMAT:
        raise ValueError("expected a pvm-image-v1 object")
    writes = image.get("writes")
    crc = image.get("crc16")
    version = image.get("image_version")
    preload = image.get("tx_preload", [])
    if not _bounded_int(crc, 0xFFFF) or not _bounded_int(version, 0xFF):
        raise ValueError("image CRC or version is out of range")
    if not isinstance(preload, (list, tuple)) or len(preload) > FIFO_DEPTH or any(
        not _bounded_int(byte, 0xFF) for byte in preload
    ):
        raise ValueError("TX preload must contain up to four bytes")
    if not isinstance(writes, (list, tuple)) or not writes:
        raise ValueError("image must contain ordered address-byte writes")

    previous = -1
    config_addresses = []
    imem_addresses = []
    for pair in writes:
        if not isinstance(pair, (list, tuple)) or len(pair) != 2:
            raise ValueError("each image write must contain one address and byte")
        address, byte = pair
        if not _bounded_int(address, 0xFFFF) or not _bounded_int(byte, 0xFF):
            raise ValueError("image write address or data is out of range")
        if address <= previous:
            raise ValueError("image write addresses must be strictly increasing")
        previous = address
        if address < 0x40:
            imem_addresses.append(address)
        elif address != IMAGE_VER:
            mask = config_write_mask(address)
            if not mask or byte & ~mask:
                raise ValueError("invalid configuration byte at 0x%04X" % address)
            config_addresses.append(address)
    if tuple(config_addresses) != CONFIG_ADDRESSES:
        raise ValueError("image must replace all configuration bytes")
    if not imem_addresses or len(imem_addresses) % 2 or any(
        low % 2 or high != low + 1
        for low, high in zip(imem_addresses[::2], imem_addresses[1::2])
    ):
        raise ValueError("instruction writes must contain low/high byte pairs")
    if tuple(writes[-1]) != (IMAGE_VER, version):
        raise ValueError("image must end with its IMAGE_VER byte")
    if crc16_ccitt_false(byte for _, byte in writes) != crc:
        raise ValueError("image payload failed CRC verification")
    return writes, crc, version, preload


def _u16(low, high):
    return low | high << 8


class DemoBoardSPI:
    """SPI mode 0, MSB first, using the selected project's TT board pins."""

    def __init__(self, board, core_clk_hz, sck_hz=None, sleep_us=None):
        if type(core_clk_hz) is not int or core_clk_hz < 16:
            raise ValueError("core_clk_hz must be an integer of at least 16 Hz")
        limit = core_clk_hz // 16
        if sck_hz is None:
            sck_hz = min(limit, 250_000)
        if type(sck_hz) is not int or not 1 <= sck_hz <= limit:
            raise ValueError("SCK must be positive and at most one sixteenth of the core clock")
        if sleep_us is None:
            from time import sleep_us

        self._board = board
        self._wait = sleep_us
        # Round the half-period up. Python and GPIO overhead slow the bus further.
        self._half_us = (500_000 + sck_hz - 1) // sck_hz
        board.ui_in[1] = 1  # CS_n
        board.ui_in[0] = 0  # SCK
        board.ui_in[2] = 0  # MOSI

    def exchange(self, payload):
        if not payload:
            return b""
        pins = self._board.ui_in
        miso = self._board.uo_out
        wait = self._wait
        half = self._half_us
        reply = bytearray()
        wait(half)  # idle CS_n even for consecutive calls
        pins[1] = 0
        try:
            wait(half)
            for byte in payload:
                incoming = 0
                for bit in range(7, -1, -1):
                    pins[2] = (byte >> bit) & 1
                    wait(half)
                    pins[0] = 1
                    wait(half)
                    incoming = (incoming << 1) | int(bool(miso[7]))
                    pins[0] = 0
                reply.append(incoming)
            wait(half)
        finally:
            pins[0] = 0
            pins[1] = 1
        return bytes(reply)


class PVMHost:
    """Byte-register access over a transport with exchange(bytes) -> bytes."""

    def __init__(self, transport):
        self._transport = transport

    def _exchange(self, frame):
        result = self._transport.exchange(frame)
        if len(result) != len(frame):
            raise PVMError("SPI transport returned the wrong frame length")
        return result

    @staticmethod
    def _header(command, address):
        if not _bounded_int(address, 0xFFFF):
            raise ValueError("address must be a 16-bit integer")
        return bytes((command, address >> 8, address & 0xFF))

    def identify(self):
        return self._exchange(bytes((0x9F, 0, 0, 0, 0)))[1:]

    def read(self, address, count=1):
        if type(count) is not int or count < 1:
            raise ValueError("read count must be positive")
        return self._exchange(self._header(3, address) + bytes(1 + count))[4:]

    def write(self, address, data):
        payload = bytes(data)
        if not payload:
            raise ValueError("write data must contain at least one byte")
        self._exchange(self._header(2, address) + payload)

    def command(self, value):
        self.write(CTRL, (value,))

    def status(self):
        status, code, pc, time_lo, time_hi = self.read(STATUS, 5)
        return {
            "state": status & 7,
            "status": status,
            "fault_code": code & 0xF,
            "fault_pc": pc & 0x1F,
            "fault_time": _u16(time_lo, time_hi),
        }

    def _expect_state(self, states, operation, polls):
        if type(polls) is not int or polls < 1:
            raise ValueError("polls must be positive")
        for _ in range(polls):
            status = self.read(STATUS)[0]
            state = status & 7
            if status & WR_REJ or state == FAULT:
                raise PVMError("%s failed: %s" % (operation, self.status()))
            if state in states:
                return status
        raise PVMError("%s timed out: %s" % (operation, self.status()))

    def _write_image_bytes(self, writes):
        start = writes[0][0]
        payload = bytearray()
        for address, byte in writes:
            if address != start + len(payload):
                self.write(start, payload)
                start = address
                payload = bytearray()
            payload.append(byte)
        self.write(start, payload)

    def load_image(self, image, *, enable=False, polls=32):
        """Load and verify an image; leave READY unless enable=True."""
        if type(polls) is not int or polls < 1:
            raise ValueError("polls must be positive")
        writes, crc, version, preload = _image_fields(image)
        if self.identify() != b"PVM!":
            raise PVMError("SPI target did not return the PVM 2.1 ID")
        self.command(0x01)  # HALT clears CRC and FIFOs.
        self._expect_state((HALT,), "halt", polls)
        self.command(CLR_IMEM)
        self._write_image_bytes(writes)
        if self.read(STATUS)[0] & WR_REJ:
            raise PVMError("target rejected an image write")
        if _u16(*self.read(CRC_CALC, 2)) != crc:
            raise PVMError("device CRC_CALC differs from the image")
        expected = bytes((crc & 0xFF, crc >> 8, version))
        self.write(CRC_EXPECT, expected[:2])
        self.command(0x02)  # VALIDATE
        status = self._expect_state((READY,), "validate", polls)
        if not status & CRC_OK or self.read(IMAGE_ID, 3) != expected:
            raise PVMError("target did not commit the expected image ID")
        self.push_tx(preload)
        if enable:
            self.enable(polls=polls)
        return self.status()

    def enable(self, *, polls=32):
        if (self.read(STATUS)[0] & 7) != READY:
            raise PVMError("ENABLE requires a committed image in READY")
        self.command(0x03)
        return self._expect_state((RUN, DONE), "enable", polls) & 7

    def wait_done(self, *, polls=1000):
        self._expect_state((DONE,), "wait for DONE", polls)
        return self.status()

    def push_tx(self, data):
        payload = bytes(data)
        if not payload:
            return
        level = self.read(FIFO_STAT)[0] & 7
        if len(payload) > FIFO_DEPTH - level:
            raise PVMError("TX FIFO has insufficient room")
        for byte in payload:
            self.write(TX_FIFO, (byte,))

    def pop_rx(self, count=1):
        if not _bounded_int(count, FIFO_DEPTH):
            raise ValueError("RX read count must be between zero and four")
        available = (self.read(FIFO_STAT)[0] >> 4) & 7
        if count > available:
            raise PVMError("RX FIFO has insufficient data")
        return bytes(self.read(RX_FIFO)[0] for _ in range(count))

    def read_monitor(self):
        """Read counters and log slots. A finished program gives a stable snapshot."""
        counts = self.read(0x0330, 7)
        raw = self.read(0x0F80, 33)
        pointer, total = raw[32] & 3, raw[32] >> 2
        slots = min(total, 4)
        entries = []
        for index in range(slots):
            offset = ((pointer - slots + index) & 3) * 8
            entry = raw[offset]
            entries.append({
                "rule": entry & 7,
                "verdict": (entry >> 3) & 3,
                "overflow": bool(entry & 0x20),
                "interval": _u16(raw[offset + 1], raw[offset + 2]),
                "timestamp": _u16(raw[offset + 3], raw[offset + 4]),
            })
        return {
            "pass": _u16(counts[0], counts[1]),
            "violation": _u16(counts[2], counts[3]),
            "inconclusive": _u16(counts[4], counts[5]),
            "state": counts[6] & 7,
            "log_total": total,
            "entries": entries,
        }
