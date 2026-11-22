"""Core-clock instruction-set model for a committed PVM 32-word image.

See spec/03_BUS_AND_REGMAP.md §3.2 and spec/04_ISA.md, including D-013
through D-015. Start at ENABLE with synchronized inputs at the engine
boundary. The SPI host, fabric, monitor and pad circuitry are outside
this model.
"""

from collections import deque
from dataclasses import dataclass
from enum import IntEnum
from struct import unpack

from .pvm_wire import IMAGE_FORMAT

WORD_MASK = 0xFFFF
FIFO_DEPTH = 4


class State(IntEnum):
    RUN = 3
    DONE = 4
    FAULT = 5


class Fault(IntEnum):
    NONE = 0
    DONE = 1
    TIMEOUT = 2
    ILLEGAL_OP = 3
    INVALID_WORD = 4


@dataclass(frozen=True)
class EngineConfig:
    clkdiv: int
    out_base: int
    out_count: int
    set_base: int
    set_count: int
    in_base: int
    side_base: int
    side_count: int
    jmp_pin: int
    wrap_bottom: int
    wrap_top: int
    shiftctrl: int
    pull_param: int
    push_param: int
    entry_pc: int
    timeout: int
    to_presc: int

    @classmethod
    def from_registers(cls, registers):
        # CLKDIV, 14 single-byte fields, TIMEOUT, TO_PRESC in address order.
        return cls(*unpack("<H14BHB", bytes(registers[addr] for addr in range(0x100, 0x113))))


@dataclass(frozen=True)
class Inputs:
    """The values presented to the engine for one core edge, after CDC."""

    pins: int = 0
    lut: int = 0
    arb_lost: bool = False
    underrun: bool = False


@dataclass
class Effects:
    """Requests generated at this edge. A missing RX byte means no push."""

    tx_pop: bool = False
    rx_byte: int | None = None
    fab_write: bool = False
    clear_arb: bool = False
    clear_underrun: bool = False


@dataclass(frozen=True)
class Completion:
    jump: int | None = None
    inject: int | None = None


COMPLETE = Completion()


class IllegalInstruction(ValueError):
    pass


