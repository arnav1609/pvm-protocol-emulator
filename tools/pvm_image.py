"""Build a deterministic, SPI-loadable PVM image from assembly and config.

The optional configuration JSON maps byte addresses to byte values. Write
addresses and values as JSON integers or strings such as "0x0108" and "0x01"
(JSON object keys must be strings). Unset configuration bytes reset to zero,
except ENTRY_PC, WRAP_BOTTOM and WRAP_TOP, which default to the first and last
program addresses. The image contains the ordered CRC-covered writes only.
The loader handles HALT, CLR_IMEM, CRC_EXPECT, VALIDATE, TX preload and ENABLE.
"""

import argparse
import json
from collections.abc import Iterable, Mapping
from pathlib import Path

if __package__:
    from .pvm_asm import IMEM_WORDS, assemble, number
    from .pvm_wire import CONFIG_ADDRESSES, IMAGE_FORMAT, IMAGE_VER, config_write_mask, crc16_ccitt_false
else:
    from pvm_asm import IMEM_WORDS, assemble, number
    from pvm_wire import CONFIG_ADDRESSES, IMAGE_FORMAT, IMAGE_VER, config_write_mask, crc16_ccitt_false


SIDE_CNT = 0x0108
WRAP_BOTTOM = 0x010A
WRAP_TOP = 0x010B
SHIFTCTRL = 0x010C
PULL_THRESH = 0x010D
PUSH_THRESH = 0x010E
ENTRY_PC = 0x010F
PIN_CONFIG = 0x0400
TX_FIFO_DEPTH = 4


def _integer(value, low, high, field):
    if type(value) is not int or not low <= value <= high:
        raise ValueError(f"{field} must be an integer in {low}..{high}, got {value!r}")
    return value


def _validate_config(config, words):
    # Match image validation in spec/07_FAULTS_LIFECYCLE.md.
    for pin in range(20):
        value = config[PIN_CONFIG + pin]
        owner, mode = value & 7, (value >> 3) & 3
        if owner == 7 or mode == 3:
            raise ValueError(f"pin {pin} has an invalid owner or mode")
        if (5 <= pin <= 11 and mode == 2) or (pin < 5 and mode != 0) or (owner and mode == 0):
            raise ValueError(f"pin {pin} has a conflicting owner or mode")

    for addr, name in ((0x0102, "OUT_BASE"), (0x0104, "SET_BASE"), (0x0106, "IN_BASE"),
                       (0x0107, "SIDE_BASE"), (0x0109, "JMP_PIN")):
        _integer(config[addr], 0, 19, name)
    _integer(config[0x0103], 0, 16, "OUT_CNT")
    _integer(config[0x0105], 0, 5, "SET_CNT")
    _integer(config[SIDE_CNT], 0, 2, "SIDE_CNT")
    threshold_max = 16 if config[SHIFTCTRL] & 0x10 else 8
    _integer(config[PULL_THRESH], 0, threshold_max, "PULL_THRESH")
    _integer(config[PUSH_THRESH], 0, threshold_max, "PUSH_THRESH")
    if config[WRAP_BOTTOM] > config[WRAP_TOP]:
        raise ValueError("WRAP_BOTTOM exceeds WRAP_TOP")
    if config[ENTRY_PC] not in words:
        raise ValueError(f"ENTRY_PC {config[ENTRY_PC]} has no assembled word")

    for lut in range(4):
        if config[0x0204 + 8 * lut] & 3 == 3:
            raise ValueError(f"fabric LUT {lut} has an invalid output mode")
    counter_control = config[0x0222]
    if counter_control & 4 and not counter_control & 1:
        raise ValueError("MANCH_EN requires CNT_EN")
    arb_control = config[0x0224]
    if arb_control & 1:
        if arb_control >> 4 == 0:
            raise ValueError("ARB_EN requires nonzero ARB_N")
        for addr, name in ((0x0225, "ARB_SDA"), (0x0226, "ARB_SCL")):
            pin = _integer(config[addr], 12, 19, name)
            if (config[PIN_CONFIG + pin] >> 3) & 3 != 2:
                raise ValueError(f"{name} must name an open-drain pin")

    for rule in range(8):
        guard_byte = config[0x0301 + 4 * rule]
        guard = (guard_byte >> 5) & 3
        action = config[0x0302 + 4 * rule] >> 2
        if guard_byte & 0x80 and (guard == 3 or action == 7):
            raise ValueError(f"monitor rule {rule} has an invalid guard or action")


