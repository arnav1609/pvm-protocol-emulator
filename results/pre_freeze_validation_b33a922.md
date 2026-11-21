# PVM D-001 freeze candidate

Candidate `b33a9227ac187f791a3733b94ac4e32879b10414` on
`codex/pvm-rtl`. All requested automated gates passed. Kalash owns the source-review verdict and
`rtl-freeze` tag on the exact candidate after sign-off.
[Candidate diff](https://github.com/arnav1609/pvm-protocol-emulator/compare/00ec783...b33a922) · [PR #1](https://github.com/arnav1609/pvm-protocol-emulator/pull/1) · [Open owner checklist](owner_review_b33a922.md)

## Arbitration regression

After SCL qualifies high, its counter still holds the old value
on the edge at which the detector sees the synchronized low
sample. On `00ec783`, simultaneous SDA and SCL falls could latch
false `ARB_LOST` and block both open-drain drive enables.
The replacement requires the current synchronized SCL sample to
be high as well as the existing high-count threshold.
[Fabric RTL](../src/pvm_fabric.v#L30) · [D-001](../spec/DECISIONS.md#d-001--f1-redefined-arbitration-loss-guard-not-sda-release) · [Fabric spec](../spec/05_FABRIC.md#5-arbitration-loss-guard-d-001)

The two new D-001 jobs froze one check each before the first run.
`arb_scl_fall` passed. Removing the SCL term caused
`arb_scl_fall_neg_stale_count` to fail only
`ARB_NO_DETECT_ON_SCL_FALL`. All 69 previous registry entries are
identical. The existing 21-check S12 fabric job still passes,
including `ARB_RELEASE_BOUND_CYCLES` for genuine loss. The
three S12 mutants and the D-016 trace mutant were caught.
[Registered jobs](../tb_rtl/pvm_jobs.json) · [D-001 and S12 logs](../evidence/pre_freeze/b33a922/d001/)

## Simulation and lint

| Gate | Result |
| --- | --- |
| Windows Icarus 12.0 | 71/71 accepted. 30 positive jobs passed and 41 mutants failed exactly their named checks. The Windows workflow verified the candidate SHA and all four golden CSV hashes with CRLF checkout enabled. [Run](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44922358383) · [Raw Actions artifact](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44922358383/artifacts/14714327163) · [71 current job logs](../evidence/pre_freeze/b33a922/windows-icarus-current-b33a922.zip) |
| Timing-enabled Verilator 5.032 | 52/52 passed across 26 distinct builds with randomized-init seeds 1 and 2. [Build and coverage map](verilator_replay_b33a922.md) · [Raw logs](../evidence/pre_freeze/b33a922/verilator/raw_logs.tar.gz) |
| Verilator `-Wall` lint | A/B/C/D pass with zero unwaived warnings. The raw inventory is identical to `00ec783` at 23/8/18/4 warning instances. [Waiver inventory](https://github.com/arnav1609/pvm-protocol-emulator/blob/c20b266/results/verilator_replay_00ec783.md#rtl-lint) |

## Tiny Tapeout

Run **44922355967** builds full variant D from
`b33a9227ac187f791a3733b94ac4e32879b10414` at 50 MHz on 8×4 tiles.
Both runs used LibreLane 3.1.0.dev4 and IHP SG13CMOS5L PDK
`89d42ee6d2fd9b50b86a1aada6fee6673c3e6008`. The flow configuration
matches `00ec783`, whose layout and metrics matched the original
`1a258a1` routed baseline. GitHub Pages serves the replacement
submission's exact OASIS bytes.
[Replacement run](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44922355967) · [Predecessor evidence](https://github.com/arnav1609/pvm-protocol-emulator/blob/c20b266/results/pre_freeze_validation_00ec783.md#tiny-tapeout) · [Submission](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44922355967/artifacts/14717262395) · [Routed reports](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44922355967/artifacts/14717307256)

| CI job | Replacement result |
| --- | --- |
| GDS | Passed. [Job](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44922355967/job/136900930230) |
| Gate-level SPI and pin-safety smoke | Passed. [Job](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44922355967/job/136925313687) · [Result and waveform](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44922355967/artifacts/14717322699) |
| Pages viewer | Passed. [Job](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44922355967/job/136925313818) · [Published layout](https://arnav1609.github.io/pvm-protocol-emulator/) |
| Tiny Tapeout precheck | 10/10 passed in 1 h 11 min 39 s. All three KLayout databases report zero violations. [Job](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44922355967/job/136925313698) · [Raw artifact](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44922355967/artifacts/14720040571) · [Verified summary](../evidence/pre_freeze/b33a922/physical/precheck_summary.json) |

| Routed variant D metric | `00ec783` | `b33a922` | Delta |
| --- | ---: | ---: | ---: |
| Overall utilization, `design__instance__utilization` | 30.9084% | 30.9734% | +0.0650 percentage points |
| Standard-cell utilization, `design__instance__utilization__stdcell` | 30.9084% | 30.9734% | +0.0650 percentage points |
| Standard cells | 24,974 | 24,863 | −111 |
| Standard-cell area | 373,427 µm² | 374,213 µm² | +786 µm² |
| Worst setup / hold total negative slack | 0 / 0 ns | 0 / 0 ns | 0 / 0 ns |
| Detailed routing violations | 0 | 0 | 0 |

| Timing corner | Baseline setup | Candidate setup | Baseline hold | Candidate hold |
| --- | ---: | ---: | ---: | ---: |
| Slow, 1.08 V / 125 °C | +2.206 ns | +3.180 ns | +0.604 ns | +0.606 ns |
| Typical, 1.20 V / 25 °C | +8.782 ns | +9.387 ns | +0.286 ns | +0.287 ns |
| Fast, 1.32 V / −40 °C | +12.639 ns | +13.002 ns | +0.108 ns | +0.108 ns |

Slow setup improved by 0.974 ns and meets the +1.0 ns floor. Hold is
positive at all three corners. Both utilization measures are below
the 33.7187% S14 baseline and 40% cap. Slow setup also exceeds
the +2.461 ns S14 reference used by D-018.
[Metric deltas and provenance](../evidence/pre_freeze/b33a922/physical/routed_comparison.json) · [Exact routed metrics CSV](../evidence/pre_freeze/b33a922/physical/metrics.csv) · [D-018 budgets](../spec/rev/PVM-AREA-D018.md)

### Routed change analysis

The new SCL qualification is the only RTL delta. The two submissions
use byte-identical `src/user_config.json` and the same clock, tile count,
PDK and flow versions. Synthesis reported 20,443 versus 20,375 mapped
cells and 311,174.627 versus 312,282.621 µm² mapped area. Both report
122,569.978 µm² of sequential cells. The changed combinational mapping
and routing account for the modest area increase despite fewer cells.

The worst slow setup path now starts at `pvm.config_bank.eng_cfg[13][2]`
(`PULL_THRESH` bit 2).
The baseline worst path started at synchronized `pvm.engine.pin_in[15]`.
Both end at `pvm.engine.set_data[1]`. The candidate's worst arrival is
17.150 ns against 20.330 ns required. The baseline's was 18.423 ns
against 20.629 ns required. The fast hold path still starts at the
first reset release stage and ends at the second stage's registered
reset output. The post-route metrics JSON and submission CSV agree.
[Baseline slow path](../evidence/pre_freeze/b33a922/physical/baseline.slow_setup.rpt) · [Candidate slow path](../evidence/pre_freeze/b33a922/physical/candidate.slow_setup.rpt) · [Resolved cell endpoints](../evidence/pre_freeze/b33a922/physical/critical_path_cells.txt) · [Synthesis report](../evidence/pre_freeze/b33a922/physical/synthesis-stats.txt)

## Open review

Kalash reviews the exact replacement candidate. Heet's independent
1-Wire and SWD model review is still open in the repository.
The fit study documents the earlier SWD launch-edge model correction
and parity mutant, and identifies the 1-Wire ideal pull-up assumption.
[Owner checklist](owner_review_b33a922.md) · [Fit study](fit_study.md)
