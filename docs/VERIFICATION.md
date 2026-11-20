# PVM verification

The RTL regression accepted 63 of 63 jobs across S01–S14, S14b and
D-016. That total includes 27 positive jobs and 36 expected-failure
mutants. Frozen checks and the corresponding fresh job logs are
listed in the freeze report. [Freeze report](../results/rtl_freeze_report.md)

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
- Variant D passed routed timing at 50 MHz with +2.461 ns slow-corner
  setup slack and 33.7187% utilization. GDS, precheck, gate-level
  SPI smoke and the Pages viewer also passed.
  [Physical CI](../results/ci_S14.md)
- Functional simulation of the routed variant-D netlist passed all
  three S14b waveforms with the pinned PDK cell models. That local
  replay used functional cell models without delay annotation.
  [Netlist replay log](../evidence/setup/s14_gate_protocols.log)

## Remaining review

Kalash’s XSim rerun and S12–S14b source review gate the RTL freeze.
Heet’s independent verification, the ISS comparison and the G3
physical checks on the final submission commit are pending.
[Freeze review packet](../reports/weekly_freeze_review.md) · [Heet’s handover](verification_handoff.md)

Current claim flags

```text
HARDWARE_VALIDATED=NO
FORMAL_PROOF=NO
GLS=NO
SILICON=NO
```
