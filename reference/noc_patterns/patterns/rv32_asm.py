"""rv32_asm.py -- minimal two-pass RV32I assembler for the Lane 1 demo firmware (R-3a; Lane 1, 2026-11-07).

Why: the board demo program (takeover plan R3.2) is ~100 instructions; this avoids the GCC download (decision R-D2 stays
open for C firmware). Scope is deliberately small: RV32I base integer instructions only (no compressed, no M), labels,
a few pseudo-instructions and data directives. Output: one 32-bit word per line ($readmemh, @00000000 header) and an
optional SystemVerilog include (scripts/hex_to_svh.py format).

Syntax: one statement per line; `#` or `//` comments; `label:`; registers x0-x31 or ABI names; immediates decimal,
0x.., or %hi(label)/%lo(label) are NOT supported -- use `li`/`la`.
Instructions: lui auipc jal jalr beq bne blt bge bltu bgeu lb lh lw lbu lhu sb sh sw addi slti sltiu xori ori andi slli
srli srai add sub sll slt sltu xor srl sra or and
Pseudo: nop, li rd,imm32 (always 2 words: lui+addi, so sizes are fixed in pass 1), la rd,label (2 words), mv, j, jr, ret,
beqz, bnez, call label (jal ra)
Directives: .word v[,v..]  .ascii "s" / .asciz "s" (packed little-endian, zero-padded to a word)  .align_to N (pad with
nop to byte address N)  .fill N, v (N words of v)

Usage: python -I scripts/rv32_asm.py <in.S> <out.hex> [<out.svh> NAME]
"""
import re
import sys
from pathlib import Path

ABI = {'zero': 0, 'ra': 1, 'sp': 2, 'gp': 3, 'tp': 4, 't0': 5, 't1': 6, 't2': 7, 's0': 8, 'fp': 8, 's1': 9,
       **{f'a{i}': 10 + i for i in range(8)}, **{f's{i}': 16 + i for i in range(2, 12)}, **{f't{i}': 25 + i for i in range(3, 7)}}
R_OPS = {'add': (0, 0), 'sub': (0, 0x20), 'sll': (1, 0), 'slt': (2, 0), 'sltu': (3, 0), 'xor': (4, 0), 'srl': (5, 0),
         'sra': (5, 0x20), 'or': (6, 0), 'and': (7, 0)}
I_OPS = {'addi': 0, 'slti': 2, 'sltiu': 3, 'xori': 4, 'ori': 6, 'andi': 7}
SH_OPS = {'slli': (1, 0), 'srli': (5, 0), 'srai': (5, 0x20)}
LD_OPS = {'lb': 0, 'lh': 1, 'lw': 2, 'lbu': 4, 'lhu': 5}
ST_OPS = {'sb': 0, 'sh': 1, 'sw': 2}
BR_OPS = {'beq': 0, 'bne': 1, 'blt': 4, 'bge': 5, 'bltu': 6, 'bgeu': 7}


class AsmError(Exception):
    pass


def reg(t):
    t = t.strip().lower()
    if t in ABI: return ABI[t]
    m = re.fullmatch(r'x(\d+)', t)
    if m and int(m.group(1)) < 32: return int(m.group(1))
    raise AsmError(f'bad register {t!r}')


def imm(t, labels=None):
    t = t.strip()
    if labels is not None and t in labels: return labels[t]
    try: return int(t, 0)
    except ValueError: raise AsmError(f'bad immediate {t!r}')


def chk(v, bits, signed=True):
    lo, hi = (-(1 << (bits - 1)), (1 << (bits - 1)) - 1) if signed else (0, (1 << bits) - 1)
    if not lo <= v <= hi: raise AsmError(f'immediate {v} out of {bits}-bit {"signed" if signed else "unsigned"} range')
    return v & ((1 << bits) - 1)


