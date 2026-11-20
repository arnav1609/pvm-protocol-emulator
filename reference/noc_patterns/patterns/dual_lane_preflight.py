"""Check active HDL declarations in an explicit compile list before tool launch."""
from pathlib import Path
import re
from dual_lane_verify import InvalidEvidence


class PreflightFailure(InvalidEvidence):
    pass


def source_names(root, job):
    root = Path(root).resolve()
    macros = {d.split('=', 1)[0] for d in job.get('defines', [])}
    if job['kind'] in ('ooc', 'implementation'):
        macros.add('SYNTHESIS')
    names, inputs, active_files = {}, {}, []
    include_dirs = [(root / d).resolve() for d in job.get('include_dirs', [])]

    def scan(path, nesting=()):
        path = path.resolve()
        if not path.is_relative_to(root) or not path.is_file():
            raise PreflightFailure(f'missing/outside HDL source: {path}')
        if path in nesting:
            raise PreflightFailure(f'recursive include: {path}')
        active_files.append(str(path))
        # Strip comments while retaining strings for include operands. Strings
        # are blanked later when searching declarations.
        token = r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/'
        text = re.sub(token, lambda m: m[0] if m[0].startswith('"') else
                      ''.join('\n' if c == '\n' else ' ' for c in m[0]),
                      path.read_text(encoding='utf-8-sig'))
        stack, active, body = [], True, []
        for number, line in enumerate(text.splitlines(), 1):
            match = re.match(r'\s*`(ifdef|ifndef|elsif|else|endif|define|undef|include)\b(.*)', line)
            if match:
                directive, operand = match.groups(); operand = operand.strip()
                word = operand.split()[0] if operand else ''
                if directive in ('ifdef', 'ifndef'):
                    condition = word in macros
                    if directive == 'ifndef': condition = not condition
                    stack.append([active, condition, False]); active = active and condition
                elif directive in ('elsif', 'else'):
                    if not stack or stack[-1][2]:
                        raise PreflightFailure(f'malformed conditional {path}:{number}')
                    frame = stack[-1]
                    condition = not frame[1] and (directive == 'else' or word in macros)
                    active = frame[0] and condition; frame[1] |= condition
                    if directive == 'else': frame[2] = True
                elif directive == 'endif':
                    if not stack: raise PreflightFailure(f'unmatched endif {path}:{number}')
                    active = stack.pop()[0]
                elif active and directive == 'define': macros.add(word.split('(')[0])
                elif active and directive == 'undef': macros.discard(word)
                elif active and directive == 'include':
                    inc = re.fullmatch(r'"([^"\r\n]+)"', operand)
                    if not inc: raise PreflightFailure(f'unsupported include {path}:{number}')
                    choices = [path.parent / inc[1]] + [d / inc[1] for d in include_dirs]
                    found = next((p for p in choices if p.is_file()), None)
                    if found is None: raise PreflightFailure(f'missing include {path}:{number}')
                    scan(found, nesting + (path,))
                continue
            if active: body.append((number, re.sub(r'"(?:\\.|[^"\\])*"', ' ', line)))
        if stack: raise PreflightFailure(f'unterminated conditional {path}')
        for number, line in body:
            for match in re.finditer(r'\b(module|macromodule|package)\s+(?:(?:automatic|static)\s+)?([A-Za-z_$][\w$]*|\\\S+)', line):
                kind, name = match.groups(); kind = 'module' if kind == 'macromodule' else kind
                key = kind + ':' + name
                location = f'{path.relative_to(root).as_posix()}:{number}'
                if key in names:
                    raise PreflightFailure(f'duplicate {key}: {names[key]} and {location}')
                names[key] = location

    for rel in job.get('sources', []):
        path = (root / rel).resolve()
        if path.suffix.lower() not in ('.sv', '.v'): continue
        key = str(path).lower()
        if key in inputs: raise PreflightFailure(f'duplicate source file: {rel}')
        inputs[key] = rel; scan(path)
    if job['kind'] in ('simulation', 'ooc', 'implementation') and 'module:' + job['top'] not in names:
        raise PreflightFailure(f'selected top not declared: {job["top"]}')
    return dict(state='PASS', declarations=names, scanned_files=active_files,
                defines=job.get('defines', []), scope='active named module/package declarations')


