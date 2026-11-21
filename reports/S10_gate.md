# PVM S10 standalone RTL gate — PASS

The runner accepted 2/2 S10 jobs and 28/28 full regression jobs. Expected
traces come from the testbench model and directed checks. ISS lockstep
and XSim remain pending.

`HARDWARE_VALIDATED=NO, FORMAL_PROOF=NO, GLS=NO, SILICON=NO`

| Job | State | Frozen checks | Stage log | Regression log |
| --- | --- | --- | --- | --- |
| s10_engine_b | PASS_FRESH | 40 | [Log](../evidence/s10_engine_b/20261120T083536.log) | [Log](../evidence/s10_engine_b/20261120T083539.log) |
| s10_engine_b_neg_wide_pull_byte_order | NEG_KILLED | 40 | [Log](../evidence/s10_engine_b_neg_wide_pull_byte_order/20261120T083536.log) | [Log](../evidence/s10_engine_b_neg_wide_pull_byte_order/20261120T083539.log) |

The byte-order mutant failed exactly `WIDE_PULL_2BYTES_LE` and
`WIDE_AUTOPULL`. WIDE tests checked the two engine ticks at CLKDIV 1
and 3, wait with one TX byte, wait with one free RX slot, and ordering
when the host reads RX between the beats. The same JMP 7 fell through
with the OSR empty and jumped after a PULL filled it.

Both EXEC forms checked parent and injected delay, advance and wrap,
jump, side-set and WAIT, nested and illegal word faults, WAIT timeout,
and a blocking FIFO operation. The engine reports the parent PC on
injected faults. WAIT and timeout logic landed in S10 for these tests.

At CLKDIV 3 the UART TX bench checked every core cycle. Relative to
completion of the setup, the start bit begins at core cycle 3, data bit
0 begins at cycle 9, and the stop bit begins at cycle 57. Each bit spans
six core cycles. The RX bench replayed the captured TX data bits and
confirmed 0x35 at the RX FIFO head.

Verilator 5.032 lint passed. Yosys 0.52 found zero structural issues
and no inferred latches after optimization.
