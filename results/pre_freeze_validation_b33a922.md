# PVM D-001 freeze candidate

Candidate `b33a9227ac187f791a3733b94ac4e32879b10414` on
`codex/pvm-rtl`. Kalash owns the source-review verdict and
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
| Windows Icarus 12.0 | Pending. Expected 71 accepted. The Windows workflow checks out the exact candidate and verifies the four golden CSV digests under normal CRLF conversion. [Run](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44922358383) |
| Timing-enabled Verilator 5.032 | Pending. 26 distinct builds, each replayed with randomized-init seeds 1 and 2. |
| Verilator `-Wall` lint | A/B/C/D pass with zero unwaived warnings. The raw inventory is identical to `00ec783` at 23/8/18/4 warning instances. [Waiver inventory](https://github.com/arnav1609/pvm-protocol-emulator/blob/c20b266/results/verilator_replay_00ec783.md#rtl-lint) |

## Tiny Tapeout

Run **44922355967** builds variant D from the replacement SHA on
8×4 IHP SG13CMOS5L tiles at 50 MHz. GDS, precheck, gate-level SPI smoke,
and Pages deployment are pending. Compare against the routed
`00ec783` predecessor, whose metrics and layout matched the original
`1a258a1` baseline byte for byte. That baseline measured 30.9084%
for both utilization metrics, +2.206 ns slow setup, and +0.108 ns
worst hold. The candidate must clear the +1.0 ns slow-corner setup
floor and retain nonnegative hold and the approved area limits.
[Replacement run](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44922355967) · [Predecessor evidence](https://github.com/arnav1609/pvm-protocol-emulator/blob/c20b266/results/pre_freeze_validation_00ec783.md#tiny-tapeout) · [Original routed run](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44862976826)

## Open review

Kalash reviews the exact replacement candidate. Heet's independent
1-Wire and SWD model review is still open in the repository.
The fit study documents the earlier SWD launch-edge model correction
and parity mutant, and identifies the 1-Wire ideal pull-up assumption.
[Owner checklist](owner_review_b33a922.md) · [Fit study](fit_study.md)
