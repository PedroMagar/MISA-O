# -*- coding: utf-8 -*-
"""
MISA-O v0 -- Terminal UI
Type assembly instructions at the prompt; changed register nibbles are highlighted.

Usage:
    python3 sim/tui.py [file] [--addr N]
"""

import sys
import os
from collections import deque

try:
    import readline
except ImportError:
    pass

_DIR = os.path.dirname(os.path.abspath(__file__))
if _DIR not in sys.path:
    sys.path.insert(0, _DIR)

from cpu import MISAO_CPU, disasm_one, W_NAMES
from asm import Assembler, AsmError, assemble_file

# ─── ANSI ─────────────────────────────────────────────────────────────────────

def _enable_ansi():
    if sys.platform == 'win32':
        try:
            import ctypes
            ctypes.windll.kernel32.SetConsoleMode(
                ctypes.windll.kernel32.GetStdHandle(-11), 7)
        except Exception:
            pass

REV = '\033[7m'
DIM = '\033[2m'
RST = '\033[0m'
CLR = '\033[2J\033[H'

S_NORM = 0
S_CHG  = 1   # reverse video -- nibble changed since last command
S_DIM  = 2   # dim           -- inactive ACC nibble (outside W width)


# ─── Segment renderer ─────────────────────────────────────────────────────────
# Visual width of a rendered string = sum(len(text) for text, _ in segments).
# ANSI codes are zero-width.

def _rend(segs):
    out = []; cur = S_NORM
    for text, sty in segs:
        if sty != cur:
            if cur != S_NORM: out.append(RST)
            if   sty == S_CHG: out.append(REV)
            elif sty == S_DIM: out.append(DIM)
            cur = sty
        out.append(text)
    if cur != S_NORM:
        out.append(RST)
    return ''.join(out)


def _bits(n):
    """'b b b b' -- 7 visual chars for one nibble."""
    return ' '.join(str((n >> (3 - i)) & 1) for i in range(4))


def _nibsegs(reg, val, n_nib, changed, first_dim=None):
    """
    Segments for n_nib nibbles of val, MSN first.
    Nibbles at index >= first_dim are dimmed (if first_dim is not None).
    Nibble index: 0 = bits[3:0], n_nib-1 = MSN.
    """
    segs = []
    for idx in range(n_nib - 1, -1, -1):
        nib = (val >> (4 * idx)) & 0xF
        chg = (reg, idx) in changed
        dim = (first_dim is not None) and (idx >= first_dim) and not chg
        sty = S_CHG if chg else (S_DIM if dim else S_NORM)
        if idx < n_nib - 1:
            segs.append(('   ', S_NORM))   # 3-space separator between nibble groups
        segs.append((_bits(nib), sty))     # 7 chars per nibble
    return segs


# ─── Cell builders ────────────────────────────────────────────────────────────
#
# Top section column widths (chars, visual):
#   col1  25 : label:>3  ' | ' content_17 ' |'   (8-bit)
#   col2  48 : label:>6  ' | ' content_37 ' |'   (16-bit)
#   col3  47 : label:>5  ' | ' content_37 ' |'   (16-bit)
#
# Bottom section:
#   col1  45 : label:>3  ' | ' content_37 ' |'   (16-bit)
#   col2  46 : special ACC / flags block
#   col3  47 : label:>5  ' | ' content_37 ' |'   (16-bit)  [same as top col3]

def _c8(lbl, reg, val, chg):
    """25-char 8-bit cell."""
    s = _rend(_nibsegs(reg, val, 2, chg))
    return f'{lbl:>3} | {s} |'

def _c16(lbl, reg, val, chg, lw=5, dim=None):
    """(lw+42)-char 16-bit cell."""
    s = _rend(_nibsegs(reg, val, 4, chg, dim))
    return f'{lbl:>{lw}} | {s} |'


# Borders
_B8    = '    |-------------------|'           # 25
_BT2   = '       |' + '-' * 39 + '|'          # 48  top col2
_BT3   = '      |'  + '-' * 39 + '|'          # 47  top col3
_BB1   = '    |'    + '-' * 39 + '|'          # 45  bot col1
_BB2   = '     |'   + '-' * 39 + '|'          # 46  bot col2
_BB3   = '      |'  + '-' * 39 + '|'          # 47  bot col3

