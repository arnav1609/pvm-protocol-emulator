# PVM v1.0 release candidate

Use the full commit SHA from the owner’s release review for the
fresh-clone check. The frozen hardware source is `rtl-freeze` at
`b33a9227ac187f791a3733b94ac4e32879b10414`.

## Fresh-clone checks

The recorded check used Python 3.12, cocotb 2.0.1 and Icarus 12.0.
With Git, make and those versions on PATH, export the reviewed full
SHA as `PVM_RELEASE_SHA` and run in Bash.

```sh
set -euo pipefail
git clone --config core.autocrlf=false --no-checkout https://github.com/arnav1609/pvm-protocol-emulator.git
cd pvm-protocol-emulator
git checkout --detach "${PVM_RELEASE_SHA:?Set the full reviewed commit SHA}"
test "$(git rev-parse HEAD)" = "$PVM_RELEASE_SHA"
test "$(git rev-parse rtl-freeze^{commit})" = b33a9227ac187f791a3733b94ac4e32879b10414
git diff --exit-code rtl-freeze HEAD -- src/ info.yaml tb_rtl/
git cat-file -e '4b13f45^{commit}'
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r test/requirements.txt
python -m unittest discover -s tools/tests -v
python tb_rtl/pvm_run.py selftest
python tb_rtl/pvm_run.py run --select all
python tb_rtl/pvm_run.py trace-golden --check
(
  cd test
  make clean
  PYTHONPATH=.. make COCOTB_TEST_MODULES=test,test_toolchain,test_iss_lockstep,capture_dmx512
  python -m cocotb_tools.check_results results.xml
)
```

Use an LF checkout for the standalone golden regeneration.
[Windows follow-up](TOOLCHAIN.md#windows-trace-regeneration-follow-up)

Build the accepted DMX512 demo from source and compare the complete
serialized image.

```sh
image_dir=$(mktemp -d)
python -m tools.pvm_image tools/examples/dmx512_tx.pvm "$image_dir/dmx512.json" \
  --config tools/examples/dmx512_tx.json
cmp "$image_dir/dmx512.json" tools/examples/dmx512_tx.image.json
```

[Baseline images and loader](TOOLCHAIN.md) · [Held-out image and capture](DMX512_TX_DEMO.md) · [Owner verification](../evidence/owner_b33a922/README.md)

The public fresh clone at `752ebb97824cfd1161581497c22d3c171c4c6ca9`
passed 25 Python unit tests, 71 registered RTL jobs and four cocotb
tests. Standalone golden regeneration matched four CSVs and the
provenance manifest. The DMX program, config and image match the
accepted source, and regeneration produced the exact serialized image.
[Fresh-clone logs](../evidence/v1.0_rc/) · [DMX source and image hashes](../evidence/v1.0_rc/dmx512.sha256) · [Software CI](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/45050929399)

## Physical release evidence

The matched build campaign uses the frozen source, one 8×4 IHP
SG13CMOS5L footprint, a 20 ns clock, and pinned LibreLane and
Tiny Tapeout tooling. The feature defines are the variant input.
The full variant is the gate-level demo target. Use the CI run
and artifact hashes in the final routed record for replay.
The final build passed GDS, all ten prechecks and the gate-level
SPI smoke test. The packaged replay script checked UART, SPI, I²C
and the initial and reloaded DMX512 executions on the routed netlist
using Icarus 13.0 and zero-delay PDK models. Static setup and hold
passed at all three corners. Slow-corner SDF simulation was inconclusive.
[Matched variant measurements and final routed build](../results/v1.0_routed.md) · [Download routed ZIP](https://raw.githubusercontent.com/arnav1609/pvm-protocol-emulator/b49f6376e3741cb211f1aa94975a220e990569b8/artifacts/PVM_v1.0_rc_routed.zip)

Use Icarus Verilog 13.0 or later for both the compiler and runtime
for gate replay. Install the validated Tiny Tapeout 13.0 build,
activate the Python environment above, extract the ZIP and verify
its SHA-256 and file manifest. From this repository, run the wrapper
with the extracted bundle directory. The wrapper checks the two
versions before it invokes the packaged replay from a temporary
checkout of the recorded routed source.

```sh
scripts/replay_routed.sh /absolute/path/to/extracted-routed-bundle
```

[Validated Icarus package](https://github.com/TinyTapeout/iverilog/releases/tag/v13.0) · [Version failure analysis](../results/gate_icarus.md)

The owner reviews the exact release commit, results, protocol evidence
and public checkout before publication of v1.0. Advance `main` by
fast-forward and tag the approved commit. Verify the published branch,
peeled tag and routed ZIP checksum from a clean clone.
