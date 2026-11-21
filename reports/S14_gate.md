# PVM S14 full RTL integration — local verification passed

The runner accepted 8/8 stage jobs and 57/57 full regression jobs.

HARDWARE_VALIDATED=NO, FORMAL_PROOF=NO, GLS=NO, SILICON=NO

All four variants passed on the public SPI and GPIO interface. The full build loads UART and SPI mode 0 programs in sequence, checks UART byte 0x35 and SPI byte 0xA6 on the pins, and reads the monitor log. The tests cover recovery after a WAIT timeout and reset while the engine runs and the host holds CS active. The three HDL check counts are frozen per variant. FULL_REGRESSION and LINT_CLEAN ran as external gates.

| Job | Result | Frozen checks | Log |
| --- | --- | ---: | --- |
| s14_top_full | PASS_FRESH | 3 | [Log](../evidence/s14_top_full/20261120T165516.log) |
| s14_top_full_neg | NEG_KILLED | 3 | [Log](../evidence/s14_top_full_neg/20261120T165518.log) |
| s14_top_engine_only | PASS_FRESH | 3 | [Log](../evidence/s14_top_engine_only/20261120T165519.log) |
| s14_top_engine_only_neg | NEG_KILLED | 3 | [Log](../evidence/s14_top_engine_only_neg/20261120T165520.log) |
| s14_top_fabric | PASS_FRESH | 3 | [Log](../evidence/s14_top_fabric/20261120T165522.log) |
| s14_top_fabric_neg | NEG_KILLED | 3 | [Log](../evidence/s14_top_fabric_neg/20261120T165524.log) |
| s14_top_monitor | PASS_FRESH | 3 | [Log](../evidence/s14_top_monitor/20261120T165525.log) |
| s14_top_monitor_neg | NEG_KILLED | 3 | [Log](../evidence/s14_top_monitor_neg/20261120T165527.log) |

Verilator lint passed for all four builds. Yosys hierarchy checks passed with zero structural problems or inferred latches. The local cocotb SPI smoke test passed. XSim and the ISS remain weekly follow-ups. [Structural evidence](../evidence/setup/s14_structure.log)

The owner directed one physical run after S14. The area comparison uses the complete S14 build and the S11 routed baseline. [RTL freeze candidate](../results/rtl_freeze_report.md)
