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
| Tiny Tapeout precheck | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44778669345/job/136489409850) |
| Gate-level SPI smoke | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44778669345/job/136489409832) |
| Pages viewer | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44778669345/job/136489410613) |

Precheck finished successfully after 1 h 14 min 47 s. KLayout spent
about 73 minutes on the main IHP design-rule checks.
[Precheck reports](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44778669345/artifacts/14663751264)

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

The three S14b pin benches also passed a local functional replay of the
routed netlist with Tiny Tapeout's Icarus 13.0 and the pinned PDK cell
models. The replay used functional cell models without delay annotation.
[Gate-level UART, SPI and I²C evidence](../evidence/setup/s14_gate_protocols.log)

The Pages action successfully deployed the routed OASIS and its 2D
preview. The separate Tiny Tapeout Explorer topology extractor failed
with the SG13CMOS5L profile on both OASIS and GDS. Both artifacts have
top-cell `VPWR` and `VGND` labels on layer 50, datatype 25. The published
OASIS matches the submission artifact byte for byte.
[Explorer replay evidence](../evidence/setup/s14_viewer.log) · [3D layout](https://arnav1609.github.io/pvm-protocol-emulator/) · [2D preview](https://arnav1609.github.io/pvm-protocol-emulator/gds_render.png)

## Local synthesis area by variant

All four builds use the same RTL and top. Yosys 0.52 flattened the
designs and mapped flip-flops with `dfflibmap` and combinational logic
with ABC. The area estimates come from `stat -liberty` using the
SG13CMOS5L standard-cell library at 1.20 V and 25 °C from the PDK revision
used in CI, `89d42ee6d2fd9b50b86a1aada6fee6673c3e6008`.
[IHP typical Liberty library](https://github.com/IHP-GmbH/IHP-Open-PDK/blob/89d42ee6d2fd9b50b86a1aada6fee6673c3e6008/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib)

| Variant | Defines | Mapped cell area before routing |
| --- | --- | ---: |
| A · engine | `PVM_NO_FABRIC`, `PVM_NO_MON` | 262,553 µm² |
| B · engine + fabric | `PVM_NO_MON` | 274,413 µm² |
| C · engine + monitor | `PVM_NO_FABRIC` | 305,144 µm² |
| D · full | Default | 320,820 µm² |

These local estimates support the variant comparison. The routed
variant-D metrics above are the physical sign-off evidence.
