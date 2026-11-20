"""Capture and compare the D-016 per-cycle RTL traces."""

import csv
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile


BASELINE = '4b13f45d977832428a590530add8aace1783022c'
VECTORS = Path('tb_rtl/vectors')
PROVENANCE = VECTORS / 'golden_provenance.json'
FIELDS = ('cycle', 'run_state', 'pc', 'instr_valid', 'out_val', 'oe_val',
          'fab_ctrl', 'fab_wr', 'tx_pop', 'rx_push', 'rx_din', 'fault_req', 'fault_code')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def trace_rows(path):
    with path.open(newline='') as stream:
        rows = csv.reader(stream)
        if tuple(next(rows, ())) != FIELDS:
            raise ValueError(f'{path}: invalid trace header')
        body = list(rows)
    if not body:
        raise ValueError(f'{path}: empty trace')
    for cycle, row in enumerate(body):
        if len(row) != len(FIELDS) or row[0] != str(cycle):
            raise ValueError(f'{path}: invalid row for cycle {cycle}')
    return body


def compare(root, job, candidate):
    root, candidate = Path(root), Path(candidate)
    relative = VECTORS / f"golden_{job['top']}.csv"
    golden = root / relative
    manifest = json.loads((root / PROVENANCE).read_text())
    expected_hash = manifest['traces'][job['top']]['sha256']
    if manifest['baseline'] != BASELINE or digest(golden) != expected_hash:
        raise ValueError(f'{relative}: golden trace provenance mismatch')
    before, after = trace_rows(golden), trace_rows(candidate)
    fields = set()
    first_difference = None
    for cycle, (expected, actual) in enumerate(zip(before, after)):
        differences = [(name, old, new) for name, old, new in zip(FIELDS, expected, actual)
                       if old != new]
        fields.update(name for name, _, _ in differences)
        if differences and first_difference is None:
            first_difference = {'cycle': cycle, 'values': differences}
    if len(before) != len(after):
        fields.add('length')

    if job.get('negative') and fields and fields != {job['mutant']['delay_output']}:
        raise ValueError(f'Unexpected trace differences in mutant: {sorted(fields)}')
    passed = not fields
    state = 'PASS' if passed else 'FAIL'
    metadata = {
        'golden': str(relative),
        'golden_sha256': expected_hash,
        'actual_sha256': digest(candidate),
        'golden_cycles': len(before),
        'actual_cycles': len(after),
        'different_fields': sorted(fields),
        'first_difference': first_difference,
    }
    detail = (f"TRACE_COMPARE {json.dumps(metadata)}\n[{state}] {job['trace_check']}\n"
              f'CHECKS : 1\nERRORS : {int(not passed)}\nRESULT : {state}\n')
    return detail, metadata


def delay_output(source, output, replace_once):
    """Delay the published value in a copied RTL source, preserving its feedback."""
    declaration = re.search(
        rf'^([ \t]*output[ \t]+reg[ \t]+(\[\d+:\d+\]))[ \t]+{re.escape(output)},$',
        source, re.MULTILINE,
    )
    if declaration is None:
        raise ValueError(f'Cannot find registered output {output}')
    internal = f'{output}_undelayed_mutant'
    renamed = re.sub(rf'\b{re.escape(output)}\b', internal, source)
    renamed = replace_once(renamed, declaration[0].replace(output, internal), declaration[0])
    return replace_once(
        renamed, '\n);\n',
        f'\n);\n\n    reg {declaration[2]} {internal};\n'
        f"    always @(posedge clk) {output} <= rst_n ? {internal} : 0;\n",
    )


def generate(root, jobs, run_job, check):
    if not jobs:
        raise ValueError('No trace jobs registered')
    root = Path(root)
    build = root / 'tb_rtl/build/golden'
    build.mkdir(parents=True, exist_ok=True)
    generated = {}
    manifest = {'baseline': BASELINE, 'sampling': 'before the rising-edge update', 'traces': {}}
    with tempfile.TemporaryDirectory(dir=build) as directory:
        copy = Path(directory)
        archive = subprocess.check_output(['git', 'archive', BASELINE, 'src'], cwd=root)
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(copy, filter='data')
        for job in jobs:
            for path in (Path(name) for name in job['sources'] if name.startswith('tb_rtl/')):
                (copy / path).parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(root / path, copy / path)
            state, info, log = run_job(job, root=str(copy), capture_trace=True)
            if state != 'PASS_FRESH':
                print(log)
                return 1
            trace = Path(info['trace'])
            top = job['top']
            path = VECTORS / f'golden_{top}.csv'
            manifest['traces'][top] = {
                'file': str(path),
                'sha256': digest(trace),
                'cycles': len(trace_rows(trace)),
                'sources': {filename: digest(copy / filename) for filename in job['sources']},
            }
            generated[path] = trace.read_bytes()
    generated[PROVENANCE] = (json.dumps(manifest, indent=2) + '\n').encode()
    for path, data in generated.items():
        destination = root / path
        if check:
            if not destination.is_file() or destination.read_bytes() != data:
                print(f'GOLDEN_MISMATCH {path}')
                return 1
        else:
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
        print(f'GOLDEN_{"MATCH" if check else "WRITTEN"} {path}')
    return 0