_BLK8  = ' ' * 25
_BLKT2 = ' ' * 48
_BLKT3 = ' ' * 47
_BLKB2 = ' ' * 46
_BLKB3 = ' ' * 47

# ─── ACC / flags cells ────────────────────────────────────────────────────────

# r3/r2/r1/r0 label row for the ACC box  (46 chars)
_ACC_HDR = '     |--- r3 ------ r2 ------ r1 ------ r0 --|'

def _flags_row(snap, chg):
    """46-char flags row:  '     | C: x    | Z: x    | N: x    | V: x    |'"""
    segs = [('     |', S_NORM)]
    for name, key in [('C', 'c'), ('Z', 'z'), ('N', 'n'), ('V', 'v')]:
        hl  = (key, 0) in chg
        segs += [(' ',                S_NORM),
                 (f'{name}: {snap[key]}', S_CHG if hl else S_NORM),
                 ('    ',             S_NORM),
                 ('|',               S_NORM)]
    return _rend(segs)   # visual: 6 + 4*10 = 46


def _acc_row(snap, chg, w_mode):
    """46-char ACC row:  ' ACC | b b b b | b b b b | b b b b | b b b b |'"""
    active = {0: 1, 1: 2}.get(w_mode, 4)   # nibble indices 0..(active-1) are live
    val = snap['acc']
    segs = [(' ACC |', S_NORM)]
    for i, idx in enumerate([3, 2, 1, 0]):   # display r3 .. r0
        nib = (val >> (4 * idx)) & 0xF
        chg_flag = ('acc', idx) in chg
        dim_flag = (idx >= active) and not chg_flag
        sty = S_CHG if chg_flag else (S_DIM if dim_flag else S_NORM)
        segs += [(' ', S_NORM), (_bits(nib), sty), (' ', S_NORM)]
        if i < 3:
            segs.append(('|', S_NORM))
    segs.append(('|', S_NORM))
    return _rend(segs)   # visual: 6 + 4*(1+7+1) + 3*1 + 1 = 46


# ─── Snapshot & diff ──────────────────────────────────────────────────────────

def _snap(cpu):
    return {
        'cfg':  cpu.cfg,       'ia':   cpu.ia,       'iar':  cpu.iar,
        'gpr1': cpu.csrs[2],   'gpr2': cpu.csrs[3],  'gpr3': cpu.csrs[4],
        'pc':   cpu.pc,        'addr': cpu.ra0,       'mem':  cpu._rw(cpu.ra0),
        'rs0':  cpu.rs0,       'rs1':  cpu.rs1,       'acc':  cpu.acc,
        'ra1':  cpu.ra1,       'ra0':  cpu.ra0,
        'c': cpu.c, 'z': cpu.z, 'n': cpu.n, 'v': cpu.v,
    }

def _diff(before, after):
    changed = set()
    widths = {
        'cfg':2, 'ia':2, 'iar':2,
        'gpr1':4, 'gpr2':4, 'gpr3':4,
        'pc':4, 'addr':4, 'mem':4,
        'rs0':4, 'rs1':4, 'acc':4, 'ra1':4, 'ra0':4,
    }
    for reg, w in widths.items():
        bv = before.get(reg, 0); av = after.get(reg, 0)
        if bv != av:
            for i in range(w):
                if ((bv >> (4*i)) & 0xF) != ((av >> (4*i)) & 0xF):
                    changed.add((reg, i))
    for f in ('c', 'z', 'n', 'v'):
        if before.get(f) != after.get(f):
            changed.add((f, 0))
    return changed


# ─── Display builder ──────────────────────────────────────────────────────────

