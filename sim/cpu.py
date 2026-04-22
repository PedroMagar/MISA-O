# -*- coding: utf-8 -*-
"""
MISA-O v0 — CPU Simulator
PC is a 16-bit nibble address. Memory is 64 KB byte-addressable.
Each byte holds two nibbles (low nibble first).
"""

COND_NAMES = ['AL','EQ','NE','CS','CC','MI','PL','VS','VC','HI','LS','GE','LT','GT','LE','??']
W_NAMES    = ['UL', 'LK8', 'LK16', 'SPE']


# ─── Disassembler (module-level, used by CPU.disasm) ─────────────────────────

_OPMAP = {
    (0x0,False):('NOP', None),   (0x0,True): ('RSV',  None),
    (0x1,False):('ADD', 'wopt'), (0x1,True): ('SUB',  'wopt'),
    (0x9,False):('INC', None),   (0x9,True): ('DEC',  None),
    (0x5,False):('AND', 'wopt'), (0x5,True): ('INV',  None),
    (0xD,False):('OR',  'wopt'), (0xD,True): ('XOR',  'wopt'),
    (0x3,False):('SHL', None),   (0x3,True): ('SHR',  None),
    (0xB,False):('BTST','nopt'), (0xB,True): ('TST',  'wopt'),
    (0x7,False):('BRC', 'brc'),  (0x7,True): ('CMP',  'wopt'),
    (0xF,False):('JAL', None),   (0xF,True): ('JMP',  None),
    (0x2,False):('CFG', 'cfg'),  (0x2,True): ('RETI', None),
    (0x6,False):('RACC',None),   (0x6,True): ('RRS',  None),
    (0xA,False):('RSS', None),   (0xA,True): ('RSA',  None),
    (0xE,False):('SS',  None),   (0xE,True): ('SA',   None),
    (0x4,False):('LDi', 'w'),    (0x4,True): ('SWI',  None),
    (0xC,False):('XMEM','xmem'), (0xC,True): ('MCPY', None),
    (0x8,False):('XOP', None),   (0x8,True): ('WFI',  None),
}

def disasm_one(rn, naddr, w=2, imm=False):
    """
    Disassemble one instruction.
      rn(nibble_addr) -> nibble value
      w: current W mode (0=UL 1=LK8 2=LK16 3=SPE)
      imm: current IMM flag
    Returns: (text, next_naddr, new_w, new_imm)
    """
    cur = naddr

    def rd():
        nonlocal cur
        v = rn(cur); cur += 1
        return v & 0xF

    def wn(ww): return 4 if ww == 0 else (8 if ww == 1 else 16)  # bits
    def wi(ww): return wn(ww) // 4                                 # nibbles

    first = rd()
    ext = False
    if first == 0x8:          # XOP prefix
        ext = True
        first = rd()

    # LK16: opcode 0x6 → CSR access
    if first == 0x6 and w == 2:
        idx = rd()
        mnem = 'CSRST' if ext else 'CSRLD'
        return f'{mnem} #{idx}', cur, w, imm

    mnem, it = _OPMAP.get((first, ext), (f'???{first:X}{"x" if ext else ""}', None))

    new_w, new_imm = w, imm

    if it == 'cfg':
        lo, hi = rd(), rd()
        v = lo | (hi << 4)
        new_w   = v & 0x3
        new_imm = bool(v & 0x8)
        ann = f'; {W_NAMES[new_w]}'
        if new_imm: ann += ', IMM=1'
        return f'CFG #0x{v:02X}{ann}', cur, new_w, new_imm

    if it == 'w':             # LDi
        v = sum(rd() << (4*i) for i in range(wi(w)))
        return f'LDi #0x{v:X}', cur, w, imm

    if it == 'wopt' and imm:  # ALU immediate
        v = sum(rd() << (4*i) for i in range(wi(w)))
        return f'{mnem} #0x{v:X}', cur, w, imm

    if it == 'nopt' and imm:  # BTST immediate (4-bit)
        idx = rd()
        return f'BTST #{idx}', cur, w, imm

    if it == 'brc':
        cond, lo, hi = rd(), rd(), rd()
        imm8 = lo | (hi << 4)
        if imm8 & 0x80: imm8 -= 256
        tgt = (cur + imm8) & 0xFFFF
        return f'BRC #{COND_NAMES[cond]} #{imm8:+d} -> 0x{tgt:04X}', cur, w, imm

    if it == 'xmem':
        f = rd()
        op  = 'ST' if (f>>3)&1 else 'LD'
        am  = ',AM' if (f>>2)&1 else '   '
        dr  = '-'  if (f>>1)&1 else '+'
        ix  = ',IX' if f&1    else '   '
        return f'XMEM #0x{f:X} ({op}{am},{dr}{ix})', cur, w, imm

    return mnem, cur, w, imm


