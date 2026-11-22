# DMX512 TX held-out image

[Draw record](https://github.com/arnav1609/pvm-protocol-emulator/blob/19b47d2b16eb6dedfce83d390d3f5f2ae18ff8ed/results/held_out_draw.md) · [Frozen RTL](https://github.com/arnav1609/pvm-protocol-emulator/tree/rtl-freeze)

The 22 November 2026 contract specifies two short DMX512-A packets.
Each contains the NULL START Code 0x00 and 24 consecutive 0xA5 data
slots. Host SPI loads and enables the committed image, then idles
through transmission. HALT and reload repeat the same transaction.

## Image

| Item | Value |
| --- | --- |
| Frozen RTL | `b33a9227ac187f791a3733b94ac4e32879b10414` |
| Protocol output | P5, `uo_out[0]`, push-pull, idle high |
| Host SPI | Dedicated `ui_in[2:0]` and `uo_out[7]` |
| Core clock / divider | 50 MHz / 100 |
| Engine tick / serial bit | 2 µs / 4 µs |
| Program size | 29 of 32 instruction words |
| TX preload | Empty |

Engine value 0 drives MARK and value 1 drives SPACE. The configured
inversion preserves high MARK through ENABLE initialization. The image
builds 0xA5 in the ISR and keeps track of the second packet in its high
byte. The send loop uses OUT and JMP for each two-tick data bit.
Slot bookkeeping fits within the two high stop bits. After the first
packet it adds 36 µs of high mark before starting the second BREAK.
[Image source](../tools/examples/dmx512_tx.pvm) · [Config](../tools/examples/dmx512_tx.json) · [Generated SPI image](../tools/examples/dmx512_tx.image.json)

Build from the repository root.

```sh
python3 -m tools.pvm_asm tools/examples/dmx512_tx.pvm /tmp/pvm-dmx512.hex
python3 -m tools.pvm_image tools/examples/dmx512_tx.pvm /tmp/pvm-dmx512.json \
  --config tools/examples/dmx512_tx.json
cmp /tmp/pvm-dmx512.json tools/examples/dmx512_tx.image.json
```

## Recorded acceptance

| Measurement | Nominal target | Accepted window |
| --- | ---: | ---: |
| BREAK low | 6,400 core cycles / 128 µs | At least 92 µs |
| Mark after BREAK | 800 cycles / 16 µs | At least 12 µs |
| Serial slot | 2,200 cycles / 44 µs | 245–255 kbit/s, one start bit, eight LSB-first data bits and two stop bits |
| First BREAK to second BREAK | 64,000 cycles / 1,280 µs | At least 1,204 µs and within the standard upper limit |
| Second packet end | Two complete stop bits then idle high | DONE by 3 ms from ENABLE |

The owner contract freezes one compound check named
`DMX512_TX_PACKET` for each of `dmx512_tx` and
`dmx512_tx_neg_short_mab`. The owner's decoder checks the two
packets before and after HALT and reload. The mutant shortens only
the first MAB to 8 µs and must fail `DMX_MAB_MIN`. The expected
inter-BREAK interval for the mutant is 1,272 µs. This is a simulated
logic-output demo. A physical bus requires an appropriate differential
line driver, cabling and termination.
[ANSI E1.11-2024, transmitter timing Table 6](https://tsp.esta.org/tsp/documents/docs/ANSI%20E1.11%20-%202024.pdf)

## Capture for the independent decoder

Run from the repository root using cocotb and Icarus. The capture
records P5 value changes before ENABLE through the idle after
transmission. It reads DONE over production host SPI after the burst
and repeats with the same image. The capture smoke test checks the
load and DONE lifecycle and supplies edges to the owner decoder.

```sh
(cd test && PYTHONPATH=.. make COCOTB_TEST_MODULES=capture_dmx512)
```

The output is `test/output/dmx512_tx/run_1_p5.csv` and
`run_2_p5.csv`, with a core cycle and line level per transition.
Use `PVM_DMX_IMAGE` to supply a different SPI image and
`PVM_DMX_CAPTURE` to choose another output directory. To build the
mutant, change the delay at the `first_mab` label from `[4]` to
`[0]` in a copy of the source and invoke the same image builder
with that copy. The owner waveform verdict and final gate-netlist
replay are separate deliverables.

### Author capture results

Icarus 12.0 and cocotb 2.0.1 captured both images on the frozen
RTL. The image and capture code were tested at software commit
`209a1526b97d799ee3b46cb093785cc5804bfb5b`. A Git diff verified that the RTL, Tiny Tapeout inputs and
registered jobs match the freeze tag.

| Capture | BREAK | First / second MAB | Bit / slot | BREAK to BREAK |
| --- | ---: | ---: | ---: | ---: |
| Positive, initial and reloaded | 128 µs | 16 / 16 µs | 4 / 44 µs | 1,280 µs |
| First-MAB mutant, initial and reloaded | 128 µs | 8 / 16 µs | 4 / 44 µs | 1,272 µs |

Every captured packet contained one 0x00 start code and 24 0xA5
data slots. Both captures finished high. The host observed DONE
2.924 ms after the ENABLE SPI frame ended. Assembly produces
29 instruction words and zero TX preload bytes. The mutant
changes the first MAB instruction at PC 7 from 0xE400 to 0xE000.
Its compiler, SPI loader and capture all ran successfully.
The independent owner decoder's `DMX_MAB_MIN` log is a separate
verification record. The release candidate's functional gate replay
matched both positive P5 captures cycle for cycle.

[Annotated waveform](../evidence/dmx512_tx/dmx512_waveform.png) · [Measured edges and logs](../evidence/dmx512_tx/) · [Exact capture summary](../evidence/dmx512_tx/waveform_summary.json) · [Final gate replay](../results/v1.0_routed.md)

### Reproduce the short-MAB capture

```sh
python3 - <<'PY'
from pathlib import Path
source = Path("tools/examples/dmx512_tx.pvm").read_text()
anchor = "first_mab:\n    set pins, 0 [4]"
assert source.count(anchor) == 1
Path("/tmp/pvm-dmx512-short-mab.pvm").write_text(
    source.replace(anchor, "first_mab:\n    set pins, 0 [0]")
)
PY
python3 -m tools.pvm_image /tmp/pvm-dmx512-short-mab.pvm /tmp/pvm-dmx512-short-mab.json \
  --config tools/examples/dmx512_tx.json
(cd test && PYTHONPATH=.. PVM_DMX_IMAGE=/tmp/pvm-dmx512-short-mab.json \
  PVM_DMX_CAPTURE=output/dmx512_short_mab make COCOTB_TEST_MODULES=capture_dmx512)
```
