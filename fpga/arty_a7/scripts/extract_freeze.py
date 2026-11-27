"""Pin, hash, and extract the FPGA handoff without rewriting line endings."""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
INPUTS = ROOT / "inputs"
COMMIT = "b33a9227ac187f791a3733b94ac4e32879b10414"
ARCHIVE_HASH = "f937ee045fd5d2ea2af42326fe25d2fd9ed810470ba12ea9c44adfc3ae978774"
FREEZE = "PVM_rtl-freeze_b33a922.zip"
HANDOFF = "PVM_Arty_A7_Handoff_b33a922.zip"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def checked_assets():
    raw = (INPUTS / FREEZE).read_bytes()
    if digest(raw) != ARCHIVE_HASH:
        raise ValueError("frozen ZIP SHA-256 mismatch")
    with ZipFile(INPUTS / HANDOFF) as handoff, ZipFile(io.BytesIO(raw)) as freeze:
        if freeze.comment != COMMIT.encode():
            raise ValueError("frozen ZIP commit comment mismatch")
        if handoff.read(FREEZE) != raw:
            raise ValueError("the handoff includes a different frozen ZIP")
        manifest = {}
        for row in handoff.read("SHA256SUMS.txt").decode("utf-8").splitlines():
            checksum, name = row.split(maxsplit=1)
            name = name.removeprefix("./")
            if digest(handoff.read(name)) != checksum or name in manifest:
                raise ValueError(f"handoff manifest mismatch: {name}")
            manifest[name] = checksum
        ordered = handoff.read("src-order.txt").decode().splitlines()
        if len(ordered) != 16 or len(set(ordered)) != 16:
            raise ValueError("expected 16 unique sources in Arnav's order")
        if any(len(PurePosixPath(name).parts) != 2 or
               PurePosixPath(name).parts[0] != "src" or not name.endswith(".v")
               for name in ordered):
            raise ValueError("unsafe or unexpected source path")
        prefixes = {p.split("/")[0] for p in freeze.namelist()}
        if len(prefixes) != 1:
            raise ValueError("unexpected Git archive root")
        prefix = prefixes.pop()
        sources = {name: freeze.read(f"{prefix}/{name}") for name in ordered}
        assets = {name: handoff.read(name) for name in manifest if name != FREEZE}
    return sources, assets


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "freeze")
    args = parser.parse_args()
    sources, assets = checked_assets()
    target = args.output
    if target.exists():
        raise SystemExit(f"refusing to overwrite existing extraction: {target}")
    target.mkdir(parents=True)
    for name, data in sources.items():
        path = target / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    for name, data in assets.items():
        relative = PurePosixPath(name)
        if relative.is_absolute() or ".." in relative.parts or "\\" in name or ":" in name:
            raise ValueError(f"unsafe handoff asset: {name}")
        path = target / "handoff" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    (target / "source_manifest.json").write_text(json.dumps({
        "commit": COMMIT, "archive_sha256": ARCHIVE_HASH,
        "sources": {name: digest(data) for name, data in sources.items()},
    }, indent=2) + "\n", encoding="utf-8")
    print(f"PASS extract {COMMIT}: {len(sources)} frozen sources, {len(assets)} handoff assets")


if __name__ == "__main__":
    main()
