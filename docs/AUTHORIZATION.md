# PVM authenticated SPI candidate

The feature worktree starts from `rtl-freeze` at
`b33a9227ac187f791a3733b94ac4e32879b10414`. The authorization build
uses the approved 8×4 footprint target and 50 MHz target. The
authorization-only utilization exception covers the internal 40%
cap and the 33.7187% comparison target. Keep the reviewed baseline
available for submission. [Baseline release candidate](https://github.com/arnav1609/pvm-protocol-emulator/tree/codex/pvm-v1.0-rc)

## Interface and ownership

Compile `pvm_top` with `PVM_AUTH` to select the secure SPI front end.
The top accepts trust inputs independently of all public pads. It
implements ID (0x9F), SUBMIT (0xA0), INFO (0xA1), and allowlisted
SAFE_READ (0xA2). The legacy 0x02/0x03 decoder is excluded from this
build. The standard baseline configuration uses the original host
decoder.

Each SUBMIT retains one entire byte-aligned frame until it retires.
The dispatcher checks device, live challenge, operation, sequence and
image root. One Keccak datapath serves the employee KDF, fixed-size
KMAC tag comparison and the SHA3 image chain. The canonical scanner
checks every address, writable bit and record order before the guarded
single-master bus can make a write. Chunk acceptance also checks native
WR_REJ. FINISH checks the terminal link, CRC and the PVM's committed
image ID and preload. Authenticated READY awaits a separate owner START.
The owner or head can cancel. Cancellation retires the challenge, halts
the program and clears authorization. An internal validation failure
allows cancellation and requires a fresh load before START.

INFO snapshots a 74-byte response at CS assertion and does not touch the
bus. SAFE_READ allocates one available read slot and zero is returned
for a disallowed address or a conflicting effect. Public reads cannot
generate a FIFO acknowledge. A verified TX or RX shortage returns retry
before any strobe or sequence update. RX output is cached with the
committed sequence so the host can check an acknowledgement without
popping data again.

## Trust provisioning design

The integrated top exposes a same-clock trust-provider interface.
`trust_valid` qualifies a stable device ID and 256-bit per-device
master key. The provider presents a 128-bit challenge with
`trust_challenge_valid` until `trust_challenge_ready` accepts it.
`trust_challenge_retired` signals cancellation or revocation. A change
of device or master key requires revocation before reasserting
`trust_valid`. The controller masks transactional strobes on revocation,
issues safe HALT and resets ownership, buffered command validity, hash
and key state. Its same-boot replay filter also refuses the most recently
accepted challenge. The provider is responsible for uniqueness across
all epochs, including power cycles.

For a production implementation, provision a device-unique random
master through a dedicated manufacturing path into a reviewed protected
OTP or equivalent secure key store. Close provisioning and disable
readback and scan access before operational mode. A boot-qualified
hardware entropy source with health tests should supply fresh 128-bit
challenges, or a protected monotonic epoch plus a keyed derivation may
provide uniqueness. A randomness or storage failure keeps trust invalid.
Treat master-key logic, credential provisioning, scan controls, entropy
qualification and generation across reset as part of the security
boundary. The signing service derives and distributes per-identity keys.
The host library takes a signer callback, and START also takes a separate
approval callback carrying the exact device and image root.

The standard Tiny Tapeout pad wrapper has no approved protected key
storage, trusted provisioning channel or reset-fresh challenge source.
Its secure configuration ties trust invalid and stays LOCKED. The
functional and mapping tops instead expose the trusted hardware interface
for controlled test vectors. They use only public fixture keys in
simulation. A locked TT wrapper or a fixture key is unsuitable as a
functional GDS release. Completing the physical build requires an
approved provider implementation connected inside the wrapper while
preserving the 8×4 footprint and existing pinout.

## Reproduce

Use Python, Icarus Verilog, OpenSSL and the repository source lists.
The integrated driver signs demo images over real chip SPI pins at
50 MHz core and 3.125 MHz SCK. It checks each accepted bus write and the
original pin-level UART, SPI and I²C assertions. DMX captures are compared
to the 392 frozen transitions relative to the first BREAK.

```sh
python verification/authenticated/run.py UART SPI I2C DMX_RELOAD DMX_NEG SECURITY FIFO \
  --output /tmp/pvm-auth-inferred
python verification/authenticated/run.py UART SPI I2C DMX_RELOAD DMX_NEG SECURITY FIFO \
  --sram --sram-models "$IHP_SRAM_MODELS" --output /tmp/pvm-auth-sram
```

Map with Yosys 0.52 and ABC against the pinned typical CMOS5L standard-cell
Liberty and the `RM_IHPSG13_1P_64x64_c2_bm_bist` Liberty at
IHP-Open-PDK `89d42ee6d2fd9b50b86a1aada6fee6673c3e6008`.

```sh
python verification/authenticated/map_full.py \
  --liberty "$IHP_CELLS_LIB" --macro-liberty "$IHP_SRAM_LIB" \
  --output /tmp/pvm-auth-map
python verification/authenticated/run.py UART SPI I2C DMX_RELOAD \
  --mapped /tmp/pvm-auth-map/sram.v --pdk-cells "$IHP_FUNCTIONAL_CELL_MODELS" \
  --sram-models "$IHP_SRAM_MODELS" --output /tmp/pvm-auth-mapped --jobs 1
```

The mapping retains only internal observation wires used by the checks.
ASIC macro area is reported separately and included in the combined
total. The SRAM physical views and functional models are available in
the pinned PDK. A future physical build must load the macro LEF, GDS and
all corner Liberty views, and connect the macro supplies to the floorplan
power grid. The synthesis and functional mapped simulation do not
measure routed timing, power or precheck.
[IHP SRAM collateral](https://github.com/IHP-GmbH/IHP-Open-PDK/tree/89d42ee6d2fd9b50b86a1aada6fee6673c3e6008/ihp-sg13g2/libs.ref/sg13g2_sram)
