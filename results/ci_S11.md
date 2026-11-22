# S11 Tiny Tapeout IHP CI — setup failure

The 20 November 2026 runs used commit `4b13f45d977832428a590530add8aace1783022c`
on `codex/pvm-rtl`. The IHP build targeted 8×4 tiles and a 20 ns clock period.

| Check | Result |
| --- | --- |
| RTL smoke test | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44704388350) |
| Datasheet build | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44704388347) |
| GDS | [Failed on post-route setup timing](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44704388354/job/136180231832) |
| Tiny Tapeout precheck | Skipped after GDS failure |
| Gate-level simulation | Skipped after GDS failure |
| Pages viewer | Skipped after GDS failure |

The diagnostic artifact contains routed GDS and reports. Final standard-cell
count was 22,554, utilization was 26.2095%, and setup WNS was −8.894 ns.
[G2 analysis](g2_area_timing.md) · [GDS logs artifact](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44704388354/artifacts/14619008855)
