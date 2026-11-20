"""Byte-level image rules shared by the desktop builder and RP2350 host."""

IMAGE_FORMAT = "pvm-image-v1"
IMAGE_VER = 0x0F0A

# 03_BUS_AND_REGMAP.md, sections 3.2 through 3.5.
_ENGINE_MASKS = (
    0xFF, 0xFF, 0x1F, 0x1F, 0x1F, 0x07, 0x1F, 0x1F,
    0x03, 0x1F, 0x1F, 0x1F, 0x1F, 0x1F, 0x1F, 0x1F,
    0xFF, 0xFF, 0x03,
)
_LUT_MASKS = (0xFF, 0xFF, 0xFF, 0xFF, 0x07, 0, 0, 0)
_FABRIC_MASKS = (0xFF, 0x03, 0x07, 0, 0xF1, 0x1F, 0x1F)
_RULE_MASKS = (0xFF, 0xFF, 0x1F, 0)


def config_write_mask(address):
    """Writable bits of a configuration byte, or zero for an unmapped byte."""
    bank, offset = divmod(address, 256)
    if bank == 1 and offset < len(_ENGINE_MASKS):
        return _ENGINE_MASKS[offset]
    if bank == 2:
        if offset < 0x20:
            return _LUT_MASKS[offset % 8]
        if offset < 0x20 + len(_FABRIC_MASKS):
            return _FABRIC_MASKS[offset - 0x20]
    if bank == 3:
        if offset < 0x20:
            return _RULE_MASKS[offset % 4]
        if offset < 0x2A:
            return 0xFF
        if offset == 0x2A:
            return 0x07
    if bank == 4 and offset < 20:
        return 0x7F
    return 0


CONFIG_ADDRESSES = tuple(
    address for address in range(0x0100, 0x0414) if config_write_mask(address)
)


def crc16_ccitt_false(data):
    """CRC-16/CCITT-FALSE over the ordered data bytes."""
    crc = 0xFFFF
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc
