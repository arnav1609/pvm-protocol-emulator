# PVM D-017 and D-018 pre-freeze candidate

The candidate was prepared on `opt/area-o1b-o4` from `9d12d97`.
The two optimization patches match both source hashes in the handoff.
D-017 adds a two-flop reset release synchronizer. D-018 changes monitor
and engine combinational logic and the monitor's source history.
[Reset contract](../spec/rev/PVM-IF-D017-RESET-RELEASE.md) · [Area decision and gates](../spec/rev/PVM-AREA-D018.md)

## Local verification

| Gate | Result |
| --- | --- |
| Frozen regression | 67/67 accepted. The 63 existing jobs retained their checks, and two reset jobs and two optimization mutants were added. |
| D-016 traces | Four candidate traces match the pre-repair baseline cycle for cycle. Golden vectors and their provenance regenerate identically. |
| O1b arithmetic proof | All 932 equivalence cells proven with original history. O2 uses the stable-selector integration invariant and its mutation test. |
| O3/O4 engine proof | All 1,298 equivalence cells proven |
| Verilator lint | Four variants passed |
| Host integration | 16 Python tests and both cocotb RTL checks passed |

S13's existing minimum-boundary mutant targets the shared comparison
of `t−M` and K. It still changes `>=` to `>` and fails only
`CHECK_MIN_PASS`, with 24 frozen checks. The new O2 mutant freezes
both affected edge checks, and the new O4 mutant freezes the four
affected shift and FIFO checks. This follows the runner's exact
expected-failure rule. The reset mutant fails the two-edge release check.

[Regression logs](../evidence/opt/regression.log) · [Golden regeneration](../evidence/opt/trace_golden.log) · [Monitor proof](../evidence/opt/equiv_mon.log) · [Engine proof](../evidence/opt/equiv_engine.log) · [Cocotb](../evidence/opt/cocotb.log)

Run the module proofs from the repository root with the baseline in
Git history and Yosys installed.

```sh
bash tb_rtl/area_opt/prove.sh monitor
bash tb_rtl/area_opt/prove.sh engine
```

## Physical gate

Use the same SG13CMOS5L target, 8×4 tiles, and 20 ns clock as the S14
baseline. Routed results are pending. The approval to prepare and test
this branch precedes Kalash's XSim and source review.
[Baseline metrics and CI](ci_S14.md)

## Variant synthesis estimates

These estimates use Yosys 0.52, ABC, and the same SG13CMOS5L typical
Liberty file and mapping flow as S14. They measure mapped standard
cells before placement, buffering, and routing.

| Variant | S14 mapped area (µm²) | D-017/D-018 mapped area (µm²) |
| --- | ---: | ---: |
| A | 262,553 | 256,759 |
| B | 274,413 | 272,672 |
| C | 305,144 | 288,168 |
| D | 320,820 | 304,340 |

Variant D's mapped estimate fell 5.1%. [Mapping provenance](../evidence/opt/mapped_area.log)