def _build_display(cpu, snap, chg):
    w = cpu.W
    R = []   # lines

    # ── Top section (9 lines) ──────────────────────────────────────────────────
    #
    #     |-------------------|                                         <- row 0: CFG top
    # CFG | b b b b   b b b b |                                        <- row 1: CFG data
    #     |---|       |---|       |---|                                 <- row 2: shared sep
    #                     GPR1 | ... |   PC | ... |                    <- row 3
    #     |---|       |---|       |---|                                 <- row 4
    #  IA | ... |     GPR2 | ... | ADDR | ... |                        <- row 5
    #     |---|       |---|       |---|                                 <- row 6
    # IAR | ... |     GPR3 | ... |  MEM | ... |                        <- row 7
    #     |---|       |---|       |---|                                 <- row 8

    R.append(_B8)
    R.append(_c8('CFG', 'cfg', snap['cfg'], chg))
    R.append(_B8  + _BT2 + _BT3)
    R.append(_BLK8 +
             _c16('GPR1','gpr1',snap['gpr1'],chg,6) +
             _c16('PC',  'pc',  snap['pc'],  chg,5))
    R.append(_B8  + _BT2 + _BT3)
    R.append(_c8(' IA', 'ia', snap['ia'], chg) +
             _c16('GPR2','gpr2',snap['gpr2'],chg,6) +
             _c16('ADDR','addr',snap['addr'],chg,5))
    R.append(_B8  + _BT2 + _BT3)
    R.append(_c8('IAR', 'iar', snap['iar'], chg) +
             _c16('GPR3','gpr3',snap['gpr3'],chg,6) +
             _c16(' I/O','mem', snap['mem'], chg,5))
    R.append(_B8  + _BT2 + _BT3)

    R.append('')   # blank line between sections

    # ── Bottom section (5 lines) ───────────────────────────────────────────────
    #
    #     |---|       | C: x    | Z: x    | N: x    | V: x    |   RA1 | ... |
    # RS1 | ... |     |--- r3 ------ r2 ------ r1 ------ r0 --|       |---|
    # RS0 | ... | ACC | b b b b | b b b b | b b b b | b b b b |   RA0 | ... |
    #     |---|       |---|                                          |---|

    R.append(_BB1 + _BB2   + _BB3)
    R.append(_c16('RS1','rs1',snap['rs1'],chg,3) +
             _flags_row(snap, chg) +
             _c16('RA1','ra1',snap['ra1'],chg,5))
    R.append(_BB1 + _ACC_HDR + _BB3)
    R.append(_c16('RS0','rs0',snap['rs0'],chg,3) +
             _acc_row(snap, chg, w) +
             _c16('RA0','ra0',snap['ra0'],chg,5))
    R.append(_BB1 + _BB2 + _BB3)

    return '\n'.join(R)


# ─── Context-preserving assembler ─────────────────────────────────────────────

class _CtxAsm(Assembler):
    """Assembler that starts with the CPU's current W/IMM/CFG state."""
    def __init__(self, w, imm, cfg):
        super().__init__()
        self._iW = w; self._iIMM = imm; self._iCFG = cfg

    def _reset_state(self):
        self._W   = self._iW
        self._IMM = self._iIMM
        self._cfg = self._iCFG


# ─── Input preprocessing & execution ──────────────────────────────────────────

def _preprocess(line):
    """
    Split on ';' and handle 'XOP MNEM' shorthand.
    'XOP SUB' -> 'XOP\\nSUB' is invalid (double-XOP); only 'XOP ADD' works.
    """
    parts = [p.strip() for p in line.split(';') if p.strip()]
    out = []
    for part in parts:
        words = part.split()
        if words and words[0].upper() == 'XOP' and len(words) > 1:
            # User typed 'XOP ADD' meaning explicit prefix + base mnemonic
            out.append('XOP')
            out.append(' '.join(words[1:]))
        else:
            out.append(part)
    return '\n'.join(out) if out else ''


def _exec_asm(cpu, text):
    """
    Assemble *text* at the current CPU PC and step through all emitted instructions.
    Returns (ok: bool, message: str).
    """
    src = _preprocess(text)
    if not src:
        return True, ''
    byte_pc = cpu.pc >> 1
    asm = _CtxAsm(cpu.W, int(cpu.IMM), cpu.cfg)
    full_src = f'.ORG 0x{byte_pc:04X}\n{src}\n'
    try:
        start_b, data = asm.assemble(full_src)
    except AsmError as e:
        return False, str(e)
    if not data:
        return False, 'No code assembled'

    end_na = (start_b + len(data)) * 2    # nibble address past last byte
    for i, b in enumerate(data):
        cpu.mem[(start_b + i) & 0xFFFF] = b
    cpu.pc = start_b * 2

    steps = 0
    while cpu.pc < end_na and not cpu._halted and steps < 200:
        cpu.step()
        steps += 1
    return True, f'{steps} step{"s" if steps != 1 else ""}'


