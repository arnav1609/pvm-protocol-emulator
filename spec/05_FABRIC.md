# 05 PINFABRIC (D-001, D-002, D-006)

All logic runs on `clk`. All outputs are registered. No combinational path from any pin input to any pin output inside the fabric.

## 1. Source vectors (D-006)
Group pins (8 bits) chosen per LUT by MODE[2]:
- GROUP 0: `pin_in[19:12]` (uio, P12..P19), bit 0 = P12.
- GROUP 1: `{pin_in[14:12], pin_in[4:0]}`: bits [4:0] = P0..P4 (ui inputs), bits [7:5] = P12..P14.

Layer 1 (L0, L1) source index s:
| s | source |
|---|---|
| 0..7 | group pin bit s |
| 8..11 | fab_in[0..3] (see section 3: fab_ctrl or Manchester active bit) |
| 12 | 1'b0 |
| 13 | 1'b1 |
| 14 | cnt_phase |
| 15 | arb_lost |

Layer 2 (L2, L3):
| s | source |
|---|---|
| 0..7 | group pin bit s |
| 8..11 | fab_in[0..3] |
| 12 | L0 (registered output) |
| 13 | L1 (registered output) |
| 14 | cnt_phase |
| 15 | 1'b0 |

## 2. LUT cell n (n = 0..3)
`idx = {src(SEL3), src(SEL2), src(SEL1), src(SEL0)}` (SEL0 is the LSB). `f = TT[idx]` (combinational).
Output mode (registered, all reset to 0, all cleared while engine not RUN):
- 0 REG: `L <= f`.
- 1 RISE: `L <= f & ~f_prev; f_prev <= f` (one-cycle pulse on rising f).
- 2 MAJ3: shift `h <= {h[1:0], f}`; `L <= majority(h[2], h[1], h[0])` (majority of the last three samples).
- 3: rejected at VALIDATE.

## 3. Counter / phase cell (D-002)
- `cnt` 10-bit down counter, `cnt_phase` 1-bit, `cnt_tc` 1-cycle pulse.
- Advances only when `CNT_EN=1` and engine state is RUN and enable `en` = (CNT_SRC ? engine_tick : 1'b1).
- On ENABLE: `cnt <= CNT_RELOAD`, `cnt_phase <= 0`.
- On each `en`: if `cnt == 0`: `cnt <= CNT_RELOAD`, `cnt_phase <= ~cnt_phase`, `cnt_tc <= 1`; else `cnt <= cnt - 1`.
  -> Half period = (CNT_RELOAD + 1) enables. Example 100 kbit/s Manchester at 50 MHz: half bit = 250 cycles -> CNT_RELOAD = 249 (60 MHz: 299). Max 1024 enables.
- `fab_in[3:0] = fab_ctrl[3:0]` normally.

## 4. Manchester holding register (F2, D-001 family flags)
Enabled by MANCH_EN=1 (requires CNT_EN=1, else CFG_INVALID).
- `hold_bit`, `hold_valid`, `act_bit`.
- Engine write to FAB (`fab_wr` pulse with value fab_ctrl): `hold_bit <= fab_ctrl[0]; hold_valid <= 1`.
- At a bit boundary = `cnt_tc` pulse at which `cnt_phase` goes 1 -> 0: if `hold_valid`: `act_bit <= hold_bit; hold_valid <= 0`; else `UNDERRUN` flag <= 1 (sticky) and `act_bit` keeps its value.
- First bit: at ENABLE, `act_bit <= 0`; the engine should write the first bit before the first boundary.
- With MANCH_EN=1: `fab_in[0] = act_bit` (replaces fab_ctrl[0]); fab_in[3:1] = fab_ctrl[3:1].
- Typical program: LUT0 TT computes `act_bit XOR cnt_phase` (or XNOR for the other convention); pin owner = fabric L0.

## 5. Arbitration-loss guard (D-001)
Enabled by ARB_EN=1. Pins ARB_SDA, ARB_SCL must be 12..19 and in MODE open-drain (VALIDATE checks).
- `scl_hi_cnt` [3:0]: if `pin_in[ARB_SCL]==1` then saturating increment, else 0.
- `sda_intent_release` = pin_guard's pre-guard intent for ARB_SDA: 1 when the owner's value for that pin is 1 (open-drain released). Provided by pin_guard as `od_release_intent[19:0]`.
- Set: if RUN and `scl_hi_cnt >= ARB_N` and `sda_intent_release` and `pin_in[ARB_SDA]==0` -> `arb_lost <= 1` (sticky).
- Effect (in pin_guard): while `arb_lost`, OE of ARB_SDA and ARB_SCL is forced 0 (released), whatever the owner drives.
- Response bound k: `arb_lost` is set 1 cycle after the synchronised observation; pin OE drops on the following registered output update -> **2 cycles after the synchronised sample, 4 cycles after the pad** (2 synchroniser cycles). Tests must check exactly this.
- Clear: EVT CLR flag 0 (engine), CTRL CLR_FLAGS (host), HALT.
- ARB_LOST is readable by engine (WAIT FLAG 0, MOV), monitor (SRC 24), fabric (layer-1 source 15) and host (FLAGS).

## 6. Ports of pvm_fabric
```
input  clk, rst_n
input  run                    // engine state == RUN
input  enable_pulse           // 1 cycle at ENABLE (init counters)
input  engine_tick
input  [19:0] pin_in
input  [19:0] od_release_intent
input  [3:0] fab_ctrl, input fab_wr
input  [127:0] cfg_lut        // 4 x {MODE[7:0], SEL[15:0], TT[15:0]} packing defined by pvm_cfg (document in file header)
input  [9:0] cnt_reload, input cnt_en, cnt_src, manch_en
input  arb_en, input [3:0] arb_n, input [4:0] arb_sda, arb_scl
input  clr_flags              // host CLR_FLAGS or HALT
input  evt_clr_arb, evt_clr_unf
output [3:0] lut_out          // L3..L0 registered
output cnt_phase, output arb_lost, output underrun
```
(Exact packing of cfg_lut: for n = 0..3, bits [32n+15:32n] = TT, [32n+31:32n+16] = {SEL3,SEL2,SEL1,SEL0}; MODE bits passed separately as `input [11:0] cfg_mode` = 4 x 3 bits. Codex may choose this packing but must document it in pvm_cfg and pvm_fabric headers identically.)
