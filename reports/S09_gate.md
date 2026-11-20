# PVM S09 standalone RTL gate — PASS

The runner accepted 2/2 stage jobs and 26/26 full regression jobs.
Expected traces come from the testbench model and directed checks. ISS
lockstep and XSim remain pending.

`HARDWARE_VALIDATED=NO, FORMAL_PROOF=NO, GLS=NO, SILICON=NO`

| Job | State | Frozen checks | Stage log | Regression log |
| --- | --- | --- | --- | --- |
| s09_engine_a | PASS_FRESH | 33 | [Log](../evidence/s09_engine_a/20261120T080253.log) | [Log](../evidence/s09_engine_a/20261120T080322.log) |
| s09_engine_a_neg_jmp7 | NEG_KILLED | 33 | [Log](../evidence/s09_engine_a_neg_jmp7/20261120T080253.log) | [Log](../evidence/s09_engine_a_neg_jmp7/20261120T080322.log) |

The condition-7 inversion failed exactly `JMP_COND_7_NOT_TAKEN`.
The test uses WIDE with a threshold of 16, so an initial count of eight
would also fail. It checks both reset and ENABLE. Verilator 5.032 lint
passed, and Yosys 0.52 reported zero structural check problems.

The bench executes the worked SET, JMP, and EVT words and verifies the
instruction fields in the worked OUT, PULL, and WAIT words. S10 and S11
supply the corresponding datapath and WAIT behavior.

## Deviations from the stage file

- Condition 0 is unconditional, so S09 freezes `JMP_COND_0_TAKEN`.
- Both outcomes are checked for each of conditions 1–6.
- S09 freezes `JMP_COND_7_NOT_TAKEN`. Condition 7 taken is deferred to
  S10 because it needs PULL. S10 will freeze `JMP_COND_7_TAKEN` and
  exercise the same JMP with an empty OSR and after a PULL fills the OSR.
