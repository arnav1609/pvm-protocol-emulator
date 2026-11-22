# PVM S13 passive protocol monitor — local verification passed

The runner accepted 6/6 stage jobs and 57/57 full regression jobs.

HARDWARE_VALIDATED=NO, FORMAL_PROOF=NO, GLS=NO, SILICON=NO

The 24 monitor checks cover priority, event sources, timing guards, verdict boundaries, overflow, saturating counters, and log wrap. The I²C stretch model records PASS at 300 clocks, VIOLATION at 200, and INCONCLUSIVE at 236. The top-level bench matched a 2,000-cycle UART trace across MON_EN values. The enabled run recorded one PASS. A hierarchical netlist audit connected each monitor output only to its configuration-bank input.

On the D-018 candidate, O1b moves the minimum equality boundary to
the shared `t−M` comparison. The existing off-by-one mutant changes
`>=` to `>` at that expression and still targets only `CHECK_MIN_PASS`.
Its 24 frozen checks passed the mutation gate with that one expected
failure. The O2 history mutant exercises the edge and I²C stretch tests.
[Candidate regression](../results/opt_area_timing.md#local-verification)

| Job | Result | Frozen checks | Log |
| --- | --- | ---: | --- |
| s13_mon | PASS_FRESH | 24 | [Log](../evidence/s13_mon/20261120T165510.log) |
| s13_mon_neg_min_off_by_one | NEG_KILLED | 24 | [Log](../evidence/s13_mon_neg_min_off_by_one/20261120T165511.log) |
| s13_mon_neg_multiple_fires | NEG_KILLED | 24 | [Log](../evidence/s13_mon_neg_multiple_fires/20261120T165511.log) |
| s13_mon_neg_timer_wrap | NEG_KILLED | 24 | [Log](../evidence/s13_mon_neg_timer_wrap/20261120T165512.log) |
| s13_mon_non_intrusion | PASS_FRESH | 1 | [Log](../evidence/s13_mon_non_intrusion/20261120T165513.log) |
| s13_mon_non_intrusion_neg | NEG_KILLED | 1 | [Log](../evidence/s13_mon_non_intrusion_neg/20261120T165514.log) |

Verilator lint passed for all four builds. Yosys hierarchy checks passed with zero structural problems or inferred latches. The local cocotb SPI smoke test passed. XSim and the ISS remain weekly follow-ups. [Structural evidence](../evidence/setup/s14_structure.log)

The owner directed one physical run after S14. The area comparison uses the complete S14 build and the S11 routed baseline. [RTL freeze candidate](../results/rtl_freeze_report.md)
