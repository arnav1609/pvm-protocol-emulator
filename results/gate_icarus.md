# Icarus version requirement for routed replay

The verified IHP SG13CMOS5L zero-delay replay requires Icarus Verilog
13.0 or later for both `iverilog` and `vvp`. The demonstrated build is
Tiny Tapeout's 13.0 package. Icarus 12.0 remains usable for the
source-level RTL regression.

## Failure mechanism

The pinned PDK's functional `sg13cmos5l_dfrbpq_1` model feeds its
flip-flop primitive from `delayed_CLK`, `delayed_D`, and
`delayed_RESET_B`. The model declares those signals as delayed
reference and data outputs of `$setuphold` and `$recrem`.
Icarus 12.0 warns that these outputs will not be driven. In the
single-cell probe they stayed at Z with the stimulus driven, and Q
stayed X during reset and capture. The behavior persisted with
`-gspecify`. Tiny Tapeout's 13.0 build drove the corresponding input
values onto those signals, gave Q=0 on reset, and captured Q=1.

The two D-017 release flops use this cell in the routed PVM netlist.
The old UART debug replay already reported X at STATUS and P5 before
the first UART bit. The single-cell probe changes reset, data and
clock at separate simulation times and reproduces the split without
the PVM testbench. The full UART bench, unmodified in both runs, failed
on 12.0 and passed on 13.0. [Compiler warnings](../evidence/v1.0_rc/icarus_version/compiler-warnings.txt)

| Replay | Icarus 12.0 | Tiny Tapeout Icarus 13.0 |
| --- | --- | --- |
| Single DFF, default flags | [Q=X](../evidence/v1.0_rc/icarus_version/probe-12-default.log) | [Reset and capture pass](../evidence/v1.0_rc/icarus_version/probe-13-default.log) |
| Single DFF, `-gspecify` | [Q=X](../evidence/v1.0_rc/icarus_version/probe-12-specify.log) | [Reset and capture pass](../evidence/v1.0_rc/icarus_version/probe-13-specify.log) |
| Full routed UART | [Fail](../evidence/v1.0_rc/icarus_version/uart-12.log) | [Pass](../evidence/v1.0_rc/icarus_version/uart-13.log) |

Routed source `752ebb97824cfd1161581497c22d3c171c4c6ca9`, netlist
SHA-256 `e7f061e6bbaab1f222dd3fd3f4925da9fcf3625588f4aaf6cabbe7cd1f9f17e7`,
and IHP PDK revision `89d42ee6d2fd9b50b86a1aada6fee6673c3e6008`.
[Exact build and package](v1.0_routed.md)

## Reproduce

The cell probe takes the unchanged PDK UDP and standard-cell models
downloaded by the routed bundle. Set `std` to
`ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/verilog` in that PDK.

```sh
iverilog -g2005 -DFUNCTIONAL -DSIM -s iv_reset_probe -o /tmp/iv-reset-probe.vvp \
  "$std/sg13cmos5l_udp.v" "$std/sg13cmos5l_stdcell.v" \
  evidence/v1.0_rc/icarus_version/iv-reset-probe.v
vvp /tmp/iv-reset-probe.vvp
```

For a gate replay, run `scripts/replay_routed.sh` on the extracted
release bundle with matching 13.0 or later tools on PATH. The
repository gate workflow pins the Tiny Tapeout action revision whose
first simulator installation step installs the exact 13.0 package.
The functional evidence remains zero-delay GLS plus all-corner STA.
The slow-corner SDF replay was inconclusive.
[Release checklist](../docs/RELEASE_CHECKLIST.md) · [Gate workflow](../.github/workflows/gds.yaml)
