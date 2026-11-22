# PVM verification

The owner accepted candidate `b33a9227ac187f791a3733b94ac4e32879b10414`.
Windows Icarus accepted all 71 jobs. The owner's 360-case arbitration
sweep passed, and the qualified-loss check preserved four-clock release.
Verilator 5.032 passed 52 seeded replays across 26 builds under D-020.
All four variants passed scoped lint. The separate 1-Wire and SWD fit
study accepted four jobs, including two mutants.
[Freeze evidence](https://github.com/arnav1609/pvm-protocol-emulator/blob/16b799f/results/pre_freeze_validation_b33a922.md) · [Fit checks](../results/fit_study.md)

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
benches. [Windows regeneration follow-up](TOOLCHAIN.md#windows-trace-regeneration-follow-up)
[Job registry](../tb_rtl/pvm_jobs.json) · [D-016 repair](../results/g2_timing_repair.md)

## Protocol and physical results

- The S14b pin benches exercise UART TX 0x35, SPI mode 0 with two
  bytes, and I²C with open drain, ACKs and target clock stretching.
  Each test loads its image through the host SPI pins and catches a
  targeted mutant. [S14b gate](../reports/S14b_protocols_gate.md)
- The toolchain tests cover assembly, image CRC and host
  transactions. A cocotb test replaces all three images in the
  integrated RTL over simulated SPI and checks image commitment,
  register readback, execution and pin waveforms. [Toolchain test commands](TOOLCHAIN.md)
- Optimized variant D passed routed timing at 50 MHz with +2.206 ns
  slow-corner setup slack and 30.9084% utilization on the predecessor.
  The `b33a922` replacement passed at 50 MHz with +3.180 ns slow
  setup, +0.108 ns worst hold and 30.9734% on both utilization measures.
  GDS, gate-level SPI smoke, Pages and all ten prechecks passed.
  [Physical CI for b33a922](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44922355967)
- Functional simulation of the release candidate's routed variant-D
  netlist passed the three S14b pin waveforms and the DMX512 TX replay.
  Both DMX512 captures matched the frozen RTL's P5 edges cycle by
  cycle. The replay used functional PDK models with zero-delay
  simulation. [Release routed evidence](../results/v1.0_routed.md)

## Demo lockstep

Python 3.12, cocotb 2.0.1 and Icarus 12.0 replayed the generated images
against `b33a922` RTL. The simulator aligns cycle zero to the first
rising edge after engine ENABLE initialization. Samples use the D-016
CSV columns and pre-update convention through the edge issuing DONE.
The comparison checks PC, engine pin values and enables, FIFO requests
and RX data, fabric outputs and fault fields for each cycle. The host
reads DONE separately. The test writes ISS and RTL CSVs under
`test/output/<demo>/` and reports the first differing field, cycle and
synchronized pin input on mismatch.

| Demo | Engine cycles matched | Pin result |
| --- | ---: | --- |
| UART TX | 5,208 | 0x35 as 8N1, 434 core cycles per bit |
| SPI mode 0 | 1,280 | 0xA6 and 0xC9 MSB first, 16 rising edges |
| I²C write | 7,360 | Address 0x50 and data 0x3C, both ACKs, open drain and target stretch |
| Total | 13,848 | Three images built, loaded and executed in one RTL simulation |

The five directed ISA scenarios below extend these comparisons. The
independent bus-model review and delay-annotated gate replays remain
follow-ups.
[Reproduce the demo replay](TOOLCHAIN.md#reproduce-the-checks) · [Owner checklist](https://github.com/arnav1609/pvm-protocol-emulator/blob/16b799f/results/owner_review_b33a922.md)

Owner sign-off flags recorded at the freeze

```text
HARDWARE_VALIDATED=NO
FORMAL_PROOF=NO
GLS=NO
SILICON=NO
```

## Directed ISA lockstep

```sh
(cd test && PYTHONPATH=.. make COCOTB_TEST_MODULES=test_iss_lockstep)
```

Five images were assembled and loaded through the production SPI
loader on the frozen RTL. The comparison covers the D-016 columns,
X/Y, ISR/OSR and shift counts, both FIFO levels, and applied stimulus.
The comparator observes synchronized inputs and acknowledged host
requests at the engine boundary. Each CSV pair uses identical
stimulus and pre-update edge sampling.

| Scenario | Matched core cycles | Coverage |
| --- | ---: | --- |
| WAIT and branches | 2,208 | X decrement loop, both pin and OSR predicates, WAIT side-set and delay, narrow TX-empty stall and wake-up |
| WIDE FIFO boundaries | 5,368 | One TX byte, full RX, one free RX slot, two-tick little-endian beats |
| Left shifts | 30 | IN/OUT counts 4, 8 and 16, 16 encoded as zero |
| Right shifts | 30 | IN/OUT counts 4, 8 and 16, 16 encoded as zero |
| Narrow FIFO boundaries | 44 | Empty nonblocking PULL fallback, if-full skip, full nonblocking PUSH drop |
| Total | 7,680 | Five directed scenarios |

Captures are in `test/output/iss_lockstep/<scenario>/`, with a JSON
summary of stalls, PC visits and FIFO operations. The first differing
field and cycle are reported on failure. The broader lockstep campaign
still needs EXEC and automatic FIFO transfers, prescaled timeout/fault
traces, simultaneous engine and host FIFO requests, and randomized
programs. The S14b demo replays contribute a separate 13,848 matched
cycles.

The attached owner verification reports the scoped Stage 3 audit
and Stage 4 fault, mutation and bounded-proof results.
[Owner evidence](../evidence/owner_b33a922/README.md)

[Directed and baseline trace ZIP](../evidence/v1.0_rc/iss_lockstep_traces.zip) · [Software CI artifact](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/45050929399/artifacts/14764634367)