# D-SYN-2 lint (Kalash 2026-10-20): a part-select WRITE whose index uses a runtime signal synthesizes to per-position
# comparator/priority chains (pq_measurement: ~113k LUTs). B-1 extension (Kalash 2026-10-20): checked in EVERY statement
# (always_ff/always_comb/always/assign), not only inside for-loops. Allowed index terms: variables of an enclosing
# for/genvar loop, ALL-CAPS constants, numbers, casts. Applied to every rtl/dual_lane/*.sv by the preflight.
import re as _re
import hashlib, json
_LHS = _re.compile(r'\b(\w+)\s*\[([^\[\]]*?)\+:\s*[^\]]+\]\s*(<=|=)(?!=)')
_ALLOWED = {'int', 'unsigned', 'signed', 'logic', 'bit'}
def lint_runtime_offset_writes(paths):
    findings = []
    for path in paths:
        text = Path(path).read_text(encoding='utf-8', errors='replace')
        text = _re.sub(r'//[^\n]*', '', _re.sub(r'/\*.*?\*/', '', text, flags=_re.S))
        lines = text.split('\n'); stack = []   # (loop vars, nesting depth at loop start, single-statement)
        # B-1: join a line whose '[' is not closed with its continuation lines (multi-line LHS such as kmac_128.sv:194);
        # the joined text is reported at the first line and the continuation lines are blanked (numbering unchanged).
        for k in range(len(lines)):
            j = k
            while lines[k].count('[') > lines[k].count(']') and j + 1 < len(lines):
                j += 1; lines[k] += ' ' + lines[j]; lines[j] = ''
        depth = 0
        for n, line in enumerate(lines, 1):
            m = _re.search(r'\bfor\s*\(\s*(?:int|integer|genvar)?\s*(\w+)\s*=', line)
            loop_vars = {v for s in stack for v in s[0]}
            scope = loop_vars | ({m.group(1)} if m else set())
            for lm in _LHS.finditer(line[m.end():] if m else line):
                idx = _re.sub(r"\d*'[sS]?[bBoOdDhH][0-9a-fA-FxXzZ_]+", '0', _re.sub(r"\w+'\(", '(', lm.group(2)))
                ids = set(_re.findall(r"[A-Za-z_]\w*", idx))
                bad = [i for i in ids if i not in scope and not i.isupper() and i not in _ALLOWED]
                where = 'in for-loop' if scope else 'outside loops'
                if bad: findings.append(f'{Path(path).as_posix()}:{n}: runtime-offset part-select write ({where}) {lm.group(1)}[{lm.group(2).strip()}+:] uses {sorted(bad)}')
            opens = len(_re.findall(r'\bbegin\b', line)); closes = len(_re.findall(r'\bend\b', line))
            if m:
                single = not _re.search(r'\bbegin\b', line[m.end():])
                stack.append(({m.group(1)}, depth, single))
            depth += opens - closes
            while stack and ((not stack[-1][2] and depth <= stack[-1][1]) or (stack[-1][2] and not (m and stack[-1][0] == {m.group(1)}) and line.strip().endswith(';'))):
                stack.pop()
    return findings