def build_image(
    words: Mapping[int, int],
    *,
    config: Mapping[int, int] | None = None,
    image_version: int = 1,
    tx_preload: Iterable[int] = (),
) -> dict:
    """Return the JSON-compatible pvm-image-v1 payload for the 32-word build."""
    _integer(image_version, 0, 255, "image version")
    if not words:
        raise ValueError("image requires at least one instruction word")
    for pc, word in words.items():
        _integer(pc, 0, IMEM_WORDS - 1, "IMEM word address")
        _integer(word, 0, 0xFFFF, f"word at PC {pc}")

    # HALT + CLR_IMEM preserves prior configuration, so fill every writable byte.
    first_pc, last_pc = min(words), max(words)
    settings = dict.fromkeys(CONFIG_ADDRESSES, 0)
    settings.update({ENTRY_PC: first_pc, WRAP_BOTTOM: first_pc, WRAP_TOP: last_pc})
    if config is not None:
        for address, value in config.items():
            _integer(address, 0, 0xFFFF, "config address")
            mask = config_write_mask(address)
            if mask == 0:
                raise ValueError(f"0x{address:04X} is not a writable configuration address")
            _integer(value, 0, 255, f"config byte at 0x{address:04X}")
            if value & ~mask:
                raise ValueError(f"config byte at 0x{address:04X} sets reserved bits")
            settings[address] = value
    _validate_config(settings, words)

    preload = list(tx_preload)
    if len(preload) > TX_FIFO_DEPTH:
        raise ValueError(f"TX preload exceeds the {TX_FIFO_DEPTH}-byte FIFO")
    for byte in preload:
        _integer(byte, 0, 255, "TX preload byte")

    writes = []
    for pc in sorted(words):
        word = words[pc]
        writes.extend(([2 * pc, word & 0xFF], [2 * pc + 1, word >> 8]))
    writes.extend([address, settings[address]] for address in CONFIG_ADDRESSES)
    writes.append([IMAGE_VER, image_version])
    return {
        "format": IMAGE_FORMAT,
        "image_version": image_version,
        "crc16": crc16_ccitt_false(value for _, value in writes),
        "writes": writes,
        "tx_preload": preload,
    }


def _config_from_json(path):
    # Decode pairs directly to catch aliases such as "264" and "0x0108".
    def decode(pairs):
        result = {}
        for key, value in pairs:
            address = number(key)
            if address in result:
                raise ValueError(f"duplicate configuration address 0x{address:04X}")
            result[address] = number(value) if isinstance(value, str) else value
        return result

    config = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=decode)
    if not isinstance(config, dict):
        raise ValueError("config JSON must be an address-to-byte object")
    return config


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("source", type=Path, help="PVM assembly source")
    parser.add_argument("output", type=Path, help="pvm-image-v1 JSON output")
    parser.add_argument("--config", type=Path, help="JSON map of configuration byte overrides")
    parser.add_argument("--image-version", type=number, default=1, help="IMAGE_VER byte (default: 1)")
    parser.add_argument("--tx", type=number, action="append", default=[], help="TX preload byte (repeatable)")
    args = parser.parse_args(argv)
    try:
        config = _config_from_json(args.config) if args.config else {}
        words = assemble(args.source.read_text(encoding="utf-8"), side_count=config.get(SIDE_CNT, 0))
        image = build_image(words, config=config, image_version=args.image_version, tx_preload=args.tx)
        args.output.write_text(json.dumps(image, indent=2) + "\n", encoding="utf-8")
    except (OSError, ValueError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
