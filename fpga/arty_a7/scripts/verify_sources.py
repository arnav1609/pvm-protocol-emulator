"""Compare the actual build source bytes with the independently pinned ZIP."""
import argparse
import json
from pathlib import Path
from extract_freeze import ARCHIVE_HASH, COMMIT, ROOT, checked_assets, digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=ROOT / "freeze")
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    root = args.source_dir.resolve()
    sources, _ = checked_assets()
    expected = {name: digest(data) for name, data in sources.items()}
    saved = json.loads((root / "source_manifest.json").read_text(encoding="utf-8"))
    if saved != {"commit": COMMIT, "archive_sha256": ARCHIVE_HASH, "sources": expected} or (
        list(saved["sources"]) != list(expected)
    ):
        raise SystemExit("frozen source manifest mismatch")
    for name, check in expected.items():
        path = root / name
        if not path.is_file() or digest(path.read_bytes()) != check:
            raise SystemExit(f"frozen source SHA-256 mismatch: {name}")
        if args.list:
            print(path.as_posix())
    if not args.list:
        print(f"PASS verified all {len(sources)} frozen source bytes and build order at {COMMIT}")


if __name__ == "__main__":
    main()
