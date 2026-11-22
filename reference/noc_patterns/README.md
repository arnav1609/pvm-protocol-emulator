# PVM ← NOC_PQATTEST reuse kit (read before writing new infrastructure)

Source: `C:\vivado_verilog_proj\NOC_PQATTEST\scripts\` (copied unchanged 20 Nov 2026, read-only reference). Owner: Kalash.

## Rule
These are **patterns to copy and adapt**, not code to run in PVM as-is. They are SystemVerilog/XSim/Windows-oriented and import NOC modules (`dual_lane`, `dual_lane_verify`, `make_merged_sources`). PVM rules still win: Verilog-2005, Icarus, `tb_rtl/pvm_run.py`, `method/PVM_METHOD_ADAPTATION.md`.

**No NOC RTL is reused.** Checked `NOC_PQATTEST.srcs/sources_1/new/` and `rtl/` (router, NI, crossbar, FIFO, KMAC/SHA3/Keccak, TRNG, PicoRV32 tiles, uart_tx, reset_sync): all SystemVerilog with packages and active-high reset, and PVM already has its own verified equivalents (S01-S11). Porting would cost more tokens than it saves and breaks D-009.

## What to reuse, for what

| File | What it is | Use in PVM | Who |
|---|---|---|---|
| `gen_arbiter_traces.py` + `arbiter_model.py` + `check_arbiter_traces.py` | Reference model → seeded per-cycle trace `.mem` files → RTL bench replays and compares cycle by cycle; `--check` regenerates and byte-compares | **Template for ISS trace vectors** (`tools/gen_engine_traces.py` → `tb_rtl/vectors/*.mem`) and for the G2 before/after equivalence (below) | Codex now; Arnav's ISS later |
| `run_r10_fetch_scope.py` | Runs the same bench on **copied** sources before/after a planned RTL change; never edits originals | **G2 timing repair**: pre-repair vs post-repair trace comparison | Codex (S11 repair) |
| `rv32_asm.py` | Two-pass assembler (labels, pseudo-ops, directives, fixed-size pass 1, `$readmemh` + include output) | Skeleton for the **PVM assembler** (`tools/pvm_asm.py`): replace RV32 tables with spec/04 encodings | Arnav |
| `hex_to_svh.py` | Word image → read-only include with source SHA-256 header | Adapt to Verilog-2005 (`reg [15:0] PROG [0:N-1]` filled in an `initial` block of the TB, not RTL) for program images | Codex / Arnav |
| `dual_lane_preflight.py` | Duplicate module-name / missing-file / recursive-include check on an explicit source list | Add the duplicate-name check to `pvm_run.py` (house method §3) | Codex |
| `test_r10_mutations.py` | Unit tests proving each mutation edit applies once, is idempotent-safe and rejects unrelated text | Add equivalent tests for `pvm_run.py` `mutant` anchors to `selftest` | Codex |
| `seed_shards.py`, `seed_campaign.py` | Compile once, run many seeds in shards with an exact ledger | Pattern for a constrained-random engine campaign (S14 / post-freeze). Replace XSim paths with Icarus `vvp` | Codex (later) |
| `verilator_build.sh`, `rtl_lint_waivers.json` | Lint invocation + waiver file with a reason per waiver | Same format for `verilator --lint-only` waivers in PVM | Codex |

## G2 repair: where are the ISS / trace vectors? (answer)
**There is no ISS yet.** The ISS is Arnav's toolchain work, which is not part of the RTL handoff, and the repo has no `tools/` directory. So for D-016 the reference is **the pre-repair RTL itself**:

1. Golden = commit `4b13f45` (S11 accepted: 6/6 S11 jobs, 34/34 regression).
2. Add a `+TRACE` plusarg to each engine/top testbench (S09-S11) that writes one CSV line per core cycle: `cycle, run_state, pc, instr_valid, out_val[19:0], oe_val[19:0], fab_ctrl, fab_wr, tx_pop, rx_push, rx_din, fault_req, fault_code`. Adding the plusarg does not change any check, so frozen counts stay as they are (state this in `checks_basis`).
3. Following `run_r10_fetch_scope.py`: copy the `4b13f45` sources to `build/golden/`, run every engine TB with `+TRACE` → `tb_rtl/vectors/golden_<tb>.csv` with SHA-256 recorded in a provenance JSON (generator pattern: `gen_arbiter_traces.py --check`).
4. After repair 1 (and repair 2 if needed), run the same TBs → compare cycle by cycle. Register this as new jobs `s11_trace_equiv_<tb>` (frozen count = number of TBs compared, each one check `TRACE_EQUAL_<TB>`), plus one negative job: a mutant that delays `out_val` by one cycle must be `NEG_KILLED`.
5. Claim word: **"trace-equivalent to pre-repair RTL"**, not "reference-checked". When Arnav's ISS lands, the same CSV format becomes the ISS comparison.

Then the routed G2 rerun: WNS ≥ +1.0 ns at `nom_slow_1p08V_125C`, GDS + precheck + GL green (D-016).
