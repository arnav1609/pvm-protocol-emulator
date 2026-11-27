# A3 release identity handoff

**Author check passed.** The required routed source and release-candidate control each matched all 83 protected files and all five runtime checks under both recorded local profiles. The script reports the exact candidate commit, mode and SHA-256 comparison per file, and tool versions. The local worktree was prepared and verified in about 8.1 wall-clock minutes. The clean test campaign took 10.89 seconds.

| Reference | Commit |
| --- | --- |
| Routed source | `752ebb97824cfd1161581497c22d3c171c4c6ca9` |
| Required release-candidate control | `e1018ff505ae4e2b2d8c0ee1f4753083b8e97e0c` |
| Current public review candidate | `0d2978a47e5e854d6881714b6bed72cc6ec72053` |
| Frozen RTL | `b33a9227ac187f791a3733b94ac4e32879b10414` |
| Checker branch | `kalash/ident-01` |

## Results

| Frozen gate | Count | Observed |
| --- | ---: | --- |
| Two required SHAs × routed and RTL profiles | 4 | PASS_FRESH 4. Each run matched 83 files and all five tools. |
| Later review candidate | 1 | Expected rejection. All 83 routed files matched and 13 additional protocol example files were named. |
| One-byte frozen-source negative control | 1 | NEG_KILLED. Exit 1 named only `src/project.v` with different SHA-256 values. |
| Wrong or missing simulator versions | 3 | NEG_KILLED 3. Wrong Icarus compiler and runtime, wrong Verilator, and absent Verilator. |
| Unresolved candidate ref | 1 | Expected exit 2 with the ref named. |

The scratch mutant used a Git blob and index in a disposable clone. It never changed an RTL source file in the working project. The native Windows fallback returned the same 83-file table and identified its mismatched or missing tools, including Python 3.13.17. The passing local Linux/WSL profile used Python 3.12.3 and cocotb 2.0.1, Icarus 12.0 for RTL and 13.0 for routed replay, and Verilator 5.032. The two profiles are the local A3 tool checks.

[Full campaign summary](frozen-linux-clean/RUN_SUMMARY.md) · [Routed source PASS](frozen-linux-clean/R01/stdout.md) · [Candidate control PASS](frozen-linux-clean/R02/stdout.md) · [Current review candidate rejection](frozen-linux-clean/R05/stdout.md) · [One-byte mutant report](frozen-linux-clean/R06/stdout.md) · [Windows fallback report](windows-fallback.md)

## Replay and release decision

[Commands and report format](README.md) · [Frozen cases](FROZEN_CHECKS.md) · [Read-only review](REVIEW_A3.md)

The present release candidate carries 13 additions under `tools/examples/matrix/`. The strict A3 rule treats each added path as a difference. The review candidate preserves the routed versions of the original 83 files. A3's own tool files would also appear as additions if integrated into the candidate under `tools/`. Keep this checker outside the evaluated revision until Kalash decides between strict inventory identity and a documented allowance for specific additions. Heet's independent acceptance and release approval remain pending.
