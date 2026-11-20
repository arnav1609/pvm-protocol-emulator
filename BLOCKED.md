# W0 baseline setup history

**Since:** 20 November 2026, IST

The handoff requires a green 8x4 Tiny Tapeout IHP template before RTL work starts. Both `main` and `codex/pvm-rtl` pointed to `e8d532f97d015ae2adfcf688471b8f9f421d7dde` when inspected. The checked-in `info.yaml` declares `tiles: "1x1"` and leaves the project title, author, and description blank.

## CI evidence for the template commit

| Branch | Test | GDS | Precheck | Docs |
| --- | --- | --- | --- | --- |
| `main` | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44676155988) | [Failed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44676156039) | [Skipped](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44676156039/job/136089512590) | [Failed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44676156027) |
| `codex/pvm-rtl` | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44676627814) | [Failed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44676627807) | [Skipped](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44676627807/job/136090071500) | [Failed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44676627805) |

The GDS logs show the failure during `./tt/tt_tool.py --create-user-config`. [Build GDS log on main](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44676156039/job/136088369130#step:3:567)

```text
Error loading /home/runner/work/pvm-protocol-emulator/pvm-protocol-emulator/info.yaml: Project title cannot be empty, Project author cannot be empty, Project description cannot be empty
```

The docs log also flags the empty pinout and missing “How it works” and “How to test” sections in `docs/info.md`. [Build docs log](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44676627805/job/136089886321)

## Current setup

The 8x4 metadata and template documentation are in [draft PR #1](https://github.com/arnav1609/pvm-protocol-emulator/pull/1). The owner approved interface revision 0 and D-008 through D-011. Baseline tests and docs passed. [Baseline GDS and precheck](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44679133846) are the remaining setup checks.

Handoff references are `BLUEPRINT.md` sections 4, 5, and 7 and `spec/DECISIONS.md` D-008 through D-011.
