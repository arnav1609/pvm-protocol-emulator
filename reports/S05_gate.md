# PVM S05 standalone RTL gate

The runner accepted 4/4 stage jobs and 14/14 regression jobs.
The baseline for this stage is commit `9dbce7a`. The evidence JSON records the source hashes.

`HARDWARE_VALIDATED=NO, FORMAL_PROOF=NO, GLS=NO, SILICON=NO`

| Job | State | Checks | Stage log | Regression log |
| --- | --- | --- | --- | --- |
| s05_hostif | PASS_FRESH | 11 | [Log](../evidence/s05_hostif/20261120T052435.log) | [Log](../evidence/s05_hostif/20261120T052449.log) |
| s05_hostif_neg_write_offset | NEG_KILLED | 11 | [Log](../evidence/s05_hostif_neg_write_offset/20261120T052435.log) | [Log](../evidence/s05_hostif_neg_write_offset/20261120T052449.log) |
| s05_hostif_neg_no_ack | NEG_KILLED | 11 | [Log](../evidence/s05_hostif_neg_no_ack/20261120T052435.log) | [Log](../evidence/s05_hostif_neg_no_ack/20261120T052449.log) |
| s05_hostif_neg_early_tx | NEG_KILLED | 11 | [Log](../evidence/s05_hostif_neg_early_tx/20261120T052435.log) | [Log](../evidence/s05_hostif_neg_early_tx/20261120T052449.log) |

The address-offset mutant failed the address checks on single, burst, wrapped, and aborted writes. The dropped acknowledgement failed `READ_RACK_SEQUENCE`. The early transmit load failed `READ_SINGLE` and `READ_BURST_8`. Each failed only its targeted checks.

Verilator 5.032 `--lint-only -Wall` passed. XSim is pending.
