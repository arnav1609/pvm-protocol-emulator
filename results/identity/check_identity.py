"""Run the frozen A3 checks with installed tools on a POSIX host."""

import argparse
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory


ROUTED = "752ebb97824cfd1161581497c22d3c171c4c6ca9"
RC = "e1018ff505ae4e2b2d8c0ee1f4753083b8e97e0c"
REVIEW = "0d2978a47e5e854d6881714b6bed72cc6ec72053"
UNKNOWN = "refs/heads/a3-frozen-ref-that-does-not-exist"
RTL_PATH = "src/project.v"
TOOL_NAMES = ("Python", "iverilog", "vvp", "cocotb", "Verilator")
FILE_STATES = ("MATCH", "ADDED", "REMOVED", "CHANGED")
MATRIX_EXTRAS = {
    f"tools/examples/matrix/{name}"
    for name in (
        "i2c_100k.json", "i2c_400k.json", "i2c_400k.pvm",
        "ps2_rx.json", "ps2_rx.pvm", "spi_mode1.json", "spi_mode1.pvm",
        "spi_mode2.json", "spi_mode2.pvm", "spi_mode3.json", "spi_mode3.pvm",
        "ws2812b_tx.json", "ws2812b_tx.pvm",
    )
}
SCRIPT_ROOT = Path(__file__).resolve().parents[2]
TIMEOUT_SECONDS = 60


def git(repo, *args, input_bytes=None, env=None):
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
        env=env,
        timeout=TIMEOUT_SECONDS,
    ).stdout


def scratch_mutant(repo, scratch):
    git(repo, "clone", "--quiet", "--shared", "--no-checkout", str(repo), str(scratch))
    original = git(scratch, "show", f"{ROUTED}:{RTL_PATH}")
    modified = bytes((original[0] ^ 1,)) + original[1:]
    blob = git(scratch, "hash-object", "-w", "--stdin", input_bytes=modified).decode().strip()
    git(scratch, "read-tree", ROUTED)
    git(scratch, "update-index", "--cacheinfo", f"100644,{blob},{RTL_PATH}")
    tree = git(scratch, "write-tree").decode().strip()
    date = git(scratch, "show", "-s", "--format=%cI", ROUTED).decode().strip()
    author = os.environ.copy()
    for role in ("AUTHOR", "COMMITTER"):
        author[f"GIT_{role}_NAME"] = "PVM A3 scratch"
        author[f"GIT_{role}_EMAIL"] = "pvm-a3@example.invalid"
        author[f"GIT_{role}_DATE"] = date
    ref = git(
        scratch, "commit-tree", tree, "-p", ROUTED,
        "-m", "A3 negative control: change one project.v blob byte", env=author,
    ).decode().strip()
    git(scratch, "update-ref", "refs/heads/a3-frozen-mutant", ref)
    if git(scratch, "diff", "--name-only", ROUTED, ref).decode().splitlines() != [RTL_PATH]:
        raise ValueError("Scratch commit did not change exactly src/project.v")
    if git(scratch, "show", f"{ref}:{RTL_PATH}") != modified:
        raise ValueError("Scratch commit did not preserve the expected one-byte mutation")
    return ref


def with_tools(*bin_dirs):
    env = os.environ.copy()
    env["PYTHON"] = sys.executable
    env["PATH"] = os.pathsep.join((*map(str, bin_dirs), env["PATH"]))
    return env


def without_verilator(env, shim):
    shim.mkdir()
    for name in ("git", "iverilog", "vvp"):
        tool = shutil.which(name, path=env["PATH"])
        if tool is None:
            raise ValueError(f"{name} is required to create the reduced PATH")
        (shim / name).symlink_to(tool)
    return {**env, "PATH": str(shim)}


def cli(repo, ref, profile, launcher):
    if launcher == "bash":
        command = ["bash", str(SCRIPT_ROOT / "tools/release_identity.sh")]
    else:
        command = [sys.executable, str(SCRIPT_ROOT / "tools/release_identity.py")]
    return [*command, ref, "--repo", str(repo), "--profile", profile]


def markdown_rows(text):
    return [
        [part.strip().strip("`") for part in line.strip("|").split("|")]
        for line in text.splitlines()
        if line.startswith("|")
    ]


def read_protected_paths(rows):
    files = {state: [] for state in FILE_STATES}
    for row in rows:
        for state in FILE_STATES:
            if state in row:
                path = next((cell for cell in row if cell.startswith(
                    ("src/", "tb_rtl/", "test/", "tools/")) or cell == "info.yaml"), None)
                if path is not None:
                    files[state].append(path)
    return files


