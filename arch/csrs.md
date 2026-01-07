# CSR Bank (Control & Extensions)

MISA-O defines a small CSR (Control and Status Register) bank to expose core configuration, flags and optional extension state without bloating the general register file. The bank is addressed by a 4-bit index (0–15), each CSR being 16-bit wide.

Access is performed through two instructions:

- **CSRLD #idx**: `ACC ← CSR[idx]` (16-bit read into ACC)
- **CSRST #idx**: `CSR[idx] ← ACC` (16-bit write from ACC)

In **UL/LK8** modes, the opcodes `RACC` / `RRS` behave as rotate instructions as described earlier. In **LK16** mode, the same opcodes are reassigned to `CSRLD` / `CSRST`, using an immediate nibble as CSR index.

## CSR implementation profiles

Two implementation profiles are envisaged:

- **Compact**: only the minimal *required* CSR set is implemented. All unimplemented CSRs read as `0` and ignore writes. This keeps area and complexity close to the original MISA-O core.

- **Baseline**: Default implementation to support rich sowtware stack. Software must not rely on any CSR beyond *required* and *baseline* unless the target profile is explicitly known. Baseline is the recommended minimum target for hosted or compiled languages.

- **Complete**: All profiles with additional CSRs are implemented for richer interrupt handling, debugging and arithmetic extensions.

## CSR Map

| Idx | Name     | Description                                        | Profile   |
|-----|----------|----------------------------------------------------|-----------|
| 0   | CPUID    | CPUID                                              | required  |
| 1   | CORECFG  | Core configuration and flags (CFG + flags)         | required  |
| 2   | GPR1     | General-Purpose Register                           | baseline  |
| 3   | GPR2     | General-Purpose Register                           | baseline  |
| 4   | GPR3     | General-Purpose Register                           | baseline  |
| 5   | TIMER    | Cycle/instruction counter (16-bit free-running).   | time      |
| 6   | TIMERCMP | Comparison value for the Timer.                    | time      |
| 7   | EVTCTRL  | Unified control: Status, Masks, and Watchdog.      | baseline  |
| 8   | INTADDR  | Interrupt base page (IA alias)                     | interrupt |
| 9–15| RSV      | Reserved for extensions                            | —         |

Note: EVTCTRL is present in baseline even if the Interrupt Profile is not implemented; fields related to interrupts read as zero when the profile is absent.

For detail explanation goes to csrs.md

---

### CSR0 – CPUID

**CSR0** is reserved as **CPUID**.

It provides implementation identification and capability discovery. Writes are ignored.

**Format:**

- [15:12] VERSION — Architecture version
  - 0x0 = MISA-O v0.x
  - 0x1 = MISA-O v1.x (future)
  - 0xF = Experimental/custom

- [11:8] PROFILES — Optional profile support (1=present)
  - [11] MAD Profile (multiply-accumulate extensions)
  - [10] Debug Profile (DBGSTEP, debug facilities)
  - [9]  Interrupt Profile (RETI/SWI/WFI, ISR support)
  - [8]  MMU Profile (memory management unit)

- [7:4] VENDOR — Vendor identifier
  - 0x0 = Reference implementation / unspecified
  - 0x1 = Reserved for standardization
  - 0x2-0xE = Vendor-specific (contact registry)
  - 0xF = Experimental / academic

- [3:0] IMPL — Implementation variant (vendor-defined)
  - Encodes implementation-specific features such as:
    - Cache presence/configuration
    - Pipeline depth
    - Acceleration units
    - Custom instruction extensions
    - Performance tier (e.g., 0=minimal, F=high-performance)

**Usage:**
Software queries CPUID at startup to detect available features and
adapt execution paths accordingly.

**Example:**
```assembly
; Check for MAD profile support
CSRLD #0            ; ACC ← CPUID
SS                  ; RS0 ← CPUID (preserve)
LDi #0x0800         ; Mask for MAD bit (bit 11)
AND
BEQz #no_mad        ; Branch if not supported
; Use MAD instructions
```

**Profile Bit Allocation:**
- Bits [11:9] are **standardized** across all MISA-O implementations
- Bit [8] (MMU) is **reserved** for future standardization
- Implementations may expose additional capabilities via **IMPL** field

---

### CSR1 – CORECFG (Core Configuration)

Combines the architectural **CFG** register (Low Byte) with the read-only ALU flags (High Byte).

