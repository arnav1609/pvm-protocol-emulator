# PVM S04 standalone RTL gate

The runner accepted 2/2 stage jobs and 10/10 regression jobs.
The baseline for this stage is commit `6907f57`. The evidence JSON records the source hashes.

`HARDWARE_VALIDATED=NO, FORMAL_PROOF=NO, GLS=NO, SILICON=NO`

| Job | State | Checks | Stage log | Regression log |
| --- | --- | --- | --- | --- |
| s04_spi_byte | PASS_FRESH | 8 | [Log](../evidence/s04_spi_byte/20261120T052207.log) | [Log](../evidence/s04_spi_byte/20261120T052209.log) |
| s04_spi_byte_neg_msb | NEG_KILLED | 8 | [Log](../evidence/s04_spi_byte_neg_msb/20261120T052207.log) | [Log](../evidence/s04_spi_byte_neg_msb/20261120T052209.log) |

Dropping the first MISO bit failed only `TX_LOAD_96`. The 16-byte receive burst ran at the specified clk/16 limit with continuous SCK.

Verilator 5.032 `--lint-only -Wall` passed. XSim is pending.
