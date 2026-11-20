# G2 timing repair under D-016

S12 awaits G2 acceptance at 50 MHz. [D-016](../spec/DECISIONS.md#d-016--s11-g2-timing-repair-at-50-mhz) · [Original G2 failure](g2_area_timing.md)

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
passed. GitHub Actions passed the RTL
smoke test and datasheet build on commit `9a38168`.
[Regression records](../evidence/) · [S11 top-level regression](../evidence/s11_top/20261120T124536.log) · [RTL CI](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44732758403) · [Datasheet CI](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44732758628)

Repair 1 is **trace-equivalent to pre-repair RTL** across the four
registered workloads, with 27,578 matching core cycles.
The negative job detected the one-cycle `out_val` delay at cycle 23.
A separate SPI probe verified rejection of an unwritten entry at PC 9
when PC 0 holds a valid word, then successful execution at PC 9 with
PC 0 unwritten.
[Trace results](../evidence/s11_trace_equiv_tb_top_s11/latest.json) · [Negative job](../evidence/s11_trace_equiv_tb_engine_c_neg_delayed_out/latest.json)

Routed measurements are pending. [Repair 1 GDS run](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44732758406)
