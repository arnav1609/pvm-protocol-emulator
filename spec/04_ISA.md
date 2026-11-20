# 04 ISA - encoding and exact semantics (PVM v2.1, 32-word build)

Status: frozen for the 32-word build. The 64-word option (D-004) is NOT implemented. Encodings marked ILLEGAL raise fault ILLEGAL_OP when executed.

## 1. Format
```
 15  13 12        8 7                 0
 [ op  ][ DS field ][     operand      ]
```
**DS field [12:8]:** with SIDE_CNT = n (0..2), the top n bits [12:12-n+1] are side-set values (mapping below) and the remaining (5-n) low bits are DELAY (0..31, 0..15, 0..7).
- n=1: side[0] = DS[4] -> pin SIDE_BASE. delay = DS[3:0].
- n=2: side[1] = DS[4] -> pin SIDE_BASE+1, side[0] = DS[3] -> pin SIDE_BASE. delay = DS[2:0].

## 2. Engine state
| Register | Width | Reset / at ENABLE |
|---|---|---|
| PC | 5 | ENTRY_PC at ENABLE |
| X, Y | 16 | 0 at ENABLE |
| OSR | 16, plus osr_cnt [4:0] = bits already shifted out | OSR=0, osr_cnt = full (empty: autopull/PULL needed) |
| ISR | 16, plus isr_cnt [4:0] = bits shifted in | 0, 0 |
| out_val[19:0], oe_val[19:0] | engine pin outputs | 0 at ENABLE |
| fab_ctrl[3:0] | to fabric | 0 |
| flags[7:2] | user flags | 0 |
| exec_pending, exec_instr | for MOV/OUT EXEC | 0 |

OSR empty definition: osr_cnt counts bits shifted out since the last PULL. OSR is **empty** when osr_cnt >= PULL_THRESH (PULL_THRESH 0 means 8 if WIDE=0, 16 if WIDE=1). Same rule for ISR "full": isr_cnt >= PUSH_THRESH.

## 3. Timing model (one engine tick = one enable pulse from pvm_tick with period CLKDIV)
- Every instruction issues on a tick. If it **completes** on that tick, the engine then waits DELAY further ticks, then the next instruction issues.
- If it **stalls** (WAIT false, blocking PULL with TX FIFO empty, blocking PUSH with RX FIFO full, autopull/autopush blocked), it re-evaluates on every following tick; DELAY starts only after completion.
- **Side-set** values are written to out_val on the first issue tick (even if the instruction then stalls) and override same-tick OUT/SET/MOV writes to the same pin.
- **PC update** after completion + delay: jumps load the target; otherwise if PC == WRAP_TOP then PC = WRAP_BOTTOM else PC = PC + 1 (mod 32).
- **Fetch check:** issuing from a word with valid = 0 -> fault INVALID_WORD (FAULT_PC = PC).
- **Timeouts** (TIMEOUT != 0): a stall counter increments on every TO_PRESC enable while the current instruction is stalled; reset when the instruction completes. If the condition becomes true on the same cycle the counter reaches TIMEOUT, completion wins. Counter reaching TIMEOUT -> fault TIMEOUT.
- Outputs reach pins through pin_guard: engine regs -> pin_guard (combinational) -> registered pin output stage (1 cycle). Inputs reach the engine 2 cycles late (synchroniser). Document cycle counts in tests.

## 4. Instructions
### 000 JMP  operand = cond[7:5] addr[4:0]
| cond | Jump if | Side effect |
|---|---|---|
| 0 | always | - |
| 1 | X == 0 | - |
| 2 | X != 0 (tested before decrement) | X = X - 1 always |
| 3 | Y == 0 | - |
| 4 | Y != 0 (before decrement) | Y = Y - 1 always |
| 5 | X != Y | - |
| 6 | pin_in[JMP_PIN] == 1 | - |
| 7 | OSR not empty | - |

### 001 WAIT  operand = pol[7] src[6:5] index[4:0]
Stall until (source == pol). src 0 PIN: pin_in[index] (index 0..19, else ILLEGAL); 1 FAB: fabric output L[index[1:0]] (index[4:2] must be 0); 2 FLAG: flags[index[2:0]] (index[4:3] must be 0); 3 ILLEGAL.

