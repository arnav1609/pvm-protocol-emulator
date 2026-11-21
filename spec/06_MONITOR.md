# 06 SPECMON (passive timed monitor)

**Passive by construction:** pvm_mon has no output that reaches the engine, IMEM, FIFOs, fabric or pin_guard. Its only outputs go to the pvm_cfg read mux. A formal/structural check of this is part of stage 11.

## 1. Timebase
- Prescaler enable `men` = every 1 / 16 / 256 / 4096 core cycles (MON_CTRL.PRESC). Use a shared `pvm_tick`-style divider.
- `tstamp` 16-bit free-running counter, increments on `men` while MON_EN=1 (wraps).
- `t` 16-bit interval timer: increments on `men`, **saturates at 0xFFFF** and sets `ovf`. Reset by actions (below) and at monitor start.
- Monitor runs when MON_EN=1 and engine state is RUN. At RUN entry: state = 0, t = 0, ovf = 0, counters unchanged (cleared only by HALT).

## 2. Event sources (SRC, 5 bits)
0..19: pin_in[SRC]; 20..23: fabric L0..L3; 24: ARB_LOST; 25: UNDERRUN; 26..31: engine user flags 2..7.
Edge detection uses the previous-cycle value of the same source (register `src_prev[31:0]` only for sources referenced - Codex may keep all 32).
EDGE: 0 rise (prev 0, now 1), 1 fall, 2 high (level), 3 low (level).

## 3. Evaluation (every core cycle while running)
For e = 0..7 in order, the **first** entry with VALID=1, FROM == state, event true and guard true **fires** (only one per cycle):
- GUARD: 0 always, 1 t < K[KIDX], 2 t >= K[KIDX].
- state <= TO.
- ACTION (on the firing cycle, using the current t and ovf):
| ACTION | Effect |
|---|---|
| 0 NONE | - |
| 1 RESET | t <= 0, ovf <= 0 |
| 2 CHECK_MIN K[KIDX] | verdict = PASS if t >= K + M; VIOLATION if t + M < K (i.e. t < K - M); else INCONCLUSIVE. Log, count, then t <= 0, ovf <= 0 |
| 3 CHECK_MAX K[KIDX] | PASS if t + M <= K; VIOLATION if t > K + M; else INCONCLUSIVE. Log, count, reset t |
| 4 MEASURE | log the interval with verdict field = 0 (no verdict); counters unchanged; reset t |
| 5 VIOLATE | verdict VIOLATION (illegal sequence), log, count, reset t |
| 6 PASS | verdict PASS, log, count, reset t |
| 7 | rejected at VALIDATE |
Arithmetic is 17-bit (no wrap). If K + M > 0xFFFF the comparison still uses 17 bits; if ovf = 1 and the verdict would rely on a value above 0xFFFF being exact (CHECK_MAX with K + M >= 0xFFFF, or CHECK_MIN with K + M > 0xFFFF), the verdict is INCONCLUSIVE. Set the log OVF bit whenever ovf = 1.

## 4. Log and counters
- Log: 4-entry ring at 0x0F80 (format in 03 section 3.7). Write at LOG_WPTR, then pointer + 1 (mod 4); total count saturates at 63. Log entry: rule = firing entry index, verdict (0 none for MEASURE, 1 PASS, 2 VIOLATION, 3 INCONCLUSIVE), OVF, interval = t (before reset), timestamp = tstamp.
- Counters PASS / VIOLATION / INCONCLUSIVE: 16-bit saturating.
- HALT clears log, pointer and counters.

## 5. Precision (document in the file header, verify in tests)
Event observed time error vs. pad: |error| < 2T + delta (T = core period, 2-flop synchroniser, delta = input skew), assuming the synchroniser resolves in one cycle (UNVERIFIED for IHP) and pulses >= 2T. M must be chosen >= the error bound in timer units by the toolchain, not by the RTL.

## 6. Ports of pvm_mon
```
input clk, rst_n, run, halt_clr
input [19:0] pin_in, input [3:0] lut_out, input arb_lost, underrun, input [7:2] user_flags
input [8*24-1:0] cfg_entries  // 8 x 24 bits {byte2, byte1, byte0}
input [63:0] cfg_k, input [15:0] cfg_m, input mon_en, input [1:0] presc
output [2:0] mon_state
output [15:0] cnt_pass, cnt_viol, cnt_inc
output [4*40-1:0] log_flat, output [1:0] log_wptr, output [5:0] log_total
```
