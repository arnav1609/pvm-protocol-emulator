# G2 area and timing — blocked

Measured on 20 November 2026 for S11 commit
`4b13f45d977832428a590530add8aace1783022c` in an 8×4 IHP SG13G2
layout at 50 MHz (20 ns).
[GDS run](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44704388354)

| Post-route metric | Measured | G2 condition |
| --- | ---: | --- |
| Standard-cell utilization | 26.2095% | At most 40% · passes |
| Standard-cell count | 22,554 | Recorded |
| Standard-cell area | 316,656 µm² | Recorded |
| Setup worst negative slack | −8.894 ns | At least 0 ns · fails |
| Setup total negative slack | −153.342 ns | 23 violating endpoints |
| Worst hold slack | +0.138 ns | Zero hold violations |
| Detailed routing violations | 0 | Final routing iteration |

Worst setup slack by corner was +8.198 ns at fast (1.32 V, −40 °C), +1.723 ns
at typical (1.20 V, 25 °C), and −8.894 ns at slow (1.08 V, 125 °C).
[Post-route metrics and reports](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44704388354/artifacts/14619008855)

## Failing path

All 23 setup violations launch from `pvm.config_bank.state[1]` and end at
the engine's `out_val` or `oe_val` registers. The worst path runs from
`_33072_/Q` to `_33202_/D` (`pvm.engine.out_val[9]`). It passes through
the state-controlled mux that selects `ENTRY_PC` or the engine PC, then
through the instruction-memory read mux and the engine's pin update logic.
At the endpoint, arrival time is 29.039 ns and required time is 20.146 ns.
[GDS logs artifact](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44704388354/artifacts/14619008855)

The evidence can be reproduced from `runs/wokwi/final/metrics.json`, the
`max.rpt` and `violator_list.rpt` files under
`runs/wokwi/55-openroad-stapostpnr/nom_slow_1p08V_125C/`, and
`runs/wokwi/final/nl/tt_um_arnav1609_pvm.nl.v` for the RTL net names.

## Owner decision

First try a separate `ENTRY_PC` validity lookup for image validation.
This lets the engine PC address its instruction port directly and removes
the state decode and address mux from the fetch path. Measure the rerouted
design at 50 MHz. If the next critical path still runs through pin updates,
evaluate simplification of the OUT, MOV, SET, and side-set pin update logic
with the existing tick behavior as the reference.

If those changes cannot close timing, potential scope reductions for
owner review include restricting programmable pin placement to simplify
the pin update logic, or revising the target clock. Either option changes
the baseline and requires a new routed result.

For a timing repair, rerun the frozen S11 checks and full regression,
then require routed setup slack to meet G2 and GDS, precheck, gate-level
simulation, and the Pages viewer to pass on the repair commit.
