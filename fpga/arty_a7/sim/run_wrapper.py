"""Replay all five frozen loads through the real wrapper UART and compare pad traces."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import io
import json
import os
from pathlib import Path
import subprocess
import sys
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from compare_capture import compare, DEFAULT_HANDOFF


def frames_for(image, results):
    rows = []
    def frame(data, checks=()):
        rows.append(" ".join((str(len(data)), *(f"{b:02x}" for b in data),
                   *map(str, [-1] * (len(data) - len(checks)) + list(checks)))))
    def write(addr, data):
        frame([2, addr >> 8, addr & 255, *data])
    def read(addr, checks):
        frame([3, addr >> 8, addr & 255, 0, *([0] * len(checks))], checks)
    def run(oracle, limit):
        frame([0x9f, 0, 0, 0, 0], [0, 0x50, 0x56, 0x4d, 0x21])
        write(0xf00, [1])
        write(0xf00, [4])
        pending = []
        for addr, data in image["writes"]:
            if not pending or addr != pending[-1][0] + 1:
                if pending:
                    write(pending[0][0], [b for _, b in pending])
                pending = []
            pending.append((addr, data))
        if pending:
            write(pending[0][0], [b for _, b in pending])
        read(0xf06, [image["crc16"] & 255, image["crc16"] >> 8])
        write(0xf08, [image["crc16"] & 255, image["crc16"] >> 8])
        write(0xf00, [2])
        read(0xf01, [0x42])
        read(0xf20, bytes.fromhex(oracle["image_id"]))
        for b in image["tx_preload"]:
            write(0xf10, [b])
        rows.append(f"-2 {limit}")
        write(0xf00, [3])
        rows.append("-3")
        o = oracle["status"]
        read(0xf01, [o["status"], o["fault_code"], o["fault_pc"]])
        read(0xf12, [oracle["fifo_stat"]])
        read(0xf0b, [oracle["flags"]])
        read(0x330, [0] * 7)
        read(0xfa0, [0])
    rows.append("-1")
    for oracle, limit in results:
        run(oracle, limit)
    return "\n".join(rows) + "\n"


def test_case(task):
    protocol, demo, limit, args, binary = task
    folder = args.output / protocol
    folder.mkdir(parents=True, exist_ok=True)
    with ZipFile(DEFAULT_HANDOFF) as assets:
        image = json.loads(assets.read(f"images/{demo}/image.json"))
        names = ["run_1_readback.json", "run_2_readback.json"] if protocol == "dmx512" else ["readback.json"]
        expected = [(json.loads(assets.read(f"evidence/{demo}/{name}")), limit) for name in names]
    (folder / "frames.txt").write_text(frames_for(image, expected), encoding="ascii")
    with (folder / "simulation.log").open("w") as log:
        subprocess.run([args.vvp, str(binary), f"+fixture={int(protocol == 'i2c')}"],
                       cwd=folder, stdout=log, stderr=subprocess.STDOUT, timeout=900, check=True)
    if "PASS UART_TO_SPI" not in (folder / "simulation.log").read_text():
        raise RuntimeError(f"Missing simulation verdict for {protocol}")
    traces = [folder / f"capture_{n}.csv" for n in range(1, 1+len(expected))]
    for result in compare(protocol, traces, DEFAULT_HANDOFF, 50_000_000, {}, "fixture"):
        print(f"PASS {protocol}: {result}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iverilog", default="iverilog")
    parser.add_argument("--vvp", default="vvp")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--protocol", choices=("uart", "spi", "i2c", "dmx512"), action="append")
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    binary = args.output / "wrapper.vvp"
    ordered = (ROOT / "freeze/handoff/src-order.txt").read_text().splitlines()
    subprocess.run([args.iverilog, "-g2012", "-DSIM", "-s", "tb_pvm_arty_top", "-o", str(binary),
                    str(ROOT / "sim/tb_pvm_arty_top.v"),
                    *[str(ROOT / "freeze" / name) for name in ordered],
                    *[str(p) for p in sorted((ROOT / "rtl").glob("*.v"))]], check=True)
    subprocess.run([args.vvp, str(binary), "+probe_only=1"], check=True, timeout=20)
    cases = [("uart", "uart_tx", 45000), ("spi", "spi_mode0", 45000),
             ("i2c", "i2c_write", 45000), ("dmx512", "dmx512_tx", 170000)]
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        list(pool.map(test_case, [(p, d, t, args, binary) for p, d, t in cases
                                if not args.protocol or p in args.protocol]))


if __name__ == "__main__":
    main()
