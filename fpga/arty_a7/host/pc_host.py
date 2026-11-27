"""Use the Arty USB-UART bridge as a PVMHost SPI transport."""

from math import isfinite
from threading import Lock
from time import monotonic

from pvm_host import PVMError


UART_BAUD = 115_200
MAX_SPI_BYTES = 260
EXCHANGE = 0x01
RESET_TARGET = 0x02
OK = 0x00
REJECTED = 0xFF


class SerialSPI:
    """Frame one SPI transaction at a time on a serial port with finite I/O timeouts."""

    def __init__(self, serial_port, timeout=2.0, *, clock=monotonic):
        if not isfinite(timeout) or timeout <= 0:
            raise ValueError("serial transaction timeout must be finite and positive")
        self._port = serial_port
        self._timeout = timeout
        self._clock = clock
        self._lock = Lock()
        self._synchronized = True

    def _write_all(self, request, deadline):
        sent = 0
        while sent < len(request):
            if self._clock() >= deadline:
                raise PVMError("USB-UART bridge write timed out")
            count = self._port.write(request[sent:])
            if not isinstance(count, int) or not 0 < count <= len(request) - sent:
                raise PVMError("USB-UART bridge write did not complete")
            sent += count

    def _read_exact(self, count, deadline):
        data = bytearray()
        while len(data) < count:
            if self._clock() >= deadline:
                raise PVMError(f"USB-UART bridge response timed out ({len(data)}/{count} bytes)")
            data.extend(self._port.read(count - len(data)))
        return bytes(data)

    def _request(self, request, response_size):
        with self._lock:
            if not self._synchronized:
                raise PVMError("USB-UART bridge stream lost synchronization. Reset the board and reopen the port.")
            deadline = self._clock() + self._timeout
            try:
                self._write_all(request, deadline)
                status = self._read_exact(1, deadline)[0]
                if status == REJECTED:
                    raise PVMError("USB-UART bridge rejected the request")
                if status != OK:
                    raise PVMError(f"Unexpected USB-UART bridge status 0x{status:02X}")
                return self._read_exact(response_size, deadline)
            except (OSError, PVMError) as exc:
                # A partial transfer can leave response bytes or a committed SPI write.
                self._synchronized = False
                raise PVMError(str(exc)) from exc

    def exchange(self, payload):
        """Hold CS across one bridge request and return its raw SPI response."""
        payload = bytes(payload)
        if not payload:
            return b""
        if len(payload) > MAX_SPI_BYTES:
            raise ValueError(f"SPI frames are limited to {MAX_SPI_BYTES} bytes")
        return self._request(bytes((EXCHANGE,)) + len(payload).to_bytes(2, "big") + payload, len(payload))

    def reset_target(self):
        """Request an active-low reset of the PVM target."""
        self._request(bytes((RESET_TARGET,)), 0)
