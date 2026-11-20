# Blocked at S11 G2

Since 20 November 2026, the S11 Tiny Tapeout run has failed at the 50 MHz
setup timing gate. The area gate passes at 26.2095% utilization.

The GDS job log reports the following error. [GDS job](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44704388354/job/136180231832)

```text
Setup violations found in the following corners:
* nom_slow_1p08V_125C
```

The frozen suite accepted 6/6 S11 jobs and 34/34 regression jobs. The
routed reports show 23 setup violations, with WNS of −8.894 ns.
Tracing the routed netlist identified the state-controlled instruction
fetch as the common path. [S11 gate](reports/S11_gate.md) · [G2 report](results/g2_area_timing.md)

Under S11 §7 and the project method §8, S12 depends on a passing G2
rerun. Kalash approved the entry-point lookup repair and pre-approved
the instruction register and static pin mapping if the first repair
leaves slow-corner setup slack below +1.0 ns. [D-016](spec/DECISIONS.md#d-016--s11-g2-timing-repair-at-50-mhz) · [Repair evidence](results/g2_timing_repair.md)
