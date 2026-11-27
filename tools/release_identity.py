"""Compare release inputs with the routed PVM source commit."""

import argparse
from dataclasses import dataclass
import hashlib
from importlib import metadata
import io
from pathlib import Path
import platform
import re
import subprocess
import sys


BASELINE = "752ebb97824cfd1161581497c22d3c171c4c6ca9"
PROTECTED_PATHS = ("src", "info.yaml", "test", "tb_rtl", "tools")
PYTHON_VERSION = re.compile(r"3\.12\.[0-9]+\Z")
ICARUS_COMPILER = re.compile(r"^Icarus Verilog version (\S+)", re.MULTILINE)
ICARUS_RUNTIME = re.compile(r"^Icarus Verilog runtime version (\S+)", re.MULTILINE)
VERILATOR = re.compile(r"^Verilator (\S+)", re.MULTILINE)


class GitError(Exception):
    """A Git input could not be read or interpreted."""


@dataclass(frozen=True)
class GitFile:
    mode: str
    kind: str
    object_id: bytes


@dataclass(frozen=True)
class ToolVersion:
    name: str
    expected: str
    detected: str
    matches: bool


def git(repo, *arguments, stdin=None):
    """Use original Git objects even when the repository has replace refs."""
    try:
        result = subprocess.run(
            ["git", "--no-replace-objects", "-C", str(repo), *arguments],
            input=stdin,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
            check=True,
        )
    except subprocess.CalledProcessError as error:
        message = error.stderr.decode("utf-8", errors="replace").strip()
        raise GitError(message or f"git {arguments[0]} failed") from error
    except (OSError, subprocess.TimeoutExpired) as error:
        raise GitError(f"git {arguments[0]}: {error}") from error
    return result.stdout


def resolve_commit(repo, revision):
    try:
        return git(
            repo, "rev-parse", "--verify", "--end-of-options", f"{revision}^{{commit}}"
        ).decode("ascii").strip()
    except GitError as error:
        raise GitError(f"Cannot resolve commit {revision!r}: {error}") from error


def list_files(repo, commit):
    entries = git(repo, "ls-tree", "-r", "-z", "--full-tree", commit, "--", *PROTECTED_PATHS)
    files = {}
    for entry in entries.split(b"\0")[:-1]:
        header, path = entry.split(b"\t", maxsplit=1)
        mode, kind, object_id = header.split()
        if path in files:
            raise GitError(f"Commit {commit} contains a repeated path {path!r}")
        files[path] = GitFile(mode.decode("ascii"), kind.decode("ascii"), object_id)
    return files


def hash_blobs(repo, *inventories):
    """Read raw committed bytes and hash each distinct blob once."""
    object_ids = sorted({
        entry.object_id for files in inventories for entry in files.values()
        if entry.kind == "blob"
    })
    if not object_ids:
        return {}

    batch_input = b"\n".join(object_ids) + b"\n"
    batch_output = io.BytesIO(git(repo, "cat-file", "--batch", stdin=batch_input))
    digests = {}
    for object_id in object_ids:
        header = batch_output.readline().split()
        if len(header) != 3 or header[:2] != [object_id, b"blob"]:
            raise GitError(f"Cannot read Git blob {object_id.decode('ascii')}")
        try:
            size = int(header[2])
        except ValueError as error:
            raise GitError(f"Invalid size for Git blob {object_id.decode('ascii')}") from error
        if size < 0:
            raise GitError(f"Invalid size for Git blob {object_id.decode('ascii')}")
        data = batch_output.read(size)
        if len(data) != size or batch_output.read(1) != b"\n":
            raise GitError(f"Incomplete Git blob {object_id.decode('ascii')}")
        digests[object_id] = hashlib.sha256(data).hexdigest()
    if batch_output.read(1):
        raise GitError("Unexpected data after Git blob batch")
    return digests


def command_version(command, version_pattern):
    try:
        result = subprocess.run(
            command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, encoding="utf-8", errors="replace", timeout=10, check=True,
        )
    except FileNotFoundError:
        return "missing from PATH"
    except subprocess.TimeoutExpired:
        return "version probe timed out"
    except subprocess.CalledProcessError as error:
        return f"version probe exited {error.returncode}"
    except OSError as error:
        return f"version probe failed ({error.strerror})"
    match = version_pattern.search(result.stdout)
    return match.group(1) if match else "unrecognized version output"


