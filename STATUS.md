# PVM RTL STATUS
Flags: HARDWARE_VALIDATED=NO, FORMAL_PROOF=NO, GLS=NO, SILICON=NO

| Stage | Plan date | State (TODO/WIP/PASS/FAIL/BLOCKED) | Gate report | Jobs accepted/total | Claim level | XSim (Kalash, weekly) | ISS cross-check (Arnav) | CI |
|---|---|---|---|---|---|---|---|---|
| S01 | 25 Nov | PASS | [S01 gate](reports/S01_gate.md) | 2/2 | Icarus-simulated, mutation-tested | Pending | | Standalone RTL |
| S02 | 26 Nov | TODO | | | | | | |
| S03 | 27 Nov | TODO | | | | | | |
| S04 | 28 Nov | TODO | | | | | | |
| S05 | 29 Nov | TODO | | | | | | |
| S06 | 30 Nov | TODO | | | | | | |
| S07 | 1 Dec | TODO | | | | | | |
| S08 | 2 Dec | TODO | | | | | | |
| S09 | 3-4 Dec | TODO | | | | | | |
| S10 | 5 Dec | TODO | | | | | | |
| S11 | 6 Dec | TODO | | | | | | |
| S12 | 7-8 Dec | TODO | | | | | | |
| S13 | 8-9 Dec | TODO | | | | | | |
| S14 | 10 Dec | TODO | | | | | | |

## Setup

- The owner approved D-008 through D-011 and interface revision 0 in the project conversation on 20 November 2026.
- The workspace uses Verilog-2005 and the handoff runner. [Runner self-test](evidence/setup/runner_selftest.log)
- The baseline uses the repository owner's GitHub handle for the planned wrapper name, `tt_um_arnav1609_pvm`.
- The 8x4 baseline is under review. [Setup pull request](https://github.com/arnav1609/pvm-protocol-emulator/pull/1)

## OPEN QUESTIONS

- [Baseline GDS and precheck](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44679133846) for the 8x4 template.

## Bug notes (after a stage PASS, reopened by review)
| ID | Stage | Found by | Description | Fix commit | Re-run evidence |
|---|---|---|---|---|---|
