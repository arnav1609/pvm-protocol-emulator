# A3 release identity review

I independently checked the routed baseline against the two release branches using Git object bytes, then authored and ran the frozen harness against the checker implementation. This review covers implementation and author-side evidence. Heet's independent acceptance is pending. Kalash owns the release decision.

| Packet exit criterion | Result | Evidence |
| --- | --- | --- |
| Routed source `752ebb97824cfd1161581497c22d3c171c4c6ca9` passes | Yes | R01 and R03 each report 83 matching protected files and five matching tool versions. |
| Release candidate `e1018ff505ae4e2b2d8c0ee1f4753083b8e97e0c` passes | Yes | R02 and R04 report the same 83 file matches and five tool matches. Public `codex/pvm-v1.0-rc` resolved to this SHA during review. |
| A one-byte change fails and names the protected file | Yes | R06 exits 1 and names only `src/project.v` as changed, in scratch commit `b46fdfac3801bb05ba268fb68d8147da409e2b46`. The mutation used the temporary clone's Git object database and index. |
| Markdown format and reproduction commands are documented | Yes | The [A3 README](README.md) explains the two entry points, tool profiles, Git scope and exit codes. |
| Latest publication candidate passes the same rule | No | R05 rejects `0d2978a47e5e854d6881714b6bed72cc6ec72053` and lists all 13 added matrix fixtures. All 83 routed paths still match. The same protected inventory difference is present in that candidate's ancestor `baa20928bdab278da32d41497232c136ff15054f`. |

The [frozen inventory](FROZEN_CHECKS.md) was in place before the first run. The [clean-path rerun](frozen-linux-clean/RUN_SUMMARY.md) met all ten expectations in 10.89 seconds from the first case receipt to the summary. It used Python 3.12.3, cocotb 2.0.1 and Verilator 5.032, with Icarus 13.0 for routed tool checks and 12.0 for RTL tool checks. It also confirmed exit 1 for incompatible Icarus, incompatible Verilator and missing Verilator, and exit 2 for an invalid Git ref. The case folders preserve the exact commands, outputs and exit codes.

The protection boundary includes file additions, deletions, modes and contents under the five specified paths. The tool profile checks binaries and the Python environment at invocation. The routed CI workflow and related source documentation retain their own pins and evidence. The routed layout and simulation results have separate evidence.

The exact-inventory rule also counts the two checker files if they are added to the SHA under evaluation. The branch can supply the checker as a tool for evaluating a separate target commit. Kalash needs to choose the release SHA and approve any change to the inventory rule before `0d2978a` can pass A3. [Current public review candidate](https://github.com/arnav1609/pvm-protocol-emulator/commit/0d2978a47e5e854d6881714b6bed72cc6ec72053) · [Original routed-build provenance](https://github.com/arnav1609/pvm-protocol-emulator/blob/e1018ff505ae4e2b2d8c0ee1f4753083b8e97e0c/results/v1.0_routed.md)
