"""C3 (M-F1 rev 7 R7.6/R7.9): exhaustive model of the shared L2 KMAC arbiter. Proves the frozen wait bounds
P <= 269 and Q <= 792 cycles (M-F1 R7.6a, Kalash 2026-10-20 Option 1; the R7.6 values 260/516 were wrong) for EVERY request pattern (not a bounded random sample).

Model (cycle level), one shared engine, requesters r0, r1 (class P, RoT-sourced) and r2, r3 (class Q):
  - each requester has at most one outstanding request; it holds it until granted; after its job completes it may
    request again in the very next cycle (the adversary chooses, every cycle, which idle requesters assert);
  - a job occupies the engine for J cycles (J = J_MAX = 128, worst case); OVH idle cycles follow every job before
    the next grant (handshake overhead; checked for OVH = 0..4);
  - grant rule (R7.6, R7.6a): when the engine is free, grant P (round-robin inside P; A0: the class pointer moves to
    the other requester after EVERY grant in that class) unless 2 consecutive P grants were
    already made while a Q request was pending, in which case grant Q (round-robin inside Q); otherwise Q if pending.
    The consecutive-P counter resets on a Q grant and on any P grant made while no Q is pending. No pre-emption.
Method: the arbiter state (pending set, owner, remaining job cycles, idle overhead, consecutive-P count, round-robin
pointers) is finite. For each requester r the worst wait is the longest path through states in which r is pending,
counted from the cycle its request is asserted to the cycle it is granted. A cycle in that subgraph would mean
unbounded starvation and fails the model. Prints ARBITER_MODEL: PASS with the exact maxima, or exits non-zero."""
import sys
from functools import lru_cache
from itertools import product

J_MAX = 128
BOUND = {0: 269, 1: 269, 2: 792, 3: 792}        # R7.6a, J_MAX 128, OVH <= 4
EARLY = False   # A1 variant: a requester may re-request while its own job is in flight
P, Q = (0, 1), (2, 3)
sys.setrecursionlimit(100000)

def step(state, asserts, J, OVH):
    """One cycle. state = (pend bitmask, owner or -1, rem, idle, consec, rrp, rrq). Returns (new_state, granted or -1)."""
    pend, owner, rem, idle, consec, rrp, rrq = state
    pend |= asserts
    granted = -1
    if owner < 0 and idle == 0 and pend:
        pp = [r for r in (P[rrp], P[1 - rrp]) if pend >> r & 1]
        qp = [r for r in (Q[rrq], Q[1 - rrq]) if pend >> r & 1]
        if pp and not (consec >= 2 and qp):
            granted = pp[0]; consec = consec + 1 if qp else 0; rrp = 1 - P.index(granted)
        elif qp:
            granted = qp[0]; consec = 0; rrq = 1 - Q.index(granted)
        if granted >= 0:
            pend &= ~(1 << granted); owner, rem = granted, J
    if owner >= 0:
        rem -= 1
        if rem == 0: owner, idle = -1, OVH
    elif idle > 0:
        idle -= 1
    return (pend, owner, rem, idle, consec, rrp, rrq), granted

def choices(state):
    pend, owner = state[0], state[1]
    idle_reqs = [r for r in range(4) if not (pend >> r & 1) and (EARLY or r != owner)]
    for bits in product((0, 1), repeat=len(idle_reqs)):
        yield sum(b << r for b, r in zip(bits, idle_reqs))

def reachable(J, OVH):
    start = (0, -1, 0, 0, 0, 0, 0); seen = {start}; todo = [start]
    while todo:
        s = todo.pop()
        for a in choices(s):
            n, _ = step(s, a, J, OVH)
            if n not in seen: seen.add(n); todo.append(n)
    return seen

def worst_wait(r, J, OVH, states):
    """Longest pending interval for requester r (cycles from assertion to grant, both counted)."""
    onstack = set()
    @lru_cache(maxsize=None)
    def longest(s):                      # s: state at a cycle start with r already pending
        if s in onstack: raise RuntimeError(f'unbounded wait for r{r} (cycle in pending subgraph)')
        onstack.add(s); best = 0
        for a in choices(s):
            n, g = step(s, a, J, OVH)
            best = max(best, 1 if g == r else 1 + longest(n))
        onstack.discard(s); return best
    worst = 0
    for s in states:                     # r asserts its request in this cycle
        if s[0] >> r & 1 or s[1] == r: continue
        for a in choices(s):
            if not (a >> r & 1): continue
            n, g = step(s, a, J, OVH)
            worst = max(worst, 1 if g == r else 1 + longest(n))
    return worst

_RULE = step
def _fixed_p(state, asserts, J, OVH):          # broken A0: fixed priority r0 > r1 inside P
    return _RULE(state[:5] + (0,) + state[6:], asserts, J, OVH)
def _rr_only_when_both(state, asserts, J, OVH): # broken A0: P pointer moves only when both P were pending
    pend = state[0] | asserts; n, g = _RULE(state, asserts, J, OVH)
    if g in P and not (pend >> P[0] & 1 and pend >> P[1] & 1): n = n[:5] + (state[5],) + n[6:]
    return n, g

def worst_all(J, OVH):
    states = reachable(J, OVH); out = {}
    for r in range(4):
        try: out[r] = worst_wait(r, J, OVH, states)
        except RuntimeError: out[r] = float('inf')
    return len(states), out

def main():
    global EARLY, step
    fails = []
    for OVH in range(0, 5):
        n, w = worst_all(J_MAX, OVH)
        for r in range(4):
            if w[r] > BOUND[r]: fails.append(f'OVH={OVH} r{r} worst {w[r]} > bound {BOUND[r]}')
        print(f'RULE J_MAX={J_MAX} OVH={OVH} states={n} worst wait: P r0={w[0]} r1={w[1]}  Q r2={w[2]} r3={w[3]} '
              f'(bounds P<={BOUND[0]} Q<={BOUND[2]})', flush=True)
    # A0 is load-bearing: both broken round-robin variants must violate the P bound.
    for name, f in (('A0 broken: fixed r0>r1 inside P', _fixed_p), ('A0 broken: P pointer moves only when both pending', _rr_only_when_both)):
        step = f; _, w = worst_all(J_MAX, 4); step = _RULE
        wp = max(w[r] for r in P)
        print(f'{name}: worst P {wp} (bound {BOUND[0]})', flush=True)
        if wp <= BOUND[0]: fails.append(f'{name} did not break the P bound: A0 not shown load-bearing')
    # A1 (one outstanding job per requester) under rule A0: informational, reported, not required to break the bound.
    EARLY = True; _, w = worst_all(J_MAX, 4); EARLY = False
    print(f'A1 off (re-request while own job in flight), rule A0 kept: worst P {max(w[r] for r in P)} Q {max(w[r] for r in Q)} '
          f'(informational: under A0 the bound does not depend on A1)', flush=True)
    for x in fails: print('FAIL', x)
    if fails: print('ARBITER_MODEL: FAIL'); sys.exit(1)
    print('ARBITER_MODEL: PASS')

if __name__ == '__main__': main()
