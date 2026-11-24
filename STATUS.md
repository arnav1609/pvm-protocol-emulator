# PVM RTL STATUS
Flags: HARDWARE_VALIDATED=NO, FORMAL_PROOF=NO, SILICON=NO

All four functional gate-level demos passed (UART, SPI, I²C and DMX512).
Static setup and hold timing passed at all three corners. The slow-corner
delay simulation was inconclusive. [Routed evidence](results/v1.0_routed.md)

| Stage | Plan date | State (TODO/WIP/PASS/FAIL/BLOCKED) | Gate report | Jobs accepted/total | Claim level | Second simulator | ISS cross-check (Arnav) | CI |
|---|---|---|---|---|---|---|---|---|
| S01 | 25 Nov | PASS | [S01 gate](reports/S01_gate.md) | 2/2 | Icarus-simulated, mutation-tested | Verilator passed | | Standalone RTL |
| S02 | 26 Nov | PASS | [S02 gate](reports/S02_gate.md) | 4/4 | Icarus-simulated, mutation-tested | Verilator passed | | Standalone RTL |
| S03 | 27 Nov | PASS | [S03 gate](reports/S03_gate.md) | 2/2 | Icarus-simulated, mutation-tested | Verilator passed | | Standalone RTL |
| S04 | 28 Nov | PASS | [S04 gate](reports/S04_gate.md) | 2/2 | Icarus-simulated, mutation-tested | Verilator passed | | Standalone RTL |
| S05 | 29 Nov | PASS | [S05 gate](reports/S05_gate.md) | 4/4 | Icarus-simulated, mutation-tested | Verilator passed | | Standalone RTL |
| S06 | 30 Nov | PASS | [S06 gate](reports/S06_gate.md) | 2/2 | Icarus-simulated, mutation-tested | Verilator passed | | Standalone RTL |
| S07 | 1 Dec | PASS | [S07 gate](reports/S07_gate.md) | 4/4 | Icarus-simulated, mutation-tested | Verilator passed | | Standalone RTL |
| S08 | 2 Dec | PASS | [S08 gate](reports/S08_gate.md) | 4/4 | Icarus-simulated, mutation-tested | Verilator passed | | [Run #15 green](results/ci_S08.md) |
| S09 | 3-4 Dec | PASS | [S09 gate](reports/S09_gate.md) | 2/2 | Icarus-simulated, mutation-tested | Verilator passed | ISS pending | Standalone RTL |
| S10 | 5 Dec | PASS | [S10 gate](reports/S10_gate.md) | 2/2 | Icarus-simulated, mutation-tested | Verilator passed | ISS pending | Standalone RTL |
| S11 | 6 Dec | PASS | [S11 gate](reports/S11_gate.md) | 6/6 stage, 5/5 trace | Trace-equivalent to pre-repair RTL, mutation-tested | Verilator passed | ISS pending | [G2 passed at 50 MHz](results/g2_timing_repair.md) |
| S12 | 7-8 Dec | PASS | [S12 gate](reports/S12_gate.md) | 4/4 | Icarus-simulated, mutation-tested | Verilator passed | ISS pending | [Physical gate passed](results/opt_area_timing.md) |
| S13 | 8-9 Dec | PASS | [S13 gate](reports/S13_gate.md) | 6/6 | Icarus-simulated, mutation-tested | Verilator passed | ISS pending | [Physical gate passed](results/opt_area_timing.md) |
| S14 | 10 Dec | PASS | [S14 gate](reports/S14_gate.md) | 8/8 | Icarus-simulated, mutation-tested | Verilator passed | ISS pending | [Physical gate passed](results/opt_area_timing.md) |
| S14b | Before freeze | PASS | [Pin-level protocol gate](reports/S14b_protocols_gate.md) | 6/6 | Icarus-simulated, mutation-tested | Verilator passed | ISS pending | [Variant D CI](results/ci_S14.md) |

## Freeze candidate and release targets

The published `rtl-freeze` tag is
`b33a9227ac187f791a3733b94ac4e32879b10414`. The one-time draw
selected DMX512 TX. The accepted 29-word image, configuration
and both zero-delay gate captures matched the accepted RTL traces.
[Freeze evidence](https://github.com/arnav1609/pvm-protocol-emulator/blob/16b799f/results/pre_freeze_validation_b33a922.md) · [Draw record](results/held_out_draw.md) · [DMX512 TX](docs/DMX512_TX_DEMO.md)

The demo images and routed baseline have passed their technical gates.
The public release and write-up target 31 December 2026, subject to
owner approval of the exact release commit. [Stage 8 write-up](docs/SUBMISSION_WRITEUP.md)

The ISS matched 13,848 baseline demo cycles and 7,680 additional
directed cycles. The Windows standalone golden-regeneration
issue remains a tooling follow-up.
[Demo and ISS evidence](docs/VERIFICATION.md#directed-isa-lockstep) · [Tooling follow-up](docs/TOOLCHAIN.md#windows-trace-regeneration-follow-up)

## Setup

- Kalash approved [D-012](spec/rev/PVM-IF-rev1-HALT-CLEARS.md) in chat before S06.

- The owner approved D-008 through D-011 and interface revision 0 in the project conversation on 20 November 2026.
- The workspace uses Verilog-2005 and the handoff runner. [Runner self-test](evidence/setup/runner_selftest.log)
- The baseline uses the repository owner's GitHub handle for the planned wrapper name, `tt_um_arnav1609_pvm`.
- The 8x4 baseline is under review. [Setup pull request](https://github.com/arnav1609/pvm-protocol-emulator/pull/1)

## Engine test plan

- D-013 fixes the initial OSR count at 16 for reset and ENABLE. [Decision record](spec/DECISIONS.md#d-013--osr-shift-count-at-reset-and-enable)
- The S09 freeze covered `JMP_COND_0_TAKEN`, both outcomes for each of conditions 1–6, and `JMP_COND_7_NOT_TAKEN`. The condition-7 inversion mutant failed only `JMP_COND_7_NOT_TAKEN`. [S09 gate](reports/S09_gate.md)
- S10 froze `JMP_COND_7_TAKEN` and recorded its S09 deferral in `checks_basis`. The same JMP fell through with an empty OSR and took its branch after PULL.

At S09, WAIT and the datapath instructions were stubbed. S10 implemented them, including the WAIT and timeout paths used by EXEC. [D-014 and D-015](spec/DECISIONS.md#d-014--wide-fifo-beats-follow-engine-ticks)

In the S10 UART TX test at CLKDIV 3, the start bit begins at core cycle 3 after setup, the first data bit at cycle 9, and the stop bit at cycle 57. Each bit spans six core cycles. [UART evidence](reports/S10_gate.md)

- D-016 passed with four cycle-by-cycle matches against the accepted S11 RTL and a killed one-cycle output-delay mutant. [G2 report](results/g2_timing_repair.md)

## Bug notes (after a stage PASS, reopened by review)
| ID | Stage | Found by | Description | Fix commit | Re-run evidence |
|---|---|---|---|---|---|