# ─── Help text ────────────────────────────────────────────────────────────────

_CFG_HELP = """\
 CFG #imm8  --  Load configuration register (8-bit immediate)

  Bit  Name   Reset  Description
  ---  -----  -----  --------------------------------------------------
  7:6  RSV      0    Reserved
   5   CI       0    Carry-in:  0 = ignore C flag  |  1 = use C as carry-in
   4   IE       0    Interrupts: 0 = disable        |  1 = enable
   3   IMM      0    Immediate: 0 = ALU op2 = RS0   |  1 = ALU op2 = inline imm
   2   SIGN     0    Arithmetic: 0 = unsigned        |  1 = signed
  1:0  W        00   Link width:
                       00 = UL   (4-bit  accumulator, 1-nibble immediates)
                       01 = LK8  (8-bit  accumulator, 2-nibble immediates)
                       10 = LK16 (16-bit accumulator, 4-nibble immediates -- RACC/RRS become CSRLD/CSRST)
                       11 = SPE  (special profile)

 Examples:
   CFG #0x01          LK8, all else off
   CFG #0x09          LK8 + IMM=1  (inline immediates for ALU)
   CFG #b0000_0001    same as #0x01 (binary format)
   CFG #b0000_1001    same as #0x09
"""

_XMEM_HELP = """\
 XMEM #imm4  --  Extended memory operation (4-bit function nibble)

  Bit  Name  Description
  ---  ----  --------------------------------------------------
   3   OP    0 = LD (memory -> ACC)   |  1 = ST (ACC -> memory)
   2   AM    0 = no auto-modify        |  1 = auto-modify enabled
   1   DIR   0 = post-increment        |  1 = pre-decrement  (only when AM=1)
   0   IDX   0 = base   addr = RA1     |  1 = indexed  addr = RA1 + RA0
              (AM modifies RA1)           (AM modifies RA0)

 Access width follows W mode:  UL=nibble  LK8=byte  LK16=word(2B)
 Stride for auto-modify:       UL/LK8=1   LK16=2

  Pattern          Meaning
  ---------------  --------------------------------------------------
  #b0000  (#0x0)   LD  from RA1
  #b0001  (#0x1)   LD  from RA1+RA0  (indexed)
  #b0100  (#0x4)   LD  from RA1,      post-increment RA1
  #b0101  (#0x5)   LD  from RA1+RA0,  post-increment RA0
  #b0110  (#0x6)   LD  from RA1,      pre-decrement  RA1
  #b0111  (#0x7)   LD  from RA1+RA0,  pre-decrement  RA0
  #b1000  (#0x8)   ST  to   RA1
  #b1001  (#0x9)   ST  to   RA1+RA0  (indexed)
  #b1100  (#0xC)   ST  to   RA1,      post-increment RA1
  #b1101  (#0xD)   ST  to   RA1+RA0,  post-increment RA0
  #b1110  (#0xE)   ST  to   RA1,      pre-decrement  RA1
  #b1111  (#0xF)   ST  to   RA1+RA0,  pre-decrement  RA0
"""

_ALU_HELP = """\
 ALU instructions  (see 'alu help')

  Mnemonic  Extended   Operation              Flags
  --------  ---------  ---------------------  -----
  ADD       SUB        ACC +/- op2            C Z N V
  INC       DEC        ACC +/- 1              C Z N V
  AND       INV        ACC & op2 / ~ACC        Z N
  OR        XOR        ACC | op2 / ACC ^ op2  Z N
  SHL       SHR        ACC << 1 / ACC >> 1    C Z N
  CMP       (n/a)      flags <- ACC - op2     C Z N V  (ACC unchanged)
  TST       BTST       ACC & op2 / bit test   Z N      (ACC unchanged)
  RACC      RRS        rotate ACC / RS0 by W bits within 16-bit  (no flags)

  op2 source:
    IMM=0  op2 = RS0
    IMM=1  op2 = inline immediate (nibbles follow opcode in instruction stream)

  Immediate width matches W mode:  UL=4b  LK8=8b  LK16=16b

  Extended (XOP) variants -- type the full mnemonic or 'XOP BASE':
    SUB INC DEC INV XOR SHR BTST CMP JMP RSA SA RRS RETI WFI
"""

