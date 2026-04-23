# -*- coding: utf-8 -*-
"""
MISA-O v0 — Two-pass assembler
Produces a nibble buffer packed low-nibble-first into bytes.

Pass 1: resolve labels (nibble addresses) and .equ values.
Pass 2: emit instruction nibbles.

Both passes track W and IMM state through CFG / .WIDTH directives so that
variable-length instructions (LDi, ALU with inline immediate) are sized
correctly in pass 1.
"""

import re
import sys


# ─── Constants ───────────────────────────────────────────────────────────────

COND_MAP = {
    'AL': 0, 'EQ': 1, 'NE': 2, 'CS': 3, 'CC': 4,
    'MI': 5, 'PL': 6, 'VS': 7, 'VC': 8,
    'HI': 9, 'LS': 10, 'GE': 11, 'LT': 12, 'GT': 13, 'LE': 14,
}

# Branch-mnemonic aliases → condition name
BRANCH_COND = {
    'BAL': 'AL', 'BEQ': 'EQ', 'BNE': 'NE', 'BCS': 'CS', 'BCC': 'CC',
    'BMI': 'MI', 'BPL': 'PL', 'BVS': 'VS', 'BVC': 'VC',
    'BHI': 'HI', 'BLS': 'LS', 'BGE': 'GE', 'BLT': 'LT', 'BGT': 'GT', 'BLE': 'LE',
}

# Number of nibbles per W mode (UL=4b, LK8=8b, LK16=16b, SPE=16b)
W_NIBBLES = [1, 2, 4, 4]

# Fixed instruction sizes in nibbles (no inline immediate)
_FIXED_SIZE = {
    'NOP':  1, 'INC':  1, 'SHL': 1, 'SS0': 1, 'SA0':  1, 'JAL': 1, 'RACC': 1, 'XOP': 1,
    'DEC':  2, 'SHR':  2, 'INV': 2, 'SS1': 2, 'SA1':  2, 'JMP': 2, 'RRS':  2,
    'RETI': 2, 'SWI':  2, 'WFI': 2, 'MCPY': 2, 'WDR': 2,
    'BRC':  4,
    'CFG':  3,   # opcode + 2 nibbles (8-bit immediate)
    'XMEM': 2,   # opcode + 1 nibble func
    'CSRLD': 2,  # opcode + 1 nibble idx (LK16)
    'CSRST': 3,  # XOP + opcode + 1 nibble idx (LK16)
}

# ALU instructions that can carry a W-width inline immediate
# (base_nibbles_without_imm, needs_XOP_prefix)
_ALU_INFO = {
    'ADD':  (1, False),
    'SUB':  (2, True),
    'AND':  (1, False),
    'OR':   (1, False),
    'XOR':  (2, True),
    'CMP':  (2, True),
    'TST':  (2, True),
    'BTST': (1, False),  # fixed 1-nibble immediate (bit index), handled separately
}

# Opcode nibbles for instructions (first nibble, with XOP prefix for ext forms)
_OPCODES = {
    # simple (1 nibble)
    'NOP':  [0x0], 'INC':  [0x9], 'AND':  [0x5],
    'SHL':  [0x3], 'OR':   [0xD], 'BRC':  [0x7],
    'JAL':  [0xF], 'CFG':  [0x2], 'SS0':  [0xA],
    'SA0':   [0xE], 'LDi':  [0x4], 'XMEM': [0xC],
    'RACC': [0x6], 'ADD':  [0x1],
    # XOP prefix (2 nibbles)
    'DEC':  [0x8, 0x9], 'INV':  [0x8, 0x5], 'SHR':  [0x8, 0x3],
    'XOR':  [0x8, 0xD], 'CMP':  [0x8, 0x7], 'JMP':  [0x8, 0xF],
    'RETI': [0x8, 0x2], 'RRS':  [0x8, 0x6], 'SS1':  [0x8, 0xA],
    'SA1':   [0x8, 0xE], 'SWI':  [0x8, 0x4], 'MCPY': [0x8, 0xC],
    'WFI':  [0x8, 0x8], 'SUB':  [0x8, 0x1], 'TST':  [0x8, 0xB],
    'WDR':  [0x8, 0x0],
    'BTST': [0xB],
    # LK16 CSR access (RACC/RRS opcode in LK16 mode)
    'CSRLD': [0x6],
    'CSRST': [0x8, 0x6],
    # XOP prefix standalone
    'XOP':   [0x8],
}


