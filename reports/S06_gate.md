# PVM S06 standalone RTL gate

The runner accepted 2/2 stage jobs and 16/16 regression jobs.
The baseline for this stage is commit `4f5340b`. The evidence JSON records the source hashes.

`HARDWARE_VALIDATED=NO, FORMAL_PROOF=NO, GLS=NO, SILICON=NO`

| Job | State | Checks | Stage log | Regression log |
| --- | --- | --- | --- | --- |
| s06_cfg_a | PASS_FRESH | 23 | [Log](../evidence/s06_cfg_a/20261120T053234.log) | [Log](../evidence/s06_cfg_a/20261120T053237.log) |
| s06_cfg_a_neg_halt_sticky | NEG_KILLED | 23 | [Log](../evidence/s06_cfg_a_neg_halt_sticky/20261120T053234.log) | [Log](../evidence/s06_cfg_a_neg_halt_sticky/20261120T053237.log) |

The HALT mutant now retains only TX_OVF, which fails exactly `HALT_CLEARS_STICKY`. The first injection also retained RX_UNF and crossed into `HALT_CLEARS_FIFOS`, so the injection was narrowed with the 23 frozen checks unchanged. The lifecycle tests load a legal IMEM image before validating; the approved D-012 checks cover FIFO contents, new RX underflow, and TX preload.

Verilator 5.032 `--lint-only -Wall` passed. XSim is pending.
