# PVM RTL STATUS
Flags: HARDWARE_VALIDATED=NO, FORMAL_PROOF=NO, GLS=NO, SILICON=NO

| Stage | Plan date | State (TODO/WIP/PASS/FAIL/BLOCKED) | Gate report | Jobs accepted/total | Claim level | XSim (Kalash, weekly) | ISS cross-check (Arnav) | CI |
|---|---|---|---|---|---|---|---|---|
| S01 | 25 Nov | BLOCKED | [W0 blocker](BLOCKED.md) | 0/0 | | | | GDS failed, precheck skipped |
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

## OPEN QUESTIONS

- Which commit on `main` establishes the 8x4 Tiny Tapeout IHP baseline, and which Actions runs show test, GDS, and precheck passing?
- What GitHub username should the Tiny Tapeout wrapper use?
- Where are Kalash and Arnav's approvals for D-008 through D-011, including interface revision 0?

## Bug notes (after a stage PASS, reopened by review)
| ID | Stage | Found by | Description | Fix commit | Re-run evidence |
|---|---|---|---|---|---|
