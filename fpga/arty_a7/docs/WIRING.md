# Arty A7-100T wiring

This pinout is for the Arty A7-100T Rev D/E (`xc7a100tcsg324-1`) and the USB-UART FPGA build. Check the model and revision printed on the unpowered board, identify each Pmod by its silkscreen, and use each connector's pin-1 marker to orient the wires. The package pins below correspond to the active board constraints. [Digilent master XDC](https://github.com/Digilent/digilent-xdc/blob/master/Arty-A7-100-Master.xdc) · [Arty A7 schematic](https://digilent.com/reference/_media/reference/programmable-logic/arty-a7/arty_a7_sch.pdf) · [Rev E schematic](https://digilent.com/reference/_media/reference/programmable-logic/arty-a7/arty-a7-e2-sch.pdf)

## Onboard connections

| Board connection | FPGA pin | Function |
| --- | --- | --- |
| J10 USB programming/UART port | A9 RX, D10 TX, from FPGA perspective | Connect a USB data cable to the PC. The onboard USB-UART carries 115200 baud, 8N1, no flow control. Vivado uses JTAG through the same cable. |
| Oscillator | E3 | 100 MHz board clock. The wrapper derives the 50 MHz PVM/ILA clock. |
| Red RESET button | C2 | Active-low reset for the board wrapper and PVM. Press and release for a fresh board reset. |
| SW0 | A8 | Logic 1 enables the internal I²C target at address `0x50`. Logic 0 disables it for an external I²C target. Set before a run. |
| LD4 | H5 | MMCM locked. |
| LD5 | J5 | PVM reset released. |
| LD6 | T9 | Heartbeat, approximately 1.5 blinks per second. |
| LD7 | T10 | Stretch indicator for active host SPI frames. |

## Pmod signal pins

| Pmod | Pin | FPGA pin | Signal | Direction at Arty |
| --- | ---: | --- | --- | --- |
| JA | 1 | G13 | Host SPI SCK | Observation output |
| JA | 2 | B11 | Host SPI CS_n | Observation output |
| JA | 3 | A11 | Host SPI MOSI | Observation output |
| JA | 4 | D12 | Host SPI MISO | Observation output |
| JB | 1 | E15 | P5, UART TX or DMX512 logic TX | Output |
| JB | 2 | E16 | P6, demo SPI SCK | Output |
| JB | 3 | D15 | P7, demo SPI MOSI | Output |
| JB | 4 | C15 | P8 | Output |
| JB | 7 | J17 | P9 | Output |
| JB | 8 | J18 | P10 | Output |
| JB | 9 | K15 | P11 | Output |
| JC | 3 | V10 | P14 | Bidirectional |
| JC | 4 | V11 | P15 | Bidirectional |
| JC | 7 | U14 | P16 | Bidirectional |
| JC | 8 | V14 | P17 | Bidirectional |
| JC | 9 | T13 | P18 | Bidirectional |
| JC | 10 | U13 | P19 | Bidirectional |
| JD | 1 | D4 | P0 | Input |
| JD | 2 | D3 | P1 | Input |
| JD | 3 | F4 | P2 | Input |
| JD | 4 | F3 | P3 | Input |
| JD | 7 | E2 | P4 | Input |

Each Pmod provides ground on pins 5 and 11 and 3.3 V on pins 6 and 12. All mapped signals use `LVCMOS33`. With USB and external power disconnected, make wiring changes and check that each 3.3 V rail is clear of shorts. Use a common ground for the Arty, analyzer and any external target. Leave unused signal pins open. On JA, attach high-impedance analyzer inputs only. Keep all Pico GPIOs and other active drivers off JA. The PC supplies the bridge traffic through J10. Connect P5 to a 3.3 V analyzer input for DMX512 logic-level capture. A differential DMX cable requires an RS-485 line driver and suitable termination.

## Onboard I²C circuit

| Board connection | FPGA pin | Function |
| --- | --- | --- |
| J3 pin 1 | M18 | P12 SDA, bidirectional and open-drain |
| J3 pin 2 | L18 | P13 SCL, bidirectional and open-drain |
| R100 feed | A13 | 3.3 V output feeding the 2.2 kΩ SDA resistor |
| R101 feed | A14 | 3.3 V output feeding the 2.2 kΩ SCL resistor |

For the all-demos run set `SW0=1`, leave J3 and the Pmod headers empty, and connect J10 to the PC. The internal target acknowledges the addressed write and holds SCL low for the first ACK. Both lines should rest high when released. The bus lines themselves are driven low or released. [Digilent Rev D pin map](https://github.com/Digilent/Arty-A7-100-GPIO/blob/master/src/constraints/Arty_Master.xdc#L911-L918) · [Digilent schematic, sheet 3](https://digilent.com/reference/_media/reference/programmable-logic/arty-a7/arty_a7_sch.pdf#page=3)

## Capture connections

The built-in ILA uses J10 and the board's own I²C resistor circuit. An external logic analyzer, if used separately, uses the inputs below and a Pmod ground. Use 3.3 V-compatible high-impedance inputs throughout.

| Signal | ILA probe | External analyzer input |
| --- | ---: | --- |
| P5 | 0 | CH0 on JB1 |
| P6 | 1 | CH1 on JB2 |
| P7 | 2 | CH2 on JB3 |
| SDA | 3 | CH3 on J3 pin 1 |
| SCL | 4 | CH4 on J3 pin 2 |
| Host SCK | 5 | CH5 on JA1 |
| Host CS_n | 6 | CH6 on JA2 |
| Host MOSI | 7 | CH7 on JA3 |
| Host MISO | 8 | Optional CH8 on JA4 |
| PVM reset_n | 9 | Internal |
| PVM I/O output enable `[7:0]` | 10 | Internal |
| PVM I/O output data `[7:0]` | 11 | Internal |

Photograph the board model/revision, USB cable and SW0 position. Use the [run procedure](../README.md) to reproduce the USB-only bench and name the captures. [Board results](../results/README.md)
