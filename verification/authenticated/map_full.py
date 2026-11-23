"""Map the frozen and trusted-input PVM tops with one IHP Liberty flow."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import json
import re
import shutil
import subprocess


MACRO = "RM_IHPSG13_1P_64x64_c2_bm_bist"
BASE = "b33a9227ac187f791a3733b94ac4e32879b10414"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--liberty", required=True, type=Path)
    parser.add_argument("--macro-liberty", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--yosys", default="yosys")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(args.liberty, out / "cells.lib")
    shutil.copyfile(args.macro_liberty, out / "macro.lib")
    frozen_info = subprocess.check_output(["git", "show", f"{BASE}:info.yaml"], cwd=repo, text=True)
    source_pattern = r'^\s*- "(\w+\.v)"$'
    source_names = re.findall(source_pattern, frozen_info, re.M)
    frozen = out / "frozen"
    frozen.mkdir(exist_ok=True)
    for name in source_names:
        data = subprocess.check_output(["git", "show", f"{BASE}:src/{name}"], cwd=repo)
        (frozen / name).write_bytes(data)
    active = [repo / "src" / name for name in re.findall(source_pattern, (repo / "info.yaml").read_text(), re.M)]

    def build(variant):
        baseline = variant == "frozen"
        macro = variant == "sram"
        top = "pvm_top"
        sources = sorted(frozen.glob("*.v")) if baseline else active
        defines = "" if baseline else "-DPVM_AUTH "
        if macro:
            defines += "-DPVM_KECCAK_IHP_SRAM "
        script = ["read_liberty -lib cells.lib"]
        if macro:
            script.append("read_liberty -lib macro.lib")
        script += [
            "read_verilog " + defines + " ".join(json.dumps(str(p)) for p in sources),
            "setattr -set keep 1 pvm_top/w:bus_we pvm_top/w:bus_re "
            "pvm_top/w:bus_rack pvm_top/w:bus_addr pvm_top/w:bus_wdata",
            f"synth -top {top} -flatten -noabc",
            "dfflibmap -liberty cells.lib",
            "abc -liberty cells.lib",
            "clean",
            "check -assert",
            f"tee -o {variant}.json stat -json -liberty cells.lib",
            f"write_verilog -noattr -noexpr -nodec {variant}.v",
        ]
        with (out / f"{variant}.log").open("w") as log:
            subprocess.run([args.yosys, "-Q", "-p", "; ".join(script)], cwd=out,
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        stats = json.loads((out / f"{variant}.json").read_text())["design"]
        count = stats["num_cells_by_type"].get(MACRO, 0)
        assert count == int(macro), stats
        macro_area = count * float(re.search(r"\barea\s*:\s*([0-9.]+)",
                                            (out / "macro.lib").read_text())[1])
        return {
            "variant": variant,
            "std_cell_area_um2": stats["area"],
            "macro_area_um2": macro_area,
            "total_area_um2": stats["area"] + macro_area,
            "macro_count": count,
            "cell_count": sum(v for k, v in stats["num_cells_by_type"].items()
                              if k.startswith("sg13cmos5l_")),
        }

    with ThreadPoolExecutor(max_workers=2) as pool:
        summary = list(pool.map(build, ("frozen", "inferred", "sram")))
    functions = out / "functions"
    functions.mkdir(exist_ok=True)
    cells = json.loads((out / "sram.json").read_text())["design"]["num_cells_by_type"]
    used = " ".join(sorted(name for name in cells if name.startswith("sg13cmos5l_")))
    script = ("read_liberty -ignore_miss_func -ignore_miss_dir cells.lib; "
              f"select {used}; write_verilog -selected -noattr functions/ihp_functional.v")
    with (out / "functions.log").open("w") as log:
        subprocess.run([args.yosys, "-Q", "-p", script], cwd=out, stdout=log,
                       stderr=subprocess.STDOUT, check=True)
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
