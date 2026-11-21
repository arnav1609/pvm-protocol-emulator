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
baseline. Run 44862976826 built `1a258a16c0f9891c55f01ba076ea7a8a9f68c09e`
with LibreLane 3.1.0.dev4 and PDK `89d42ee6d2fd9b50b86a1aada6fee6673c3e6008`.
The routed timing and utilization criteria pass. Tiny Tapeout precheck
is still running.
[Candidate workflow](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44862976826) · [S14 baseline](ci_S14.md)

| Check | Candidate result |
| --- | --- |
| GDS | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44862976826/job/136720282422) |
| Tiny Tapeout precheck | [Running](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44862976826/job/136742889835) |
| Gate-level SPI smoke | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44862976826/job/136742889831) |
| GitHub Pages viewer deployment | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44862976826/job/136742889818) |

| Routed metric at 50 MHz | S14 baseline | D-017/D-018 candidate |
| --- | ---: | ---: |
| Overall utilization, `design__instance__utilization` | 33.7187% | 30.9084% |
| Standard-cell utilization, `design__instance__utilization__stdcell` | 33.7187% | 30.9084% |
| Standard cells | 28,091 | 24,974 |
| Standard-cell area | 407,380 µm² | 373,427 µm² |
| Slow setup slack, 1.08 V / 125 °C | +2.461 ns | +2.206 ns |
| Typical setup slack, 1.20 V / 25 °C | +7.482 ns | +8.782 ns |
| Fast setup slack, 1.32 V / −40 °C | +10.476 ns | +12.639 ns |
| Worst hold slack | +0.122 ns | +0.108 ns |
| Setup and hold total negative slack | 0 ns each | 0 ns each |
| Detailed routing violations | 0 | 0 |

Both utilization measures fell by 2.8103 percentage points. The
slow-corner setup slack meets the +1.0 ns requirement and is 0.255 ns
below baseline, within the allowed 0.5 ns drop. The final metrics JSON
and the submission metrics CSV agree.
[Machine-readable comparison](../evidence/opt/routed_metrics.json) · [Routed reports](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44862976826/artifacts/14693537379) · [Netlist and submission](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44862976826/artifacts/14694105704)

UART, SPI, and I²C passed a functional replay of the candidate routed
netlist with Icarus 13.0 and the pinned PDK cell models. The replay used
functional models without delay annotation. The Pages OASIS matches the
candidate submission OASIS byte for byte.
[Netlist protocol replays](../evidence/opt/gate_protocols.log) · [Published layout](https://arnav1609.github.io/pvm-protocol-emulator/)

GitHub's toolchain/RTL test and datasheet workflows passed for the same
revision. [Test CI](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44862976810) · [Datasheet CI](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44862976814)

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
