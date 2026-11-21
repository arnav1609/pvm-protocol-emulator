# PVM S14 RTL freeze candidate

Full RTL integrated and simulated on 20 November 2026. The candidate
passed the routed timing, area, and Tiny Tapeout precheck requirements.

HARDWARE_VALIDATED=NO, FORMAL_PROOF=NO, GLS=NO, SILICON=NO

The default build uses the approved 8×4 IHP CMOS5L target at 50 MHz.

| Variant | Defines | System checks | Generic synthesis cells |
| --- | --- | --- | ---: |
| A · engine | PVM_NO_FABRIC and PVM_NO_MON | Passed | 14,986 |
| B · engine + fabric | PVM_NO_MON | Passed | 16,472 |
| C · engine + monitor | PVM_NO_FABRIC | Passed | 19,415 |
| D · full | Default | Passed | 21,806 |

The variant counts are Yosys 0.52 and ABC generic cells before technology
mapping. Routed measurements use the IHP CMOS5L flow.

[Full-design GDS run](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44778669345) · [RTL smoke CI](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44778669706) · [Datasheet CI](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44778669332)

## Physical results

The routed build used commit `aa2996b1d2be115531f00b5ce7b0ace52d964b14`.
The combined fabric and monitor increase over S11 was 7,057 routed
standard cells and 7.7589 percentage points of utilization. The four
generic syntheses above provide a separate per-variant size comparison.
[S11 routed baseline](g2_timing_repair.md) · [S14 submission metrics](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44778669345/artifacts/14658475695)

| Routed metric | Full S14 |
| --- | ---: |
| Standard cells | 28,091 |
| Standard-cell area | 407,380 µm² |
| Standard-cell utilization | 33.7187% |
| Slow-corner worst setup slack | +2.461 ns |
| Typical and fast worst setup slack | +7.482 ns and +10.476 ns |
| Worst hold slack | +0.122 ns |
| Setup and hold violations | 0 |
| Detailed routing violations | 0 |

| CI job | Result |
| --- | --- |
| GDS | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44778669345/job/136435216541) |
| Gate-level simulation | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44778669345/job/136489409832) |
| Pages viewer | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44778669345/job/136489410613) |
| Tiny Tapeout precheck | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44778669345/job/136489409850) |

## Regression

Full runner selection accepted 63/63 jobs, including the six S14b protocol jobs. The D-016 golden traces regenerated identically. All four Verilator runs, the Yosys structural checks, and the local cocotb SPI smoke test passed. [Structural evidence](../evidence/setup/s14_structure.log)