# ─── Error ───────────────────────────────────────────────────────────────────

class AsmError(Exception):
    def __init__(self, msg, lineno=None):
        self.lineno = lineno
        full = f'Line {lineno}: {msg}' if lineno else msg
        super().__init__(full)


# ─── Helpers ─────────────────────────────────────────────────────────────────

def _parse_int(s):
    """Parse an integer literal.
    Formats accepted:
      0xNN / 0XNN   hex prefix
      NNh / NNH     hex suffix
      hNN / HNN     hex prefix (no 0x)
      NNb / NNB     binary suffix
      bNNNN / BNNNN binary prefix, underscores ignored (e.g. b0000_0010)
      decimal       plain integer
    """
    s = s.strip()
    if not s:
        raise ValueError('empty string')
    if s.startswith('0x') or s.startswith('0X'):
        return int(s, 16)
    if s[0] in ('h', 'H'):
        return int(s[1:], 16)
    if s.endswith(('h', 'H')):
        return int(s[:-1], 16)
    if s[0] in ('b', 'B') and len(s) > 1:
        return int(s[1:].replace('_', ''), 2)
    if len(s) > 1 and s.endswith(('b', 'B')):
        return int(s[:-1], 2)
    return int(s, 0)


def _unescape(s):
    """Process standard C-style escape sequences in a string."""
    return s.encode('raw_unicode_escape').decode('unicode_escape')


# ─── Assembler ───────────────────────────────────────────────────────────────

