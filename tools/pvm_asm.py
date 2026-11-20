"""Assemble the PVM v2.1 ISA into a sparse map of 16-bit IMEM words.

Opcodes and operands follow spec/04_ISA.md. Write one instruction per line,
with optional comma separators, labels, and # or // comments. An instruction
can end in `side N [D]`, where either suffix may be omitted and defaults to
zero. Side-set width comes from the image's SIDE_CNT. .org moves the word
address forward, leaving invalid words in the gap. .word emits a raw encoding.
JMP conditions are always, !x, x--, !y, y--, x!=y, pin, and !osre. MOV accepts
~source (invert) and ::source (reverse). PUSH/PULL default to block and accept
the modifiers block/noblock and iffull/ifempty, respectively.
"""

import argparse
import re
from pathlib import Path


IMEM_WORDS = 32

OPCODES = {"jmp": 0, "wait": 1, "in": 2, "out": 3, "push": 4, "pull": 4,
           "mov": 5, "evt": 6, "set": 7}
JMP_CONDS = {"always": 0, "!x": 1, "x--": 2, "!y": 3, "y--": 4, "x!=y": 5,
             "pin": 6, "!osre": 7, "osr_not_empty": 7}
WAIT_SRCS = {"pin": (0, 19), "fab": (1, 3), "flag": (2, 7)}
IN_SRCS = {"pins": 0, "x": 1, "y": 2, "null": 3, "isr": 4, "osr": 5, "fab": 6}
OUT_DSTS = {"pins": 0, "x": 1, "y": 2, "null": 3, "pindirs": 4, "pc": 5,
            "fab": 6, "exec": 7}
MOV_SRCS = {"pins": 0, "x": 1, "y": 2, "null": 3, "status": 4, "isr": 5,
            "osr": 6, "fab": 7}
MOV_DSTS = {"pins": 0, "x": 1, "y": 2, "exec": 3, "pc": 4, "isr": 5,
            "osr": 6, "fab": 7}
SET_DSTS = {"pins": 0, "x": 1, "y": 2, "pindirs": 4, "fab": 6}

LABEL = re.compile(r"([a-z_][a-z_0-9]*):\s*")
DELAY = re.compile(r"\[\s*([^\[\]]+?)\s*\]$")
SIDE = re.compile(r"(?:^|\s)side\s+(\S+)$")


class AsmError(ValueError):
    """An assembly statement could not be encoded."""


def number(token):
    """Parse decimal, hexadecimal, binary or octal literals."""
    try:
        return int(token, 10 if re.fullmatch(r"[+-]?[0-9]+", token) else 0)
    except ValueError as error:
        raise ValueError(f"invalid number {token!r}") from error


def _number_in_range(token, low, high, field, labels=None):
    if labels is not None and token in labels:
        value = labels[token]
    else:
        value = number(token)
    if not low <= value <= high:
        raise ValueError(f"{field} must be in {low}..{high}, got {value}")
    return value


def _named(values, token, field):
    try:
        return values[token]
    except KeyError as error:
        raise ValueError(f"unknown {field} {token!r}") from error


def _operand(op, args, labels):
    if op == "jmp":
        match args:
            case [target]:
                cond = 0
            case [cond_name, target]:
                cond = _named(JMP_CONDS, cond_name, "JMP condition")
            case _:
                raise ValueError("JMP expects a target and an optional condition")
        return (cond << 5) | _number_in_range(target, 0, IMEM_WORDS - 1, "JMP target", labels)

    if op == "wait" and len(args) == 3:
        pol, src, index = args
        pol = _number_in_range(pol, 0, 1, "WAIT polarity")
        source, max_index = _named(WAIT_SRCS, src, "WAIT source")
        return (pol << 7) | (source << 5) | _number_in_range(index, 0, max_index, "WAIT index")

    if op in ("in", "out") and len(args) == 2:
        name, count = args
        field = _named(IN_SRCS if op == "in" else OUT_DSTS, name, f"{op.upper()} operand")
        count = _number_in_range(count, 0, 16, "shift count")
        if op == "out" and name == "exec" and count not in (0, 16):
            raise ValueError("OUT EXEC requires a 16-bit shift count")
        return (field << 5) | (count % 16)

    if op in ("push", "pull"):
        conditional = "iffull" if op == "push" else "ifempty"
        allowed = {"block", "noblock", conditional}
        modifiers = set(args)
        if len(args) != len(modifiers) or modifiers - allowed or {"block", "noblock"} <= modifiers:
            raise ValueError(f"{op.upper()} accepts {conditional} and either block or noblock")
        direction = int(op == "pull")
        conditional_bit = int(conditional in modifiers)
        block = int("noblock" not in modifiers)
        return (direction << 7) | (conditional_bit << 6) | (block << 5)

    if op == "mov" and len(args) == 2:
        dst, src = args
        if src.startswith("~"):
            operation, src = 1, src[1:]
        elif src.startswith("::"):
            operation, src = 2, src[2:]
        else:
            operation = 0
        destination = _named(MOV_DSTS, dst, "MOV destination")
        source = _named(MOV_SRCS, src, "MOV source")
        return (destination << 5) | (operation << 3) | source

    if op == "evt":
        match args:
            case ["done"]:
                return 0xC0
            case ["set", index]:
                return _number_in_range(index, 2, 7, "EVT SET flag")
            case ["clr", index]:
                return 0x40 | _number_in_range(index, 0, 7, "EVT CLR flag")
            case _:
                raise ValueError("EVT expects done, set INDEX, or clr INDEX")

    if op == "set" and len(args) == 2:
        dst, immediate = args
        destination = _named(SET_DSTS, dst, "SET destination")
        return (destination << 5) | _number_in_range(immediate, 0, 31, "SET immediate")

    raise ValueError(f"wrong number of operands for {op.upper()}")


