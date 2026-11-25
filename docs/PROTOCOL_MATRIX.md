# Protocol coverage on frozen PVM RTL

Programs target `rtl-freeze` at
`b33a9227ac187f791a3733b94ac4e32879b10414` and a 50 MHz core.
CLKDIV measures core clocks per engine tick. All results are digital.

| Transaction | Words | CLKDIV | RTL and mutation evidence | Functional gate replay |
| --- | ---: | ---: | --- | --- |
| UART TX 0x35 | 8 | 217 | S14b | Passed |
| SPI controller mode 0 | 7 | 32 | S14b | Passed |
| I²C write to 0x50 | 18 | 80 | S14b, ACK and target stretch | Passed |
| DMX512 TX, held out | 29 | 100 | Contract and short-MAB mutant | Passed, including reload |
| 1-Wire power-supply read | 19 | 200 | Digital fit study, write-zero mutant | Fit study only |
| SWD initialized read | 32 | 20 | Digital fit study, parity mutant | Fit study only |
| SPI controller mode 1 | 7 | 32 | Author check and targeted mutant | Pending |
| SPI controller mode 2 | 7 | 32 | Author check and targeted mutant | Pending |
| SPI controller mode 3 | 7 | 32 | Author check and targeted mutant | Pending |
| I²C nominal 100 kHz data cells | 22 | 100 | Author check and targeted mutant | Pending |
| I²C nominal 400 kHz data cells | 22 | 25 | Author check and targeted mutant | Pending |
| WS2812B-format one-pixel TX | 11 | 4 | Author check and targeted mutant | Pending |
| PS/2 device-to-host one-byte RX | 27 | 16 | Author check and targeted mutant | Pending |

The baseline I²C image at divider 80 delivered a 320-core-clock
regular bit period in the ideal model (156.25 kHz). The nominal
100 and 400 kHz images share a separately scheduled program. The FPGA column for all
rows remains pending an authorized board run.
[Baseline pin gate](../reports/S14b_protocols_gate.md) · [Routed replay](../results/v1.0_routed.md) · [Fit studies](../results/fit_study.md) · [Frozen 1-Wire and SWD rerun](../evidence/v1.0_rc/protocol_matrix/frozen-fit-replay.log) · [Held-out draw](../results/held_out_draw.md)

## Build the new images

Run from the repository root with Python 3.10 or later. Each command
outputs the SPI loader's JSON with ordered writes, CRC and TX preload.

```sh
set -euo pipefail
out=$(mktemp -d)
matrix=tools/examples/matrix
for mode in 1 2 3; do
    image=spi_mode$mode
    python3 -m tools.pvm_image "$matrix/$image.pvm" "$out/$image.json" \
        --config "$matrix/$image.json" --tx 0xA6 --tx 0xC9
done
python3 -m tools.pvm_image "$matrix/i2c_400k.pvm" "$out/i2c_400k.json" \
    --config "$matrix/i2c_400k.json" --tx 0xA0 --tx 0x3C
python3 -m tools.pvm_image "$matrix/i2c_400k.pvm" "$out/i2c_100k.json" \
    --config "$matrix/i2c_100k.json" --tx 0xA0 --tx 0x3C
python3 -m tools.pvm_image "$matrix/ws2812b_tx.pvm" "$out/ws2812b_tx.json" \
    --config "$matrix/ws2812b_tx.json" --tx 0x96 --tx 0x3C --tx 0xA5
python3 -m tools.pvm_image "$matrix/ps2_rx.pvm" "$out/ps2_rx.json" \
    --config "$matrix/ps2_rx.json"
```

## Checks proposed for independent acceptance

| Images | One compound positive check per image | One targeted mutation per image |
| --- | --- | --- |
| SPI modes 1, 2 and 3 | Correct idle polarity, 16 sampling edges, stable MSB-first A6/C9 on the mode's sampling edge, expected return to idle | Extend the active half-cycle by one engine tick and require an exact timing failure |
| I²C nominal 400 kHz | START, address 0x50/write, 0x3C, both ACK releases, stretch, STOP and 125 core clocks between regular data rises | Shorten OUT's low-phase delay by one tick and detect the regular-bit timing change |
| WS2812B-format TX | 24 GRB bits, 320 ns zero/720 ns one highs, 1.28 µs cells and at least 300 µs low before DONE | Shorten the latch-low loop |
| PS/2 RX | 0x96 from a valid LSB-first odd-parity frame, reject bad parity with an empty RX FIFO and FLAG3 | Bypass the parity rejection branch |

The original six compound checks and their six negative runs were
fixed before execution. A separate 100 kHz case uses the same I²C
schedule and low-phase mutant. Before its first run, its frozen
compound check requires 500 core clocks per ordinary data period,
two ACKs, target stretch and STOP. It must catch the mutant at
`I2C_DATA_PERIOD`. Independent target models and an acceptance record
are required for the new rows.

## Author-side RTL replay

The SPI-loaded runs use the frozen RTL and unchanged release loader
and benches. With Python 3.12, Icarus 12.0 and cocotb 2.0.1, the
author harness accepted seven positive cases and caught all seven
mutants at the named criteria. The I²C data periods were 500 and 125
core clocks in the ideal model. The WS2812B-format run held the final
low for 16,475 clocks (329.5 µs). The PS/2 run received 0x96 and
rejected a wrong parity bit with the RX FIFO empty. The four 1-Wire
and SWD fit-study jobs also passed on a separate freeze checkout,
including the expected mutation detections.

```sh
(cd test && PYTHONPATH=..:../evidence/v1.0_rc/protocol_matrix make COCOTB_TEST_MODULES=test_author_replay &&
  python3 -m cocotb_tools.check_results results.xml)
```

The new rows await independent model acceptance. The simulated
digital rates and waveforms do not establish electrical compliance
or hardware operation.
[Author bench](../evidence/v1.0_rc/protocol_matrix/test_author_replay.py) · [Raw author replay](../evidence/v1.0_rc/protocol_matrix/author-replay.log)
