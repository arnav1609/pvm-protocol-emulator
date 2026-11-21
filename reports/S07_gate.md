# PVM S07 standalone RTL gate

The runner accepted 4/4 stage jobs and 20/20 regression jobs.
The baseline for this stage is commit `6883fc7`. The evidence JSON records the source hashes.

`HARDWARE_VALIDATED=NO, FORMAL_PROOF=NO, GLS=NO, SILICON=NO`

| Job | State | Checks | Stage log | Regression log |
| --- | --- | --- | --- | --- |
| s07_cfg_b | PASS_FRESH | 22 | [Log](../evidence/s07_cfg_b/20261120T053536.log) | [Log](../evidence/s07_cfg_b/20261120T053538.log) |
| s07_cfg_b_neg_od_on_uo | NEG_KILLED | 22 | [Log](../evidence/s07_cfg_b_neg_od_on_uo/20261120T053536.log) | [Log](../evidence/s07_cfg_b_neg_od_on_uo/20261120T053538.log) |
| s07_cfg_b_neg_crc_order | NEG_KILLED | 22 | [Log](../evidence/s07_cfg_b_neg_crc_order/20261120T053536.log) | [Log](../evidence/s07_cfg_b_neg_crc_order/20261120T053538.log) |
| s07_cfg_b_neg_image_id | NEG_KILLED | 22 | [Log](../evidence/s07_cfg_b_neg_image_id/20261120T053536.log) | [Log](../evidence/s07_cfg_b_neg_image_id/20261120T053538.log) |

The three mutants were killed by the open-drain pin rule, CRC-before-pins fault priority, and the latched image ID checks. Valid images complete validation within 31 core cycles.

Verilator 5.032 `--lint-only -Wall` passed. XSim is pending.
