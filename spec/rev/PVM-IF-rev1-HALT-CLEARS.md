# PVM-IF revision 1 — HALT clears FIFO sticky bits and FIFOs

Approved by Kalash in chat on 20 November 2026 before S06 implementation.
This revision is additive to rev0 (spec/02–07).

## Frozen decisions

1. CTRL HALT clears STATUS[3] WR_REJ, STATUS[4] TX_OVF, and STATUS[5]
   RX_UNF in addition to the effects in the lifecycle spec.
2. CTRL HALT asserts clear on both FIFOs. Their contents are discarded and
   their levels return to zero. ENABLE preserves FIFO contents, so a host
   can preload TX after HALT and before ENABLE.

## Boundaries retained

Register addresses, bit positions, CTRL codes, and the other HALT effects
retain their rev0 definitions.

## Milestones and evidence

- S06 `HALT_CLEARS_STICKY` asserts that all three sticky bits are clear after HALT.
- S06 `HALT_CLEARS_FIFOS` checks that both levels return to zero and that an
  acknowledged empty RX read returns zero and raises RX_UNF.
