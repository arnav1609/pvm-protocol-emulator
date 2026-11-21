# 03 Internal bus, host SPI protocol, register map

## 1. Internal byte bus (single master: pvm_hostif)
| Signal | Width | Driver | Meaning |
|---|---|---|---|
| bus_addr | 16 | hostif | byte address, valid whenever bus_we/bus_re/bus_rack is 1 |
| bus_wdata | 8 | hostif | write data, valid with bus_we |
| bus_we | 1 | hostif | 1-cycle write strobe |
| bus_re | 1 | hostif | 1-cycle read strobe (prefetch / **non-destructive**) |
| bus_rdata | 8 | pvm_cfg (read mux) | read data, **valid exactly 1 cycle after bus_re**, held until next bus_re |
| bus_rack | 1 | hostif | 1-cycle pulse: the byte read from `bus_addr` was fully shifted out to the host. Only side effect: RX FIFO pop when bus_addr = 0x0F11 |

Rules:
- At most one of bus_we / bus_re / bus_rack is 1 in any cycle.
- Reads never have side effects except via bus_rack.
- Address decode, write permission and the read mux live in `pvm_cfg`. Blocks expose plain config outputs and status inputs.

## 2. Host SPI frame (SPI mode 0, MSB first)
- SCK idles low; MOSI sampled on SCK rising; MISO changes after SCK falling.
- **Limit: f_SCK <= f_clk / 16** (oversampled target; 3.125 MHz at 50 MHz). The host tool enforces this.
- CS_n high: frame idle, MISO = 0, byte counter reset. Every frame starts at CS_n falling.

| Command byte | Frame (bytes on MOSI) | MISO |
|---|---|---|
| 0x02 WRITE | 0x02, A[15:8], A[7:0], D0, D1, ... | 0x00 |
| 0x03 READ | 0x03, A[15:8], A[7:0], dummy, then N clocked bytes | 0x00 for the first 4 bytes, then D0 = mem[A], D1 = mem[A+1], ... |
| 0x9F ID | 0x9F, then N bytes | 0x00, then 0x50 'P', 0x56 'V', 0x4D 'M', 0x21 (version 2.1), then 0x00 |
| other | ignored until CS_n high | 0x00 |

Timing inside hostif (cycles counted after edges are detected on synchronised signals):
- WRITE: after the 8th rising SCK of each data byte -> one bus_we with the current address; then address += 1.
- READ: after the 8th rising SCK of the dummy byte -> bus_re(A); 1 cycle later load bus_rdata into the MISO shift register; MSB appears on MISO after the next falling SCK edge; then shift on each falling edge. After the 8th rising SCK of each data byte -> bus_rack(addr of that byte) then bus_re(addr+1) the next cycle, address += 1.
- Address wraps 0xFFFF -> 0x0000.

## 3. Register map (byte addresses; multi-byte fields little-endian: low byte at lower address)
Access: RW = read/write; R = read only; W = write only (reads 0x00); WH = writable **only in state HALT** (otherwise write rejected, STATUS.WR_REJ set). Unmapped reads return 0x00; unmapped writes set WR_REJ.

### 3.1 IMEM 0x0000-0x007F (64-word window, 32 implemented)
| Addr | Access | Content |
|---|---|---|
| 0x0000 + 2i | WH | word i [7:0], i = 0..31 |
| 0x0001 + 2i | WH | word i [15:8]; **writing the high byte sets valid[i]=1** |
| 0x0040-0x007F | - | reserved for 64-word option: writes rejected (WR_REJ) |
Valid bits are cleared by reset and by CTRL command CLR_IMEM. Word storage itself is not reset. A read of word i returns the stored byte if valid[i]=1, else 0x00.

### 3.2 Engine configuration 0x0100-0x011F (all WH, reset 0)
| Addr | Field | Bits | Meaning |
|---|---|---|---|
| 0x0100-0x0101 | CLKDIV | 16 | engine tick every CLKDIV core cycles; 0 or 1 = every cycle |
| 0x0102 | OUT_BASE | [4:0] | first protocol pin for OUT PINS / MOV PINS |
| 0x0103 | OUT_CNT | [4:0] | number of pins for OUT/MOV PINS (0..16; >16 = CFG_INVALID) |
| 0x0104 | SET_BASE | [4:0] | first pin for SET PINS |
| 0x0105 | SET_CNT | [2:0] | 0..5 pins for SET PINS (>5 = CFG_INVALID) |
| 0x0106 | IN_BASE | [4:0] | first pin for IN PINS / MOV src PINS |
| 0x0107 | SIDE_BASE | [4:0] | first side-set pin |
| 0x0108 | SIDE_CNT | [1:0] | 0..2 side-set bits (3 = CFG_INVALID) |
| 0x0109 | JMP_PIN | [4:0] | pin tested by JMP PIN |
| 0x010A | WRAP_BOTTOM | [4:0] | |
| 0x010B | WRAP_TOP | [4:0] | |
| 0x010C | SHIFTCTRL | [4:0] | b0 OUT_SHR (1 = shift right/LSB first), b1 IN_SHR, b2 AUTOPULL, b3 AUTOPUSH, b4 WIDE (D-007) |
| 0x010D | PULL_THRESH | [4:0] | 1..8 (WIDE=0) or 1..16 (WIDE=1); 0 means max (8 or 16) |
| 0x010E | PUSH_THRESH | [4:0] | same rule |
| 0x010F | ENTRY_PC | [4:0] | PC at ENABLE |
| 0x0110-0x0111 | TIMEOUT | 16 | 0 = no timeout on blocking ops |
| 0x0112 | TO_PRESC | [1:0] | timeout counter enable every 1 / 16 / 256 / 4096 core cycles |
Pin index arithmetic for BASE + k is modulo 20.

