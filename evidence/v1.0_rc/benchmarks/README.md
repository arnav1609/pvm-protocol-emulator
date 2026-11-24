# Stage 6 architecture benchmarks

These scripts and logs come from the Stage 06–07 owner handoff. The
benchmarks run on frozen RTL at `b33a9227ac187f791a3733b94ac4e32879b10414`.
They use a 50 MHz simulated core and the frozen benches and toolchain.
F1 and F2 load their programs through the production SPI pins. M1 adds
oracle checks to a temporary copy of the monitor bench.

| Study | Reproduction script | Archived output |
| --- | --- | --- |
| F1 arbitration guard | [f1_i2c.py](f1_i2c.py) | [24 cases across two configurations and six dividers](f1-validated.log) |
| F2 Manchester | [f2_manchester.py](f2_manchester.py) | [Absolute edge cycles, decoded verdicts and waveform-write counts](f2-manchester.log) |
| M1 timing monitor | [monitor_boundary.py](monitor_boundary.py) | [18 comparisons against the integer oracle plus 24 existing checks](monitor-boundary.log) |

Run from the release source root with Git, Python 3 and Icarus Verilog
12.0 (`iverilog` and `vvp` on PATH).

```sh
set -euo pipefail
study="$PWD/evidence/v1.0_rc/benchmarks"
work=$(mktemp -d)
frozen="$work/frozen"
git worktree add --detach "$frozen" b33a9227ac187f791a3733b94ac4e32879b10414
python3 "$study/f1_i2c.py" "$frozen" | tee "$work/f1.log"
python3 "$study/f2_manchester.py" "$frozen" | tee "$work/f2.log"
python3 "$study/monitor_boundary.py" "$frozen" | tee "$work/m1.log"
git worktree remove "$frozen"
```

F1 uses an ideal open-drain target. F2 aligns the two traces at the
first expected transition and compares the eight-bit payload. The
fabric trace also records an underrun after the payload. F1 and F2
contain no board-level electrical measurements. M1 evaluates digital
event intervals at the configured rule boundaries. Its temporary test
adds 18 comparisons without changing the frozen regression list.

The [360-case arbitration sweep](arbitration_results_b33a922.txt) is the
separate owner verification of the D-001 regression. The [source
identity record](source-identity.log) accompanies the original runs.
[Routed variant measurements](../../../results/v1.0_routed.md) · [Manuscript](../../../docs/MANUSCRIPT.md)
