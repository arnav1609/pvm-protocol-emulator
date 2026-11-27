"""Load the frozen PVM demos through the Arty USB-UART bridge."""

import argparse
from contextlib import nullcontext
from dataclasses import dataclass
from hashlib import sha256
import json
from pathlib import Path
import sys
from time import sleep
from zipfile import BadZipFile, ZipFile

from pc_host import SerialSPI, UART_BAUD
from pvm_host import DONE, FIFO_STAT, IMAGE_ID, PVMError, PVMHost


DEMOS = ("uart_tx", "spi_mode0", "i2c_write", "dmx512_tx")
HANDOFF = Path(__file__).resolve().parents[1] / "inputs" / "PVM_Arty_A7_Handoff_b33a922.zip"
FLAGS = 0x0F0B
READY_STATUS = 0x42
ENABLE = 0x03
DMX_IDLE_SECONDS = 0.010


@dataclass(frozen=True)
class DemoCase:
    name: str
    run: int
    image: dict
    expected: dict


def read_demo_cases(handoff, names=DEMOS):
    """Read the verified image JSONs and per-run readback oracles from Arnav's ZIP."""
    cases = []
    with ZipFile(handoff) as archive:
        manifest = {}
        for line in archive.read("SHA256SUMS.txt").decode("ascii").splitlines():
            digest, member = line.split(maxsplit=1)
            manifest[member.removeprefix("./")] = digest

        def read_json(member):
            data = archive.read(member)
            if sha256(data).hexdigest() != manifest.get(member):
                raise ValueError(f"Handoff checksum mismatch for {member}")
            return json.loads(data)

        for name in names:
            if name not in DEMOS:
                raise ValueError(f"Unknown demo {name}")
            image = read_json(f"images/{name}/image.json")
            if name == "dmx512_tx":
                for run in (1, 2):
                    expected = read_json(f"evidence/{name}/run_{run}_readback.json")
                    cases.append(DemoCase(name, run, image, expected))
            else:
                expected = read_json(f"evidence/{name}/readback.json")
                cases.append(DemoCase(name, 1, image, expected))
    return cases


def run_demo(host, case, *, before_start=None, wait=sleep):
    """Load once, let the operator arm the capture, then check the terminal readback."""
    ready = host.load_image(case.image)
    if ready["status"] != READY_STATUS:
        raise PVMError(f"{case.name} run {case.run} did not reach exact READY: {ready!r}")
    if before_start:
        before_start(case)
    # Preserve a quiet programming bus while both short DMX packets are emitted.
    if case.name == "dmx512_tx":
        host.command(ENABLE)
        wait(DMX_IDLE_SECONDS)
    else:
        host.enable()
    observed = {
        "status": host.wait_done(),
        "fifo_stat": host.read(FIFO_STAT)[0],
        "flags": host.read(FLAGS)[0],
        "image_id": host.read(IMAGE_ID, 3).hex(),
        "monitor": host.read_monitor(),
    }
    if observed["status"]["state"] != DONE:
        raise PVMError(f"{case.name} run {case.run} did not reach DONE")
    for name, expected in case.expected.items():
        actual = observed[name]
        if name == "status":
            actual = {key: value for key, value in actual.items() if key != "fault_time"}
            expected = {key: value for key, value in expected.items() if key != "fault_time"}
        if actual != expected:
            raise PVMError(f"{case.name} run {case.run} {name}: expected {expected!r}, got {actual!r}")
    return {"demo": case.name, "run": case.run, "ready_status": ready["status"], **observed}


def _arm(case):
    print(f"Arm capture for {case.name} run {case.run}, then press Enter to send ENABLE.", file=sys.stderr)
    input()


def _wait_for_ila(label):
    print(f"READY {label}", flush=True)
    if sys.stdin.readline().strip() != "GO":
        raise PVMError(f"ILA controller did not arm {label}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True, help="Arty USB-UART device, such as COM5 or /dev/ttyUSB1")
    parser.add_argument("--demo", choices=(*DEMOS, "all"), default="all")
    parser.add_argument("--handoff", type=Path, default=HANDOFF)
    capture = parser.add_mutually_exclusive_group()
    capture.add_argument("--arm", action="store_true", help="wait for the analyzer before each run")
    capture.add_argument("--ila-sync", action="store_true", help="coordinate captures with Vivado over standard I/O")
    parser.add_argument("--output", type=Path, help="write a new readback JSON Lines file")
    args = parser.parse_args(argv)
    if args.ila_sync and args.output is None:
        parser.error("--ila-sync requires --output so that stdout carries only capture control messages")
    try:
        import serial
    except ImportError:
        parser.error("pySerial is required to open the Arty USB-UART port")

    try:
        cases = read_demo_cases(args.handoff, DEMOS if args.demo == "all" else (args.demo,))
        output = args.output.open("x", encoding="utf-8") if args.output else nullcontext(sys.stdout)
        with output as stream, serial.Serial(
            args.port,
            UART_BAUD,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=0.050,
            write_timeout=0.250,
        ) as port:
            port.reset_input_buffer()
            transport = SerialSPI(port)
            if args.ila_sync:
                _wait_for_ila("reset")
            transport.reset_target()
            if args.ila_sync:
                print("DONE reset", flush=True)
            host = PVMHost(transport)
            before_start = _arm if args.arm else None
            if args.ila_sync:
                before_start = lambda case: _wait_for_ila(f"{case.name} {case.run}")
            for case in cases:
                result = run_demo(host, case, before_start=before_start)
                print(json.dumps(result), file=stream, flush=True)
                print(f"READBACK PASS {case.name} run {case.run}", file=sys.stderr)
                if args.ila_sync:
                    print(f"DONE {case.name} {case.run}", flush=True)
    except (BadZipFile, KeyError, OSError, PVMError, ValueError) as exc:
        print(f"FAIL {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
