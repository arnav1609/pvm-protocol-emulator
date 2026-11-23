"""Authenticated SPI pin replay on the secure RTL or a mapped trusted-input top."""

import argparse
import csv
from concurrent.futures import ThreadPoolExecutor
from functools import lru_cache
from hashlib import sha3_256
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys

THIS = Path(__file__).resolve().parent
ROOT = THIS.parents[1]
sys.path.insert(0, str(ROOT))
from tools import pvm_auth as auth
from tools.pvm_asm import assemble
from tools.pvm_image import build_image, _config_from_json

MASTER = bytes(range(32))  # Public simulation fixture only.
DEVICE = bytes.fromhex("0000000000000001")
CHALLENGE = bytes(range(16))
SECOND = bytes(range(16, 32))
THIRD = bytes(range(32, 48))
PROTOCOLS = ("UART", "SPI", "I2C", "DMX", "DMX_RELOAD", "DMX_NEG", "SECURITY", "FIFO")


def kmac(key, body, domain):
    command = [os.environ.get("OPENSSL", "openssl"), "mac", "-binary", "-macopt",
               f"hexkey:{key.hex()}", "-macopt", f"custom:{domain}", "-macopt", "size:32", "KMAC256"]
    return subprocess.check_output(command, input=body)


@lru_cache
def employee(identity):
    return kmac(MASTER, DEVICE + bytes([identity]), "PVM-KEY1")


def signed(operation, sequence, root, payload=b"", identity=1, challenge=CHALLENGE):
    return auth.signed_frame(operation, identity, DEVICE, challenge, sequence,
                             root, payload, lambda body: kmac(employee(identity), body, "PVM-CMD1"))


def fixture(protocol):
    name, preload = {
        "UART": ("uart_tx", [0x35]), "SPI": ("spi_mode0", [0xA6, 0xC9]),
        "I2C": ("i2c_write", [0xA0, 0x3C]),
        "DMX": ("dmx512_tx", []), "DMX_RELOAD": ("dmx512_tx", []),
        "DMX_NEG": ("dmx512_tx", []),
    }[protocol]
    stem = ROOT / "tools/examples" / name
    config = _config_from_json(stem.with_suffix(".json"))
    source = stem.with_suffix(".pvm").read_text()
    if protocol == "DMX_NEG":
        assert source.count("first_mab:\n    set pins, 0 [4]") == 1
        source = source.replace("first_mab:\n    set pins, 0 [4]", "first_mab:\n    set pins, 0 [0]")
    image = build_image(assemble(source, side_count=config.get(0x108, 0)),
                        config=config, tx_preload=preload)
    if protocol in ("DMX", "DMX_RELOAD"):
        assert image == json.loads(stem.with_suffix(".image.json").read_text())
    return image


class Scenario:
    def __init__(self):
        self.rows = []
        self.writes = []

    def challenge(self, nonce):
        self.rows.append("0 " + nonce[::-1].hex())

    def control(self, mode):
        self.rows.append(str(mode))
        if mode == 4:
            self.writes.append((0xF00, 1))

    def frame(self, data, phase, owner, seen, effects=(), result=0, mode=1):
        effects = tuple(effects)
        self.writes.extend(effects)
        self.rows.append(f"{mode} {len(data)} {phase:x} {result:x} {owner:x} {seen:08x} {len(effects)}"
                         + " " + data.hex(" "))

    def load(self, image, nonce, owner=1, approve=True, start_mode=2, reject_owner=False):
        plan = auth.plan_image(image)
        def frame(op, seq, payload=b"", identity=owner):
            return signed(op, seq, plan.root, payload, identity, nonce)
        self.frame(frame(auth.OPEN, 0, plan.meta), 1, owner, 0, [(0xF00, 1), (0xF00, 4)])
        for seq, chunk in enumerate(plan.chunks, 1):
            idx = (seq - 1) * 8
            self.frame(frame(auth.CHUNK, seq, chunk), 1, owner, seq, image["writes"][idx:idx + 8])
        seq = len(plan.chunks) + 1
        crc = image["crc16"]
        self.frame(frame(auth.FINISH, seq), 2, owner, seq,
                   [(0xF08, crc & 255), (0xF09, crc >> 8), (0xF00, 2)]
                   + [(0xF10, value) for value in image["tx_preload"]])
        if reject_owner:
            for other in (2, 11):
                self.frame(frame(auth.START, seq + 1, identity=other), 2, owner, seq, result=1)
        if approve:
            self.frame(frame(auth.START, seq + 1), 3, owner, seq + 1, [(0xF00, 3)], mode=start_mode)
        return plan, seq + int(approve)