# S1 rule (2026-10-21, P7 hang root cause): an always_comb that WRITES a valid/flit signal and READS a ready signal can
# oscillate in zero time against the consumer's own combinational ready (default-then-override assignments produce
# transient values). Valid/ready paths must be continuous single assignments. Findings use the line of `always_comb`.
import re as _re
_VALID = _re.compile(r'(valid|_rv|_nv|_iv|_ov|flit|_rf|_nf)$'); _READY = _re.compile(r'(ready|_rr|_nr|_ir|_or)$')
def lint_valid_ready_comb(paths):
    out = []
    for path in paths:
        raw = Path(path).read_text(encoding='utf-8', errors='replace')
        t = _re.sub(r'//[^\n]*', lambda m: ' ' * len(m.group(0)), raw)
        for m in _re.finditer(r'\balways_comb\s+begin', t):
            i = m.end(); d = 1; body = None
            for tok in _re.finditer(r'\b(begin|end)\b', t[i:]):
                d += 1 if tok.group(1) == 'begin' else -1
                if d == 0: body = t[i:i + tok.start()]; break
            if body is None: continue
            lhs = set(_re.findall(r'\b([A-Za-z_]\w*)(?:\[[^\]]*\])*(?:\.\w+)?\s*=(?!=)', body))
            ids = set(_re.findall(r'\b[A-Za-z_]\w*\b', body))
            w = sorted(x for x in lhs if _VALID.search(x)); r = sorted(x for x in ids - lhs if _READY.search(x))
            if w and r:
                line = t[:m.start()].count('\n') + 1
                out.append(f'{Path(path).as_posix()}:{line}: always_comb writes {w[:3]} and reads {r[:3]} (valid/ready combinational feedback)')
    return out

# S1 bench rule (2026-10-22, reports/S1_NOTES_20261021.md sec. 6): XSim 2024.1 leaves a later declarator X (or wrong) when a
# chained automatic declaration has an initializer with a cast, e.g. `automatic coord_t s = f(e_t'(a)), d = f(e_t'(b));`
# (measured: d = x). Locals of that kind are set by statements. Findings use the line of the declaration.
def lint_chained_cast_init(paths):
    out = []
    for path in paths:
        raw = Path(path).read_text(encoding='utf-8', errors='replace')
        t = _re.sub(r'//[^\n]*', lambda m: ' ' * len(m.group(0)), raw)
        for m in _re.finditer(r'\bautomatic\b([^;]*);', t):
            depth = 0; parts = ['']
            for ch in m.group(1):
                if ch in '([{': depth += 1
                elif ch in ')]}': depth -= 1
                if ch == ',' and depth == 0: parts.append('')
                else: parts[-1] += ch
            inits = [p for p in parts if _re.search(r'(?<![=!<>])=(?!=)', p)]
            if len(inits) >= 2 and any(_re.search(r"\w'\(", p) for p in parts):
                out.append(f"{Path(path).as_posix()}:{t[:m.start()].count(chr(10)) + 1}: chained automatic declaration with a cast initializer")
    return out

# B-1 waivers (Kalash 2026-10-20: no RTL change before the area decision). A finding passes only if a waiver names its
# path and line AND the SHA-256 of that source line still matches; a stale or unused waiver fails the preflight.
def lint_with_waivers(paths, waiver_file):
    waivers = json.loads(Path(waiver_file).read_text(encoding='utf-8'))['waivers'] if Path(waiver_file).is_file() else []
    root = Path(waiver_file).resolve().parents[1]   # waiver paths are repo-relative (scripts/ is one level down)
    same = lambda a, b: (root / a).resolve() == Path(b).resolve()
    findings = lint_runtime_offset_writes(paths) + lint_valid_ready_comb(paths); unwaived = []; used = set()
    for f in findings:
        loc = f.split(': ', 1)[0]; path, line = loc.rsplit(':', 1)
        src = Path(path).read_text(encoding='utf-8', errors='replace').splitlines()[int(line) - 1].strip()
        h = hashlib.sha256(src.encode()).hexdigest()
        w = [i for i, x in enumerate(waivers) if same(x['path'], path) and int(x['line']) == int(line) and x['line_sha256'] == h]
        if w: used.add(w[0])
        else: unwaived.append(f)
    stale = [f"stale or unused waiver {x['path']}:{x['line']}" for i, x in enumerate(waivers)
             if i not in used and any(same(x['path'], p) for p in paths)]
    return unwaived + stale
