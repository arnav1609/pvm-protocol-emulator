# Weekly freeze review packet for Kalash

Use `codex/pvm-rtl`. The candidate includes the engine, fabric, monitor
and the D-017/D-018 changes. Variant D routed from `1a258a1`. The
physical gate, protocol checks and 32-word fit gate passed.
[Physical evidence](../results/opt_area_timing.md) · [S14b gate](S14b_protocols_gate.md) · [Fit gate](../results/fit_study.md)

The Codex review of the changed RTL is recorded. The freeze awaits
Kalash's source-review sign-off. [Source review](../results/opt_area_timing.md#source-review)

## Freeze checklist

- [x] Variant D physical gate, including Tiny Tapeout precheck.
- [x] Icarus regression and D-016 trace comparisons.
- [x] Timing-enabled Verilator replay accepted under D-020.
- [x] D-019 32-word fit gate.
- [ ] Kalash records source-review sign-off for the candidate SHA.

Verilator 5.032 passed all 24 distinct positive bench configurations,
including the D-017 reset bench and S14b I²C. The Icarus regression
includes the four D-016 trace comparisons and their output-delay mutant.
[Decision D-020](../spec/DECISIONS.md#d-020--use-verilator-for-the-freeze-simulator-gate) · [Replay evidence](../evidence/opt/verilator_timing.log)

## Review S12–S14 against the interface

| Scope | Review points |
| --- | --- |
| PINFABRIC | Confirm selector packing, both pin groups, registered L0/L1 feed-forward, REG/RISE/MAJ3 timing, and the counter reload. Check Manchester capture when write and bit boundary coincide. Confirm the four-core-clock arbitration release from pad observation and the explicit sticky-flag clear events. |
| SPECMON | Confirm first-match priority, previous-cycle edge sampling, 17-bit verdict arithmetic, overflow behavior, timer and counter saturation, and log byte order. Verify that monitor outputs terminate at the configuration read path. |
| Top and variants | Check both disable defines, safe pins outside RUN, SPI-loaded image recovery, and the UART, SPI, and I²C waveforms. Inspect the I²C target stretching interval and the release of SDA during each ACK. |
| D-017 and D-018 | Inspect reset fanout and two-edge release, monitor arithmetic and stable source selectors, and the shared engine mux and shift paths. |

[Fabric spec](../spec/05_FABRIC.md) · [Fabric RTL](../src/pvm_fabric.v) · [Monitor spec](../spec/06_MONITOR.md) · [Monitor RTL](../src/pvm_mon.v) · [Top RTL](../src/pvm_top.v)

Record the source-review verdict and the reviewed Git SHA. Capture
findings with the reproducing job and the affected spec paragraph.
Current claims include Icarus simulation, timing-enabled Verilator
simulation of the positive benches, mutation testing, and D-016 engine
trace equivalence. An ISS comparison will need Arnav's toolchain.

`HARDWARE_VALIDATED=NO, FORMAL_PROOF=NO, GLS=NO, SILICON=NO`
