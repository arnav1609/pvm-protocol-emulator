# Verilator freeze-candidate replay

Candidate commit `35f8d942b1a6107c71dff9b58b7f05ad7cc62276`. Run date 21 November 2026 (IST).
Simulator `Verilator 5.032 2025-01-01 rev (Debian 5.032-1+b2)`.

**Randomized-initialization replay 48/48 passed.** The run compiled 24 distinct positive RTL bench configurations and executed each build with seeds 1 and 2.

```sh
verilator --binary --timing --language 1364-2005 --x-assign unique --x-initial unique \
  -Wno-fatal -CFLAGS -O0 -j 1 --top-module <top> --Mdir <obj> -o sim \
  <registry defines, includes, and sources>
<obj>/sim +verilator+rand+reset+2 +verilator+seed+1
<obj>/sim +verilator+rand+reset+2 +verilator+seed+2
```

Each seed result below is shown as `CHECKS / ERRORS / RESULT`.
The two seeds exercise reset and initialization in the covered scenarios.
Icarus remains the four-state reference and retains the mutation suite.
[Frozen registry](../tb_rtl/pvm_jobs.json)

## Direct Verilator builds

| Registry job / build | Top | Defines | Frozen | Seed 1 | Seed 2 |
| --- | --- | --- | ---: | --- | --- |
| `s01_primitives` | `tb_primitives` | — | 17 | 17 / 0 / PASS | 17 / 0 / PASS |
| `s02_fifo` | `tb_fifo` | — | 9 | 9 / 0 / PASS | 9 / 0 / PASS |
| `s02_crc16` | `tb_crc16` | — | 5 | 5 / 0 / PASS | 5 / 0 / PASS |
| `s03_imem` | `tb_imem` | — | 8 | 8 / 0 / PASS | 8 / 0 / PASS |
| `s04_spi_byte` | `tb_spi_byte` | — | 8 | 8 / 0 / PASS | 8 / 0 / PASS |
| `s05_hostif` | `tb_hostif` | — | 11 | 11 / 0 / PASS | 11 / 0 / PASS |
| `s06_cfg_a` | `tb_cfg_a` | — | 23 | 23 / 0 / PASS | 23 / 0 / PASS |
| `s07_cfg_b` | `tb_cfg_b` | — | 22 | 22 / 0 / PASS | 22 / 0 / PASS |
| `s08_pin_guard` | `tb_pin_guard` | — | 17 | 17 / 0 / PASS | 17 / 0 / PASS |
| `s09_engine_a` | `tb_engine_a` | — | 33 | 33 / 0 / PASS | 33 / 0 / PASS |
| `s10_engine_b` | `tb_engine_b` | — | 40 | 40 / 0 / PASS | 40 / 0 / PASS |
| `s11_engine_c` | `tb_engine_c` | — | 12 | 12 / 0 / PASS | 12 / 0 / PASS |
| `s11_top` | `tb_top_s11` | — | 2 | 2 / 0 / PASS | 2 / 0 / PASS |
| `s12_fabric` | `tb_fabric` | — | 21 | 21 / 0 / PASS | 21 / 0 / PASS |
| `s13_mon` | `tb_mon` | — | 24 | 24 / 0 / PASS | 24 / 0 / PASS |
| `s13_mon_non_intrusion` | `tb_top` | `PVM_MON_NON_INTRUSION` | 1 | 1 / 0 / PASS | 1 / 0 / PASS |
| `s14_top_full` | `tb_top` | — | 3 | 3 / 0 / PASS | 3 / 0 / PASS |
| `s14_top_engine_only` | `tb_top` | `PVM_NO_FABRIC`, `PVM_NO_MON` | 3 | 3 / 0 / PASS | 3 / 0 / PASS |
| `s14_top_fabric` | `tb_top` | `PVM_NO_MON` | 3 | 3 / 0 / PASS | 3 / 0 / PASS |
| `s14_top_monitor` | `tb_top` | `PVM_NO_FABRIC` | 3 | 3 / 0 / PASS | 3 / 0 / PASS |
| `s14b_uart` | `tb_protocols` | `PVM_PROTOCOL_UART` | 1 | 1 / 0 / PASS | 1 / 0 / PASS |
| `s14b_spi` | `tb_protocols` | `PVM_PROTOCOL_SPI` | 1 | 1 / 0 / PASS | 1 / 0 / PASS |
| `s14b_i2c` | `tb_protocols` | `PVM_PROTOCOL_I2C` | 1 | 1 / 0 / PASS | 1 / 0 / PASS |
| `d017_reset_sync` | `tb_reset_sync` | — | 3 | 3 / 0 / PASS | 3 / 0 / PASS |

