# Check PVM release identity

This check compares a candidate Git revision with [routed source 752ebb9](https://github.com/arnav1609/pvm-protocol-emulator/commit/752ebb97824cfd1161581497c22d3c171c4c6ca9). It reads committed bytes, so checkout line endings and uncommitted edits do not affect the result. It checks the complete file inventory, Git modes and SHA-256 of every file in `src/`, `info.yaml`, `test/`, `tb_rtl/` and `tools/`.

## Run the check

Use a clone containing the routed source and candidate commits. Run from that clone with the checker files available. For example, the bundled checker can sit in a separate working directory and use `--repo` to point to the clone.

```bash
bash tools/release_identity.sh e1018ff --profile routed > release-identity.md
bash tools/release_identity.sh e1018ff --profile rtl > rtl-identity.md
```

On Windows, use the Python entry point from PowerShell. Use `Out-File` to save UTF-8 on PowerShell 5.1.

```powershell
python .\tools\release_identity.py e1018ff --profile routed | Out-File -FilePath .\release-identity.md -Encoding utf8
$LASTEXITCODE
```

The Markdown report starts with the verdict, two full commit IDs and the path counts. It lists changed paths, the observed versions alongside their required values, and a SHA-256 comparison for each protected file. Exit 0 means the complete comparison and tool check passed. Exit 1 means a file or local tool differed. Exit 2 indicates invalid input or inability to read Git objects.

## Tool versions checked

| Local profile | Icarus compiler and runtime | Python | cocotb | Verilator |
| --- | --- | --- | --- | --- |
| `routed` (default) | 13.0 | 3.12.x | 2.0.1 | 5.032 |
| `rtl` | 12.0 | 3.12.x | 2.0.1 | 5.032 |

These profiles combine the recorded local Python and cocotb environment, the Icarus version for each flow, and the secondary simulator used for seeded RTL replay. The Bash wrapper checks the Python environment selected by `PYTHON` or `python3`. The Python fallback checks the interpreter actually running it, its installed cocotb version, and the executables found on PATH. The CI workflow has a separate Python 3.11 pin. The later routed replay wrapper accepts Icarus 13.0 or newer. These profiles check the versions used as reference for A3. [RTL verification](https://github.com/arnav1609/pvm-protocol-emulator/blob/752ebb97824cfd1161581497c22d3c171c4c6ca9/docs/VERIFICATION.md) · [Archived routed replay](https://github.com/arnav1609/pvm-protocol-emulator/blob/e1018ff505ae4e2b2d8c0ee1f4753083b8e97e0c/evidence/v1.0_rc/physical/gate_replay/dmx512.log) · [CI configuration](https://github.com/arnav1609/pvm-protocol-emulator/blob/752ebb97824cfd1161581497c22d3c171c4c6ca9/.github/workflows/test.yaml)

## Interpret the current release review

The strict release-candidate control is `e1018ff`. All 83 original protected files are also unchanged in `0d2978a`, which adds 13 protocol example files under `tools/examples/matrix/`. Those additions fail the exact-inventory rule. The same rule rejects new checker files if they are included under `tools/` in the SHA being evaluated. Run this checker from its review branch or external handoff against the candidate SHA. Kalash owns any change to the release inventory rule, and the strict report preserves the differences for that decision.

The checker reports source and local tool identity. The routed artifact checks and gate replay have their own evidence. [A3 handoff](HANDOVER.md) · [Frozen check plan](FROZEN_CHECKS.md)
