# PVM S02 standalone RTL gate

The runner accepted four S02 jobs and all six regression jobs.
The baseline for this stage is commit `c38da66`. The evidence JSON records the source hashes.

`HARDWARE_VALIDATED=NO, FORMAL_PROOF=NO, GLS=NO, SILICON=NO`

| Job | State | Checks | Stage log | Regression log |
| --- | --- | --- | --- | --- |
| s02_fifo | PASS_FRESH | 9 | [Log](../evidence/s02_fifo/20261120T051859.log) | [Log](../evidence/s02_fifo/20261120T051910.log) |
| s02_fifo_neg | NEG_KILLED | 9 | [Log](../evidence/s02_fifo_neg/20261120T051859.log) | [Log](../evidence/s02_fifo_neg/20261120T051910.log) |
| s02_crc16 | PASS_FRESH | 5 | [Log](../evidence/s02_crc16/20261120T051900.log) | [Log](../evidence/s02_crc16/20261120T051910.log) |
| s02_crc16_neg | NEG_KILLED | 5 | [Log](../evidence/s02_crc16_neg/20261120T051900.log) | [Log](../evidence/s02_crc16_neg/20261120T051910.log) |

Suppressing the FIFO overflow pulse failed `OVF_DROP` and `WRAP`.
Ignoring the CRC clear strobe failed `CLR_RESTART`. Each mutant failed only its targeted checks.

Verilator 5.032 `--lint-only -Wall` passed for both modules. XSim is pending.
