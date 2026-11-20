# G2 timing repair under D-016

S12 awaits G2 acceptance at 50 MHz. [D-016](../spec/DECISIONS.md#d-016--s11-g2-timing-repair-at-50-mhz) · [Original G2 failure](g2_area_timing.md)

## Repair 1

Image validation now reads the validity bit addressed by `ENTRY_PC`
directly. The engine PC drives the instruction read port in every state.
Both reads use the existing valid-bit vector.

The unchanged frozen jobs accepted S09 (2/2), S10 (2/2), S11 (6/6) and
the full regression (34/34). Verilator lint and the local cocotb smoke
test passed. The routed measurements and ISS comparison are pending.
[Regression records](../evidence/) · [S11 top-level regression](../evidence/s11_top/20261120T120329.log)
