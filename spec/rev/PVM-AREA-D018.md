# D-018 monitor and engine area optimization

Approved in chat on 21 November 2026 for candidate implementation and
physical evaluation. Kalash Bheda's uploaded PVM Area/Timing Optimization
handoff and patch kit supplied the design and scratch measurements.
Baseline `9d12d97` matches both input RTL hashes in the handoff.

| Change | RTL effect | Verification |
| --- | --- | --- |
| O1b | Terms `t+M` and `t−M` are shared across monitor rules. A selected K is compared against the 17-bit terms. Overflow checks use the unsigned complement of M. | Monitor arithmetic equivalence with original history |
| O2 | Each of the eight rule entries samples the selected source into its own history flop. | Monitor edge and stretch checks, history mutant, and integration regression |
| O3 | IN and MOV share the 16-bit source mux. The IN codes are mapped to the MOV selection codes. | Engine equivalence and D-016 traces |
| O4 | IN and OUT share two right shifters. Bit reversal implements left shift. | Engine equivalence, D-016 traces, and left-shift mutant |

O2 relies on an integration invariant. The configuration bank accepts
rule writes only in HALT. Selectors are fixed in RUN, and the monitor
suppresses rule firing on its first active cycle. Therefore whenever
a rule can fire, its sampled source is the previous value of that same
selector. The monitor module proof restores the original source history
to isolate O1b. Arbitrary live selector changes are outside O2's
integration contract.

The withdrawn serial O1 comparison put an adder after K selection.
The handoff's Yosys 0.33 generic scratch measurement increased longest
logic depth from 58 to 77 gates with O1. The supplied O1b/O2/O3/O4 set
reports 17,953 versus 20,166 generic cells and depth 46. The routed IHP
gate determines acceptance using measured metrics.

| Required physical check | Criterion |
| --- | --- |
| Setup at `nom_slow_1p08V_125C` | At least +1.0 ns at 50 MHz. A drop greater than 0.5 ns from +2.461 ns requires a documented cause. |
| Hold | Nonnegative slack |
| Utilization | Both routed utilization measures below the S14 baseline of 33.7187% |
| Physical tests | GDS, Tiny Tapeout precheck and gate-level simulation pass |

The proposal pairs D-018 with D-017 for one candidate physical build.
If setup misses the gate, evaluate O1b withdrawal first. If utilization
fails to improve, evaluate O1b + O2 without the engine changes. Record
measured results and the release decision in the candidate gate report.
The freeze requires the second-simulator replay accepted under D-020
and Kalash's source-review sign-off.
[Decision D-020](../DECISIONS.md#d-020--use-verilator-for-the-freeze-simulator-gate)
[Candidate gate](../../results/opt_area_timing.md) · [Baseline physical evidence](../../results/ci_S14.md)
