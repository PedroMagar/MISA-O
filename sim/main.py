# -*- coding: utf-8 -*-
"""
MISA-O v0 — Interactive simulator / debugger
Combines cpu.py (CPU model) with asm.py (assembler) into a cmd.Cmd REPL.

Commands:
  load  <file> [addr]  — load .bin or .asm file at optional byte address
  run   [max]          — run until halt / breakpoint
  step  [n]            — single-step n instructions (default 1)
  regs                 — show register state
  mem   <addr> [len]   — hexdump memory (byte addresses)
  dis   [addr] [n]     — disassemble n instructions (default 10)
  break <addr>         — toggle breakpoint at byte or nibble address
  blist                — list breakpoints
  setreg <reg> <val>   — set a register
  setmem <addr> <val>  — write a byte at addr
  reset                — reset CPU (memory preserved)
  trace [on|off]       — toggle instruction trace
  symbols              — print loaded symbol table
  assemble <file>      — assemble and load (shorthand: asm)
  quit / exit / q      — exit
"""

import cmd
import sys
import os
import struct
import shlex

# Make imports work both as a script and as a module
_DIR = os.path.dirname(os.path.abspath(__file__))
if _DIR not in sys.path:
    sys.path.insert(0, _DIR)

from cpu import MISAO_CPU, disasm_one, W_NAMES
from asm import Assembler, AsmError, assemble_file


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _parse_addr(s: str) -> int:
    """Parse a hex/decimal address. Strips trailing 'h'/'H'."""
    s = s.strip().rstrip('hH')
    return int(s, 16) if s.startswith('0x') or s.startswith('0X') else int(s, 0)


def _fmt_addr(na: int) -> str:
    """Format nibble address with byte address for display."""
    return f'0x{na:04X}(n) / 0x{na >> 1:04X}(b)'


# ─── Debugger ─────────────────────────────────────────────────────────────────

