# PVM pre-freeze validation

Candidate `00ec783b0bd7cdb23ad8a00df03c77ec840e2725` on `codex/pvm-rtl`.
The three approved fixes are in one commit. This evidence branch points back
to the exact tested source. Kalash records the source-review verdict and tags
that SHA after sign-off.
[Candidate](https://github.com/arnav1609/pvm-protocol-emulator/commit/00ec783b0bd7cdb23ad8a00df03c77ec840e2725) · [PR #1](https://github.com/arnav1609/pvm-protocol-emulator/pull/1) · [Open owner checklist](owner_review_00ec783.md)

## Candidate changes

- **D-021** records that the monitor timestamp advances at the configured prescaler rate only in RUN with MON_EN set. It holds across DONE, HALT and reload, wraps at 16 bits, and clears on chip reset. Six checks were frozen for each of the new timestamp jobs before their first run. The HALT-clear mutant failed only `TIMESTAMP_SURVIVES_HALT_RELOAD`. The first local run revealed that the bench pulsed the event before the first prescaler tick. The candidate waits for that tick and retains every original predicate and count. [D-021](../spec/DECISIONS.md#d-021--monitor-timestamp-lifetime) · [Monitor spec](../spec/06_MONITOR.md#1-timebase) · [Timestamp bench](../tb_rtl/tb_mon_timestamp_pause.v)
- **D-017** drops `ASYNC_REG` from the two-stage reset synchronizer. The direct reset bench passed three checks and the one-edge mutant failed only `RESET_TWO_EDGE_RELEASE`. [D-017 addendum](../spec/rev/PVM-IF-D017-RESET-RELEASE.md) · [Reset RTL](../src/pvm_top.v#L15)
- **Windows golden vectors** use `tb_rtl/vectors/golden_*.csv -text`. The four checkout files exactly match their Git blobs and provenance SHA-256 values with `core.autocrlf=true`. The D-016 job compared every cycle with the stored pre-repair RTL traces and caught the delayed-`out_val` mutant. The Linux regeneration also reproduced the four CSVs and provenance JSON exactly. [Attributes](../.gitattributes) · [Golden trace provenance](../tb_rtl/vectors/golden_provenance.json)

`git diff --name-status 1a258a1 84174ee -- src/ info.yaml .github/workflows/`
returned no paths. The routed baseline and the review base therefore
share the same RTL, Tiny Tapeout metadata and workflows. From `84174ee`
to `00ec783`, the sole RTL delta is the reset attribute deletion.
The registry retains its earlier 67 entries and adds the D-021 pair.
[Prior review and routed baseline](opt_area_timing.md) · [Candidate diff](https://github.com/arnav1609/pvm-protocol-emulator/compare/84174ee...00ec783)

## Simulation and lint

| Gate | Outcome |
| --- | --- |
| Native Windows Icarus 12.0 | 69/69 accepted, 29 positives passed and 40 mutants caught. Covers the D-016 five jobs, both D-017 and D-021 jobs, and the S14b UART, SPI and I²C jobs. [Run](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44888245404) · [Raw logs](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44888245404/artifacts/14700696594) |
| Verilator 5.032 timing replay | In progress on the exact candidate. Two seeds for each of 25 distinct builds. |
| Verilator `-Wall` lint | A/B/C/D raw warnings were 23/8/18/4, identical to the prior inventory by class, location and text. All four scoped reruns exited cleanly with zero unwaived diagnostics. [Prior waiver inventory](verilator_replay_35f8d94.md#rtl-lint) |

The first Windows run also accepted all 69 jobs. Its workflow failed
afterwards because the PowerShell summary assertion used positional
arguments in the wrong order. The validation-only branch corrected the
assertion and reran the same candidate. [First run](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44888110645) · [Corrected validation workflow](https://github.com/arnav1609/pvm-protocol-emulator/blob/daec6a5f38cb467ecce5a7780e8d259f187ccd47/.github/workflows/test.yaml)

## Reset equivalence and synthesis

Yosys 0.52 read `src/*.v` at `84174ee` and `00ec783` in separate
directories with identical relative paths. The generic synthesis command
was `synth -flatten -top tt_um_arnav1609_pvm -noabc`. Both outputs have
**18,831 logic cells** and 20 Yosys hierarchy metadata cells, with identical
counts for every cell type. Both the native and synthesized top-level JSON
netlists match structurally after removing the attribute on
`pvm.reset_release` and its source column location.

The formal equivalence flow applies `prep -flatten`, `memory_map`,
`opt` and `async2sync` equally to both flattened tops, then runs
`equiv_make`, `equiv_struct`, `equiv_simple -short -seq 4`,
`equiv_induct -seq 4` and `equiv_status -assert`. All **4,154**
full-top equivalence cells were proven. A second proof selected the reset
flop cone and proved both reset stages. The native netlist retains identical
active-low asynchronous reset wiring and reset value for the two
flip-flops, complementing the sampled equivalence proof. An initial
unmapped-memory proof attempt hit a Yosys assertion during preparation.
The mapped proof completed. [Proof commands and outputs](../evidence/pre_freeze/00ec783/yosys/)

## Tiny Tapeout

Run **44888057444** builds the candidate's full variant D with the
8×4 IHP SG13CMOS5L configuration at 50 MHz. The workflow is in progress.
The comparison uses the D-017/D-018 routed baseline from run
44862976826 on `1a258a1`. Its two utilization measures were 30.9084%,
slow-corner setup slack was +2.206 ns, and worst hold slack was +0.108 ns.
The candidate requires GDS, precheck, gate-level SPI smoke, Pages viewer,
and at least +1.0 ns slow-corner setup slack.
[Candidate workflow](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44888057444) · [Routed baseline](opt_area_timing.md#physical-gate)

## Owner review

Kalash's review of this SHA and the `rtl-freeze` tag are open. Heet's
independent 1-Wire/SWD model review is also pending in the repository.
The fit study records the prior SWD launch-edge model error that masked
a parity bug, its correction, and the corrupted-parity mutant evidence.
[Owner checklist](owner_review_00ec783.md) · [Fit study](../results/fit_study.md)
