#!/usr/bin/env bash
# Check the functional-model prerequisite before the archive downloads or compiles anything.
set -euo pipefail

for tool in iverilog vvp; do
    if ! command -v "$tool" >/dev/null; then
        printf 'Routed replay requires %s from Icarus Verilog 13.0 or later.\n' "$tool" >&2
        exit 2
    fi
    version=$("$tool" -V 2>&1) || true
    if ! [[ "$version" =~ Icarus[[:space:]]Verilog([[:space:]]runtime)?[[:space:]]version[[:space:]]([0-9]+)\. ]] ||
        (( BASH_REMATCH[2] < 13 )); then
        printf 'Routed replay requires Icarus Verilog 13.0 or later. Found %s: %s\n' \
            "$tool" "${version%%$'\n'*}" >&2
        exit 2
    fi
done

if [[ ${1:-} == --check-tools && $# == 1 ]]; then
    printf 'Icarus compiler and runtime meet the routed replay minimum.\n'
    exit 0
fi

if [[ $# -lt 1 || $# -gt 3 ]]; then
    printf 'Usage: %s EXTRACTED_ROUTED_BUNDLE [SOURCE_CHECKOUT] [OUTPUT_DIR]\n' "$0" >&2
    exit 2
fi
bundle=$(cd "$1" && pwd)
if [[ $# -ge 2 ]]; then
    exec bash "$bundle/replay.sh" "$2" "${3:-pvm-gate-replay}"
fi

# The immutable archive checks the exact routed bench and toolchain inputs.
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d)
cleanup() {
    if [[ -e "$scratch/source/.git" ]]; then
        git -C "$repo" worktree remove --force "$scratch/source"
    fi
    rmdir "$scratch"
}
trap cleanup EXIT
git -C "$repo" worktree add --quiet --detach "$scratch/source" 752ebb97824cfd1161581497c22d3c171c4c6ca9
bash "$bundle/replay.sh" "$scratch/source" pvm-gate-replay
