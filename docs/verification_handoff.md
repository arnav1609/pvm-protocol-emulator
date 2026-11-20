# PVM verification handover for Heet

## Starting point

Work from the `codex/pvm-rtl` branch of
`arnav1609/pvm-protocol-emulator`. The full design routed in the Tiny
Tapeout flow from RTL commit `aa2996b`. Use the branch tip for the
S14b protocol tests and review records. The same RTL builds all four
experiment variants. [Repository branch](https://github.com/arnav1609/pvm-protocol-emulator/tree/codex/pvm-rtl)

## What is complete

- The host can load and validate an image over SPI. The RTL includes
  configuration and lifecycle control, CRC, instruction memory, TX and
  RX FIFOs, the execution engine, and safe output gating.
- The pin fabric implements the two-layer LUT network, counter,
  Manchester hold, and open-drain arbitration guard. The passive
  monitor runs timing rules and records verdicts, counters, and a
  four-entry log that the host can read over SPI.
- The full regression accepted 63 jobs, including the 57 existing jobs
  and six new S14b jobs. The four D-016 engine traces regenerated from
  their golden source. The new pin tests load images over SPI and check
  UART TX 0x35, SPI mode 0 bytes 0xA6 and 0xC9, and an open-drain I²C
  write to address 0x50 with ACK and target clock stretching. Each
  protocol test caught its own mutant. [Regression and evidence](https://github.com/arnav1609/pvm-protocol-emulator/blob/codex/pvm-rtl/results/rtl_freeze_report.md) · [Pin-level test gate](https://github.com/arnav1609/pvm-protocol-emulator/blob/codex/pvm-rtl/reports/S14b_protocols_gate.md)
- Variant D routed at 50 MHz with +2.461 ns slow-corner setup slack and
  33.7187% utilization. GDS, gate-level SPI smoke, and the Pages viewer
  passed. Use the CI record for the final precheck status.
  [Variant D CI](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44778669345)

## Heet's task list

1. **Reproduce the baseline.** Record the commit, simulator version, and
   date. Rebuild the D-016 CSVs, run the full regression, and send Kalash
   the summary and links to the logs. Reproduce any failure before
   editing the RTL.
2. **Review and replay S12–S14b with Kalash.** Use the weekly XSim packet
   to cover all positive testbenches and build variants. Prioritize
   arbitration release and Manchester boundary timing, monitor verdict
   edges and log order, and open-drain ACK and stretch at the pads.
   Record the first differing cycle and a waveform for any finding.
   Kalash records the freeze review decision.
3. **Turn the protocol benches into reproducible demos.** Coordinate
   with Arnav on the assembler and SPI host tool. Package the UART, SPI,
   and I²C images with the write and run steps and an expected waveform.
   Record a clean I²C transaction and a deliberately stretched or
   out-of-window case with the resulting monitor log.
4. **Prepare the four-way experiment evidence.** Use matched workloads
   and clock settings across A/B/C/D. Measure arbitration release
   latency, Manchester timing and missed writes, and monitor
   PASS/VIOLATION/INCONCLUSIVE at the stated timing boundaries. Keep
   simulator results, generic synthesis counts, and routed measurements
   labeled by the actual variant and commit.
5. **Maintain the verification record.** Add reproducible discrepancies
   to the bug notes. Capture the physical run IDs and precheck status in
   the review. When Arnav's ISS becomes available, compare its traces
   independently. The current claim is Icarus-simulated, mutation-tested,
   and trace-equivalent for the engine D-016 comparison.

From the repository root with Icarus Verilog on PATH:

```sh
python3 tb_rtl/pvm_run.py selftest
python3 tb_rtl/pvm_run.py trace-golden --check
python3 tb_rtl/pvm_run.py run --select S14b_protocols
python3 tb_rtl/pvm_run.py run --select all
```

Expected runner results are six of six S14b jobs and 63 of 63 full
regression jobs accepted. The freeze tag depends on the variant-D
physical gate, the pin-test evidence, and Kalash's XSim and source
review. [Weekly review packet](https://github.com/arnav1609/pvm-protocol-emulator/blob/codex/pvm-rtl/reports/weekly_freeze_review.md)
