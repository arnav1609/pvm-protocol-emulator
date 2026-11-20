# PVM S11 top-level integration — G2 pending

The runner accepted 6/6 stage jobs and 34/34 regression jobs.
The baseline for this stage is commit `8e1235f`. The evidence JSON records the source hashes.

`HARDWARE_VALIDATED=NO, FORMAL_PROOF=NO, GLS=NO, SILICON=NO`

| Job | State | Checks | Stage log | Regression log |
| --- | --- | --- | --- | --- |
| s11_engine_c | PASS_FRESH | 12 | [Log](../evidence/s11_engine_c/20261120T083923.log) | [Log](../evidence/s11_engine_c/20261120T083942.log) |
| s11_engine_c_neg_timeout_priority | NEG_KILLED | 12 | [Log](../evidence/s11_engine_c_neg_timeout_priority/20261120T083923.log) | [Log](../evidence/s11_engine_c_neg_timeout_priority/20261120T083943.log) |
| s11_engine_c_neg_wait_polarity | NEG_KILLED | 12 | [Log](../evidence/s11_engine_c_neg_wait_polarity/20261120T083923.log) | [Log](../evidence/s11_engine_c_neg_wait_polarity/20261120T083943.log) |
| s11_engine_c_neg_fault_keep_running | NEG_KILLED | 12 | [Log](../evidence/s11_engine_c_neg_fault_keep_running/20261120T083923.log) | [Log](../evidence/s11_engine_c_neg_fault_keep_running/20261120T083943.log) |
| s11_top | PASS_FRESH | 2 | [Log](../evidence/s11_top/20261120T083924.log) | [Log](../evidence/s11_top/20261120T083943.log) |
| s11_top_neg_fault_guard | NEG_KILLED | 2 | [Log](../evidence/s11_top_neg_fault_guard/20261120T083924.log) | [Log](../evidence/s11_top_neg_fault_guard/20261120T083943.log) |

The four mutants were killed by the same-cycle timeout priority, WAIT polarity, fault stop, and bidirectional output safety checks. The top-level bench uses only SPI and pad signals to load a UART image, transmit 0x35 from the host TX FIFO, and confirm that an engine timeout releases the driven pin and reports fault PC 2.

Verilator 5.032 lint passed. Yosys 0.52 reported zero structural issues and no latches after optimization. The cocotb SPI smoke test passed locally. XSim and ISS remain pending.

The engine, instruction-memory addressing, both FIFO paths, and lifecycle faults are wired into the Tiny Tapeout top. G2 requires routed utilization and setup slack at 50 MHz, successful precheck, and a green Pages viewer. [Branch workflows](https://github.com/arnav1609/pvm-protocol-emulator/actions?query=branch%3Acodex%2Fpvm-rtl)