### 3.3 Fabric 0x0200-0x023F (all WH, reset 0) - semantics in 05_FABRIC.md
| Addr | Field |
|---|---|
| 0x0200 + 8n, n=0..3 | LUTn TT[7:0] |
| 0x0201 + 8n | LUTn TT[15:8] |
| 0x0202 + 8n | LUTn SEL0[3:0], SEL1[7:4] |
| 0x0203 + 8n | LUTn SEL2[3:0], SEL3[7:4] |
| 0x0204 + 8n | LUTn MODE: [1:0] out mode (0 REG, 1 RISE, 2 MAJ3, 3 = CFG_INVALID), [2] GROUP (0: uio group, 1: ui group) |
| 0x0220-0x0221 | CNT_RELOAD [9:0] |
| 0x0222 | CNT_CTRL: [0] CNT_EN, [1] CNT_SRC (0 every cycle, 1 engine tick), [2] MANCH_EN |
| 0x0224 | ARB_CTRL: [0] ARB_EN, [7:4] ARB_N (stable SCL-high cycles, 1..15; 0 = CFG_INVALID when ARB_EN) |
| 0x0225 | ARB_SDA [4:0] (must be 12..19 when ARB_EN) |
| 0x0226 | ARB_SCL [4:0] (must be 12..19 when ARB_EN) |

### 3.4 Monitor 0x0300-0x037F (WH unless marked R) - semantics in 06_MONITOR.md
| Addr | Field |
|---|---|
| 0x0300 + 4e, e=0..7 | entry e byte0: [2:0] FROM, [5:3] TO, [7:6] EDGE (0 rise,1 fall,2 high,3 low) |
| 0x0301 + 4e | byte1: [4:0] SRC, [6:5] GUARD (0 always,1 t<K,2 t>=K,3 CFG_INVALID), [7] VALID |
| 0x0302 + 4e | byte2: [1:0] KIDX, [4:2] ACTION, [7:5] reserved (write 0) |
| 0x0303 + 4e | reserved |
| 0x0320-0x0327 | K0..K3, 16 bit each |
| 0x0328-0x0329 | MARGIN M, 16 bit |
| 0x032A | MON_CTRL: [0] MON_EN, [2:1] PRESC (1/16/256/4096) |
| 0x0330-0x0331 | R: PASS count (saturating 16) |
| 0x0332-0x0333 | R: VIOLATION count |
| 0x0334-0x0335 | R: INCONCLUSIVE count |
| 0x0336 | R: MON_STATE [2:0] |

### 3.5 Pins 0x0400-0x0413 (WH, reset 0)
Byte 0x0400 + p for pin Pp: [2:0] OWNER, [4:3] MODE, [5] IDLE, [6] INV, [7] reserved.
OWNER: 0 none, 1 engine OUT/SET/MOV, 2 engine side-set, 3 fabric L0, 4 L1, 5 L2, 6 L3, 7 = CFG_INVALID.
MODE: 0 input-only, 1 push-pull, 2 open-drain, 3 = CFG_INVALID. Rules in 07.

### 3.6 Control and status 0x0F00-0x0F1F
| Addr | Access | Field |
|---|---|---|
| 0x0F00 | W | CTRL command: 0x01 HALT, 0x02 VALIDATE (then COMMIT if OK), 0x03 ENABLE, 0x04 CLR_IMEM (HALT only), 0x05 CLR_FAULT (FAULT/DONE -> HALT), 0x06 CLR_FLAGS (ARB_LOST, UNDERRUN), others ignored + WR_REJ |
| 0x0F01 | R | STATUS: [2:0] STATE (0 HALT, 1 VALIDATING, 2 READY, 3 RUN, 4 DONE, 5 FAULT), [3] WR_REJ (sticky, cleared by HALT cmd), [4] TX_OVF (sticky), [5] RX_UNF (sticky), [6] CRC_OK (last validate) |
| 0x0F02 | R | FAULT_CODE [3:0] (07 section 3) |
| 0x0F03 | R | FAULT_PC [4:0] |
| 0x0F04-0x0F05 | R | FAULT_TIME: core-cycle timestamp (16-bit free-running) at fault |
| 0x0F06-0x0F07 | R | CRC_CALC: CRC-16 accumulated since last HALT command |
| 0x0F08-0x0F09 | WH | CRC_EXPECT (these two writes are NOT included in the CRC) |
| 0x0F0A | WH | IMAGE_VER (included in CRC) |
| 0x0F0B | R | FLAGS: [0] ARB_LOST, [1] UNDERRUN, [7:2] user flags 2..7 |
| 0x0F0C | R | ENGINE_PC [4:0] (live) |
| 0x0F10 | W | TX FIFO push (any state; full -> drop, TX_OVF) |
| 0x0F11 | R | RX FIFO head (peek on bus_re; pop on bus_rack; empty -> 0x00, RX_UNF) |
| 0x0F12 | R | FIFO_STAT: [2:0] TX level, [6:4] RX level |
| 0x0F20 | R | IMAGE ID: CRC_EXPECT low byte, 0x0F21 high byte, 0x0F22 IMAGE_VER (copies latched at COMMIT) |

### 3.7 Monitor log 0x0F80-0x0F9F (R)
4 entries x 8 bytes, entry j at 0x0F80 + 8j:
byte0 [2:0] rule (entry index), [4:3] verdict (1 PASS, 2 VIOLATION, 3 INCONCLUSIVE), [5] OVF; bytes1-2 interval (timer units); bytes3-4 timestamp (monitor timebase); bytes5-7 0.
0x0FA0 R: LOG_WPTR [1:0] (next slot), [7:2] total entries written (saturating at 63).