## D-016 trace-job coverage

These four positive registry jobs reuse the builds below. The seeded
columns show the underlying Verilog bench result. The trace result
column shows the one-check CSV comparison rerun in Icarus on the
same candidate. The Icarus output-delay trace mutant was caught.

| Positive trace job | Verilator build | Top | Defines | Bench frozen | Seed 1 | Seed 2 | Trace frozen | Icarus trace |
| --- | --- | --- | --- | ---: | --- | --- | ---: | --- |
| `s11_trace_equiv_tb_engine_a` | `s09_engine_a` | `tb_engine_a` | — | 33 | 33 / 0 / PASS | 33 / 0 / PASS | 1 | 1 / 0 / PASS |
| `s11_trace_equiv_tb_engine_b` | `s10_engine_b` | `tb_engine_b` | — | 40 | 40 / 0 / PASS | 40 / 0 / PASS | 1 | 1 / 0 / PASS |
| `s11_trace_equiv_tb_engine_c` | `s11_engine_c` | `tb_engine_c` | — | 12 | 12 / 0 / PASS | 12 / 0 / PASS | 1 | 1 / 0 / PASS |
| `s11_trace_equiv_tb_top_s11` | `s11_top` | `tb_top_s11` | — | 2 | 2 / 0 / PASS | 2 / 0 / PASS | 1 | 1 / 0 / PASS |

## RTL lint

Verilator `--lint-only -Wall` reported 53 warning instances across
the four variants. The unwaived runs treated those warnings as errors.
The reruns scoped each waiver to its warning class, file and line.
All four lint runs then exited cleanly with zero unwaived diagnostics.

| Variant | Defines | Raw warnings | Unwaived warnings |
| --- | --- | ---: | ---: |
| A | `PVM_NO_FABRIC`, `PVM_NO_MON` | 23 | 0 |
| B | `PVM_NO_MON` | 8 | 0 |
| C | `PVM_NO_FABRIC` | 18 | 0 |
| D | — | 4 | 0 |