_RS_HELP = """\
 RS register interactions  (ALU operand detail: 'alu help')

 RS0  --  ALU second operand (IMM=0), swap target for SS, rotate target for RRS

  Instruction  RS0 role
  -----------  --------------------------------------------------
  SS           ACC <-> RS0  (W-bits wide, atomic swap)
  RRS          RS0 rotated right by W bits within 16-bit
  ADD/SUB/AND/OR/XOR/CMP/TST/BTST  op2 = RS0 when IMM=0

 RS1  --  secondary source, swap partner for RS0

  Instruction  RS1 role
  -----------  --------------------------------------------------
  RSS          RS0 <-> RS1  (full 16-bit swap)
  MCPY         byte count  (signed: positive=forward, negative=backward)
               RS1 is cleared to 0 after the copy
"""

_RA_HELP = """\
 RA register interactions

  Instruction  Role
  -----------  --------------------------------------------------
  SA           ACC <-> RA0  (full 16-bit swap)
  RSA          RA0 <-> RA1  (full 16-bit swap)

 RA1  --  jump/link target, memory base address
 RA0  --  memory offset / swap target for SA

  Instruction  RA1 role
  -----------  --------------------------------------------------
  JAL          PC <- RA1 (jump);  RA1 <- PC_next (link)  [atomic, read-before-write]
  JMP          PC <- RA1  (RA1 unchanged)
  XMEM IDX=0   addr = RA1         AM modifies RA1
  XMEM IDX=1   addr = RA1 + RA0   AM modifies RA0 (not RA1)
  MCPY         source address (modified during copy)

  Instruction  RA0 role
  -----------  --------------------------------------------------
  SA           ACC <-> RA0  (full 16-bit swap)
  XMEM IDX=1   offset added to RA1; AM modifies RA0
  MCPY         destination address (modified during copy)

 Loading RA0 / RA1 (no direct load instruction -- route through ACC):
   CFG #0x02        ; LK16 (full 16-bit)
   LDi #0x0200      ; ACC = 0x0200
   SA               ; RA0 = 0x0200
   RSA              ; RA1 = 0x0200, RA0 = previous RA1
"""

