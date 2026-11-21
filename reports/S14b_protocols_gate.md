# PVM S14b pin-level protocols — local verification passed

The runner accepted all six S14b jobs and all 63 jobs in the full
regression. Each S14b job has one frozen check. The testbench loads
each image and its configuration over the wrapper's host SPI port.

`HARDWARE_VALIDATED=NO, FORMAL_PROOF=NO, GLS=NO, SILICON=NO`

| Protocol | Observed at the pins | Positive | Negative |
| --- | --- | --- | --- |
| UART TX | P5 sends 0x35 as 8N1. Every bit is sampled across its 434 core clocks. At 50 MHz the programmed rate is about 115,207 baud, 0.0064% above 115,200. | [PASS_FRESH](../evidence/s14b_uart/20261120T190424.log) | [NEG_KILLED](../evidence/s14b_uart_neg/20261120T190425.log) |
| SPI mode 0 controller | P6 and P7 send 0xA6 and 0xC9 MSB first. The check measures SCK high and low intervals and verifies MOSI throughout each high phase and its setup interval. | [PASS_FRESH](../evidence/s14b_spi/20261120T190426.log) | [NEG_KILLED](../evidence/s14b_spi_neg/20261120T190426.log) |
| I²C controller write | P12 and P13 send 7-bit address 0x50 with write direction and data 0x3C. A pull-up model and open-drain target supply both ACKs and hold the first ACK clock low for 331 core clocks after controller release. The check verifies START, STOP, line release, and recovery from the stretch. | [PASS_FRESH](../evidence/s14b_i2c/20261120T190427.log) | [NEG_KILLED](../evidence/s14b_i2c_neg/20261120T190428.log) |

The UART mutant lengthens the engine tick by one clock. The SPI mutant
flips the configured shift direction. The I²C mutant bypasses the SCL
wait at P13, so the controller advances during the target stretch.
[Registry](../tb_rtl/pvm_jobs.json) · [Bench](../tb_rtl/tb_protocols.v)

These pin-level jobs are Icarus-simulated and mutation-tested. The
D-016 trace-equivalence claim covers the pre- and post-repair engine
comparison. The three positive benches passed the D-020 Verilator
replay. Heet's independent rerun and Kalash's source-review sign-off
are pending. [Verilator replay](../evidence/opt/verilator_timing.log)
All three positive benches also passed local functional simulation of
the routed variant-D netlist with Tiny Tapeout's Icarus 13.0 setup.
[Gate replay evidence](../evidence/setup/s14_gate_protocols.log) · [Weekly review packet](weekly_freeze_review.md)