### 010 IN  operand = src[7:5] count[4:0]
count 0 = 16; count > 16 = ILLEGAL. Source value (16 bits): 0 PINS: {pin_in[IN_BASE+15..IN_BASE]} (mod 20, bit 0 = pin IN_BASE); 1 X; 2 Y; 3 NULL (zeros); 4 ISR; 5 OSR; 6 FAB {12'b0, L3, L2, L1, L0}; 7 ILLEGAL.
Shift: IN_SHR=1: ISR = {src[count-1:0], ISR[15:count]}. IN_SHR=0: ISR = {ISR[15-count:0], src[count-1:0]}. isr_cnt = min(isr_cnt + count, 16).
Autopush (AUTOPUSH=1): after the shift, if isr_cnt >= PUSH_THRESH: push and clear ISR/isr_cnt; if RX FIFO cannot take it, the IN instruction stalls (shift happens only once, when completion is possible - i.e. check FIFO space first).

### 011 OUT  operand = dst[7:5] count[4:0]
count 0 = 16, > 16 ILLEGAL. Autopull (AUTOPULL=1): if OSR empty before the OUT, first PULL (stall while TX FIFO lacks the bytes needed). Data = count bits from OSR: OUT_SHR=1 takes OSR[count-1:0] and OSR = OSR >> count; OUT_SHR=0 takes OSR[15:16-count] and OSR = OSR << count. osr_cnt += count (saturate 31).
dst: 0 PINS: out_val[OUT_BASE+k] = data[k], k < min(count, OUT_CNT); 1 X = zero-extended data; 2 Y; 3 NULL; 4 PINDIRS: oe_val[OUT_BASE+k] = data[k]; 5 PC = data[4:0] (jump); 6 FAB: fab_ctrl = data[3:0] and pulse fab_wr (see 05); 7 EXEC: execute data[15:0] as the next instruction (on the next tick, PC not advanced for it).

### 100 PUSH / PULL  operand = dir[7] cond[6] block[5] 0[4:0]
- dir 0 PUSH: cond (if-full) = 1 -> do nothing unless isr_cnt >= PUSH_THRESH. Push ISR[7:0] (WIDE=0) or ISR[7:0] then ISR[15:8] (WIDE=1, needs 2 free entries) to RX FIFO, clear ISR, isr_cnt=0. RX full: block=1 stall, block=0 drop data (no fault).
- dir 1 PULL: cond (if-empty) = 1 -> do nothing unless OSR empty. Pop 1 byte into OSR[7:0] (OSR[15:8]=0) (WIDE=0) or 2 bytes, first -> OSR[7:0], second -> OSR[15:8] (WIDE=1). osr_cnt=0. When OUT_SHR=0 and WIDE=0, place the byte in OSR[15:8] instead so MSB-first shifting works. TX empty: block=1 stall, block=0 OSR = X (PIO behaviour), osr_cnt = 0.
- operand[4:0] != 0 -> ILLEGAL.

### 101 MOV  operand = dst[7:5] op[4:3] src[2:0]
src: 0 PINS (as IN), 1 X, 2 Y, 3 NULL, 4 STATUS = {13'b0, tx_empty, rx_full, osr_empty}, 5 ISR, 6 OSR, 7 FAB {12'b0, L3, L2, L1, L0}.
op: 0 none, 1 invert (~), 2 bit-reverse 16 bits, 3 ILLEGAL.
dst: 0 PINS (OUT_BASE/OUT_CNT), 1 X, 2 Y, 3 EXEC, 4 PC (value[4:0]), 5 ISR (isr_cnt=0), 6 OSR (osr_cnt=0), 7 FAB (fab_ctrl = value[3:0], pulse fab_wr).

### 110 EVT  operand = kind[7:6] 0[5:3] idx[2:0]
kind 0 SET flag idx (idx 2..7; idx 0/1 ILLEGAL), 1 CLR flag idx (idx 0 clears ARB_LOST, 1 clears UNDERRUN, 2..7 user flags), 2 ILLEGAL, 3 DONE: engine enters DONE (STATUS.STATE=4, FAULT_CODE=DONE, outputs to idle via pin_guard). operand[5:3] != 0 -> ILLEGAL.

### 111 SET  operand = dst[7:5] imm[4:0]
dst 0 PINS: out_val[SET_BASE+k] = imm[k], k < SET_CNT; 1 X = imm; 2 Y = imm; 4 PINDIRS: oe_val[SET_BASE+k] = imm[k]; 6 FAB: fab_ctrl = imm[3:0], pulse fab_wr; 3,5,7 ILLEGAL.

## 5. Worked encodings (use as test vectors)
| Assembly (SIDE_CNT=1) | Hex |
|---|---|
| out pins, 1 side 0 [7] | 0x6701 |
| jmp x-- 2 | 0x0042 |
| set x, 7 side 0 [7] | 0xE727 |
| pull block side 1 [7] | 0x97A0 |
| wait 0 pin 12 | 0x200C |
| evt done | 0xC0C0 |
Check each in the stage tests by decoding fields, and against Arnav's assembler once available.