class Assembler:
    """
    Two-pass MISA-O assembler.

    Usage:
        asm = Assembler()
        start_byte, data = asm.assemble(source_text)
        # asm.symbols  — dict label → nibble address
        # asm.equates  — dict name  → integer value
    """

    def __init__(self):
        self.symbols: dict = {}   # label → nibble address
        self.equates: dict = {}   # name  → integer
        self._nib:    dict = {}   # nibble_addr → nibble_value (sparse)
        self._errors: list = []
        self._W:      int  = 0    # tracked W mode (0–3)
        self._IMM:    int  = 0    # tracked IMM flag
        self._cfg:    int  = 0    # full CFG byte

    # ── Public API ────────────────────────────────────────────────────────────

    def assemble(self, text: str):
        """
        Assemble *text* and return (start_byte_addr, bytes).
        Raises AsmError with all collected errors on failure.
        """
        lines = text.splitlines()
        self.symbols  = {}
        self.equates  = {}
        self._errors  = []
        self._nib     = {}

        self._reset_state()
        self._pass1(lines)

        self._reset_state()
        self._pass2(lines)

        if self._errors:
            raise AsmError('\n'.join(self._errors))

        return self._pack_nibbles()

    # ── State helpers ─────────────────────────────────────────────────────────

    def _reset_state(self):
        self._W   = 0
        self._IMM = 0
        self._cfg = 0

    def _w_nibbles(self):
        return W_NIBBLES[self._W]

    def _update_cfg(self, val: int):
        self._cfg = val & 0xFF
        self._W   = self._cfg & 0x3
        self._IMM = (self._cfg >> 3) & 1

    # ── Tokeniser ─────────────────────────────────────────────────────────────

    def _tokenize(self, raw: str):
        """
        Parse one source line.
        Returns (label_or_None, mnemonic_or_None, args_str).
        """
        line = raw.split(';')[0].rstrip()  # strip comment
        label = None

        m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s*:', line)
        if m:
            label = m.group(1)
            line  = line[m.end():].strip()

        parts = line.split(None, 1)
        if not parts:
            return label, None, ''

        mnem = parts[0].upper()
        args = parts[1].strip() if len(parts) > 1 else ''
        return label, mnem, args

    def _split_args(self, s: str):
        """Split comma-separated args, returning stripped non-empty strings."""
        if not s.strip():
            return []
        return [a.strip() for a in s.split(',') if a.strip()]

    # ── Symbol / expression resolution ───────────────────────────────────────

    def _resolve(self, expr: str, lineno: int) -> int:
        """
        Resolve an expression to an integer.
        Handles: label names, .equ names, integer literals.
        Leading '#' or '@' sigils are stripped.
        """
        s = expr.strip().lstrip('#').lstrip('@')
        key = s.upper()
        if key in self.equates:
            return self.equates[key]
        if s in self.symbols:
            return self.symbols[s]
        try:
            return _parse_int(s)
        except (ValueError, TypeError):
            raise AsmError(f'Unresolved: {expr!r}', lineno)

    # ── Instruction size (pass 1) ─────────────────────────────────────────────

    def _instr_size(self, mnem: str, args: str, lineno: int) -> int:
        """
        Return instruction size in nibbles.
        For CFG and .WIDTH, also updates tracked W/IMM state as a side effect.
        """
        argv = self._split_args(args)

        # Branch-mnemonic aliases are all 4 nibbles (same as BRC)
        if mnem in BRANCH_COND:
            return 4

        # Fixed-size instructions
        if mnem in _FIXED_SIZE:
            if mnem == 'CFG':
                # Track W/IMM changes so subsequent instruction sizes are right
                if argv:
                    try:
                        v = self._resolve(argv[0], lineno)
                        self._update_cfg(v)
                    except AsmError:
                        pass
            return _FIXED_SIZE[mnem]

        # LDi: opcode + W_nibbles
        if mnem == 'LDi' or mnem == 'LDI':
            return 1 + self._w_nibbles()

        # BTST: opcode [+ 1 nibble index if has arg]
        if mnem == 'BTST':
            return 2 if argv else 1

        # ALU with optional W-width inline immediate
        if mnem in _ALU_INFO:
            base, _ = _ALU_INFO[mnem]
            if argv:
                return base + self._w_nibbles()
            return base

        raise AsmError(f'Unknown mnemonic: {mnem!r}', lineno)

    # ── Pass 1 ────────────────────────────────────────────────────────────────

    def _pass1(self, lines: list):
        npc = 0
        for lineno, raw in enumerate(lines, 1):
            try:
                label, mnem, args = self._tokenize(raw)
            except Exception as e:
                self._errors.append(f'Line {lineno}: {e}')
                continue

            if label:
                if label in self.symbols:
                    self._errors.append(f'Line {lineno}: Duplicate label {label!r}')
                else:
                    self.symbols[label] = npc

            if mnem is None:
                continue

            if mnem.startswith('.'):
                try:
                    npc = self._directive_size(mnem, args, lineno, npc)
                except AsmError as e:
                    self._errors.append(str(e))
                continue

            try:
                size = self._instr_size(mnem, args, lineno)
                npc  = (npc + size) & 0xFFFF
            except AsmError as e:
                self._errors.append(str(e))
                npc = (npc + 1) & 0xFFFF  # best-effort advance

    def _directive_size(self, mnem: str, args: str, lineno: int, npc: int) -> int:
        """Compute size effect of a directive in pass 1; update equates/state."""
        argv = self._split_args(args)

        if mnem == '.ORG':
            if not argv:
                raise AsmError('.ORG requires an address', lineno)
            byte_addr = self._resolve(argv[0], lineno)
            return byte_addr * 2  # convert byte address → nibble address

        if mnem == '.EQU':
            if len(argv) < 2:
                raise AsmError('.EQU requires <name>, <value>', lineno)
            name = argv[0].upper()
            val  = self._resolve(argv[1], lineno)
            self.equates[name] = val
            return npc

        if mnem == '.BYTE':
            return npc + 2 * len(argv)   # 1 byte = 2 nibbles

        if mnem == '.WORD':
            return npc + 4 * len(argv)   # 2 bytes = 4 nibbles

        if mnem in ('.ASCII', '.ASCIIZ'):
            m = re.search(r'"((?:[^"\\]|\\.)*)"', args)
            if not m:
                raise AsmError(f'{mnem}: expected quoted string', lineno)
            s = _unescape(m.group(1))
            n = len(s) * 2
            if mnem == '.ASCIIZ':
                n += 2  # NUL terminator
            return npc + n

        if mnem == '.WIDTH':
            if not argv:
                raise AsmError('.WIDTH requires a bit-width argument', lineno)
            n = self._resolve(argv[0], lineno)
            w_map = {4: 0, 8: 1, 16: 2}
            w = w_map.get(n, n & 3)
            new_cfg = (self._cfg & 0xFC) | w
            self._update_cfg(new_cfg)
            return npc + 3   # emits CFG #new_cfg (3 nibbles)

        if mnem == '.ALIGN':
            if not argv:
                return npc
            n       = self._resolve(argv[0], lineno)
            align_n = n * 2  # byte alignment → nibble alignment
            if align_n > 0 and npc % align_n:
                npc += align_n - (npc % align_n)
            return npc

        if mnem == '.SPACE':
            if not argv:
                raise AsmError('.SPACE requires a byte count', lineno)
            n = self._resolve(argv[0], lineno)
            return npc + n * 2   # n zero bytes = n*2 nibbles

        # Unknown directive — skip silently
        return npc

    # ── Pass 2 ────────────────────────────────────────────────────────────────

    def _pass2(self, lines: list):
        npc = 0
        for lineno, raw in enumerate(lines, 1):
            try:
                label, mnem, args = self._tokenize(raw)
                if mnem is None:
                    continue
                if mnem.startswith('.'):
                    npc = self._emit_directive(mnem, args, lineno, npc)
                    continue
                size = self._emit_instr(mnem, args, lineno, npc)
                npc  = (npc + size) & 0xFFFF
            except AsmError as e:
                self._errors.append(str(e))
                npc = (npc + 1) & 0xFFFF

    def _emit_nibbles(self, npc: int, *vals) -> int:
        """Store nibble values starting at npc; return count emitted."""
        for i, v in enumerate(vals):
            self._nib[npc + i] = v & 0xF
        return len(vals)

    def _emit_instr(self, mnem: str, args: str, lineno: int, npc: int) -> int:
        """Emit instruction nibbles at npc; return nibbles emitted."""
        argv = self._split_args(args)
        emit = lambda *ns: self._emit_nibbles(npc, *ns)

        def iarg(i):
            if i >= len(argv):
                raise AsmError(f'{mnem}: missing argument {i}', lineno)
            return self._resolve(argv[i], lineno)

        def imm_nibbles(val, wn=None):
            """Return list of wn nibbles encoding val little-endian."""
            n = wn if wn is not None else self._w_nibbles()
            return [(val >> (4 * i)) & 0xF for i in range(n)]

        # ── Branch-mnemonic aliases ──
        if mnem in BRANCH_COND:
            cond   = COND_MAP[BRANCH_COND[mnem]]
            target = iarg(0)
            offset = target - (npc + 4)
            if not (-128 <= offset <= 127):
                raise AsmError(
                    f'{mnem}: target out of range '
                    f'(offset={offset} nibbles, max ±127)', lineno)
            if offset < 0:
                offset += 256
            lo, hi = offset & 0xF, (offset >> 4) & 0xF
            return emit(0x7, cond, lo, hi)

        # ── Fixed-size / no-operand instructions ──
        if mnem in ('NOP', 'INC', 'SHL', 'SS0', 'SA0', 'JAL', 'RACC', 'XOP',
                    'DEC', 'SHR', 'INV', 'SS1', 'SA1',  'JMP', 'RRS',
                    'RETI', 'SWI', 'WFI', 'MCPY', 'WDR'):
            return emit(*_OPCODES[mnem])

        # ── CFG #imm8 ──
        if mnem == 'CFG':
            v = iarg(0)
            self._update_cfg(v)
            return emit(0x2, v & 0xF, (v >> 4) & 0xF)

        # ── LDi #immW ──
        if mnem in ('LDi', 'LDI'):
            v  = iarg(0)
            wn = self._w_nibbles()
            return emit(0x4, *imm_nibbles(v, wn))

        # ── BRC #cond, #offset_or_label ──
        if mnem == 'BRC':
            if len(argv) < 2:
                raise AsmError('BRC: requires <cond>, <target>', lineno)
            cond_str = argv[0].strip().lstrip('#').upper()
            if cond_str not in COND_MAP:
                raise AsmError(f'BRC: unknown condition {cond_str!r}', lineno)
            cond = COND_MAP[cond_str]
            # Target may be a label (nibble addr) or a literal offset
            tgt_str = argv[1].strip()
            try:
                # Try literal offset first
                offset = _parse_int(tgt_str.lstrip('#'))
            except ValueError:
                # Must be a label → compute offset from nibble address
                target = self._resolve(tgt_str, lineno)
                offset = target - (npc + 4)
            if not (-128 <= offset <= 127):
                raise AsmError(
                    f'BRC {cond_str}: target out of range '
                    f'(offset={offset} nibbles)', lineno)
            if offset < 0:
                offset += 256
            return emit(0x7, cond, offset & 0xF, (offset >> 4) & 0xF)

        # ── XMEM #func ──
        if mnem == 'XMEM':
            f = iarg(0)
            return emit(0xC, f & 0xF)

        # ── CSR access (LK16 mode) ──
        if mnem == 'CSRLD':
            idx = iarg(0)
            return emit(0x6, idx & 0xF)

        if mnem == 'CSRST':
            idx = iarg(0)
            return emit(0x8, 0x6, idx & 0xF)

        # ── BTST [#bit_index] ──
        if mnem == 'BTST':
            if argv:
                idx = iarg(0) & 0xF
                return emit(0xB, idx)
            return emit(0xB)

        # ── ALU with optional W-width inline immediate ──
        if mnem in _ALU_INFO:
            base_nibbles, _ = _ALU_INFO[mnem]
            opcodes = _OPCODES[mnem]
            if argv:
                v = iarg(0)
                return emit(*opcodes, *imm_nibbles(v))
            return emit(*opcodes)

        raise AsmError(f'Unknown mnemonic: {mnem!r}', lineno)

    def _emit_directive(self, mnem: str, args: str, lineno: int, npc: int) -> int:
        """Emit data for a directive; return new npc."""
        argv = self._split_args(args)

        if mnem == '.ORG':
            byte_addr = self._resolve(argv[0], lineno)
            return byte_addr * 2

        if mnem == '.EQU':
            if len(argv) >= 2:
                name = argv[0].upper()
                val  = self._resolve(argv[1], lineno)
                self.equates[name] = val
            return npc

        if mnem == '.BYTE':
            for a in argv:
                v = self._resolve(a, lineno) & 0xFF
                self._nib[npc]     = v & 0xF
                self._nib[npc + 1] = (v >> 4) & 0xF
                npc += 2
            return npc

        if mnem == '.WORD':
            for a in argv:
                v = self._resolve(a, lineno) & 0xFFFF
                for i in range(4):
                    self._nib[npc + i] = (v >> (4 * i)) & 0xF
                npc += 4
            return npc

        if mnem in ('.ASCII', '.ASCIIZ'):
            m = re.search(r'"((?:[^"\\]|\\.)*)"', args)
            if not m:
                raise AsmError(f'{mnem}: expected quoted string', lineno)
            s = _unescape(m.group(1))
            for ch in s:
                v = ord(ch) & 0xFF
                self._nib[npc]     = v & 0xF
                self._nib[npc + 1] = (v >> 4) & 0xF
                npc += 2
            if mnem == '.ASCIIZ':
                self._nib[npc] = 0; self._nib[npc + 1] = 0
                npc += 2
            return npc

        if mnem == '.WIDTH':
            n       = self._resolve(argv[0], lineno)
            w_map   = {4: 0, 8: 1, 16: 2}
            w       = w_map.get(n, n & 3)
            new_cfg = (self._cfg & 0xFC) | w
            self._update_cfg(new_cfg)
            v = new_cfg
            self._nib[npc]     = 0x2        # CFG opcode
            self._nib[npc + 1] = v & 0xF
            self._nib[npc + 2] = (v >> 4) & 0xF
            return npc + 3

        if mnem == '.ALIGN':
            if argv:
                n       = self._resolve(argv[0], lineno)
                align_n = n * 2
                if align_n > 0 and npc % align_n:
                    npc += align_n - (npc % align_n)
            return npc

        if mnem == '.SPACE':
            n = self._resolve(argv[0], lineno)
            for i in range(n * 2):
                self._nib[npc + i] = 0
            return npc + n * 2

        return npc  # unknown / no-op directive

    # ── Output packing ────────────────────────────────────────────────────────

    def _pack_nibbles(self):
        """
        Pack the sparse nibble dict into a contiguous bytearray.
        Returns (start_byte_addr, bytes).
        """
        if not self._nib:
            return 0, b''

        min_na = min(self._nib)
        max_na = max(self._nib)

        # Align nibble range to byte boundaries
        start_na = min_na & ~1          # round down to even nibble
        end_na   = (max_na + 2) & ~1   # round up to even nibble (exclusive)

        result = bytearray((end_na - start_na) // 2)
        for na, val in self._nib.items():
            byte_off = (na - start_na) >> 1
            if na & 1:   # high nibble
                result[byte_off] |= (val & 0xF) << 4
            else:        # low nibble
                result[byte_off] |= val & 0xF

        start_byte = start_na >> 1
        return start_byte, bytes(result)


# ─── Module-level convenience ─────────────────────────────────────────────────

def assemble(text: str):
    """
    Assemble *text* and return (start_byte_addr, bytes, symbols, equates).
    Raises AsmError on failure.
    """
    asm = Assembler()
    start, data = asm.assemble(text)
    return start, data, asm.symbols, asm.equates


def assemble_file(path: str):
    """
    Read and assemble the file at *path*.
    Returns (start_byte_addr, bytes, symbols, equates).
    """
    with open(path, 'r', encoding='utf-8') as f:
        text = f.read()
    return assemble(text)


# ─── CLI ─────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    import argparse, os

    parser = argparse.ArgumentParser(description='MISA-O assembler')
    parser.add_argument('src', help='Source .asm file')
    parser.add_argument('-o', '--out', help='Output binary (default: <src>.bin)')
    parser.add_argument('--symbols', action='store_true', help='Print symbol table')
    parser.add_argument('--hex',     action='store_true', help='Print hex dump instead of writing file')
    args = parser.parse_args()

    try:
        start, data, syms, eqs = assemble_file(args.src)
    except AsmError as e:
        print(f'Assembly failed:\n{e}', file=sys.stderr)
        sys.exit(1)

    if args.hex:
        for i in range(0, len(data), 16):
            row = data[i:i + 16]
            addr = start + i
            hex_str = ' '.join(f'{b:02X}' for b in row)
            asc_str = ''.join(chr(b) if 32 <= b < 127 else '.' for b in row)
            print(f'  {addr:04X}h: {hex_str:<48}  {asc_str}')
    else:
        out = args.out or (os.path.splitext(args.src)[0] + '.bin')
        with open(out, 'wb') as f:
            f.write(data)
        print(f'Assembled {len(data)} bytes → {out}  (start=0x{start:04X})')

    if args.symbols:
        print('\nSymbols (nibble address):')
        for name, na in sorted(syms.items(), key=lambda kv: kv[1]):
            print(f'  {name:<20} 0x{na:04X}  (byte 0x{na>>1:04X})')
        if eqs:
            print('\nEquates:')
            for name, val in sorted(eqs.items()):
                print(f'  {name:<20} {val}')