def enc_r(f3, f7, rd, rs1, rs2): return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | 0x33
def enc_i(op, f3, rd, rs1, v): return (chk(v, 12) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op
def enc_s(f3, rs2, rs1, v):
    v = chk(v, 12); return ((v >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((v & 0x1F) << 7) | 0x23
def enc_b(f3, rs1, rs2, off):
    if off & 1: raise AsmError('odd branch offset')
    v = chk(off, 13)
    return (((v >> 12) & 1) << 31) | (((v >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | \
           (((v >> 1) & 0xF) << 8) | (((v >> 11) & 1) << 7) | 0x63
def enc_u(op, rd, v): return (chk(v, 20, signed=False) << 12) | (rd << 7) | op
def enc_j(rd, off):
    if off & 1: raise AsmError('odd jump offset')
    v = chk(off, 21)
    return (((v >> 20) & 1) << 31) | (((v >> 1) & 0x3FF) << 21) | (((v >> 11) & 1) << 20) | (((v >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F


def hi_lo(v):
    v &= 0xFFFFFFFF
    lo = v & 0xFFF
    if lo >= 0x800: lo -= 0x1000
    hi = ((v - lo) >> 12) & 0xFFFFF
    return hi, lo


def mem_operand(t):
    m = re.fullmatch(r'\s*(-?\w+)?\s*\(\s*(\w+)\s*\)\s*', t)
    if not m: raise AsmError(f'bad memory operand {t!r}')
    return int(m.group(1) or '0', 0), reg(m.group(2))


def split_args(rest):
    out, cur, q = [], '', False
    for ch in rest:
        if ch == '"': q = not q
        if ch == ',' and not q: out.append(cur.strip()); cur = ''
        else: cur += ch
    if cur.strip(): out.append(cur.strip())
    return out


def string_words(s, zero):
    data = s.encode('latin-1').decode('unicode_escape').encode('latin-1') + (b'\0' if zero else b'')
    data += b'\0' * (-len(data) % 4)
    return [int.from_bytes(data[i:i + 4], 'little') for i in range(0, len(data), 4)]


def strip_comment(raw):
    """Cut at the first # or // that is outside a double-quoted string."""
    q = False
    for i, ch in enumerate(raw):
        if ch == '"': q = not q
        elif not q and (ch == '#' or raw.startswith('//', i)): return raw[:i]
    return raw


def size_of(op, args):
    if op in ('li', 'la'): return 2
    if op == '.word': return len(args)
    if op in ('.ascii', '.asciz'): return len(string_words(args[0].strip('"'), op == '.asciz'))
    if op == '.fill': return imm(args[0])
    return 1


def assemble(text):
    stmts = []
    for n, raw in enumerate(text.splitlines(), 1):
        line = strip_comment(raw).strip()
        while True:
            m = re.match(r'^([A-Za-z_]\w*):\s*(.*)$', line)
            if not m: break
            stmts.append((n, 'label', [m.group(1)])); line = m.group(2)
        if line:
            op, _, rest = line.partition(' ')
            stmts.append((n, op.lower(), split_args(rest)))
    labels, pc = {}, 0
    for n, op, args in stmts:                     # pass 1: sizes are fixed per statement
        try:
            if op == 'label':
                if args[0] in labels: raise AsmError(f'duplicate label {args[0]}')
                labels[args[0]] = pc
            elif op == '.align_to':
                tgt = imm(args[0])
                if tgt < pc or tgt % 4: raise AsmError(f'.align_to {tgt:#x} behind pc {pc:#x}')
                pc = tgt
            else: pc += 4 * size_of(op, args)
        except AsmError as e: raise AsmError(f'line {n}: {e}')
    words, pc = [], 0
    for n, op, args in stmts:                     # pass 2
        try:
            out = []
            if op == 'label': continue
            if op == '.align_to': out = [0x00000013] * ((imm(args[0]) - pc) // 4)
            elif op == '.word': out = [imm(a, labels) & 0xFFFFFFFF for a in args]
            elif op in ('.ascii', '.asciz'): out = string_words(args[0].strip('"'), op == '.asciz')
            elif op == '.fill': out = [imm(args[1]) & 0xFFFFFFFF] * imm(args[0])
            elif op == 'nop': out = [enc_i(0x13, 0, 0, 0, 0)]
            elif op in ('li', 'la'):
                v = imm(args[1], labels if op == 'la' else None); h, l = hi_lo(v); rd = reg(args[0])
                out = [enc_u(0x37, rd, h), enc_i(0x13, 0, rd, rd, l)]
            elif op == 'mv': out = [enc_i(0x13, 0, reg(args[0]), reg(args[1]), 0)]
            elif op == 'j': out = [enc_j(0, labels[args[0]] - pc)]
            elif op == 'call': out = [enc_j(1, labels[args[0]] - pc)]
            elif op == 'jr': out = [enc_i(0x67, 0, 0, reg(args[0]), 0)]
            elif op == 'ret': out = [enc_i(0x67, 0, 0, 1, 0)]
            elif op in ('beqz', 'bnez'): out = [enc_b(0 if op == 'beqz' else 1, reg(args[0]), 0, labels[args[1]] - pc)]
            elif op == 'lui': out = [enc_u(0x37, reg(args[0]), imm(args[1]))]
            elif op == 'auipc': out = [enc_u(0x17, reg(args[0]), imm(args[1]))]
            elif op == 'jal':
                rd, tgt = (reg(args[0]), args[1]) if len(args) == 2 else (1, args[0])
                out = [enc_j(rd, (labels[tgt] if tgt in labels else imm(tgt)) - (pc if tgt in labels else 0))]
            elif op == 'jalr':
                if len(args) == 2: off, rs1 = mem_operand(args[1])
                else: rs1, off = reg(args[1]), imm(args[2])
                out = [enc_i(0x67, 0, reg(args[0]), rs1, off)]
            elif op in BR_OPS:
                tgt = args[2]; off = labels[tgt] - pc if tgt in labels else imm(tgt)
                out = [enc_b(BR_OPS[op], reg(args[0]), reg(args[1]), off)]
            elif op in LD_OPS: off, rs1 = mem_operand(args[1]); out = [enc_i(0x03, LD_OPS[op], reg(args[0]), rs1, off)]
            elif op in ST_OPS: off, rs1 = mem_operand(args[1]); out = [enc_s(ST_OPS[op], reg(args[0]), rs1, off)]
            elif op in I_OPS: out = [enc_i(0x13, I_OPS[op], reg(args[0]), reg(args[1]), imm(args[2]))]
            elif op in SH_OPS:
                f3, f7 = SH_OPS[op]; sh = chk(imm(args[2]), 5, signed=False)
                out = [(f7 << 25) | (sh << 20) | (reg(args[1]) << 15) | (f3 << 12) | (reg(args[0]) << 7) | 0x13]
            elif op in R_OPS: f3, f7 = R_OPS[op]; out = [enc_r(f3, f7, reg(args[0]), reg(args[1]), reg(args[2]))]
            else: raise AsmError(f'unknown op {op!r}')
            if op not in ('.align_to',) and len(out) != size_of(op, args): raise AsmError('size mismatch (internal)')
        except (AsmError, KeyError) as e: raise AsmError(f'line {n}: {op} {args}: {e}')
        words += out; pc += 4 * len(out)
    return words, labels


def main():
    src, hexo = Path(sys.argv[1]), Path(sys.argv[2])
    words, labels = assemble(src.read_text(encoding='utf-8'))
    hexo.write_text('@00000000\n' + ''.join(f'{w:08X}\n' for w in words), newline='\n')
    if len(sys.argv) > 4:
        import subprocess
        subprocess.run([sys.executable, '-I', str(Path(__file__).with_name('hex_to_svh.py')), str(hexo), sys.argv[3], sys.argv[4]], check=True)
    print(f'{src.name}: {len(words)} words ({4 * len(words)} bytes); labels: ' + ', '.join(f'{k}={v:#x}' for k, v in labels.items()))


if __name__ == '__main__':
    main()
