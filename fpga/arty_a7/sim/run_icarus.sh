#!/usr/bin/env bash
set -euo pipefail
overlay=$(cd "$(dirname "$0")/.." && pwd)
python3 -B "$overlay/scripts/verify_sources.py"
iv=${IVERILOG:-iverilog}
vv=${VVP:-vvp}
for tool in "$iv" "$vv"; do
    version=$("$tool" -V 2>&1) || true
    [[ $version =~ Icarus[[:space:]]Verilog([[:space:]]runtime)?[[:space:]]version[[:space:]]([0-9]+)\. ]]
    (( BASH_REMATCH[2] >= 12 ))
done
python3 -B "$overlay/sim/run_wrapper.py" --iverilog "$iv" --vvp "$vv" "$@"