_HELP = """\
 Instructions (omit XOP prefix -- use extended mnemonic directly or 'XOP BASE'):
  NOP                 No op
  ADD [#v]  SUB [#v]  Add / subtract ACC with RS0 or immediate (needs CFG.IMM=1)
  INC       DEC       ACC++ / ACC--
  AND [#v]  INV       AND with RS0/imm / bitwise NOT
  OR  [#v]  XOR [#v]  OR / XOR with RS0 or imm
  SHL       SHR       Shift left / right by 1
  BTST [#i] TST [#v]  Bit test (bit idx) / mask test (no ACC write)
  CMP  [#v]           Compare ACC - OP2 (flags only)
  BRC  <cond>,<tgt>   Branch relative conditional; target = label or nibble offset
  BAL/BEQ/BNE/BCS/BCC/BMI/BPL/BVS/BVC/BHI/BLS/BGE/BLT/BGT/BLE
                      Branch alias mnemonics
  JAL                 PC <- RA1 (jump), RA1 <- PC_next (link)
  JMP                 PC <- RA1
  CFG  #imm8          Load CFG register (W[1:0], SIGN[2], IMM[3], IE[4], CI[5])
  LDi  #imm           ACC = immediate (W-bit wide)
  SS                  ACC <-> RS0 (W bits)     SA     ACC <-> RA0 (16-bit)
  RSS                 RS0 <-> RS1              RSA    RA0 <-> RA1
  RACC                Rotate ACC (non-LK16)    RRS    Rotate RS0 (non-LK16)
  CSRLD #i  CSRST #i  CSR access (LK16 mode only)
  XMEM #f             Memory op; f=OP(3)|AM(2)|DIR(1)|IDX(0)
                        LD=0/ST=1  AM=auto-modify  DIR=0+/1-  IDX=0direct/1indexed
  MCPY                Block copy [RA0]->[RA1], RS1 bytes (signed)
  RETI                Return from interrupt
  SWI                 Software interrupt
  WFI                 Halt / wait for interrupt

 Directives:  .ORG addr   .EQU name,val   .WIDTH 4|8|16
              .BYTE v...  .WORD v...      .ASCII "s"  .ASCIIZ "s"

 TUI commands:
  reset               Reset CPU registers (memory preserved)
  load <f> [addr]     Load .bin or .asm file at optional byte address
  mem  [addr] [n]     Hex dump n bytes (default 64) at addr (default RA0)
  dis  [addr] [n]     Disassemble n instrs (default 10) from addr (default PC)
  setreg <r> <val>    Set register: pc acc rs0 rs1 ra0 ra1 cfg ia iar c z n v csr0-15
  setmem <addr> <val> Write byte to memory
  step [n]  / +       Step n instructions; Enter or '+' steps 1
  run  [max]          Run until halt / breakpoint
  break <addr>        Toggle breakpoint (byte address)
  blist               List breakpoints
  alu  help           ALU instruction reference
  cfg  help           CFG bit-field reference
  xmem help           XMEM function-nibble reference
  rs   help           RS0/RS1 instruction interactions
  ra   help           RA0/RA1 instruction interactions
  help / ?            This help
  quit / q            Exit

 Highlight rules:
  Reversed nibbles = changed since last command
  Dimmed nibbles   = outside active ACC width (W mode)
"""


# ─── TUI ──────────────────────────────────────────────────────────────────────

