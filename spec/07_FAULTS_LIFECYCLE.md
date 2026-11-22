# 07 Lifecycle, validation, pin rules, faults

## 1. States (STATUS.STATE)
| Code | State | Engine | Pins |
|---|---|---|---|
| 0 | HALT | stopped | safe: uio_oe=0, uo = IDLE bits |
| 1 | VALIDATING | stopped | safe |
| 2 | READY (committed) | stopped | safe |
| 3 | RUN | running | per pin_guard rules |
| 4 | DONE | stopped | safe |
| 5 | FAULT | stopped | safe |

Reset -> HALT. Transitions:
| From | Event | To |
|---|---|---|
| any | CTRL HALT | HALT; clears WR_REJ, TX_OVF, RX_UNF, CRC accumulator, monitor log/counters, ARB_LOST, UNDERRUN, and both FIFOs; does NOT clear IMEM or config (rev1, D-012) |
| HALT | CTRL VALIDATE | VALIDATING |
| VALIDATING | all checks pass | READY (latch IMAGE ID copies) |
| VALIDATING | any check fails | FAULT with code CRC_FAIL / PIN_CONFLICT / CFG_INVALID (first failing check in the order of section 2) |
| READY | CTRL ENABLE | RUN; pulse `enable_pulse` (engine, fabric, monitor initialise) |
| READY | any WH write | rejected (WR_REJ); host must HALT first |
| RUN | EVT DONE | DONE |
| RUN | engine fault | FAULT |
| FAULT / DONE | CTRL CLR_FAULT | HALT |
Any CTRL command not allowed in the current state is ignored and sets WR_REJ.

## 2. VALIDATE checks (sequential over at most 32 cycles is fine)
1. CRC: CRC_CALC == CRC_EXPECT -> else CRC_FAIL. CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF, no reflection, no xorout) over every **accepted WH write data byte** since the last HALT command, in write order, excluding writes to CRC_EXPECT. (Toolchain computes the same stream.) Known vector: bytes "123456789" -> 0x29B1.
2. Pins, for every p: OWNER == 7 or MODE == 3 -> CFG_INVALID. MODE open-drain on p in 5..11 (uo) -> PIN_CONFLICT. MODE push-pull/open-drain on p in 0..4 (ui, input only) -> PIN_CONFLICT. OWNER != 0 with MODE input-only -> PIN_CONFLICT.
3. Engine: OUT_CNT > 16, SET_CNT > 5, SIDE_CNT == 3, any BASE or JMP_PIN > 19, WRAP_BOTTOM > WRAP_TOP, valid[ENTRY_PC] == 0 -> CFG_INVALID.
4. Fabric: any LUT MODE out mode == 3; MANCH_EN without CNT_EN; ARB_EN with ARB_N == 0, or ARB_SDA/ARB_SCL not in 12..19, or not open-drain -> CFG_INVALID.
5. Monitor: any VALID entry with GUARD == 3 or ACTION == 7, or FROM/TO fine (3 bits always valid) -> CFG_INVALID.

## 3. Fault codes (FAULT_CODE [3:0])
| Code | Name | Raised by |
|---|---|---|
| 0 | NONE | |
| 1 | DONE | EVT DONE (state DONE, not FAULT) |
| 2 | TIMEOUT | blocking op exceeded TIMEOUT |
| 3 | ILLEGAL_OP | executing an ILLEGAL encoding |
| 4 | INVALID_WORD | fetch from valid = 0 |
| 5 | CRC_FAIL | VALIDATE |
| 6 | PIN_CONFLICT | VALIDATE |
| 7 | CFG_INVALID | VALIDATE |
ARB_LOST and UNDERRUN are **flags** (FLAGS register), not faults: the engine keeps running.
On a fault: FAULT_CODE, FAULT_PC (engine PC at the faulting instruction; 0 for VALIDATE faults), FAULT_TIME (16-bit core cycle counter) are latched.

## 4. pin_guard rules (per pin p, combinational then one output register stage)
Inputs: owner/mode/idle/inv per pin; engine out_val, oe_val, side-set already merged into out_val/oe_val by the engine; fabric lut_out; arb_lost + ARB_SDA/ARB_SCL; state.
1. If state != RUN: drive = IDLE (uo pins), oe = 0 (uio pins). Done.
2. Source value v and source enable s:
   - OWNER 0: v = IDLE, s = 0.
   - OWNER 1 or 2: v = out_val[p], s = oe_val[p] for uio pins; s = 1 for uo pins (uo cannot be disabled).
   - OWNER 3..6: v = L[OWNER-3], s = 1.
3. v' = v XOR INV.
4. MODE push-pull: out = v', oe = s. MODE open-drain (uio only): out = 0, oe = s & ~v' (pull low when v' = 0, release when 1). Export `od_release_intent[p] = (MODE==OD) & (v' == 1 | s == 0)`.
5. ARB: if arb_lost and (p == ARB_SDA or p == ARB_SCL): oe = 0.
6. uo pins (5..11): uo_out bit = (MODE input-only ? IDLE : out). uio pins: uio_out = out, uio_oe = oe. ui pins (0..4): nothing driven.
7. The final values are registered once (1-cycle latency) and that register is reset to IDLE=0 / oe=0.
Properties to assert (stage 6 and formal later): open-drain pins never have (oe=1 and out=1); when state != RUN all uio_oe = 0; ARB pins released within the bound in 05 section 5.
