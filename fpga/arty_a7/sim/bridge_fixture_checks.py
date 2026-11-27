"""Run the FPGA UART bridge and I2C fixture checks and their named mutants."""
import re
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CASES = (
    ("bridge", "uart_spi_bridge", 9, (
        ("mutant", (("{miso_shift[6:0], spi_miso}",
                     "{miso_shift[6:0], (bit_index == 0 ? 1'b0 : spi_miso)}"),), "BRIDGE_MISO"),
    )),
    ("fixture", "i2c_target_fixture", 4, (
        ("mutant", (("incoming == 8'ha0", "incoming == 8'ha2"),), "FIXTURE_ACK"),
        ("mutant_ack_gap", (
            ("sda_low <= matches_demo_byte;", ""),
            ("ACK_SETUP: if (scl_fall) begin",
             "ACK_SETUP: if (scl_fall) begin\n                        sda_low <= acknowledge;"),
        ), "FIXTURE_ACK_GAP"),
    )),
)


def run() -> None:
    logs = ROOT / "results"
    logs.mkdir(exist_ok=True)
    for bench, rtl_file, count, mutants in CASES:
        rtl = ROOT / "rtl" / f"{rtl_file}.v"
        testbench = ROOT / "sim" / f"tb_{bench}.v"
        source = rtl.read_text(encoding="utf-8")
        with tempfile.TemporaryDirectory(prefix="pvm_bridge_") as temporary:
            work = Path(temporary)
            staged = work / rtl.name
            executable = work / f"{bench}.vvp"
            for variant, edits, failing_check in (("positive", (), None), *mutants):
                data = source
                for original, mutant in edits:
                    if data.count(original) != 1:
                        raise RuntimeError(f"Expected one {variant} anchor in {rtl.name}")
                    data = data.replace(original, mutant)
                staged.write_text(data, encoding="utf-8")
                command = [
                    "iverilog", "-Wall", "-g2005", "-s", f"tb_{bench}",
                    "-o", str(executable), str(testbench), str(staged),
                ]
                compile_result = subprocess.run(command, capture_output=True, text=True, check=False)
                log = logs / f"{bench}_{variant}.log"
                evidence = compile_result.stdout + compile_result.stderr
                log.write_text(evidence, encoding="utf-8")
                compile_result.check_returncode()
                simulation = subprocess.run(
                    ["vvp", str(executable)], capture_output=True, text=True, timeout=120, check=False,
                )
                evidence += simulation.stdout + simulation.stderr
                log.write_text(evidence, encoding="utf-8")
                verdict = f"RESULT PASS CHECKS {count}"
                if variant == "positive":
                    simulation.check_returncode()
                    if verdict not in evidence or len(re.findall(r"^PASS ", evidence, re.M)) != count:
                        raise RuntimeError(f"{bench} failed frozen checks, see {log}")
                    print(f"PASS_FRESH {bench}: {count} checks")
                else:
                    failures = re.findall(r"^FAIL (\w+) ", evidence, re.M)
                    if simulation.returncode == 0 or failures != [failing_check] or verdict in evidence:
                        raise RuntimeError(f"{bench} mutant survived or failed the wrong check, see {log}")
                    print(f"NEG_KILLED {bench}: {failing_check}")


if __name__ == "__main__":
    run()
