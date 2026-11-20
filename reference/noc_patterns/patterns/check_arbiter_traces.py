"""Job arbiter_traces_check: regenerate the arbiter traces from scripts/arbiter_model.py and compare them with the committed
sim/dual_lane/arbiter/arb_trace*.mem. Prints ARB_TRACES_CHECK: PASS or exits non-zero."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_arbiter_traces as G
if __name__ == '__main__':
    sys.argv = [sys.argv[0], '--check']; G.main()
