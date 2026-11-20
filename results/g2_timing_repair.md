# G2 timing repair under D-016 — PASS

Repair 2 passed G2 at 50 MHz with +5.102 ns slow-corner setup slack and
25.9598% standard-cell utilization. The 8×4 tile budget and the D-016
+1.0 ns timing margin are met. S12 is unblocked.
[D-016](../spec/DECISIONS.md#d-016--s11-g2-timing-repair-at-50-mhz) · [Original G2 failure](g2_area_timing.md)

## Trace acceptance

Kalash designated the accepted RTL at `4b13f45` as the D-016
reference. The four S09–S11 benches record one CSV row per core clock
with `+TRACE`. Sampling occurs at the rising edge before register
updates. The validity column describes the instruction on issue attempts,
including injected instructions. It is zero between issue attempts.
The RX byte is recorded on push cycles. Standalone benches record the
run enable, and the top-level bench records the lifecycle state.
[Read-only reuse kit](../reference/noc_patterns/README.md)

```sh
python3 tb_rtl/pvm_run.py trace-golden --check
python3 tb_rtl/pvm_run.py run --select G2_TRACE
```

The generator compiles a copied tree of golden RTL with the same
instrumented benches, and `--check` regenerates and verifies all CSVs
and their SHA-256 manifest. The trace jobs each have one frozen check.
The original frozen check counts are unchanged.
[Golden traces and provenance](../tb_rtl/vectors/)

## Repair 1

Image validation now reads the validity bit addressed by `ENTRY_PC`
directly. The engine PC drives the instruction read port in every state.
Both reads use the existing valid-bit vector.

The unchanged frozen jobs accepted S09 (2/2), S10 (2/2), and S11 (6/6).
The full regression accepted 39/39 jobs, including the five trace jobs.
Verilator lint, Yosys structure checks, and the local cocotb smoke test
passed. GitHub Actions passed the RTL smoke test and datasheet build on
commit `9a38168`.
[Regression records](../evidence/) · [S11 top-level regression](../evidence/s11_top/20261120T124536.log) · [RTL CI](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44732758403) · [Datasheet CI](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44732758628)

Repair 1 is **trace-equivalent to pre-repair RTL** across the four
registered workloads, with 27,578 matching core cycles.
The negative job detected the one-cycle `out_val` delay at cycle 23.
A separate SPI probe verified rejection of an unwritten entry at PC 9
when PC 0 holds a valid word, then successful execution at PC 9 with
PC 0 unwritten.
[Trace results](../evidence/s11_trace_equiv_tb_top_s11/20261120T124537.json) · [Negative job](../evidence/s11_trace_equiv_tb_engine_c_neg_delayed_out/20261120T124537.json)

Repair 1 missed the +1.0 ns target in the slow corner. Its worst
setup slack improved by 3.133 ns relative to the original routed result.
The worst path still passes through the instruction-memory mux and ends
at `pvm.engine.out_val[16]` with a 26.106 ns arrival time and a 20.346 ns
requirement. GDS failed on setup timing. Precheck, gate-level simulation,
and the viewer were skipped.
[Repair 1 GDS run](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44732758406) · [Routed reports](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44732758406/artifacts/14632930991)

| Routed metric | Repair 1 |
| --- | ---: |
| Setup worst slack, slow | −5.761 ns |
| Setup worst slack, typical / fast | +3.701 ns / +9.498 ns |
| Setup total negative slack | −95.271 ns |
| Setup violating endpoints | 23 |
| Worst hold slack | +0.107 ns |
| Standard cells | 22,539 |
| Standard-cell utilization | 26.2945% |
| Detailed routing violations | 0 |

## Repair 2

At ENABLE the instruction register loads the entry word. On the
tick that completes an instruction, it captures the next word and
validity bit at the resolved PC, or the injected EXEC word. The register
holds through stalls, both WIDE transfer beats until completion, and
delay ticks. PC advances at the existing architectural boundary.
At ENABLE, the engine also computes and stores the modulo-20 pin
selectors and masks from the static configuration.

Repair 2 is **trace-equivalent to pre-repair RTL** across the
27,578 core cycles. All 39 regression jobs were accepted, including
the four trace comparisons and the delayed-output mutant.
Verilator lint, Yosys structure checks, and the local cocotb smoke test
passed.
[Repair 2 top-level trace](../evidence/s11_trace_equiv_tb_top_s11/20261120T133322.json) · [Repair 2 mutant](../evidence/s11_trace_equiv_tb_engine_c_neg_delayed_out/20261120T133322.json)

The routed build used commit `7911f439c39e846e43b32cb21caf94e287278237`,
the existing 20 ns clock, and the 8×4 tile budget. It met the D-016
slow-corner target with +5.102 ns worst setup slack. The flow reports
0 ns worst negative slack and zero violating setup endpoints.
[Submission artifact with metrics.csv](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44745463003/artifacts/14639641935)

| Routed metric | Repair 2 |
| --- | ---: |
| Setup worst slack, slow | +5.102 ns |
| Setup worst slack, typical / fast | +9.071 ns / +11.401 ns |
| Setup total negative slack | 0 ns |
| Worst hold slack | +0.111 ns |
| Hold violating endpoints | 0 |
| Standard cells | 21,034 |
| Standard-cell utilization | 25.9598% |
| Detailed routing violations | 0 |

| CI job | Result |
| --- | --- |
| RTL smoke test | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44745463098) |
| Datasheet build | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44745463095) |
| GDS | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44745463003/job/136319493318) |
| Gate-level simulation | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44745463003/job/136364070353) |
| Pages viewer | [Passed](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44745463003/job/136364070363) |
| Tiny Tapeout precheck | [Passed in 1 h 11 min 37 s](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44745463003/job/136364070854) |

Precheck passed all ten checks, including SG13CMOS5L DRC, pin geometry,
boundary, and layer checks. The published viewer returned HTTP 200.
[Viewer](https://arnav1609.github.io/pvm-protocol-emulator/) · [Precheck reports](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44745463003/artifacts/14646991455)