# ─── CPU ─────────────────────────────────────────────────────────────────────

class MISAO_CPU:
    """MISA-O v0 CPU — nibble-based accumulator architecture."""

    def __init__(self, mem_size=0x10000):
        self.mem = bytearray(mem_size)
        self.reset()

    def reset(self):
        self.pc  = 0       # 16-bit nibble address
        self.acc = 0       # accumulator (16-bit internal; W limits effective width)
        self.rs0 = 0       # source register 0 (16-bit)
        self.rs1 = 0       # source register 1 (16-bit)
        self.ra0 = 0       # address register 0 — jump / link (16-bit)
        self.ra1 = 0       # address register 1 — memory base (16-bit)
        self.cfg = 0       # configuration register (8-bit)
        self.ia  = 0       # interrupt page MSB (8-bit)
        self.iar = 0       # interrupt return page MSB (8-bit)
        # Flags
        self.c = 0; self.z = 0; self.n = 0; self.v = 0
        # CSR bank (16 × 16-bit)
        self.csrs = [0] * 16
        self.csrs[0] = 0x0F00  # CPUID: v0, vendor=F (experimental)
        self._halted = False
        self.cycles  = 0
        self.trace   = False

    # ── CFG fields ────────────────────────────────────────────────────────────
    @property
    def W(self):    return self.cfg & 0x3
    @property
    def SIGN(self): return bool(self.cfg & 0x04)
    @property
    def IMM(self):  return bool(self.cfg & 0x08)
    @property
    def IE(self):   return bool(self.cfg & 0x10)
    @property
    def CI(self):   return bool(self.cfg & 0x20)

    def _wbits(self): return 4 if self.W == 0 else (8 if self.W == 1 else 16)
    def _wmask(self): return (1 << self._wbits()) - 1

    # ── ACC width-aware access ────────────────────────────────────────────────
    def get_acc(self):
        return self.acc & self._wmask()

    def set_acc(self, val):
        m = self._wmask()
        self.acc = (self.acc & (0xFFFF ^ m)) | (int(val) & m)

    # ── Memory helpers ────────────────────────────────────────────────────────
    def _rb(self, a):       return self.mem[a & 0xFFFF]
    def _wb(self, a, v):    self.mem[a & 0xFFFF] = int(v) & 0xFF
    def _rw(self, a):       return self._rb(a) | (self._rb(a+1) << 8)
    def _ww(self, a, v):    self._wb(a, v); self._wb(a+1, int(v) >> 8)

    def _rn(self, na):
        """Read nibble at nibble address na."""
        b = self.mem[(na >> 1) & 0xFFFF]
        return (b >> 4) & 0xF if (na & 1) else b & 0xF

    def _fn(self):
        """Fetch one nibble and advance PC."""
        v = self._rn(self.pc)
        self.pc = (self.pc + 1) & 0xFFFF
        return v

    def _fi(self, n):
        """Fetch n nibbles as little-endian unsigned value."""
        return sum(self._fn() << (4*i) for i in range(n))

    # ── CSR ──────────────────────────────────────────────────────────────────
    def csr_r(self, i):
        i &= 0xF
        if i == 0: return self.csrs[0]           # CPUID (RO)
        if i == 1:                                # CORECFG
            return self.cfg | (self.c<<8) | (self.z<<9) | (self.n<<10) | (self.v<<11)
        if i == 8: return self.ia                 # INTADDR
        return self.csrs[i]

    def csr_w(self, i, v):
        i &= 0xF; v &= 0xFFFF
        if i == 0: return                         # CPUID read-only
        if i == 1: self.cfg = v & 0xFF; return   # CORECFG: flags portion is RO
        if i == 8: self.ia  = v & 0xFF; return   # INTADDR
        self.csrs[i] = v

    # ── Flag helpers ──────────────────────────────────────────────────────────
    def _upd_zn(self, r, bits):
        self.z = 1 if (r & ((1<<bits)-1)) == 0 else 0
        self.n = (r >> (bits-1)) & 1

    def _do_add(self, a, b, bits, sub=False, ci=False):
        """Compute a±b with carry/borrow; update all flags. Returns result."""
        mask = (1 << bits) - 1
        cin  = self.c if (ci and self.CI) else 0
        sa   = (a >> (bits-1)) & 1
        sb   = (b >> (bits-1)) & 1

        if sub:
            full = a - b - cin
            self.c = 1 if full < 0 else 0
            self.v = 1 if (sa != sb and ((full & mask) >> (bits-1)) & 1 != sa) else 0
        else:
            full = a + b + cin
            self.c = (full >> bits) & 1
            self.v = 1 if (sa == sb and ((full & mask) >> (bits-1)) & 1 != sa) else 0

        r = full & mask
        self.z = 1 if r == 0 else 0
        self.n = (r >> (bits-1)) & 1
        return r

    def _eval_cond(self, cc):
        c, z, n, v = self.c, self.z, self.n, self.v
        return [
            True,           # AL
            z==1,           # EQ
            z==0,           # NE
            c==1,           # CS
            c==0,           # CC
            n==1,           # MI
            n==0,           # PL
            v==1,           # VS
            v==0,           # VC
            c==0 and z==0,  # HI
            c==1 or  z==1,  # LS
            n==v,           # GE
            n!=v,           # LT
            z==0 and n==v,  # GT
            z==1 or  n!=v,  # LE
            False,          # reserved
        ][cc & 0xF]

    # ── Operand fetch (RS0 or W-immediate) ───────────────────────────────────
    def _get_b(self):
        """Return second operand: immediate (if IMM) or RS0, both W-masked."""
        mask = self._wmask()
        if self.IMM:
            return self._fi(self._wbits() // 4) & mask
        return self.rs0 & mask

    # ── Instructions ─────────────────────────────────────────────────────────
    def _i_add(self, ext):      # ADD / SUB
        bits = self._wbits()
        r = self._do_add(self.get_acc(), self._get_b(), bits, sub=ext, ci=True)
        self.set_acc(r)

    def _i_incdec(self, ext):   # INC / DEC
        bits = self._wbits(); mask = self._wmask(); a = self.get_acc()
        sa = (a >> (bits-1)) & 1
        if ext: full = a - 1; self.c = 1 if full < 0 else 0
        else:   full = a + 1; self.c = (full >> bits) & 1
        r = full & mask
        self.v = 1 if sa != (r >> (bits-1)) & 1 else 0
        self._upd_zn(r, bits); self.set_acc(r)

    def _i_and(self, ext):      # AND / INV
        bits = self._wbits(); a = self.get_acc()
        r = (~a & self._wmask()) if ext else (a & self._get_b())
        self._upd_zn(r, bits); self.set_acc(r)

    def _i_or(self, ext):       # OR / XOR
        bits = self._wbits()
        r = self.get_acc() ^ self._get_b() if ext else self.get_acc() | self._get_b()
        self._upd_zn(r, bits); self.set_acc(r)

    def _i_shift(self, ext):    # SHL / SHR
        bits = self._wbits(); mask = self._wmask(); v = self.get_acc()
        if ext: self.c = v & 1;           r = (v >> 1) & mask
        else:   self.c = (v>>(bits-1))&1; r = (v << 1) & mask
        self._upd_zn(r, bits); self.set_acc(r)

    def _i_btst(self, ext):     # BTST / TST
        if ext:  # TST
            bits = self._wbits(); a = self.get_acc()
            m = self._get_b()
            tmp = a & m
            self.c = 1 if tmp != 0 else 0
            self.z = 1 if tmp == 0 else 0
            self.n = (tmp >> (bits-1)) & 1
        else:  # BTST — bit index addresses full 16-bit register
            idx = (self._fn() if self.IMM else self.rs0) & 0xF
            bit = (self.acc >> idx) & 1
            self.c = bit; self.z = 1 - bit

    def _i_brc(self, ext):      # BRC / CMP
        if ext:  # CMP — subtract without writing ACC
            self._do_add(self.get_acc(), self._get_b(), self._wbits(), sub=True, ci=True)
        else:  # BRC
            cond = self._fn(); lo = self._fn(); hi = self._fn()
            imm8 = lo | (hi << 4)
            if imm8 & 0x80: imm8 -= 256
            if self._eval_cond(cond):
                self.pc = (self.pc + imm8) & 0xFFFF

    def _i_jal(self, ext):      # JAL / JMP
        if ext:  # JMP
            self.pc = self.ra0
        else:    # JAL — atomic read-before-write on RA0
            target  = self.ra0
            self.ra0 = self.pc   # save return address in RA0
            self.pc  = target    # jump to target

    def _i_cfg(self, ext):      # CFG / RETI
        if ext:  # RETI
            base = self.iar << 8
            self.pc  = self._rw(base + 0x00)  # stored as nibble address
            self.cfg = self._rb(base + 0x02)
            fl = self._rb(base + 0x03)
            self.c, self.z, self.n, self.v = (fl>>0)&1,(fl>>1)&1,(fl>>2)&1,(fl>>3)&1
            self.ia  = self._rb(base + 0x04)
            self.iar = self._rb(base + 0x05)
            self.ra0 = self._rw(base + 0x06)
            self.acc = self._rw(base + 0x08)
        else:  # CFG #imm
            self.cfg = self._fi(2) & 0xFF

    def _i_racc(self, ext):     # RACC/RRS or CSRLD/CSRST
        w = self.W
        if w == 2:  # LK16 → CSR access
            idx = self._fn()
            if ext: self.csr_w(idx, self.acc)
            else:   self.acc = self.csr_r(idx)
        else:  # rotate full 16-bit register right by W bits
            amt = self._wbits()          # 4 for UL, 8 for LK8, 16 for SPE
            if ext:  # RRS
                v = self.rs0 & 0xFFFF
                self.rs0 = ((v >> amt) | (v << (16 - amt))) & 0xFFFF
            else:    # RACC
                v = self.acc & 0xFFFF
                self.acc = ((v >> amt) | (v << (16 - amt))) & 0xFFFF

    def _i_rss(self, ext):      # RSS / RSA
        if ext: self.ra0, self.ra1 = self.ra1, self.ra0
        else:   self.rs0, self.rs1 = self.rs1, self.rs0

    def _i_ss(self, ext):       # SS / SA
        if ext:  # SA — full 16-bit swap ACC ↔ RA0
            self.acc, self.ra0 = self.ra0, self.acc
        else:    # SS — W-width swap ACC ↔ RS0
            mask = self._wmask()
            av = self.acc & mask;  rv = self.rs0 & mask
            self.set_acc(rv)
            self.rs0 = (self.rs0 & (0xFFFF ^ mask)) | av

    def _i_ldi(self, ext):      # LDi / SWI
        if not ext:
            self.set_acc(self._fi(self._wbits() // 4))
        # SWI: trigger software interrupt (interrupt profile)
        # stub — treat as NOP in minimal implementation

    def _i_xmem(self, ext):     # XMEM / MCPY
        if ext:  # MCPY — src=RA1, dst=RA0 (RA1 is now memory base)
            cnt = self.rs1 if self.rs1 < 0x8000 else self.rs1 - 0x10000
            while cnt != 0:
                if cnt > 0:
                    self._wb(self.ra0, self._rb(self.ra1))
                    self.ra1 = (self.ra1 + 1) & 0xFFFF
                    self.ra0 = (self.ra0 + 1) & 0xFFFF
                    cnt -= 1
                else:
                    self.ra1 = (self.ra1 - 1) & 0xFFFF
                    self.ra0 = (self.ra0 - 1) & 0xFFFF
                    self._wb(self.ra0, self._rb(self.ra1))
                    cnt += 1
            self.rs1 = 0
            return

        func = self._fn()
        op, am, dr, ix = (func>>3)&1, (func>>2)&1, (func>>1)&1, func&1
        w = self.W; stride = 2 if w == 2 else 1

        if am and dr:  # pre-decrement
            if ix: self.ra0 = (self.ra0 - stride) & 0xFFFF   # auto-modify offset (RA0)
            else:  self.ra1 = (self.ra1 - stride) & 0xFFFF   # auto-modify base (RA1)

        addr = ((self.ra1 + self.ra0) & 0xFFFF) if ix else self.ra1

        if op == 0:  # Load
            if   w == 2: self.acc = self._rw(addr)
            elif w == 1: self.acc = (self.acc & 0xFF00) | self._rb(addr)
            else:        self.acc = (self.acc & 0xFFF0) | (self._rb(addr) & 0xF)
        else:        # Store
            if   w == 2: self._ww(addr, self.acc)
            elif w == 1: self._wb(addr, self.acc & 0xFF)
            else:        self._wb(addr, (self._rb(addr) & 0xF0) | (self.acc & 0xF))

        if am and not dr:  # post-increment
            if ix: self.ra0 = (self.ra0 + stride) & 0xFFFF   # auto-modify offset (RA0)
            else:  self.ra1 = (self.ra1 + stride) & 0xFFFF   # auto-modify base (RA1)

    # ── Interrupt entry ───────────────────────────────────────────────────────
    def _take_interrupt(self):
        base = self.ia << 8
        self._ww(base + 0x00, self.pc)
        self._wb(base + 0x02, self.cfg)
        self._wb(base + 0x03, self.c|(self.z<<1)|(self.n<<2)|(self.v<<3))
        self._wb(base + 0x04, self.ia)
        self._wb(base + 0x05, self.iar)
        self._ww(base + 0x06, self.ra0)
        self._ww(base + 0x08, self.acc)
        self.iar = self.ia
        self.cfg &= 0xEF  # clear IE
        self.pc  = ((self.ia << 8) + 0x10) * 2  # ISR entry as nibble address

    # ── Dispatch ─────────────────────────────────────────────────────────────
    _DISPATCH = {
        0x0: lambda s,e: None,        # NOP
        0x1: lambda s,e: s._i_add(e),
        0x9: lambda s,e: s._i_incdec(e),
        0x5: lambda s,e: s._i_and(e),
        0xD: lambda s,e: s._i_or(e),
        0x3: lambda s,e: s._i_shift(e),
        0xB: lambda s,e: s._i_btst(e),
        0x7: lambda s,e: s._i_brc(e),
        0xF: lambda s,e: s._i_jal(e),
        0x2: lambda s,e: s._i_cfg(e),
        0x6: lambda s,e: s._i_racc(e),
        0xA: lambda s,e: s._i_rss(e),
        0xE: lambda s,e: s._i_ss(e),
        0x4: lambda s,e: s._i_ldi(e),
        0xC: lambda s,e: s._i_xmem(e),
    }

    def _exec(self, op, ext):
        if op == 0x8:
            if ext: self._halted = True      # WFI — halt in simulator
            else:   self._exec(self._fn(), True)   # XOP prefix
        else:
            self._DISPATCH[op](self, ext)

    def step(self):
        if self._halted: return False
        if self.trace:
            print(f'  PC={self.pc:04X}h ', end='')
        self.cycles += 1
        op = self._fn()
        self._exec(op, False)
        return True

    def run(self, max_cycles=10_000_000):
        while not self._halted and max_cycles > 0:
            self.step(); max_cycles -= 1
        return self._halted

    # ── Load / inspect ────────────────────────────────────────────────────────
    def load(self, data: bytes, byte_addr: int = 0):
        """Load binary data at byte_addr; set PC to that address."""
        for i, b in enumerate(data):
            self.mem[(byte_addr + i) & 0xFFFF] = b
        self.pc = byte_addr * 2  # convert byte address → nibble address

    def dump_regs(self) -> str:
        return (
            f"  PC ={self.pc:04X}h  ACC={self.acc:04X}h  "
            f"RS0={self.rs0:04X}h  RS1={self.rs1:04X}h\n"
            f"  RA0={self.ra0:04X}h  RA1={self.ra1:04X}h\n"
            f"  CFG={self.cfg:02X}h  W={W_NAMES[self.W]:<4}  "
            f"CI={self.CI:d} IMM={self.IMM:d} SIGN={self.SIGN:d} IE={self.IE:d}\n"
            f"  FLAGS  C={self.c} Z={self.z} N={self.n} V={self.v}  "
            f"IA={self.ia:02X}h IAR={self.iar:02X}h\n"
            f"  GPR1={self.csrs[2]:04X}h  GPR2={self.csrs[3]:04X}h  "
            f"GPR3={self.csrs[4]:04X}h   cycles={self.cycles}"
        )

    def dump_mem(self, byte_addr: int, length: int = 64) -> str:
        lines = []
        for row in range(0, length, 16):
            a  = byte_addr + row
            bs = [self.mem[(a+i) & 0xFFFF] for i in range(min(16, length-row))]
            hx = ' '.join(f'{b:02X}' for b in bs)
            ac = ''.join(chr(b) if 32 <= b < 127 else '.' for b in bs)
            lines.append(f'  {a:04X}h: {hx:<48}  {ac}')
        return '\n'.join(lines)

    def disasm(self, naddr: int = None, count: int = 10) -> str:
        """Disassemble count instructions from naddr (nibble address)."""
        if naddr is None: naddr = self.pc
        w, imm = self.W, self.IMM
        lines  = []
        for _ in range(count):
            start = naddr
            text, naddr, w, imm = disasm_one(self._rn, naddr, w, imm)
            mark = '>' if start == self.pc else ' '
            # Show byte address alongside nibble address for readability
            lines.append(f'  {mark} {start:04X}h(n) / {start>>1:04X}h(b)  {text}')
        return '\n'.join(lines)