| Warning | Location | Variants | Diagnostic | Waiver reason |
| --- | --- | --- | --- | --- |
| `DECLFILENAME` | [src/project.v:6:8](../src/project.v#L6) | A, B, C, D | Filename 'project' does not match MODULE name: 'tt_um_arnav1609_pvm' | Tiny Tapeout project.v is the template file name and the wrapper has its required project-specific module name. |
| `UNUSEDSIGNAL` | [src/pvm_top.v:30:17](../src/pvm_top.v#L30) | A, C | Signal is not used: 'od_release_intent' | PVM_NO_FABRIC omits the only consumer. Shared top-level wiring is retained for the four variants. |
| `UNUSEDSIGNAL` | [src/pvm_top.v:45:10](../src/pvm_top.v#L45) | A, C | Signal is not used: 'engine_tick' | PVM_NO_FABRIC omits the only consumer. Shared top-level wiring is retained for the four variants. |
| `UNUSEDSIGNAL` | [src/pvm_top.v:45:23](../src/pvm_top.v#L45) | A, C | Signal is not used: 'fab_wr' | PVM_NO_FABRIC omits the only consumer. Shared top-level wiring is retained for the four variants. |
| `UNUSEDSIGNAL` | [src/pvm_top.v:45:31](../src/pvm_top.v#L45) | A, C | Signal is not used: 'evt_clr_arb' | PVM_NO_FABRIC omits the only consumer. Shared top-level wiring is retained for the four variants. |
| `UNUSEDSIGNAL` | [src/pvm_top.v:45:44](../src/pvm_top.v#L45) | A, C | Signal is not used: 'evt_clr_unf' | PVM_NO_FABRIC omits the only consumer. Shared top-level wiring is retained for the four variants. |
| `UNUSEDSIGNAL` | [src/pvm_top.v:46:16](../src/pvm_top.v#L46) | A, C | Signal is not used: 'fab_ctrl' | PVM_NO_FABRIC omits the only consumer. Shared top-level wiring is retained for the four variants. |
| `UNUSEDSIGNAL` | [src/pvm_top.v:62:10](../src/pvm_top.v#L62) | A | Signal is not used: 'halt_pulse' | Only the fabric and monitor consume halt_pulse at the wrapper. Both blocks are omitted in variant A. |
| `UNUSEDSIGNAL` | [src/pvm_top.v:63:10](../src/pvm_top.v#L63) | A, C | Signal is not used: 'clr_flags_pulse' | PVM_NO_FABRIC omits the only consumer. Shared top-level wiring is retained for the four variants. |
| `UNUSEDSIGNAL` | [src/pvm_top.v:80:18](../src/pvm_top.v#L80) | A, C | Signal is not used: 'cfg_lut' | PVM_NO_FABRIC omits the only consumer. Shared top-level wiring is retained for the four variants. |
| `UNUSEDSIGNAL` | [src/pvm_top.v:81:17](../src/pvm_top.v#L81) | A, C | Signal is not used: 'cfg_mode' | PVM_NO_FABRIC omits the only consumer. Shared top-level wiring is retained for the four variants. |
| `UNUSEDSIGNAL` | [src/pvm_top.v:82:16](../src/pvm_top.v#L82) | A, C | Signal is not used: 'cnt_reload' | PVM_NO_FABRIC omits the only consumer. Shared top-level wiring is retained for the four variants. |
| `UNUSEDSIGNAL` | [src/pvm_top.v:83:10](../src/pvm_top.v#L83) | A, C | Signal is not used: 'cnt_en' | PVM_NO_FABRIC omits the only consumer. Shared top-level wiring is retained for the four variants. |
| `UNUSEDSIGNAL` | [src/pvm_top.v:84:10](../src/pvm_top.v#L84) | A, C | Signal is not used: 'cnt_src' | PVM_NO_FABRIC omits the only consumer. Shared top-level wiring is retained for the four variants. |
| `UNUSEDSIGNAL` | [src/pvm_top.v:85:10](../src/pvm_top.v#L85) | A, C | Signal is not used: 'manch_en' | PVM_NO_FABRIC omits the only consumer. Shared top-level wiring is retained for the four variants. |
| `UNUSEDSIGNAL` | [src/pvm_top.v:86:16](../src/pvm_top.v#L86) | A, C | Signal is not used: 'arb_n' | PVM_NO_FABRIC omits the only consumer. Shared top-level wiring is retained for the four variants. |
| `UNUSEDSIGNAL` | [src/pvm_top.v:87:18](../src/pvm_top.v#L87) | A, B | Signal is not used: 'cfg_entries' | PVM_NO_MON omits the only consumer. Shared top-level wiring is retained for the four variants. |
| `UNUSEDSIGNAL` | [src/pvm_top.v:88:17](../src/pvm_top.v#L88) | A, B | Signal is not used: 'cfg_k' | PVM_NO_MON omits the only consumer. Shared top-level wiring is retained for the four variants. |
| `UNUSEDSIGNAL` | [src/pvm_top.v:89:17](../src/pvm_top.v#L89) | A, B | Signal is not used: 'cfg_m' | PVM_NO_MON omits the only consumer. Shared top-level wiring is retained for the four variants. |
| `UNUSEDSIGNAL` | [src/pvm_top.v:90:10](../src/pvm_top.v#L90) | A, B | Signal is not used: 'mon_en' | PVM_NO_MON omits the only consumer. Shared top-level wiring is retained for the four variants. |
| `UNUSEDSIGNAL` | [src/pvm_top.v:91:16](../src/pvm_top.v#L91) | A, B | Signal is not used: 'mon_presc' | PVM_NO_MON omits the only consumer. Shared top-level wiring is retained for the four variants. |
| `BLKSEQ` | [src/pvm_engine.v:163:17](../src/pvm_engine.v#L163) | A, B, C, D | Blocking assignment '=' in sequential logic process | Blocking assignments are to the local protocol_pin sum temporary, in calculation order. The function returns the wrapped index. |
| `BLKSEQ` | [src/pvm_engine.v:165:21](../src/pvm_engine.v#L165) | A, B, C, D | Blocking assignment '=' in sequential logic process | Blocking assignments are to the local protocol_pin sum temporary, in calculation order. The function returns the wrapped index. |
| `UNUSEDSIGNAL` | [src/pvm_mon.v:57:25](../src/pvm_mon.v#L57) | C, D | Bits of signal are not used: 'entry'[23:21] | Monitor entry bits [23:21] are reserved by spec 03 and masked at configuration write. |

Kalash's source-review sign-off for the tested commit is pending.
[Build and run logs](../evidence/opt/verilator_random_35f8d94.log) · [Owner review](../reports/weekly_freeze_review.md)
