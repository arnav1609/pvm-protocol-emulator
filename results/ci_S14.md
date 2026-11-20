# PVM S14 Tiny Tapeout results

Variant D used RTL commit `aa2996b1d2be115531f00b5ce7b0ace52d964b14` on
IHP SG13CMOS5L with 8×4 tiles and a 20 ns clock. The routed slow-corner
setup slack exceeds the +1.0 ns freeze requirement.
[Physical run 44778669345](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44778669345)

| Check | Result |
| --- | --- |
| GitHub RTL smoke | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44778669706) |
| Datasheet | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44778669332) |
| GDS | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44778669345/job/136435216541) |
| Tiny Tapeout precheck | [Running](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44778669345/job/136489409850) |
| Gate-level SPI smoke | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44778669345/job/136489409832) |
| Pages viewer | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44778669345/job/136489410613) |

| Metric from run 44778669345 | Measured value |
| --- | ---: |
| `design__instance__utilization` | 33.7187% |
| `design__instance__utilization__stdcell` | 33.7187% |
| Standard-cell count | 28,091 |
| Standard-cell area | 407,380 µm² |
| Slow-corner worst setup slack | +2.461 ns |
| Global worst negative slack | 0 ns |
| Total negative slack | 0 ns |
| Worst hold slack | +0.122 ns |
| Setup, hold, and detailed routing violations | 0 each |

Compared with the S11 routed engine baseline, variant D uses 7,057 more
standard cells and 7.7589 percentage points more utilization. The
freeze report records A/B/C/D generic Yosys synthesis counts. The
gate-level result is the CI SPI smoke test.
[S14 metrics artifact](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44778669345/artifacts/14658475695) · [S11 baseline](g2_timing_repair.md) · [Freeze report](rtl_freeze_report.md)