class Engine:
    """Interpret a validated image from ENABLE, with one step per core edge."""

    def __init__(self, config, words, tx_preload=()):
        self.config = config
        self.words = dict(words)
        self.tx = deque(tx_preload)
        self.rx = deque()
        self.cycle = 0
        self.state = State.RUN
        self.pc = config.entry_pc
        self.x = self.y = self.isr = self.osr = 0
        self.isr_count = 0
        self.osr_count = 16
        self.out_val = self.oe_val = self.fab_ctrl = self.user_flags = 0
        self.fault_code = Fault.NONE
        self.fault_pc = None
        self.delay = 0
        self.stall_count = 0
        self.stalled = False
        self._next_pc = None
        self._injected = None
        self._wide_half = None

        self.divider = max(config.clkdiv, 1)
        self.timeout_period = 16 ** config.to_presc
        self.out_right = bool(config.shiftctrl & 1)
        self.in_right = bool(config.shiftctrl & 2)
        self.auto_pull = bool(config.shiftctrl & 4)
        self.auto_push = bool(config.shiftctrl & 8)
        self.wide = bool(config.shiftctrl & 16)
        self.pull_threshold = config.pull_param or (16 if self.wide else 8)
        self.push_threshold = config.push_param or (16 if self.wide else 8)

    @classmethod
    def from_image(cls, image):
        if image.get("format") != IMAGE_FORMAT:
            raise ValueError("expected a committed pvm-image-v1 image")
        registers = dict(image["writes"])
        words = {
            address // 2: registers[address] << 8 | registers.get(address - 1, 0)
            for address in range(1, 0x40, 2) if address in registers
        }
        return cls(EngineConfig.from_registers(registers), words, image["tx_preload"])

    @property
    def osr_empty(self):
        return self.osr_count >= self.pull_threshold

    def _fault(self, code):
        self.state = State.FAULT
        self.fault_code = code
        self.fault_pc = self.pc

    def step(self, inputs=Inputs()):
        """Advance one core edge and return FIFO, fabric and flag requests."""
        effects = Effects()
        was_stalled = self.stalled
        self.cycle += 1
        if self.state != State.RUN:
            return effects

        if self.cycle % self.divider == 0:
            self._tick(inputs, effects)

        if (self.state == State.RUN and was_stalled and self.stalled and
                self.config.timeout and self.cycle % self.timeout_period == 0):
            self.stall_count += 1
            if self.stall_count >= self.config.timeout:
                self._fault(Fault.TIMEOUT)
        return effects

    def _tick(self, inputs, effects):
        if self.delay:
            self.delay -= 1
            if self.delay == 0 and self._next_pc is not None:
                self.pc = self._next_pc
            return

        word = self._injected if self._injected is not None else self.words.get(self.pc)
        if word is None:
            self._fault(Fault.INVALID_WORD)
            return
        first_issue = not self.stalled and self._wide_half is None
        try:
            outcome = self._execute(word >> 13, word & 0xFF, inputs, effects)
        except IllegalInstruction:
            self._fault(Fault.ILLEGAL_OP)
            return

        delay_bits = 5 - self.config.side_count
        if first_issue and self.config.side_count:
            side_data = word >> (8 + delay_bits)
            self._pins("out_val", self.config.side_base, self.config.side_count, side_data)
        self.stalled = outcome is None and self._wide_half is None
        if outcome is None:
            return

        self.stall_count = 0
        self._injected = outcome.inject
        self.delay = (word >> 8) & ((1 << delay_bits) - 1)
        if self.state != State.RUN or outcome.inject is not None:
            self._next_pc = None
            return
        following = self.config.wrap_bottom if self.pc == self.config.wrap_top else (self.pc + 1) % 32
        self._next_pc = following if outcome.jump is None else outcome.jump
        if not self.delay:
            self.pc = self._next_pc

    def _pins(self, register, base, count, value):
        # Spec 03 §3.2 bases and consecutive pin indices wrap modulo 20.
        previous = getattr(self, register)
        for offset in range(count):
            bit = 1 << ((base + offset) % 20)
            if value & (1 << offset):
                previous |= bit
            else:
                previous &= ~bit
        setattr(self, register, previous)

    def _pin_word(self, pins):
        return sum(((pins >> ((self.config.in_base + k) % 20)) & 1) << k for k in range(16))

    def _flags(self, inputs):
        return self.user_flags | (int(inputs.underrun) << 1) | int(inputs.arb_lost)

    def _execute(self, opcode, operand, inputs, effects):
        selector, low = divmod(operand, 32)
        if opcode == 0:  # JMP
            return self._jump(selector, low, inputs.pins)
        if opcode == 1:  # WAIT
            return self._wait(operand, inputs)
        if opcode in (2, 3):  # IN, OUT
            count = low or 16
            if count > 16:
                raise IllegalInstruction()
            if opcode == 2:
                return self._shift_in(selector, count, inputs, effects)
            return self._shift_out(selector, count, effects)
        if opcode == 4:  # PUSH / PULL
            return self._fifo(operand, effects)
        if opcode == 5:  # MOV
            return self._move(selector, operand, inputs, effects)
        if opcode == 6:  # EVT
            return self._event(operand, effects)
        return self._set(selector, low, effects)

    def _jump(self, cond, address, pins):
        taken = (True, self.x == 0, self.x != 0, self.y == 0, self.y != 0,
                 self.x != self.y, bool(pins & (1 << self.config.jmp_pin)), not self.osr_empty)[cond]
        if cond == 2:
            self.x = (self.x - 1) & WORD_MASK
        if cond == 4:
            self.y = (self.y - 1) & WORD_MASK
        return Completion(jump=address) if taken else COMPLETE

    def _wait(self, operand, inputs):
        polarity = operand >> 7
        source = (operand >> 5) & 3
        index = operand & 31
        if source == 3 or index >= (20, 4, 8)[source]:
            raise IllegalInstruction()
        value = (inputs.pins, inputs.lut, self._flags(inputs))[source]
        return COMPLETE if (value >> index) & 1 == polarity else None

    def _shift_in(self, selector, count, inputs, effects):
        if selector == 7:
            raise IllegalInstruction()
        sources = (self._pin_word(inputs.pins), self.x, self.y, 0, self.isr, self.osr, inputs.lut)
        bits = sources[selector] & ((1 << count) - 1)
        if self.in_right:
            value = (self.isr >> count) | (bits << (16 - count))
        else:
            value = ((self.isr << count) | bits) & WORD_MASK
        new_count = min(self.isr_count + count, 16)
        if self.auto_push and new_count >= self.push_threshold:
            if not self._push(value, effects):
                return None
        else:
            self.isr, self.isr_count = value, new_count
        return COMPLETE

    def _shift_out(self, selector, count, effects):
        if selector == 7 and (count != 16 or self._injected is not None):
            raise IllegalInstruction()
        if self.auto_pull and self.osr_empty and not self._pull(effects):
            return None
        if self.out_right:
            value = self.osr & ((1 << count) - 1)
            self.osr >>= count
        else:
            value = self.osr >> (16 - count)
            self.osr = (self.osr << count) & WORD_MASK
        self.osr_count = min(self.osr_count + count, 31)
        pin_count = min(count, self.config.out_count)
        if selector == 0:
            self._pins("out_val", self.config.out_base, pin_count, value)
        elif selector == 4:
            self._pins("oe_val", self.config.out_base, pin_count, value)
        elif selector == 5:
            return Completion(jump=value & 31)
        elif selector == 6:
            self._fabric(value, effects)
        elif selector == 7:
            return Completion(inject=value)
        else:
            self._scratch(selector, value)
        return COMPLETE

    def _fifo(self, operand, effects):
        if operand & 31:
            raise IllegalInstruction()
        pull, conditional, block = (bool(operand & bit) for bit in (128, 64, 32))
        if pull:
            if conditional and not self.osr_empty:
                return COMPLETE
            if self._pull(effects):
                return COMPLETE
            if block or self.wide:
                return None
            self.osr, self.osr_count = self.x, 0
        else:
            if conditional and self.isr_count < self.push_threshold:
                return COMPLETE
            if self._push(self.isr, effects):
                return COMPLETE
            if block or self.wide:
                return None
            self.isr = self.isr_count = 0
        return COMPLETE

    def _pull(self, effects):
        if self._wide_half is not None:
            self.osr = self._wide_half | self.tx.popleft() << 8
            self._wide_half = None
        else:
            if len(self.tx) < (2 if self.wide else 1):
                return False
            byte = self.tx.popleft()
            if self.wide:
                self._wide_half = byte
                effects.tx_pop = True
                return False
            self.osr = byte if self.out_right else byte << 8
        effects.tx_pop = True
        self.osr_count = 0
        return True

    def _push(self, value, effects):
        if self._wide_half is not None:
            byte = self._wide_half
            self._wide_half = None
        else:
            if FIFO_DEPTH - len(self.rx) < (2 if self.wide else 1):
                return False
            byte = value & 0xFF
            if self.wide:
                self._wide_half = value >> 8
                self.rx.append(byte)
                effects.rx_byte = byte
                return False
        self.rx.append(byte)
        effects.rx_byte = byte
        self.isr = self.isr_count = 0
        return True

    def _move(self, selector, operand, inputs, effects):
        operation = (operand >> 3) & 3
        if operation == 3 or (selector == 3 and self._injected is not None):
            raise IllegalInstruction()
        status = (int(not self.tx) << 2) | (int(len(self.rx) == FIFO_DEPTH) << 1) | int(self.osr_empty)
        sources = (self._pin_word(inputs.pins), self.x, self.y, 0, status, self.isr, self.osr, inputs.lut)
        value = sources[operand & 7]
        if operation == 1:
            value ^= WORD_MASK
        elif operation == 2:
            value = int(f"{value:016b}"[::-1], 2)

        if selector == 0:
            self._pins("out_val", self.config.out_base, self.config.out_count, value)
        elif selector == 3:
            return Completion(inject=value)
        elif selector == 4:
            return Completion(jump=value & 31)
        elif selector == 5:
            self.isr, self.isr_count = value, 0
        elif selector == 6:
            self.osr, self.osr_count = value, 0
        elif selector == 7:
            self._fabric(value, effects)
        else:
            self._scratch(selector, value)
        return COMPLETE

    def _set(self, selector, value, effects):
        if selector in (3, 5, 7):
            raise IllegalInstruction()
        if selector in (0, 4):
            dest = "out_val" if selector == 0 else "oe_val"
            self._pins(dest, self.config.set_base, self.config.set_count, value)
        elif selector == 6:
            self._fabric(value, effects)
        else:
            self._scratch(selector, value)
        return COMPLETE

    def _fabric(self, value, effects):
        self.fab_ctrl = value & 15
        effects.fab_write = True

    def _scratch(self, selector, value):
        if selector == 1:
            self.x = value
        elif selector == 2:
            self.y = value

    def _event(self, operand, effects):
        kind, index = operand >> 6, operand & 7
        if operand & 0x38 or kind == 2 or (kind == 0 and index < 2):
            raise IllegalInstruction()
        if kind == 0:
            self.user_flags |= 1 << index
        elif kind == 1:
            effects.clear_arb = index == 0
            effects.clear_underrun = index == 1
            self.user_flags &= ~(1 << index)
        else:
            self.state = State.DONE
            self.fault_code = Fault.DONE
            self.fault_pc = self.pc
        return COMPLETE
