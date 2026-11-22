# PVM v1.0 release candidate

Use the public review branch `codex/pvm-v1.0-rc` for the fresh-clone
check. The frozen hardware source is `rtl-freeze` at
`b33a9227ac187f791a3733b94ac4e32879b10414`.

## Fresh-clone checks

With Git, make, Python 3.10+ and Icarus Verilog on PATH, run

```sh
git clone --branch codex/pvm-v1.0-rc https://github.com/arnav1609/pvm-protocol-emulator.git
cd pvm-protocol-emulator
git diff --exit-code rtl-freeze HEAD -- src/ info.yaml tb_rtl/
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r test/requirements.txt
python -m unittest discover -s tools/tests -v
python tb_rtl/pvm_run.py selftest
python tb_rtl/pvm_run.py run --select all
python tb_rtl/pvm_run.py trace-golden --check
(cd test && PYTHONPATH=.. make COCOTB_TEST_MODULES=test,test_toolchain,test_iss_lockstep,capture_dmx512)
```

Use an LF checkout for the standalone golden regeneration.
[Windows follow-up](TOOLCHAIN.md#windows-trace-regeneration-follow-up)

Build the accepted DMX512 demo from source and compare the complete
serialized image.

```sh
python -m tools.pvm_image tools/examples/dmx512_tx.pvm /tmp/pvm-dmx512.json \
  --config tools/examples/dmx512_tx.json
cmp /tmp/pvm-dmx512.json tools/examples/dmx512_tx.image.json
```

[Baseline images and loader](TOOLCHAIN.md) · [Held-out image and capture](DMX512_TX_DEMO.md) · [Owner verification](../evidence/owner_b33a922/README.md)

## Physical release evidence

The matched build campaign uses the frozen source, one 8×4 IHP
SG13CMOS5L footprint, a 20 ns clock, and pinned LibreLane and
Tiny Tapeout tooling. The feature defines are the variant input.
The full variant is the gate-level demo target. Use the CI run
and artifact hashes in the final routed record for replay.

The owner reviews the exact release commit, results, protocol
evidence and public checkout before publication of v1.0.
