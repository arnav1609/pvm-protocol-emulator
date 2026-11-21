# PVM S03 standalone RTL gate

The runner accepted both S03 jobs and all eight regression jobs.
The baseline for this stage is commit `1ead7e4`. The evidence JSON records the source hashes.

`HARDWARE_VALIDATED=NO, FORMAL_PROOF=NO, GLS=NO, SILICON=NO`

| Job | State | Checks | Stage log | Regression log |
| --- | --- | --- | --- | --- |
| s03_imem | PASS_FRESH | 8 | [Log](../evidence/s03_imem/20261120T052024.log) | [Log](../evidence/s03_imem/20261120T052026.log) |
| s03_imem_neg_unmasked | NEG_KILLED | 8 | [Log](../evidence/s03_imem_neg_unmasked/20261120T052024.log) | [Log](../evidence/s03_imem_neg_unmasked/20261120T052026.log) |

Serving stale bytes on invalid bus reads failed exactly `BUS_READ_MASK` and `CLR_VALID`.

Verilator 5.032 `--lint-only -Wall` passed. XSim is pending.
