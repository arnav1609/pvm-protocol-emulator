# PVM S01 standalone RTL gate

The runner accepted both jobs. The baseline for this change is commit `22f328ec72439e547e9d587f10498b225298b0a4`. Each evidence JSON records the SHA-256 of the exact simulation inputs. [8x4 setup CI](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44679133846)

`HARDWARE_VALIDATED=NO, FORMAL_PROOF=NO, GLS=NO, SILICON=NO`

## Evidence

| Scope | Job | State | Checks | Log |
| --- | --- | --- | --- | --- |
| S01 | Primitives | PASS_FRESH | 17 | [Log](../evidence/s01_primitives/20261120T051604.log) |
| S01 | Synchronizer bypass | NEG_KILLED | 17 | [Log](../evidence/s01_primitives_neg_sync_bypass/20261120T051604.log) |
| Regression | Primitives | PASS_FRESH | 17 | [Log](../evidence/s01_primitives/20261120T051606.log) |
| Regression | Synchronizer bypass | NEG_KILLED | 17 | [Log](../evidence/s01_primitives_neg_sync_bypass/20261120T051606.log) |

Passing the synchronizer input straight to the output flop caused exactly `SYNC_LATENCY_2` to fail. The testbench samples tick and prescaler enables on the consuming clock edge.

Verilator 5.032 `--lint-only -Wall` passed for all four primitives. XSim is pending. The Tiny Tapeout source list still builds the template adder during the standalone stages.