| Stage | Job | Frozen checks | Result |
| --- | --- | ---: | --- |
| S01 | s01_primitives | 17 | [PASS_FRESH](../evidence/s01_primitives/20261120T165504.log) |
| S01 | s01_primitives_neg_sync_bypass | 17 | [NEG_KILLED](../evidence/s01_primitives_neg_sync_bypass/20261120T165505.log) |
| S02 | s02_fifo | 9 | [PASS_FRESH](../evidence/s02_fifo/20261120T165505.log) |
| S02 | s02_fifo_neg | 9 | [NEG_KILLED](../evidence/s02_fifo_neg/20261120T165505.log) |
| S02 | s02_crc16 | 5 | [PASS_FRESH](../evidence/s02_crc16/20261120T165505.log) |
| S02 | s02_crc16_neg | 5 | [NEG_KILLED](../evidence/s02_crc16_neg/20261120T165505.log) |
| S03 | s03_imem | 8 | [PASS_FRESH](../evidence/s03_imem/20261120T165505.log) |
| S03 | s03_imem_neg_unmasked | 8 | [NEG_KILLED](../evidence/s03_imem_neg_unmasked/20261120T165505.log) |
| S04 | s04_spi_byte | 8 | [PASS_FRESH](../evidence/s04_spi_byte/20261120T165505.log) |
| S04 | s04_spi_byte_neg_msb | 8 | [NEG_KILLED](../evidence/s04_spi_byte_neg_msb/20261120T165505.log) |
| S05 | s05_hostif | 11 | [PASS_FRESH](../evidence/s05_hostif/20261120T165505.log) |
| S05 | s05_hostif_neg_write_offset | 11 | [NEG_KILLED](../evidence/s05_hostif_neg_write_offset/20261120T165505.log) |
| S05 | s05_hostif_neg_no_ack | 11 | [NEG_KILLED](../evidence/s05_hostif_neg_no_ack/20261120T165505.log) |
| S05 | s05_hostif_neg_early_tx | 11 | [NEG_KILLED](../evidence/s05_hostif_neg_early_tx/20261120T165505.log) |
| S06 | s06_cfg_a | 23 | [PASS_FRESH](../evidence/s06_cfg_a/20261120T165505.log) |
| S06 | s06_cfg_a_neg_halt_sticky | 23 | [NEG_KILLED](../evidence/s06_cfg_a_neg_halt_sticky/20261120T165505.log) |
| S07 | s07_cfg_b | 22 | [PASS_FRESH](../evidence/s07_cfg_b/20261120T165505.log) |
| S07 | s07_cfg_b_neg_od_on_uo | 22 | [NEG_KILLED](../evidence/s07_cfg_b_neg_od_on_uo/20261120T165505.log) |
| S07 | s07_cfg_b_neg_crc_order | 22 | [NEG_KILLED](../evidence/s07_cfg_b_neg_crc_order/20261120T165505.log) |
| S07 | s07_cfg_b_neg_image_id | 22 | [NEG_KILLED](../evidence/s07_cfg_b_neg_image_id/20261120T165505.log) |
| S08 | s08_pin_guard | 17 | [PASS_FRESH](../evidence/s08_pin_guard/20261120T165505.log) |
| S08 | s08_pin_guard_neg_od_one | 17 | [NEG_KILLED](../evidence/s08_pin_guard_neg_od_one/20261120T165505.log) |
| S08 | s08_pin_guard_neg_run_gate | 17 | [NEG_KILLED](../evidence/s08_pin_guard_neg_run_gate/20261120T165506.log) |
| S08 | s08_pin_guard_neg_arb | 17 | [NEG_KILLED](../evidence/s08_pin_guard_neg_arb/20261120T165506.log) |
| S09 | s09_engine_a | 33 | [PASS_FRESH](../evidence/s09_engine_a/20261120T165506.log) |
| S09 | s09_engine_a_neg_jmp7 | 33 | [NEG_KILLED](../evidence/s09_engine_a_neg_jmp7/20261120T165506.log) |
| S10 | s10_engine_b | 40 | [PASS_FRESH](../evidence/s10_engine_b/20261120T165506.log) |
| S10 | s10_engine_b_neg_wide_pull_byte_order | 40 | [NEG_KILLED](../evidence/s10_engine_b_neg_wide_pull_byte_order/20261120T165506.log) |
| S11 | s11_engine_c | 12 | [PASS_FRESH](../evidence/s11_engine_c/20261120T165506.log) |
| S11 | s11_engine_c_neg_timeout_priority | 12 | [NEG_KILLED](../evidence/s11_engine_c_neg_timeout_priority/20261120T165506.log) |
| S11 | s11_engine_c_neg_wait_polarity | 12 | [NEG_KILLED](../evidence/s11_engine_c_neg_wait_polarity/20261120T165506.log) |
| S11 | s11_engine_c_neg_fault_keep_running | 12 | [NEG_KILLED](../evidence/s11_engine_c_neg_fault_keep_running/20261120T165506.log) |
| S11 | s11_top | 2 | [PASS_FRESH](../evidence/s11_top/20261120T165507.log) |
| S11 | s11_top_neg_fault_guard | 2 | [NEG_KILLED](../evidence/s11_top_neg_fault_guard/20261120T165508.log) |
| G2_TRACE | s11_trace_equiv_tb_engine_a | 1 | [PASS_FRESH](../evidence/s11_trace_equiv_tb_engine_a/20261120T165508.log) |
| G2_TRACE | s11_trace_equiv_tb_engine_b | 1 | [PASS_FRESH](../evidence/s11_trace_equiv_tb_engine_b/20261120T165508.log) |
| G2_TRACE | s11_trace_equiv_tb_engine_c | 1 | [PASS_FRESH](../evidence/s11_trace_equiv_tb_engine_c/20261120T165508.log) |
| G2_TRACE | s11_trace_equiv_tb_top_s11 | 1 | [PASS_FRESH](../evidence/s11_trace_equiv_tb_top_s11/20261120T165509.log) |
| G2_TRACE | s11_trace_equiv_tb_engine_c_neg_delayed_out | 1 | [NEG_KILLED](../evidence/s11_trace_equiv_tb_engine_c_neg_delayed_out/20261120T165509.log) |
| S12 | s12_fabric | 21 | [PASS_FRESH](../evidence/s12_fabric/20261120T165509.log) |
| S12 | s12_fabric_neg_layer_feedback | 21 | [NEG_KILLED](../evidence/s12_fabric_neg_layer_feedback/20261120T165509.log) |
| S12 | s12_fabric_neg_maj2 | 21 | [NEG_KILLED](../evidence/s12_fabric_neg_maj2/20261120T165510.log) |
| S12 | s12_fabric_neg_ignore_arb_n | 21 | [NEG_KILLED](../evidence/s12_fabric_neg_ignore_arb_n/20261120T165510.log) |
| S13 | s13_mon | 24 | [PASS_FRESH](../evidence/s13_mon/20261120T165510.log) |
| S13 | s13_mon_neg_min_off_by_one | 24 | [NEG_KILLED](../evidence/s13_mon_neg_min_off_by_one/20261120T165511.log) |
| S13 | s13_mon_neg_multiple_fires | 24 | [NEG_KILLED](../evidence/s13_mon_neg_multiple_fires/20261120T165511.log) |
| S13 | s13_mon_neg_timer_wrap | 24 | [NEG_KILLED](../evidence/s13_mon_neg_timer_wrap/20261120T165512.log) |
| S13 | s13_mon_non_intrusion | 1 | [PASS_FRESH](../evidence/s13_mon_non_intrusion/20261120T165513.log) |
| S13 | s13_mon_non_intrusion_neg | 1 | [NEG_KILLED](../evidence/s13_mon_non_intrusion_neg/20261120T165514.log) |
| S14 | s14_top_full | 3 | [PASS_FRESH](../evidence/s14_top_full/20261120T165516.log) |
| S14 | s14_top_full_neg | 3 | [NEG_KILLED](../evidence/s14_top_full_neg/20261120T165518.log) |
| S14 | s14_top_engine_only | 3 | [PASS_FRESH](../evidence/s14_top_engine_only/20261120T165519.log) |
| S14 | s14_top_engine_only_neg | 3 | [NEG_KILLED](../evidence/s14_top_engine_only_neg/20261120T165520.log) |
| S14 | s14_top_fabric | 3 | [PASS_FRESH](../evidence/s14_top_fabric/20261120T165522.log) |
| S14 | s14_top_fabric_neg | 3 | [NEG_KILLED](../evidence/s14_top_fabric_neg/20261120T165524.log) |
| S14 | s14_top_monitor | 3 | [PASS_FRESH](../evidence/s14_top_monitor/20261120T165525.log) |
| S14 | s14_top_monitor_neg | 3 | [NEG_KILLED](../evidence/s14_top_monitor_neg/20261120T165527.log) |
| S14b_protocols | s14b_uart | 1 | [PASS_FRESH](../evidence/s14b_uart/20261120T190424.log) |
| S14b_protocols | s14b_uart_neg | 1 | [NEG_KILLED](../evidence/s14b_uart_neg/20261120T190425.log) |
| S14b_protocols | s14b_spi | 1 | [PASS_FRESH](../evidence/s14b_spi/20261120T190426.log) |
| S14b_protocols | s14b_spi_neg | 1 | [NEG_KILLED](../evidence/s14b_spi_neg/20261120T190426.log) |
| S14b_protocols | s14b_i2c | 1 | [PASS_FRESH](../evidence/s14b_i2c/20261120T190427.log) |
| S14b_protocols | s14b_i2c_neg | 1 | [NEG_KILLED](../evidence/s14b_i2c_neg/20261120T190428.log) |

## Remaining verification

Kalash’s XSim and source review are the remaining RTL freeze gates. The ISS is a separate toolchain deliverable. [S14b pin-level checks](../reports/S14b_protocols_gate.md) · [Weekly review packet](../reports/weekly_freeze_review.md)