- **Bits [7:0] – CFG (R/W)**: maps directly to the core configuration (Branch Width, Scale, Interrupt Enable, Immediate Mode, Sign Mode, Link Mode).
- Bits [11:8] - ALU flags (RO):
  - [8]  `C` → Carry flag
  - [9]  `Z` → Zero flag
  - [10] `N` → Negative flag (MSB of the result according to W)
  - [11] `V` → Overflow flag (signed overflow for ADD/SUB)
- Bits [15:12] → reserved (read as 0, writes ignored).

Flags are latched architectural state and reflect the most recent flag-setting instruction.

---

### CSR2-4 – GPR (General-Purpose Registers)

CSRs 2–4 define up to three **General Purpose Registers (GPR1–GPR3)**.

These registers are intended to assist calling conventions, reduce memory traffic, and enable more efficient compilation of non-leaf functions. They are accessed exclusively through CSR instructions and do not alter the core register file or datapath.

| Idx | Name     | Description                                        | Profile   |
|-----|----------|----------------------------------------------------|-----------|
| 2   | GPR1     | General-Purpose Register                           | baseline  |
| 3   | GPR2     | General-Purpose Register                           | baseline  |
| 4   | GPR3     | General-Purpose Register                           | baseline  |

**Typical Usage:**
- GPR1: Stack Pointer (SP) or callee-saved
- GPR2: Temp / staging register
- GPR3: Link Register (LR) or callee-saved

See **Calling Convention** section for details.

---

### CSR5 – TIMER (Cycle Counter)

A 16-bit free-running counter that increments once per **retired instruction** (recommended). Minimal implementations may instead increment once per clock cycle, but software must treat TIMER as an opaque monotonic counter.
* **Read**: Returns current counter value.
* **Write**: Loads a new value (e.g., to reset or create delayed events).
* **Overflow**: Wraps from 0xFFFF to 0x0000 silently.

---

### CSR6 – TIMERCMP (Timer Compare)

Holds the comparison value for the system timer.

- On each increment of TIMER, if the value transitions from `TIMER != TIMERCMP` to `TIMER == TIMERCMP`, hardware sets the T_P (Timer Pending) bit in EVTCTRL.
- T_P remains set until cleared by software (write-1-to-clear).
- Changing TIMERCMP does not automatically clear T_P.

On a match event:

1. If EVTCTRL.WDOG = 1, the core performs a watchdog reset.
2. Else, if EVTCTRL.T_IE = 1 and CFG.IE = 1, a timer interrupt is raised
   (T_P is set and the core vectors to the ISR).

---

### CSR7 – EVTCTRL (Interrupt Control & Watchdog)

Consolidates interrupt enables, pending status, and watchdog policy.

Low Byte [7:0] – Configuration (R/W):

- [0] SW_IE  – Software interrupt enable.
- [1] EXT_IE – External interrupt enable.
- [2] T_IE   – Timer interrupt enable.
- [7] WDOG   – Watchdog mode. When set, a timer match (TIMER == TIMERCMP) causes
               a core reset instead of raising a timer interrupt.

Bits [6:3] are reserved (read as 0, writes ignored).

High Byte [15:8] – Status (R / W1C):

- [8]  IN_ISR  – Core is currently executing inside an ISR.
- [9]  EXT_P   – External interrupt pending.
- [10] T_P     – Timer match pending (set when TIMER == TIMERCMP).
- [11] SW_P    – Software interrupt pending (set by SWI).
- [12] DBGSTEP – Debug single-step (optional):
  - 0: normal execution.
  - 1: **arm single-step** — after the next **non-ISR instruction** retires,
       the core triggers a SWI before fetching the following instruction and
       automatically clears this bit on trap entry.
- [15:13] reserved.

Status bits EXT_P, T_P and SW_P are cleared by writing '1' to their positions (write-one-to-clear). IN_ISR is managed by hardware (RO for software).

Effective enable per source:

- SWI interrupt: taken when CFG.IE = 1 and SW_IE = 1 and SW_P = 1.
- External interrupt: taken when CFG.IE = 1 and EXT_IE = 1 and EXT_P = 1.
- Timer interrupt: taken when CFG.IE = 1, T_IE = 1, WDOG = 0 and T_P = 1.

---

### CSR8 – INTADDR (Interrupt Base Address)

Alias of the architectural IA register.

- Bits [7:0]  – IA (Interrupt Address page MSB).
- Bits [15:8] – Reserved.

CSRLD #8 reads IA; CSRST #8 writes IA using ACC[7:0]. No extra physical register is required.

---

### CSR9-15 - RSV

Reserved CSRs for profiles, extension and design freedom.
