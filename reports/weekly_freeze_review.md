# Weekly freeze review packet for Kalash

Use `codex/pvm-rtl`. The candidate includes the engine, fabric, monitor
and the D-017/D-018 changes. Variant D routed from `1a258a1`. The
physical gate, protocol checks and 32-word fit gate passed.
[Physical evidence](../results/opt_area_timing.md) · [S14b gate](S14b_protocols_gate.md) · [Fit gate](../results/fit_study.md)

Include the D-017 positive reset bench in the simulator replay. Inspect the
reset fanout and two-edge release, the monitor arithmetic and the stable
source selector invariant, and shared engine mux and shift paths.
[Candidate report](../results/opt_area_timing.md)

## Run the testbenches in XSim

1. Record the Git SHA, Vivado release, and date. Use the positive jobs in
   the registry as the run list. For each job, use its exact `sources`,
   `defines`, and `top` in a fresh working directory. The four D-016 trace
   jobs replay benches already present in this list.
2. Compile as Verilog, elaborate the named top, and run to completion.
   Pass each define to `xvlog` with `--define`. For the S14b I²C job, use
   `PVM_PROTOCOL_I2C` and the `s14b_i2c` source list, then run
   `xelab tb_protocols -s pvm_i2c` and `xsim pvm_i2c -runall`.
3. Capture the `CONFIG`, `CHECKS`, `ERRORS`, and `RESULT` lines for every
   run. Confirm the frozen counts and zero errors. Attach the first
   failing waveform and relevant clock numbers for any discrepancy.
   The Icarus mutation runs are already recorded.

[Job registry](../tb_rtl/pvm_jobs.json) · [AMD simulator options](https://docs.amd.com/r/en-US/2026.1/ug900-vivado-logic-simulation/xelab-xvhdl-and-xvlog-xsim-Command-Options)

## Review S12–S14 against the interface

| Scope | Review points |
| --- | --- |
| PINFABRIC | Confirm selector packing, both pin groups, registered L0/L1 feed-forward, REG/RISE/MAJ3 timing, and the counter reload. Check Manchester capture when write and bit boundary coincide. Confirm the four-core-clock arbitration release from pad observation and the explicit sticky-flag clear events. |
| SPECMON | Confirm first-match priority, previous-cycle edge sampling, 17-bit verdict arithmetic, overflow behavior, timer and counter saturation, and log byte order. Verify that monitor outputs terminate at the configuration read path. |
| Top and variants | Check both disable defines, safe pins outside RUN, SPI-loaded image recovery, and the UART, SPI, and I²C waveforms. Inspect the I²C target stretching interval and the release of SDA during each ACK. |

[Fabric spec](../spec/05_FABRIC.md) · [Fabric RTL](../src/pvm_fabric.v) · [Monitor spec](../spec/06_MONITOR.md) · [Monitor RTL](../src/pvm_mon.v) · [Top RTL](../src/pvm_top.v)

Record the XSim pass count and source-review verdict in the freeze
review. Capture any findings with the reproducing job and the affected
spec paragraph. Current claims are Icarus-simulated, mutation-tested,
and trace-equivalent for the engine D-016 comparison. An ISS comparison
will need Arnav's toolchain.

`HARDWARE_VALIDATED=NO, FORMAL_PROOF=NO, GLS=NO, SILICON=NO`