def security(scenario):
    image = fixture("UART")
    plan = auth.plan_image(image)
    scenario.frame(b"\x02\x0f\x00\x03", 0, 0, auth.NO_SEQUENCE, result=4)
    for identity in range(1, 12):
        nonce = bytes((identity,)) + CHALLENGE[1:]
        scenario.challenge(nonce)
        open_frame = signed(auth.OPEN, 0, plan.root, plan.meta, identity, nonce)
        scenario.frame(open_frame, 1, identity, 0, [(0xF00, 1), (0xF00, 4)])
        scenario.frame(open_frame, 1, identity, 0, result=1)
        scenario.frame(signed(auth.CANCEL, 1, plan.root, identity=11, challenge=nonce),
                       0, 0, 1, [(0xF00, 1)])
    scenario.challenge(SECOND)
    open_frame = signed(auth.OPEN, 0, plan.root, plan.meta, challenge=SECOND)
    scenario.frame(open_frame[:-1], 0, 0, auth.NO_SEQUENCE)
    scenario.frame(open_frame, 0, 0, auth.NO_SEQUENCE, mode=5)
    bad_tag = open_frame[:-1] + bytes([open_frame[-1] ^ 1])
    scenario.frame(bad_tag, 0, 0, auth.NO_SEQUENCE, result=1)
    scenario.frame(open_frame, 1, 1, 0, [(0xF00, 1), (0xF00, 4)], mode=8)
    bad_chunk = bytes([plan.chunks[0][0] ^ 1]) + plan.chunks[0][1:]
    scenario.frame(signed(auth.CHUNK, 1, plan.root, bad_chunk, challenge=SECOND), 1, 1, 0, result=1)
    scenario.frame(signed(auth.FINISH, 1, plan.root, challenge=SECOND), 1, 1, 0, result=1)
    scenario.frame(signed(auth.CHUNK, 1, plan.root, plan.chunks[0], challenge=SECOND),
                   1, 1, 1, image["writes"][:8])
    scenario.control(4)
    scenario.challenge(THIRD)
    scenario.frame(open_frame, 0, 0, auth.NO_SEQUENCE, result=1)
    scenario.frame(signed(auth.OPEN, 0, plan.root, plan.meta, challenge=THIRD),
                   0, 0, auth.NO_SEQUENCE, mode=6)
    fourth = bytes(range(48, 64))
    scenario.challenge(fourth)
    # A valid MAC and valid first chain link cannot authorize a reserved address.
    reserved = bytes.fromhex("0f0003") + plan.chunks[0][3:]
    root = sha3_256(b"PVM-BLK1\x00\x00\x08" + reserved).digest()
    scenario.frame(signed(auth.OPEN, 0, root, plan.meta, challenge=fourth),
                   1, 1, 0, [(0xF00, 1), (0xF00, 4)])
    scenario.frame(signed(auth.CHUNK, 1, root, reserved, challenge=fourth), 1, 1, 0, result=1)
    scenario.frame(signed(auth.CANCEL, 1, root, challenge=fourth),
                   0, 0, 1, [(0xF00, 1)])
    fifth = bytes(range(64, 80))
    scenario.challenge(fifth)
    # An authenticated canonical chain with the wrong expected CRC must stop
    # at FINISH before CRC_EXPECT, VALIDATE, preload, or ENABLE can be issued.
    wrong_meta = plan.meta[:2] + bytes([plan.meta[2] ^ 1]) + plan.meta[3:]
    link = sha3_256(b"PVM-END1" + wrong_meta).digest()
    chunks = []
    for index in reversed(range(len(plan.chunks))):
        body = plan.chunks[index][:-32] + link
        chunks.append(body)
        link = sha3_256(b"PVM-BLK1" + struct.pack(">HB",index,(len(body)-32)//3) + body).digest()
    scenario.frame(signed(auth.OPEN, 0, link, wrong_meta, challenge=fifth),
                   1, 1, 0, [(0xF00, 1), (0xF00, 4)])
    for seq, body in enumerate(reversed(chunks),1):
        begin = (seq - 1) * 8
        scenario.frame(signed(auth.CHUNK, seq, link, body, challenge=fifth),
                       1, 1, seq, image["writes"][begin:begin + 8])
    seq = len(chunks) + 1
    scenario.frame(signed(auth.FINISH, seq, link, challenge=fifth),
                   4, 1, seq-1, [(0xF00, 1)], result=3)
    scenario.frame(signed(auth.START, seq, link, challenge=fifth), 4, 1, seq-1, result=1)


def fifo(scenario):
    scenario.challenge(CHALLENGE)
    # Produce one RX byte then wait indefinitely on TX. Runtime transfer requests are
    # indivisible even while the engine shares the FIFOs.
    source = "set x, 23\nin x, 8\npush block\npull block\nevt done\n"
    image = build_image(assemble(source), config={0x100: 4})
    plan, seq = scenario.load(image, CHALLENGE, start_mode=1)
    scenario.control(10)
    scenario.frame(signed(auth.RX_POP, seq+1, plan.root, b"\x02"), 3, 1, seq, result=2)
    scenario.frame(signed(auth.RX_POP, seq+1, plan.root, b"\x01"), 3, 1, seq+1)
    scenario.frame(signed(auth.RX_POP, seq+2, plan.root, b"\x01"), 3, 1, seq+1, result=2)
    values = b"\x53\x12\x34\x56"
    scenario.frame(signed(auth.TX_PUSH, seq+2, plan.root, values),
                   3, 1, seq+2, [(0xF10, byte) for byte in values])
    scenario.frame(signed(auth.CANCEL, seq+3, plan.root), 0, 0, seq+3, [(0xF00, 1)])
    scenario.challenge(SECOND)
    stalled = build_image(assemble("wait 1 pin 3\nevt done\n"), config={0x100: 4},
                          tx_preload=(1, 2, 3, 4))
    plan, seq = scenario.load(stalled, SECOND, start_mode=1)
    scenario.frame(signed(auth.TX_PUSH, seq+1, plan.root, b"\x53", challenge=SECOND),
                   3, 1, seq, result=2)
    scenario.control(4)


def vectors(protocol, out):
    scenario = Scenario()
    if protocol == "SECURITY":
        security(scenario)
    elif protocol == "FIFO":
        fifo(scenario)
    elif protocol == "DMX_RELOAD":
        scenario.challenge(CHALLENGE)
        image = fixture(protocol)
        plan, seq = scenario.load(image, CHALLENGE, start_mode=7)
        scenario.frame(signed(auth.CANCEL, seq + 1, plan.root), 0, 0, seq + 1, [(0xF00, 1)])
        scenario.challenge(SECOND)
        scenario.load(image, SECOND)
    else:
        scenario.challenge(CHALLENGE)
        scenario.load(fixture(protocol), CHALLENGE, reject_owner=protocol == "UART")
    out.write_text(str(len(scenario.rows)) + "\n" + "\n".join(scenario.rows) + "\n")
    return [tuple(pair) for pair in scenario.writes]


def run(protocol, args):
    stdout = args.output / f"{protocol}.log"
    image = args.output / f"{protocol}.hex"
    writes = vectors(protocol, image)
    prototype = "DMX" if protocol.startswith("DMX") else "SECURITY" if protocol=="FIFO" else protocol
    extra = []
    if args.mapped:
        sources = [str(args.mapped), *map(str, sorted(args.pdk_cells.rglob("*.v")))]
        extra.extend(["-DFUNCTIONAL", "-DSIM"])
    else:
        sources = list(map(str, sorted((ROOT / "src").glob("*.v"))))
        if args.sram:
            extra.append("-DPVM_KECCAK_IHP_SRAM")
    if args.sram or args.mapped:
        extra.append("-DFUNCTIONAL")
        sources += [str(args.sram_models / name) for name in
                    ("RM_IHPSG13_1P_64x64_c2_bm_bist.v", "RM_IHPSG13_1P_core_behavioral_bm_bist.v")]
    binary = args.output / f"{protocol}.vvp"
    subprocess.run([args.iverilog, "-g2005", "-DPVM_AUTH", "-DPVM_AUTH_TEST",
                    f"-DPVM_PROTOCOL_{prototype}", "-I", str(THIS), "-s", "tb_protocols",
                    "-o", str(binary), *extra, *sources, str(ROOT / "tb_rtl/tb_protocols.v")],check=True)
    with stdout.open("w") as log:
        sim = subprocess.run([args.vvp,"-i","-n",str(binary),f"+VECTORS={image}",
                              f"+DMX={args.output / 'dmx_reference.txt'}"],stdout=log,stderr=subprocess.STDOUT)
    binary.unlink()
    log = stdout.read_text()
    got = [tuple(int(hexbyte, 16) for hexbyte in record)
           for record in re.findall(r"^WRITE (\w+) (\w+)$", log, re.M)]
    assert got == writes, f"{protocol}: bus write mismatch at {next((i for i, (a, b) in enumerate(zip(got,writes)) if a != b), min(len(got),len(writes)))}\n{log[-1800:]}"
    if protocol == "DMX_NEG":
        assert sim.returncode and "DMX_MAB_MIN" in log, log[-1800:]
    else:
        assert sim.returncode == 0 and "RESULT : PASS" in log, log[-1800:]
    print(f"{protocol}: {'mutant caught' if protocol=='DMX_NEG' else 'pass'}, {len(writes)} exact bus writes",
          flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("protocol", nargs="+", choices=PROTOCOLS)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--iverilog", default="iverilog")
    parser.add_argument("--vvp", default="vvp")
    parser.add_argument("--sram", action="store_true")
    parser.add_argument("--sram-models", type=Path)
    parser.add_argument("--mapped", type=Path)
    parser.add_argument("--pdk-cells", type=Path)
    parser.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    with (THIS / "dmx_frozen_p5.csv").open() as stream:
        edges = [(int(row["core_cycle"]),int(row["p5"])) for row in csv.DictReader(stream)][1:]
    assert len(edges)==392
    (args.output / "dmx_reference.txt").write_text("".join(f"{cycle-edges[0][0]} {bit}\n"
                                                          for cycle,bit in edges))
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        list(pool.map(lambda protocol:run(protocol,args),args.protocol))


if __name__ == "__main__":
    main()
