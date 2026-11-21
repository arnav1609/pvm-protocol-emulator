#!/usr/bin/env bash
# Reproduce the two D-018 module proofs against the pre-optimization RTL.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
cd "$root"
proof=tb_rtl/area_opt
baseline=9d12d97c7b155bc0412ff56f31c8ec9f5737932c
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

case "${1:-}" in
    monitor)
        module=pvm_mon
        blacklist="$proof/blacklist_mon_O1b.txt"
        deps="src/pvm_presc.v"
        # Per-entry history is justified by the stable configuration invariant.
        # Restore the original history here to prove the arithmetic in isolation.
        cp src/pvm_mon.v "$scratch/gate.v"
        patch --reverse --force --silent "$scratch/gate.v" "$proof/monitor_history.patch"
        ;;
    engine)
        module=pvm_engine
        blacklist="$proof/blacklist_engine_O3_O4.txt"
        deps="src/pvm_tick.v src/pvm_presc.v"
        cp src/pvm_engine.v "$scratch/gate.v"
        ;;
    *)
        printf 'Usage: %s monitor|engine\n' "$0" >&2
        exit 2
        ;;
esac

git show "$baseline:src/$module.v" > "$scratch/gold.v"
printf 'D-018 %s at baseline %s\n' "$module" "$baseline"
yosys -V
timeout 600 yosys -Q -T -p "
    read_verilog $deps $scratch/gold.v
    prep -flatten -top $module
    rename $module gold
    design -stash gold
    read_verilog $deps $scratch/gate.v
    prep -flatten -top $module
    rename $module gate
    design -stash gate
    design -copy-from gold -as gold gold
    design -copy-from gate -as gate gate
    equiv_make -blacklist $blacklist gold gate eq
    hierarchy -top eq
    equiv_simple -seq 4
    equiv_induct -seq 4
    equiv_status -assert
"