def tool_versions(profile):
    icarus_version = "13.0" if profile == "routed" else "12.0"
    python_version = platform.python_version()
    try:
        cocotb_version = metadata.version("cocotb")
    except metadata.PackageNotFoundError:
        cocotb_version = "missing in this Python environment"

    versions = (
        ("iverilog", icarus_version, command_version(["iverilog", "-V"], ICARUS_COMPILER)),
        ("vvp", icarus_version, command_version(["vvp", "-V"], ICARUS_RUNTIME)),
        ("cocotb", "2.0.1", cocotb_version),
        ("Verilator", "5.032", command_version(["verilator", "--version"], VERILATOR)),
    )
    tools = [ToolVersion("Python", "3.12.x", python_version, bool(PYTHON_VERSION.fullmatch(python_version)))]
    tools.extend(ToolVersion(name, expected, detected, detected == expected) for name, expected, detected in versions)
    return tools


def code_cell(value):
    if isinstance(value, bytes):
        value = value.decode("utf-8", errors="surrogateescape")
    safe = value.replace("\\", "\\\\").encode("ascii", errors="backslashreplace").decode("ascii")
    safe = re.sub(r"[\x00-\x1f\x7f`|]", lambda match: f"\\x{ord(match.group()):02x}", safe)
    return f"`{safe}`"


def file_details(entry, digests):
    if entry is None:
        return "-", "-"
    if entry.kind == "blob":
        return entry.mode, digests[entry.object_id]
    return entry.mode, f"{entry.kind} {entry.object_id.decode('ascii')} (no blob)"


def print_report(release, profile, baseline_files, release_files, digests, tools):
    rows = []
    for path in sorted(baseline_files.keys() | release_files.keys()):
        before = file_details(baseline_files.get(path), digests)
        after = file_details(release_files.get(path), digests)
        if path not in baseline_files:
            status = "ADDED"
        elif path not in release_files:
            status = "REMOVED"
        else:
            status = "MATCH" if before == after else "CHANGED"
        rows.append((path, *before, *after, status))

    differences = sum(row[-1] != "MATCH" for row in rows)
    failures = sum(not tool.matches for tool in tools)
    passed = differences == failures == 0
    verdict = "PASS" if passed else "FAIL"
    print("# Release identity\n")
    print(f"- **Result:** {verdict}")
    print(f"- Routed baseline `{BASELINE}`")
    print(f"- Release `{release}`")
    print(f"- Runtime profile `{profile}`")
    print(f"- Protected paths {len(baseline_files)} baseline, {len(release_files)} release, {differences} differences")
    print(f"- Runtime tools {len(tools) - failures}/{len(tools)} matched\n")
    print("## Runtime tools\n")
    print("| Tool | Expected | Detected | Status |")
    print("| --- | --- | --- | --- |")
    for tool in tools:
        status = "MATCH" if tool.matches else "FAIL"
        print(f"| {tool.name} | {code_cell(tool.expected)} | {code_cell(tool.detected)} | {status} |")
    print("\n## Protected files\n")
    print("| Path | Baseline mode | Baseline SHA-256 | Release mode | Release SHA-256 | Status |")
    print("| --- | --- | --- | --- | --- | --- |")
    for path, before_mode, before_hash, after_mode, after_hash, status in rows:
        print(
            f"| {code_cell(path)} | {before_mode} | {before_hash} | "
            f"{after_mode} | {after_hash} | {status} |"
        )
    return 0 if passed else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("release", help="Git commit or ref to check")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--profile", choices=("routed", "rtl"), default="routed")
    args = parser.parse_args()

    try:
        release = resolve_commit(args.repo, args.release)
        baseline_files = list_files(args.repo, resolve_commit(args.repo, BASELINE))
        release_files = list_files(args.repo, release)
        digests = hash_blobs(args.repo, baseline_files, release_files)
    except GitError as error:
        print(f"Release identity error: {error}", file=sys.stderr)
        return 2

    return print_report(
        release, args.profile, baseline_files, release_files, digests, tool_versions(args.profile)
    )


if __name__ == "__main__":
    sys.exit(main())
