# BLOCKED — W0 setup before S01

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

## Needed to resume

- Kalash to establish the 8x4 template on `main` and provide or identify the commit with passing test, GDS, and precheck runs.
- Kalash to confirm the GitHub username for the final Tiny Tapeout wrapper.
- Kalash and Arnav to record approval of D-008 through D-011, including interface revision 0. The uploaded decision register lists all four as proposed.

Handoff references are `BLUEPRINT.md` sections 4, 5, and 7 and `spec/DECISIONS.md` D-008 through D-011.