class TUI:
    def __init__(self):
        self.cpu       = MISAO_CPU()
        self._snap     = _snap(self.cpu)
        self._chg      = set()
        self._hist     = deque(maxlen=10)   # (input_str, ok, msg)
        self._bps      = set()              # nibble addresses
        self._prog     = None              # saved (byte_addr, data) from last load
        self._prog_pc  = 0                 # nibble PC at load time

    # ── Main loop ─────────────────────────────────────────────────────────────

    def run(self):
        _enable_ansi()
        while True:
            self._redraw()
            try:
                line = input('> ').strip()
            except (EOFError, KeyboardInterrupt):
                print(); break
            if not line or line == '+':
                self._do_steps(1)
                continue
            if not self._dispatch(line):
                break

    # ── Screen ────────────────────────────────────────────────────────────────

    def _redraw(self):
        sys.stdout.write(CLR)
        sys.stdout.flush()

        print()   # margin from top of terminal
        print()
        # Register display
        print(_build_display(self.cpu, self._snap, self._chg))
        print()

        # Status line
        nxt, _, _, _ = disasm_one(
            self.cpu._rn, self.cpu.pc, self.cpu.W, self.cpu.IMM)
        hlt = '  [HALTED]' if self.cpu._halted else ''
        print(f'  PC {self.cpu.pc:04X}h(n)/{self.cpu.pc>>1:04X}h(b)'
              f'   W={W_NAMES[self.cpu.W]}'
              f'  IMM={int(self.cpu.IMM)}'
              f'  IE={int(self.cpu.IE)}'
              f'   cycles={self.cpu.cycles}{hlt}')
        print(f'  Next: {nxt}')
        print()

        # Command history
        if self._hist:
            for cmd, ok, msg in self._hist:
                mark = '' if ok else f'  [!] {msg}'
                print(f'  {cmd}{mark}')
            print()

    # ── Dispatch ──────────────────────────────────────────────────────────────

    def _dispatch(self, line):
        tok = line.split()
        cmd = tok[0].lower() if tok else ''
        args = line[len(cmd):].strip()

        if cmd in ('quit', 'q', 'exit'):
            return False

        if cmd in ('help', '?'):
            sys.stdout.write(CLR)
            print(_HELP)
            input('Press Enter to return...')
            return True

        if cmd == 'cfg' and args.lower() == 'help':
            sys.stdout.write(CLR)
            print(_CFG_HELP)
            input('Press Enter to return...')
            return True

        if cmd == 'xmem' and args.lower() == 'help':
            sys.stdout.write(CLR)
            print(_XMEM_HELP)
            input('Press Enter to return...')
            return True

        if cmd == 'alu' and args.lower() == 'help':
            sys.stdout.write(CLR)
            print(_ALU_HELP)
            input('Press Enter to return...')
            return True

        if cmd == 'rs' and args.lower() == 'help':
            sys.stdout.write(CLR)
            print(_RS_HELP)
            input('Press Enter to return...')
            return True

        if cmd == 'ra' and args.lower() == 'help':
            sys.stdout.write(CLR)
            print(_RA_HELP)
            input('Press Enter to return...')
            return True

        if cmd == 'reset':
            self.cpu.reset()
            if self._prog is not None:
                addr, data = self._prog
                for i, b in enumerate(data):
                    self.cpu.mem[(addr + i) & 0xFFFF] = b
                self.cpu.pc = self._prog_pc
            self._snap = _snap(self.cpu); self._chg = set()
            self._hist.append(('reset', True, ''))
            return True

        if cmd == 'clear':
            self._hist.clear(); self._chg = set()
            return True

        if cmd == 'load':
            self._do_load(args); return True

        if cmd in ('mem', 'm'):
            self._do_mem(args); return True

        if cmd in ('dis', 'd'):
            self._do_dis(args); return True

        if cmd == 'setreg':
            self._do_setreg(args); return True

        if cmd == 'setmem':
            self._do_setmem(args); return True

        if cmd in ('step', 's'):
            n = int(tok[1]) if len(tok) > 1 and tok[1].isdigit() else 1
            self._do_steps(n); return True

        if cmd == 'run':
            lim = int(tok[1]) if len(tok) > 1 and tok[1].isdigit() else 10_000_000
            self._do_run(lim); return True

        if cmd in ('break', 'b'):
            self._do_break(args); return True

        if cmd == 'blist':
            for na in sorted(self._bps):
                self._hist.append((f'  bp @ {na>>1:04X}h', True, ''))
            return True

        # Treat as assembly instruction
        self._do_asm(line)
        return True

    # ── Handlers ──────────────────────────────────────────────────────────────

    def _do_asm(self, line):
        before = _snap(self.cpu)
        ok, msg = _exec_asm(self.cpu, line)
        self._snap = _snap(self.cpu)
        self._chg  = _diff(before, self._snap)
        self._hist.append((line, ok, msg if not ok else ''))

    def _do_steps(self, n):
        before = _snap(self.cpu)
        for _ in range(n):
            if self.cpu._halted: break
            self.cpu.step()
        self._snap = _snap(self.cpu)
        self._chg  = _diff(before, self._snap)
        self._hist.append((f'step {n}', True, ''))

    def _do_run(self, limit):
        before = _snap(self.cpu); steps = 0
        while not self.cpu._halted and steps < limit:
            if steps > 0 and self.cpu.pc in self._bps: break
            self.cpu.step(); steps += 1
        self._snap = _snap(self.cpu)
        self._chg  = _diff(before, self._snap)
        self._hist.append((f'run -> {steps} steps', True, ''))

    def _do_load(self, args):
        parts = args.split()
        if not parts:
            self._hist.append(('load: missing filename', False, '')); return
        path = parts[0]
        addr = int(parts[1], 0) if len(parts) > 1 else None
        if not os.path.exists(path):
            self._hist.append((f'load: not found: {path}', False, '')); return
        before = _snap(self.cpu)
        ext = os.path.splitext(path)[1].lower()
        try:
            if ext in ('.asm', '.s'):
                start, data, syms, _ = assemble_file(path)
                if addr is not None: start = addr
                self.cpu.load(data, start)
                label = f'{len(data)}b @ {start:04X}h  ({len(syms)} labels)'
            else:
                with open(path, 'rb') as f: data = f.read()
                self.cpu.load(data, addr or 0)
                label = f'{len(data)}b @ {addr or 0:04X}h'
            self._hist.append((f'load {os.path.basename(path)}: {label}', True, ''))
        except (AsmError, OSError) as e:
            self._hist.append((f'load error', False, str(e)[:60]))
            return
        self._prog    = (self.cpu.pc >> 1, bytes(data))
        self._prog_pc = self.cpu.pc
        self._snap = _snap(self.cpu)
        self._chg  = _diff(before, self._snap)

    def _do_mem(self, args):
        parts = args.split()
        try:
            addr = int(parts[0], 0) if parts else self.cpu.ra0
            n    = int(parts[1], 0) if len(parts) > 1 else 64
        except ValueError:
            addr = self.cpu.ra0; n = 64
        sys.stdout.write(CLR)
        print(self.cpu.dump_mem(addr, n))
        input('\nPress Enter...')

    def _do_dis(self, args):
        parts = args.split()
        try:
            addr = int(parts[0], 0) * 2 if parts else self.cpu.pc
            n    = int(parts[1], 0) if len(parts) > 1 else 10
        except ValueError:
            addr = self.cpu.pc; n = 10
        sys.stdout.write(CLR)
        print(self.cpu.disasm(addr, n))
        input('\nPress Enter...')

    def _do_setreg(self, args):
        parts = args.split()
        if len(parts) < 2:
            return
        reg = parts[0].lower()
        try: val = int(parts[1], 0)
        except ValueError: return
        before = _snap(self.cpu); cpu = self.cpu
        _map = {
            'pc':  lambda v: setattr(cpu,'pc', v&0xFFFF),
            'acc': lambda v: cpu.set_acc(v),
            'rs0': lambda v: setattr(cpu,'rs0',v&0xFFFF),
            'rs1': lambda v: setattr(cpu,'rs1',v&0xFFFF),
            'ra0': lambda v: setattr(cpu,'ra0',v&0xFFFF),
            'ra1': lambda v: setattr(cpu,'ra1',v&0xFFFF),
            'cfg': lambda v: setattr(cpu,'cfg',v&0xFF),
            'ia':  lambda v: setattr(cpu,'ia', v&0xFF),
            'iar': lambda v: setattr(cpu,'iar',v&0xFF),
            'c':   lambda v: setattr(cpu,'c',  v&1),
            'z':   lambda v: setattr(cpu,'z',  v&1),
            'n':   lambda v: setattr(cpu,'n',  v&1),
            'v':   lambda v: setattr(cpu,'v',  v&1),
        }
        if reg in _map:
            _map[reg](val)
        elif reg.startswith('csr') and reg[3:].isdigit():
            cpu.csr_w(int(reg[3:]), val)
        self._snap = _snap(self.cpu)
        self._chg  = _diff(before, self._snap)
        self._hist.append((f'setreg {reg}={val:#x}', True, ''))

    def _do_setmem(self, args):
        parts = args.split()
        if len(parts) < 2: return
        try:
            addr = int(parts[0], 0); val = int(parts[1], 0) & 0xFF
        except ValueError: return
        before = _snap(self.cpu)
        self.cpu._wb(addr, val)
        self._snap = _snap(self.cpu)
        self._chg  = _diff(before, self._snap)
        self._hist.append((f'setmem {addr:#x}={val:#x}', True, ''))

    def _do_break(self, args):
        parts = args.split()
        if not parts: return
        try: na = int(parts[0], 0) * 2
        except ValueError: return
        if na in self._bps:
            self._bps.discard(na)
            self._hist.append((f'break removed @ {na>>1:04X}h', True, ''))
        else:
            self._bps.add(na)
            self._hist.append((f'break set @ {na>>1:04X}h', True, ''))


# ─── Entry point ──────────────────────────────────────────────────────────────

def main():
    import argparse
    p = argparse.ArgumentParser(description='MISA-O v0 TUI')
    p.add_argument('file', nargs='?', help='Binary or .asm file to load')
    p.add_argument('--addr', '-a', type=lambda s: int(s, 0), default=0,
                   metavar='ADDR', help='Load address (byte)')
    args = p.parse_args()

    tui = TUI()
    if args.file:
        tui._do_load(f'{args.file} {args.addr}' if args.addr else args.file)
    tui.run()


if __name__ == '__main__':
    main()
