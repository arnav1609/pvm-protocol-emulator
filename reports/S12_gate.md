# PVM S12 pin fabric — local verification passed

The runner accepted 4/4 stage jobs and 57/57 full regression jobs.

HARDWARE_VALIDATED=NO, FORMAL_PROOF=NO, GLS=NO, SILICON=NO

The 21 frozen checks cover 1,000 seeded LUT vectors, both source groups, registered feed-forward layers, output modes, counter reloads and tick gating, a decoded 16-bit Manchester stream, and the exact arbitration release bound. A Manchester boundary write queues the next bit while the previous holding bit is consumed. The datapath clears outside RUN and evidence flags follow the explicit sticky clear events in the fabric and lifecycle specs. The arbitration check uses the real synchronizer and pin guard and observes OE dropping two clocks after the synchronized sample, four after the pad.

| Job | Result | Frozen checks | Log |
| --- | --- | ---: | --- |
| s12_fabric | PASS_FRESH | 21 | [Log](../evidence/s12_fabric/20261120T165509.log) |
| s12_fabric_neg_layer_feedback | NEG_KILLED | 21 | [Log](../evidence/s12_fabric_neg_layer_feedback/20261120T165509.log) |
| s12_fabric_neg_maj2 | NEG_KILLED | 21 | [Log](../evidence/s12_fabric_neg_maj2/20261120T165510.log) |
| s12_fabric_neg_ignore_arb_n | NEG_KILLED | 21 | [Log](../evidence/s12_fabric_neg_ignore_arb_n/20261120T165510.log) |

Verilator lint passed for all four builds. Yosys hierarchy checks passed with zero structural problems or inferred latches. The local cocotb SPI smoke test passed. XSim and the ISS remain weekly follow-ups. [Structural evidence](../evidence/setup/s14_structure.log)

The owner directed one physical run after S14. The area comparison uses the complete S14 build and the S11 routed baseline. [RTL freeze candidate](../results/rtl_freeze_report.md)
