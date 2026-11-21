# PVM verification

The RTL regression accepted 67 of 67 jobs. The baseline covered 63
jobs across S01–S14, S14b and D-016. D-017 and D-018 add the reset
bench and three mutants. The separate 1-Wire and SWD suite accepted
four program-fit jobs, including two mutants.
[Baseline checks](../results/rtl_freeze_report.md) · [Optimization checks](../results/opt_area_timing.md) · [Fit checks](../results/fit_study.md)

## Reproduce the evidence

```sh
python3 tb_rtl/pvm_run.py selftest
python3 tb_rtl/pvm_run.py run --select all
python3 tb_rtl/pvm_run.py trace-golden --check
```

The runner requires Python, Icarus Verilog and VVP. The trace command
also needs Git history containing `4b13f45`. The D-016 comparison
replays four tests cycle by cycle against that pre-repair RTL. A
one-cycle delayed-output mutant fails the comparison. The evidence
supports engine trace equivalence to pre-repair RTL for these
benches. An independent ISS comparison is pending.
[Job registry](../tb_rtl/pvm_jobs.json) · [D-016 repair](../results/g2_timing_repair.md)

## Protocol and physical results

- The S14b pin benches exercise UART TX 0x35, SPI mode 0 with two
  bytes, and I²C with open drain, ACKs and target clock stretching.
  Each test loads its image through the host SPI pins and catches a
  targeted mutant. [S14b gate](../reports/S14b_protocols_gate.md)
- The toolchain tests cover assembly, image CRC and host
  transactions. A cocotb test replaces all three images in the
  integrated RTL over simulated SPI and checks image commitment
  and register readback. [Toolchain test commands](TOOLCHAIN.md)
- Optimized variant D passed routed timing at 50 MHz with +2.206 ns
  slow-corner setup slack and 30.9084% utilization. GDS, precheck,
  gate-level SPI smoke and the Pages viewer passed.
  [Physical CI](../results/opt_area_timing.md)
- Functional simulation of the routed variant-D netlist passed all
  three S14b waveforms with the pinned PDK cell models. That local
  replay used functional cell models without delay annotation.
  [Netlist replay log](../evidence/setup/s14_gate_protocols.log)

## Remaining review

The second-simulator freeze gate passed with Verilator 5.032 and
timing enabled under D-020. Kalash’s source-review sign-off remains
pending. Heet’s independent verification, the ISS comparison and the G3
physical checks on the final submission commit are pending.
[Freeze review packet](../reports/weekly_freeze_review.md) · [Heet’s handover](verification_handoff.md)

Current claim flags

```text
HARDWARE_VALIDATED=NO
FORMAL_PROOF=NO
GLS=NO
SILICON=NO
```
