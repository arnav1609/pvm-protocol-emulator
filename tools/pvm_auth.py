"""Authenticated SPI v1 framing, image commitment, and host control."""

from dataclasses import dataclass
from hashlib import sha3_256
import struct

from .pvm_host import PVMError, _image_fields


OPEN, CHUNK, FINISH, START, CANCEL, TX_PUSH, RX_POP, CLEAR_FLAGS = range(1, 9)
INFO_SIZE = 74
NO_SEQUENCE = 0xFFFFFFFF


@dataclass(frozen=True)
class ImagePlan:
    root: bytes
    meta: bytes
    chunks: tuple[bytes, ...]


def plan_image(image):
    writes, crc, _, preload = _image_fields(image)
    groups = [writes[index:index + 8] for index in range(0, len(writes), 8)]
    meta = struct.pack(">HHB", len(groups), crc, len(preload)) + bytes(preload)
    link = sha3_256(b"PVM-END1" + meta).digest()
    bodies = []
    for index in reversed(range(len(groups))):
        group = groups[index]
        records = b"".join(struct.pack(">HB", address, byte) for address, byte in group)
        body = records + link
        bodies.append(body)
        link = sha3_256(b"PVM-BLK1" + struct.pack(">HB", index, len(group)) + body).digest()
    return ImagePlan(link, meta, tuple(reversed(bodies)))


def signed_frame(operation, identity, device, challenge, sequence, root, payload, sign):
    """Sign one exact body. The provided signer controls credential access."""
    if operation not in range(OPEN, CLEAR_FLAGS + 1) or identity not in range(1, 12):
        raise ValueError("invalid operation or employee ID")
    if (len(device), len(challenge), len(root)) != (8, 16, 32):
        raise ValueError("invalid device, challenge, or image root length")
    if not 0 <= sequence < NO_SEQUENCE or len(payload) > 56:
        raise ValueError("invalid sequence or payload length")
    body = (bytes((1, operation, identity)) + device + challenge + struct.pack(">I", sequence)
            + root + bytes((len(payload),)) + payload)
    tag = sign(body)
    if len(tag) != 32:
        raise ValueError("signer did not return a 32-byte tag")
    return bytes((0xA0,)) + body + tag


@dataclass(frozen=True)
class Info:
    phase: int
    busy: bool
    result: int
    owner: int
    device: bytes
    challenge: bytes
    next_sequence: int
    last_committed: int
    root: bytes
    rx: bytes


def decode_info(data):
    if len(data) != INFO_SIZE or data[0] != 1 or data[69] > 4:
        raise PVMError("invalid authenticated PVM INFO response")
    next_seq, last = struct.unpack(">II", data[29:37])
    return Info(data[1], bool(data[2]), data[3], data[4], data[5:13], data[13:29],
                next_seq, last, data[37:69], data[70:70 + data[69]])


class AuthorizedHost:
    """Control an authenticated PVM over a transport with exchange(bytes)."""

    def __init__(self, transport, identity, sign, polls=32):
        self.transport = transport
        self.identity = identity
        self.sign = sign
        self.polls = polls

    def _exchange(self, frame):
        response = self.transport.exchange(frame)
        if len(response) != len(frame):
            raise PVMError("authenticated SPI response length differs from request")
        return response

    def info(self):
        return decode_info(self._exchange(bytes((0xA1, 0)) + bytes(INFO_SIZE))[2:])

    def safe_read(self, address):
        return self._exchange(struct.pack(">BHB", 0xA2, address, 0) + b"\0")[4]

    def _command(self, before, operation, payload=b"", root=None):
        if before.busy or before.result == 4:
            raise PVMError("authorization guard is busy or unavailable")
        frame = signed_frame(operation, self.identity, before.device, before.challenge,
                             before.next_sequence, before.root if root is None else root,
                             payload, self.sign)
        self._exchange(frame)
        for _ in range(self.polls):
            after = self.info()
            if not after.busy:
                break
        else:
            raise PVMError("timed out waiting for PVM authorization")
        if after.last_committed != before.next_sequence or after.result != 0:
            raise PVMError(f"authorization result {after.result}, sequence not committed")
        expected_root = before.root if root is None else root
        if operation == CANCEL:
            expected = (before.device, bytes(16), bytes(32), 0)
        else:
            expected = (before.device, before.challenge, expected_root, self.identity)
        if (after.device, after.challenge, after.root, after.owner) != expected:
            raise PVMError("authorization receipt changed device, owner, or session")
        return after

    def load(self, image):
        """Load a canonical image through authenticated READY."""
        plan = plan_image(image)
        ready = self._command(self.info(), OPEN, plan.meta, plan.root)
        for data in plan.chunks:
            ready = self._command(ready, CHUNK, data)
        ready = self._command(ready, FINISH)
        if ready.phase != 2 or ready.root != plan.root:
            raise PVMError("image did not reach authenticated READY")
        return ready

    def start(self, expected, approve):
        """Request a separate confirmation for this device and image root."""
        ready = self.info()
        if (ready.phase, ready.owner, ready.device, ready.challenge, ready.root) != (
                2, self.identity, expected.device, expected.challenge, expected.root):
            raise PVMError("approved image is no longer READY for this owner")
        if not approve(ready.device, ready.root):
            raise PVMError("START approval declined")
        return self._command(ready, START)

    def cancel(self):
        return self._command(self.info(), CANCEL)

    def tx_push(self, data):
        if not 1 <= len(data) <= 4:
            raise ValueError("TX_PUSH requires one to four bytes")
        return self._command(self.info(), TX_PUSH, data)

    def rx_pop(self, count):
        if count not in range(1, 5):
            raise ValueError("RX_POP requires one to four bytes")
        return self._command(self.info(), RX_POP, bytes((count,))).rx

    def clear_flags(self):
        return self._command(self.info(), CLEAR_FLAGS)
