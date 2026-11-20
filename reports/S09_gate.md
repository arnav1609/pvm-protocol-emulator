# PVM S09 gate — pending S08 sign-off

The JMP coverage below was approved in chat on 20 November 2026.
S09 job registration and simulation are pending.

## Deviations from the stage file

- Freeze `JMP_COND_0_TAKEN`. Condition 0 is unconditional and has no
  not-taken case.
- Freeze `JMP_COND_1_TAKEN` and `JMP_COND_1_NOT_TAKEN` through
  `JMP_COND_6_TAKEN` and `JMP_COND_6_NOT_TAKEN`.
- Freeze `JMP_COND_7_NOT_TAKEN` in S09. D-013 makes the OSR empty at reset
  and ENABLE. The taken case is deferred to S10 because it needs PULL.
  Inverting condition 7 must kill the mutant on
  `JMP_COND_7_NOT_TAKEN`.
- S09 `checks_basis` will record: “cond 0 has no not-taken case; cond 7
  taken deferred to S10 (needs PULL)”.
- Freeze `JMP_COND_7_TAKEN` in S10 and cite the S09 deferral in
  `checks_basis`. Run the same JMP with the OSR empty and again after a
  PULL. The second run must take the branch.
