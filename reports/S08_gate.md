# PVM S08 integration gate — CI pending

The runner accepted 4/4 stage jobs and 24/24 regression jobs.
The baseline for this stage is commit `c29812a`. The evidence JSON records the source hashes.

`HARDWARE_VALIDATED=NO, FORMAL_PROOF=NO, GLS=NO, SILICON=NO`

| Job | State | Checks | Stage log | Regression log |
| --- | --- | --- | --- | --- |
| s08_pin_guard | PASS_FRESH | 17 | [Log](../evidence/s08_pin_guard/20261120T053750.log) | [Log](../evidence/s08_pin_guard/20261120T054001.log) |
| s08_pin_guard_neg_od_one | NEG_KILLED | 17 | [Log](../evidence/s08_pin_guard_neg_od_one/20261120T053750.log) | [Log](../evidence/s08_pin_guard_neg_od_one/20261120T054001.log) |
| s08_pin_guard_neg_run_gate | NEG_KILLED | 17 | [Log](../evidence/s08_pin_guard_neg_run_gate/20261120T053750.log) | [Log](../evidence/s08_pin_guard_neg_run_gate/20261120T054001.log) |
| s08_pin_guard_neg_arb | NEG_KILLED | 17 | [Log](../evidence/s08_pin_guard_neg_arb/20261120T053750.log) | [Log](../evidence/s08_pin_guard_neg_arb/20261120T054001.log) |

The open-drain, lifecycle masking, and arbitration mutants each failed their targeted checks. The pin readback uses the driven output register plus one readback register, as specified for P5–P11.

Verilator 5.032 lint passed for the pin guard and the Tiny Tapeout wrapper (with the template's `project.v` filename exception). Icarus elaborated the wrapper in Verilog-2005 with array-sensitivity notices in the register bank. XSim is pending.

## Top-level smoke test

The cocotb smoke test passed in Icarus (1/1), covering SPI ID, program and pin configuration, CRC and committed image ID, and HALT pin safety. [Local log](../evidence/setup/s08_cocotb.log)

GitHub Actions test, GDS, and precheck must be evaluated for this integration commit. [Branch workflows](https://github.com/arnav1609/pvm-protocol-emulator/actions?query=branch%3Acodex%2Fpvm-rtl)
