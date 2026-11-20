"""Trace equivalence, arbiter RTL vs the signed model (Kalash 01:32: 'the model is what is signed').
Generates request traces with scripts/arbiter_model.py's own step() (rule R7.6/R7.6a + A0, EARLY = False) and writes,
per cycle, the asserted requests and the model's grant. tb_arbiter_trace replays them into rtl/dual_lane/l2_arbiter.sv
(reset between traces) and compares the grant (none / requester id) cycle by cycle.

Cycle semantics (identical in model and RTL): a job granted in cycle c occupies cycles c .. c+J-1; OVH idle cycles
follow; the RTL engine stub raises done in cycle c+J-1, so J >= 2. OVH = 4 (the A2 worst case, elaborated in the TB).
Traces (seeded, deterministic): 9,800 random traces (64 cycles, J in 2..8, per-trace assert probability 0.05..0.9) and
200 adversarial traces (1,000 cycles, J = 128, every idle requester asserts every cycle = continuous P and Q load).
Files: sim/dual_lane/arbiter/arb_trace_hdr.mem (per trace: J[7:0], length[15:0] as 6 hex digits) and
       sim/dual_lane/arbiter/arb_trace.mem (per cycle one byte: [7:4] grant code 0-3 or F = none, [3:0] asserts).
Usage: gen_arbiter_traces.py [--check]  (--check: regenerate in memory and compare with the committed files)."""
import random, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import arbiter_model as A

ROOT = Path(__file__).resolve().parents[1]; OUT = ROOT / 'sim/dual_lane/arbiter'
OVH, SEED = 4, 0x7A11E1
N_RANDOM, N_ADV, LEN_RANDOM, LEN_ADV = 9800, 200, 64, 1000

def trace(rng, J, length, p):
    s = (0, -1, 0, 0, 0, 0, 0); rows = []
    for _ in range(length):
        pend, owner = s[0], s[1]
        idle_reqs = [r for r in range(4) if not (pend >> r & 1) and r != owner]
        a = sum(1 << r for r in idle_reqs if rng.random() < p)
        s, g = A.step(s, a, J, OVH)
        rows.append(((g if g >= 0 else 0xF) << 4) | a)
    return rows

def build():
    rng = random.Random(SEED); hdr = []; body = []
    for i in range(N_RANDOM + N_ADV):
        adv = i >= N_RANDOM
        J = 128 if adv else rng.randint(2, 8); n = LEN_ADV if adv else LEN_RANDOM
        rows = trace(rng, J, n, 1.0 if adv else rng.uniform(0.05, 0.9))
        hdr.append(f'{J:02x}{n:04x}'); body += [f'{b:02x}' for b in rows]
    return '\n'.join(hdr) + '\n', '\n'.join(body) + '\n'

def main():
    h, b = build()
    grants = sum(1 for x in b.split() if x[0] != 'f')
    if '--check' in sys.argv:
        ok = (OUT / 'arb_trace_hdr.mem').read_text() == h and (OUT / 'arb_trace.mem').read_text() == b
        print(f'ARB_TRACES_CHECK: {"PASS" if ok else "FAIL"} traces={len(h.split())} cycles={len(b.split())} grants={grants}')
        sys.exit(0 if ok else 1)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'arb_trace_hdr.mem').write_text(h, newline='\n'); (OUT / 'arb_trace.mem').write_text(b, newline='\n')
    print(f'ARB_TRACES: traces={len(h.split())} cycles={len(b.split())} grants={grants}')

if __name__ == '__main__': main()
