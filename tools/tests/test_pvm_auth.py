import struct
import unittest

from tools import pvm_auth as auth
from tools.pvm_host import PVMError


DEVICE = bytes(range(8))
CHALLENGE = bytes(range(16))
ROOT = bytes(range(32))


def response(phase=2, sequence=6, challenge=CHALLENGE):
    return (bytes((1, phase, 0, 0, 1)) + DEVICE + challenge
            + struct.pack(">II", sequence, sequence - 1) + ROOT + bytes(5))


class Transport:
    def __init__(self, replies):
        self.replies = iter(replies)
        self.frames = []

    def exchange(self, frame):
        self.frames.append(frame)
        if frame[0] == 0xA1:
            return bytes(2) + next(self.replies)
        return bytes(len(frame))


class AuthHostTest(unittest.TestCase):
    def test_start_requires_separate_approval(self):
        transport = Transport([response()])
        host = auth.AuthorizedHost(transport, 1, lambda body: self.fail("must not sign"))
        with self.assertRaisesRegex(PVMError, "declined"):
            host.start(auth.decode_info(response()), lambda device, root: False)
        self.assertEqual([frame[0] for frame in transport.frames], [0xA1])

    def test_start_binds_the_presented_device_challenge_and_root(self):
        transport = Transport([response(), response(phase=3,sequence=7)])
        body_seen = []
        def sign(body):
            body_seen.append(body)
            return bytes.fromhex("a5" * 32)

        host = auth.AuthorizedHost(transport, 1, sign)
        confirmed = []
        def approve(device, root):
            confirmed.append((device,root))
            return True

        after = host.start(auth.decode_info(response()), approve)
        self.assertEqual(confirmed, [(DEVICE,ROOT)])
        self.assertEqual(after.last_committed, 6)
        self.assertEqual(body_seen, [bytes((1,4,1)) + DEVICE + CHALLENGE
                                     + struct.pack(">I",6) + ROOT + bytes(1)])

    def test_receipt_from_other_challenge_cannot_confirm_start(self):
        transport = Transport([response(), response(phase=3,sequence=7,challenge=bytes(16))])
        host = auth.AuthorizedHost(transport, 1, lambda body: bytes(32))
        with self.assertRaisesRegex(PVMError, "session"):
            host.start(auth.decode_info(response()), lambda device, root: True)

    def test_short_spi_response_is_rejected(self):
        transport = Transport([b""])
        host = auth.AuthorizedHost(transport, 1, lambda body: bytes(32))
        with self.assertRaisesRegex(PVMError, "response length"):
            host.info()

    def test_bad_signer_tag_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "32-byte tag"):
            auth.signed_frame(auth.START, 1, DEVICE, CHALLENGE, 6, ROOT, b"", lambda body: b"")


if __name__ == "__main__":
    unittest.main()