def validate(test_id, exit_code, stdout, stderr):
    if test_id == "R10":
        if exit_code != 2 or UNKNOWN not in stderr or stdout:
            return f"expected exit 2 and the unresolved ref on stderr, observed exit {exit_code}"
        return None

    expected_exit = 0 if test_id in {"R01", "R02", "R03", "R04"} else 1
    expected_result = "PASS" if expected_exit == 0 else "FAIL"
    if exit_code != expected_exit or f"**Result:** {expected_result}" not in stdout:
        return f"expected exit {expected_exit} and {expected_result}, observed exit {exit_code}"
    rows = markdown_rows(stdout)
    paths = read_protected_paths(rows)
    expected_counts = {
        "MATCH": 82 if test_id == "R06" else 83,
        "ADDED": 13 if test_id == "R05" else 0,
        "REMOVED": 0,
        "CHANGED": 1 if test_id == "R06" else 0,
    }
    counts = {state: len(entries) for state, entries in paths.items()}
    if counts != expected_counts:
        return f"expected path counts {expected_counts}, observed {counts}"
    if test_id == "R05" and set(paths["ADDED"]) != MATRIX_EXTRAS:
        return "added paths differ from the 13 frozen matrix fixtures"
    if test_id == "R06" and paths["CHANGED"] != [RTL_PATH]:
        return "the changed path must be src/project.v"

    bad_tools = {
        "R07": {"iverilog", "vvp"},
        "R08": {"Verilator"},
        "R09": {"Verilator"},
    }.get(test_id, set())
    icarus = "12.0" if test_id in {"R03", "R04", "R07"} else "13.0"
    expected_versions = {
        "iverilog": icarus,
        "vvp": icarus,
        "cocotb": "2.0.1",
        "Verilator": "5.020" if test_id == "R08" else "5.032",
    }
    for tool in TOOL_NAMES:
        reports = [row for row in rows if row[0] == tool]
        expected = "FAIL" if tool in bad_tools else "MATCH"
        if len(reports) != 1 or len(reports[0]) != 4 or reports[0][-1] != expected:
            return f"expected one {tool} runtime row with {expected}, observed {reports}"
        detected = reports[0][2]
        if tool == "Python":
            version_matches = re.fullmatch(r"3\.12\.\d+", detected)
        elif test_id == "R09" and tool == "Verilator":
            version_matches = re.search(r"missing|not found|absent", detected, re.IGNORECASE)
        else:
            version_matches = detected == expected_versions[tool]
        if not version_matches:
            return f"{tool} reported an unexpected version or diagnostic: {detected}"
    return None


def run_case(test_id, command, env, logs):
    log = logs / test_id
    log.mkdir()
    (log / "command.txt").write_text(
        f"PATH={env['PATH']}\nPYTHON={env['PYTHON']}\n{shlex.join(command)}\n",
        encoding="utf-8",
    )
    try:
        run = subprocess.run(command, env=env, capture_output=True, timeout=TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired as exc:
        (log / "stdout.md").write_bytes(exc.stdout or b"")
        (log / "stderr.txt").write_bytes(exc.stderr or b"")
        return f"timed out after {TIMEOUT_SECONDS} seconds"
    except OSError as exc:
        (log / "stderr.txt").write_text(str(exc), encoding="utf-8")
        return "unable to launch the release identity checker"
    (log / "stdout.md").write_bytes(run.stdout)
    (log / "stderr.txt").write_bytes(run.stderr)
    (log / "exit.txt").write_text(f"{run.returncode}\n", encoding="utf-8")
    return validate(
        test_id,
        run.returncode,
        run.stdout.decode("utf-8", errors="replace"),
        run.stderr.decode("utf-8", errors="replace"),
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True, help="Git repository with the frozen SHAs")
    parser.add_argument("--logs", type=Path, required=True, help="New directory for raw logs")
    parser.add_argument("--routed-icarus-bin", type=Path, required=True)
    parser.add_argument("--rtl-icarus-bin", type=Path, required=True)
    parser.add_argument("--verilator-bin", type=Path, required=True)
    parser.add_argument("--wrong-verilator-bin", type=Path, required=True)
    parser.add_argument("--launcher", choices=("bash", "python"), default="bash")
    args = parser.parse_args()
    repo = args.repo.resolve()
    logs = args.logs.resolve()
    logs.mkdir(parents=True)
    routed = with_tools(args.routed_icarus_bin, args.verilator_bin)
    rtl = with_tools(args.verilator_bin, args.rtl_icarus_bin)
    wrong_verilator = with_tools(args.routed_icarus_bin, args.wrong_verilator_bin)
    summary = [
        "# A3 author check results",
        "",
        "| Case | Status | Observation |",
        "| --- | --- | --- |",
    ]
    failures = 0
    with TemporaryDirectory(prefix="pvm-a3-") as temp_dir:
        temp = Path(temp_dir)
        scratch = temp / "mutant"
        mutant = scratch_mutant(repo, scratch)
        reduced = without_verilator(routed, temp / "reduced-path")
        cases = (
            ("R01", repo, ROUTED, "routed", args.launcher, routed),
            ("R02", repo, RC, "routed", args.launcher, routed),
            ("R03", repo, ROUTED, "rtl", args.launcher, rtl),
            ("R04", repo, RC, "rtl", args.launcher, rtl),
            ("R05", repo, REVIEW, "routed", args.launcher, routed),
            ("R06", scratch, mutant, "routed", args.launcher, routed),
            ("R07", repo, ROUTED, "routed", args.launcher, rtl),
            ("R08", repo, ROUTED, "routed", args.launcher, wrong_verilator),
            ("R09", repo, ROUTED, "routed", "python", reduced),
            ("R10", repo, UNKNOWN, "routed", args.launcher, routed),
        )
        for test_id, target_repo, ref, profile, launcher, env in cases:
            failure = run_case(test_id, cli(target_repo, ref, profile, launcher), env, logs)
            if failure is not None:
                failures += 1
                observation = failure.replace("|", "\\|").replace("\n", " ")
                summary.append(f"| {test_id} | FAIL | {observation} |")
            else:
                status = "PASS_FRESH" if test_id <= "R04" else "NEG_KILLED"
                summary.append(f"| {test_id} | {status} | Frozen observations matched |")
            print(summary[-1], flush=True)
    summary.extend(("", f"{len(cases) - failures}/{len(cases)} checks met the frozen expectations.", ""))
    (logs / "RUN_SUMMARY.md").write_text("\n".join(summary), encoding="utf-8")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