def _instruction(op, rest, labels, side_count):
    opcode = _named(OPCODES, op, "instruction")
    delay_width = 5 - side_count
    delay = 0
    side = 0
    if suffix := DELAY.search(rest):
        delay = _number_in_range(suffix[1], 0, (1 << delay_width) - 1, "delay")
        rest = rest[:suffix.start()].rstrip()
    if suffix := SIDE.search(rest):
        if side_count == 0:
            raise ValueError("side-set suffix requires a nonzero SIDE_CNT")
        side = _number_in_range(suffix[1], 0, (1 << side_count) - 1, "side-set value")
        rest = rest[:suffix.start()].rstrip()
    args = re.split(r"\s*,\s*|\s+", rest) if rest else []
    return (opcode << 13) | (side << (8 + delay_width)) | (delay << 8) | _operand(op, args, labels)


def assemble(source: str, *, side_count: int = 0) -> dict[int, int]:
    """Return PC-to-word encodings. PCs missing from the mapping are invalid."""
    if type(side_count) is not int or not 0 <= side_count <= 2:
        raise AsmError("SIDE_CNT must be 0, 1, or 2")
    labels = {}
    statements = []
    pc = 0
    for lineno, raw in enumerate(source.splitlines(), 1):
        line = re.split(r"#|//", raw, maxsplit=1)[0].strip().lower()
        try:
            while label := LABEL.match(line):
                name = label[1]
                if name in labels:
                    raise ValueError(f"duplicate label {name!r}")
                if pc >= IMEM_WORDS:
                    raise ValueError(f"label {name!r} is outside IMEM")
                labels[name] = pc
                line = line[label.end():]
            if not line:
                continue
            op, *operands = line.split(maxsplit=1)
            rest = operands[0] if operands else ""
            if op == ".org":
                pc = _number_in_range(rest, pc, IMEM_WORDS - 1, ".org word address")
                continue
            if pc >= IMEM_WORDS:
                raise ValueError(f"program exceeds {IMEM_WORDS} IMEM words")
            statements.append((lineno, pc, op, rest))
            pc += 1
        except ValueError as error:
            raise AsmError(f"line {lineno}: {error}") from error

    words = {}
    for lineno, pc, op, rest in statements:
        try:
            if op == ".word":
                words[pc] = _number_in_range(rest, 0, 0xFFFF, ".word encoding", labels)
            else:
                words[pc] = _instruction(op, rest, labels, side_count)
        except ValueError as error:
            raise AsmError(f"line {lineno}: {error}") from error
    return words


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("source", type=Path, help="PVM assembly source")
    parser.add_argument("output", type=Path, help="addressed Verilog readmemh word file")
    parser.add_argument("--side-count", type=number, default=0, help="SIDE_CNT from the target image")
    args = parser.parse_args(argv)
    try:
        words = assemble(args.source.read_text(encoding="utf-8"), side_count=args.side_count)
        hex_words = "".join(f"@{pc:02X} {word:04X}\n" for pc, word in words.items())
        args.output.write_text(hex_words, encoding="utf-8")
    except (OSError, ValueError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