class Debugger(cmd.Cmd):
    intro  = (
        'MISA-O v0 Simulator  --  type "help" for commands\n'
        '  Addresses are byte addresses unless noted otherwise.\n'
    )
    prompt = '(misa-o) '

    def __init__(self):
        super().__init__()
        self.cpu       = MISAO_CPU()
        self.symbols   = {}   # label -> nibble address (from last assemble)
        self.equates   = {}
        self._bps: set = set()  # breakpoints (nibble addresses)

    # ── Internal helpers ──────────────────────────────────────────────────────

    def _load_binary(self, path: str, byte_addr: int = 0):
        with open(path, 'rb') as f:
            data = f.read()
        self.cpu.load(data, byte_addr)
        print(f'Loaded {len(data)} bytes at 0x{byte_addr:04X}  '
              f'(PC -> nibble 0x{self.cpu.pc:04X})')

    def _load_asm(self, path: str, force_addr: int = None):
        try:
            asm = Assembler()
            start, data, syms, eqs = assemble_file(path)
            if force_addr is not None:
                start = force_addr
            self.cpu.load(data, start)
            self.symbols = syms
            self.equates = eqs
            print(f'Assembled {len(data)} bytes -> loaded at 0x{start:04X}  '
                  f'(PC -> nibble 0x{self.cpu.pc:04X})')
            if syms:
                print(f'  {len(syms)} label(s) defined.')
        except AsmError as e:
            print(f'Assembly error:\n{e}')

    def _run_until(self, max_steps: int = 10_000_000):
        """Run until halt, breakpoint, or max_steps."""
        steps = 0
        while not self.cpu._halted and steps < max_steps:
            pc = self.cpu.pc
            if steps > 0 and pc in self._bps:
                print(f'Breakpoint hit at {_fmt_addr(pc)}')
                return steps
            self.cpu.step()
            steps += 1
            if self.cpu._halted:
                print(f'CPU halted after {steps} step(s).  '
                      f'Total cycles: {self.cpu.cycles}')
                return steps
        if steps >= max_steps:
            print(f'Stopped after {steps} step(s) (limit reached).')
        return steps

    # ── Commands ──────────────────────────────────────────────────────────────

    def do_load(self, line: str):
        """load <file> [addr]  — load binary (.bin) or source (.asm) file."""
        parts = line.split()
        if not parts:
            print('Usage: load <file> [byte_addr]')
            return
        path = parts[0]
        addr = int(parts[1], 0) if len(parts) > 1 else 0

        if not os.path.exists(path):
            print(f'File not found: {path}')
            return

        ext = os.path.splitext(path)[1].lower()
        if ext in ('.asm', '.s'):
            self._load_asm(path, addr if len(parts) > 1 else None)
        else:
            self._load_binary(path, addr)

    def do_assemble(self, line: str):
        """assemble <file>  — assemble a source file and load it."""
        parts = line.split()
        if not parts:
            print('Usage: assemble <file>')
            return
        self._load_asm(parts[0])

    # shorthand
    do_asm = do_assemble

    def do_run(self, line: str):
        """run [max_steps]  — run until halt or breakpoint."""
        parts = line.split()
        limit = int(parts[0]) if parts else 10_000_000
        if self.cpu._halted:
            print('CPU is halted.  Use "reset" to restart.')
            return
        self._run_until(limit)

    def do_step(self, line: str):
        """step [n]  — single-step n instructions (default 1)."""
        parts = line.split()
        n = int(parts[0]) if parts else 1
        for i in range(n):
            if self.cpu._halted:
                print('CPU halted.')
                break
            pc = self.cpu.pc
            if i > 0 and pc in self._bps:
                print(f'Breakpoint hit at {_fmt_addr(pc)}')
                break
            self.cpu.step()
        print(self.cpu.dump_regs())

    # shorthand
    do_s = do_step

    def do_regs(self, line: str):
        """regs  — display all registers and flags."""
        print(self.cpu.dump_regs())

    do_r = do_regs

    def do_mem(self, line: str):
        """mem <byte_addr> [length]  — hexdump memory."""
        parts = line.split()
        if not parts:
            print('Usage: mem <byte_addr> [length]')
            return
        try:
            addr = _parse_addr(parts[0])
            length = int(parts[1]) if len(parts) > 1 else 64
        except ValueError as e:
            print(f'Bad address: {e}')
            return
        print(self.cpu.dump_mem(addr, length))

    do_m = do_mem

    def do_dis(self, line: str):
        """dis [byte_addr] [n]  — disassemble n instructions (default 10)."""
        parts = line.split()
        if parts:
            try:
                byte_addr = _parse_addr(parts[0])
                naddr = byte_addr * 2
            except ValueError:
                naddr = self.cpu.pc
        else:
            naddr = self.cpu.pc

        n = int(parts[1]) if len(parts) > 1 else 10
        print(self.cpu.disasm(naddr, n))

    do_d = do_dis

    def do_break(self, line: str):
        """break <byte_addr>  — toggle breakpoint (set if absent, clear if present)."""
        parts = line.split()
        if not parts:
            print('Usage: break <byte_addr>')
            return
        try:
            na = _parse_addr(parts[0]) * 2  # byte -> nibble address
        except ValueError as e:
            print(f'Bad address: {e}')
            return
        if na in self._bps:
            self._bps.discard(na)
            print(f'Breakpoint removed at {_fmt_addr(na)}')
        else:
            self._bps.add(na)
            print(f'Breakpoint set at {_fmt_addr(na)}')

    do_b = do_break

    def do_blist(self, line: str):
        """blist  — list all breakpoints."""
        if not self._bps:
            print('No breakpoints.')
        else:
            print('Breakpoints:')
            for na in sorted(self._bps):
                label = self._label_for(na)
                suffix = f'  <{label}>' if label else ''
                print(f'  {_fmt_addr(na)}{suffix}')

    def do_bdel(self, line: str):
        """bdel <byte_addr>  — delete breakpoint."""
        parts = line.split()
        if not parts:
            self._bps.clear()
            print('All breakpoints cleared.')
            return
        try:
            na = _parse_addr(parts[0]) * 2
        except ValueError as e:
            print(f'Bad address: {e}')
            return
        if na in self._bps:
            self._bps.discard(na)
            print(f'Breakpoint removed at {_fmt_addr(na)}')
        else:
            print(f'No breakpoint at {_fmt_addr(na)}')

    def do_setreg(self, line: str):
        """setreg <reg> <value>  — set a register by name."""
        parts = line.split()
        if len(parts) < 2:
            print('Usage: setreg <reg> <value>')
            print('  Registers: pc acc rs0 rs1 ra0 ra1 cfg ia iar c z n v')
            print('  CSRs: csr0 … csr15')
            return
        reg = parts[0].lower()
        try:
            val = int(parts[1], 0)
        except ValueError:
            print(f'Bad value: {parts[1]}')
            return

        cpu = self.cpu
        reg_map = {
            'pc': lambda v: setattr(cpu, 'pc',  v & 0xFFFF),
            'acc': lambda v: cpu.set_acc(v),
            'rs0': lambda v: setattr(cpu, 'rs0', v & 0xFFFF),
            'rs1': lambda v: setattr(cpu, 'rs1', v & 0xFFFF),
            'ra0': lambda v: setattr(cpu, 'ra0', v & 0xFFFF),
            'ra1': lambda v: setattr(cpu, 'ra1', v & 0xFFFF),
            'cfg': lambda v: setattr(cpu, 'cfg', v & 0xFF),
            'ia':  lambda v: setattr(cpu, 'ia',  v & 0xFF),
            'iar': lambda v: setattr(cpu, 'iar', v & 0xFF),
            'c':   lambda v: setattr(cpu, 'c',   v & 1),
            'z':   lambda v: setattr(cpu, 'z',   v & 1),
            'n':   lambda v: setattr(cpu, 'n',   v & 1),
            'v':   lambda v: setattr(cpu, 'v',   v & 1),
        }
        if reg in reg_map:
            reg_map[reg](val)
            print(f'{reg.upper()} ← 0x{val:X}')
        elif reg.startswith('csr') and reg[3:].isdigit():
            idx = int(reg[3:])
            cpu.csr_w(idx, val)
            print(f'CSR[{idx}] ← 0x{val:04X}')
        else:
            print(f'Unknown register: {reg}')

    def do_setmem(self, line: str):
        """setmem <byte_addr> <byte_value>  — write one byte to memory."""
        parts = line.split()
        if len(parts) < 2:
            print('Usage: setmem <byte_addr> <byte_value>')
            return
        try:
            addr = _parse_addr(parts[0])
            val  = int(parts[1], 0) & 0xFF
        except ValueError as e:
            print(f'Bad argument: {e}')
            return
        self.cpu._wb(addr, val)
        print(f'mem[0x{addr:04X}] ← 0x{val:02X}')

    def do_reset(self, line: str):
        """reset  — reset CPU state (memory is preserved)."""
        mem = self.cpu.mem
        self.cpu.reset()
        self.cpu.mem = mem
        print('CPU reset.')

    def do_trace(self, line: str):
        """trace [on|off]  — toggle or set instruction trace."""
        s = line.strip().lower()
        if s == 'on':
            self.cpu.trace = True
        elif s == 'off':
            self.cpu.trace = False
        else:
            self.cpu.trace = not self.cpu.trace
        print(f'Trace: {"ON" if self.cpu.trace else "OFF"}')

    def do_symbols(self, line: str):
        """symbols  — print symbol table from last assembly."""
        if not self.symbols:
            print('No symbols loaded.')
            return
        print(f'{"Label":<24} {"Nibble addr":>12}  {"Byte addr":>10}')
        print('-' * 52)
        for name, na in sorted(self.symbols.items(), key=lambda kv: kv[1]):
            print(f'  {name:<22} 0x{na:04X}          0x{na >> 1:04X}')
        if self.equates:
            print('\nEquates:')
            for name, val in sorted(self.equates.items()):
                print(f'  {name:<22} {val}')

    do_sym = do_symbols

    def do_info(self, line: str):
        """info  — show CPU summary (registers + next instruction)."""
        print(self.cpu.dump_regs())
        print('\nNext instructions:')
        print(self.cpu.disasm(self.cpu.pc, 3))

    do_i = do_info

    def do_csrs(self, line: str):
        """csrs  — dump all CSR values."""
        cpu = self.cpu
        names = ['CPUID','CORECFG','EVTCTRL','INTADDR','TIMER',
                 'TIMERCMP','CSR6','CSR7','CSR8','CSR9','CSR10',
                 'CSR11','CSR12','CSR13','CSR14','CSR15']
        print('CSR Bank:')
        for i in range(16):
            val  = cpu.csr_r(i)
            name = names[i] if i < len(names) else f'CSR{i}'
            print(f'  [{i:2d}] {name:<10}  0x{val:04X}')

    def do_quit(self, line: str):
        """quit  — exit the debugger."""
        return True

    do_exit = do_quit
    do_q    = do_quit

    # ── Helpers ───────────────────────────────────────────────────────────────

    def _label_for(self, naddr: int):
        """Return the label name for a nibble address, or None."""
        for name, na in self.symbols.items():
            if na == naddr:
                return name
        return None

    def default(self, line: str):
        """Try to resolve line as a symbol or expression and print its value."""
        s = line.strip()
        if s in self.symbols:
            na = self.symbols[s]
            print(f'{s} = nibble 0x{na:04X} / byte 0x{na >> 1:04X}')
        else:
            print(f'Unknown command: {s!r}  (type "help" for commands)')

    def emptyline(self):
        """Repeat last step on empty input."""
        pass

    def do_help(self, line: str):
        if line:
            super().do_help(line)
        else:
            print("""\
Commands:
  load  <file> [addr]   Load binary (.bin) or assembly (.asm/.s) file
  asm   <file>          Assemble and load (alias: assemble)
  run   [max]           Run until halt or breakpoint
  step  [n]             Single-step n instructions  (alias: s)
  regs                  Show registers  (alias: r)
  info                  Registers + next 3 instructions  (alias: i)
  mem   <addr> [len]    Hexdump memory  (alias: m)
  dis   [addr] [n]      Disassemble  (alias: d)
  break <addr>          Toggle breakpoint  (alias: b)
  blist                 List breakpoints
  bdel  [addr]          Delete breakpoint (no addr = clear all)
  setreg <reg> <val>    Set register
  setmem <addr> <val>   Write byte to memory
  reset                 Reset CPU (memory intact)
  trace [on|off]        Toggle instruction trace
  symbols               Print symbol table  (alias: sym)
  csrs                  Dump CSR bank
  quit / q              Exit
""")


# ─── Entry point ──────────────────────────────────────────────────────────────

def main():
    import argparse
    parser = argparse.ArgumentParser(
        description='MISA-O v0 interactive simulator')
    parser.add_argument('file', nargs='?',
                        help='Binary or assembly file to load on startup')
    parser.add_argument('--addr', '-a', type=lambda s: int(s, 0), default=0,
                        metavar='ADDR',
                        help='Load address (byte address, default 0)')
    parser.add_argument('--run', '-r', action='store_true',
                        help='Run immediately after loading')
    parser.add_argument('--trace', action='store_true',
                        help='Enable instruction trace from the start')
    args = parser.parse_args()

    dbg = Debugger()

    if args.trace:
        dbg.cpu.trace = True

    if args.file:
        dbg.do_load(f'{args.file} {args.addr}' if args.addr else args.file)
        if args.run:
            dbg.do_run('')
            return

    try:
        dbg.cmdloop()
    except KeyboardInterrupt:
        print()


if __name__ == '__main__':
    main()
