# S08 Tiny Tapeout IHP CI — PASS

Run #15 used commit `4225eac78659c8dbf626725fed008fc4c85d5f9f`, with the
same RTL, build configuration, tests, and workflow as integration commit
`011cd45a36f0554f7cc1a2e2246504e21963b4cc`. LibreLane 3.1.0.dev4 built the
`ihp-sg13cmos5l` design for 8x4 tiles at 50 MHz (20 ns).

| Check | Result |
| --- | --- |
| RTL smoke test | [Pass](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44683036252) |
| Datasheet build | [Pass](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44683036196) |
| GDS | [Pass](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44683036190/job/136160729472) |
| Tiny Tapeout precheck | [Pass](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44683036190/job/136160730066) |
| Gate-level simulation | [Pass](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44683036190/job/136160788026) |
| Pages viewer | [Pass on attempt 2](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44683036190/job/136160727411) |

Post-route metrics from run #15 are 12,259 standard cells, 17.1016%
standard-cell utilization, +9.352 ns worst setup slack (0 ns setup WNS),
and +0.109 ns worst hold slack. The flow reported zero routing DRC errors.
[Submission artifact with metrics.csv](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44683036190/artifacts/14609110996)

The repository owner set GitHub Pages to use GitHub Actions. Rerunning
only the viewer reused the GDS artifact and brought run #15 to success.
The published OASIS file returned HTTP 200. [Published viewer](https://arnav1609.github.io/pvm-protocol-emulator/)
