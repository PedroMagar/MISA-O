# MISA-O
**My ISA Version 0** is a 4-bit MISC ISA made to be functional.
>The specification is under review...

## Architecture
MISA-O is a compact 4-bit MISC accumulator ISA featuring variable-length encoding (nibble or byte immediates) and an **XOP** prefix for extensions.
It uses a unified **XMEM** class for memory access (load/store with optional post-increment).
The architecture includes one program counter, four 4-bit accumulators, two 16-bit source registers, and two 16-bit address registers.
Accumulators can be linked into wider configurations (2×8-bit or 1×16-bit), while logic and arithmetic operations act primarily on the active accumulator.

### Characteristics:
- 1x16-bit PC (Program Counter) register.
- 1x8-bit IA (Interrupt Address) register.
- 1x8-bit IAR (Interrupt Address Return) register.
- 4x4-bit ACC (Accumulator) register.
- 2x16-bit RS (Register Source) register.
- 2x16-bit RA (Address) register.
  - RA0: Active address.
  - RA1: Return address.
- 1x8-bit CFG (Configuration) register.
  - [7]: CI - Carry-in, (0: disable / 1: enable). Reset: 0 (disable).
    - 0: Carry-in = 0 (ignore carry, default)
    - 1: Carry-in = C flag (use carry)
  - [6]: BW - Branch immediate width. Reset: 0 (imm4).
    - 0: imm4 (4-bit total)
    - 1: imm8 (8-bit total)
  - [5]: BRS - Branch relative scale. Reset: 0 (<<0).
    - 0: shift by 0, 1-byte step (Default).
    - 1: shift by 2, 4-byte step.
  - [4]: IE - Interrupts (0: disable / 1: enable). Reset: 0 (disable).
  - [3]: IMM - Immediate instruction mode (0: disable / 1: enable). Reset: 0 (disable).
  - [2]: SIGN - Signed mode (1: signed / 0: unsigned). Reset: 0 (unsigned).
  - [1:0]: W - LINK - Link Mode:
    - 2b00: UL (Unlinked) - 4-bit mode (Default).
    - 2b01: LK8 (Link 8) - 8-bit mode.
    - 2b10: LK16 (Link 16) - 16-bit mode.
    - 2b11: SPE - Special mode (reserved for custom profile).

#### CFG Table:
| Bit | Name     | Default | Description                                                                                |
|-----|----------|---------|--------------------------------------------------------------------------------------------|
|  7  | Reserved |    0    | Reads as 0, writes ignored.                                                                |
|  6  | BW       |    0    | Branch immediate width: 0=imm4, 1=imm8                                                     |
|  5  | BRS      |    0    | Branch relative scale: 0=×1, 1=×4 (<<2)                                                    |
|  4  | IE       |    0    | Interrupt enable                                                                           |
|  3  | IMM      |    0    | When set, selected ALU opcodes use an embedded immediate instead of RS0 as second operand. |
|  2  | SIGN     |    0    | Signed arithmetic mode                                                                     |
| 1:0 | W (LINK) |   00    | Accumulator link width: UL(4), LK8, LK16, reserved                                         |


## Instructions
The following table lists the architecture instructions:

|Binary| Default  | Extended | Description                                          |
|------|----------|----------|------------------------------------------------------|
| 0001 |ADD       |SUB       | Add / Sub                                            |
| 1001 |INC       |DEC       | Increment / Decrement                                |
| 0101 |AND       |INV       | AND / Invert                                         |
| 1101 |OR        |XOR       | OR / XOR                                             |
| 0011 |SHL       |SHR       | Shift Left / Right                                   |
| 1011 |BTST      |TST       | Bit Test / Test                                      |
| 0111 |BEQz      |BC        | Branch if Equal Zero / Branch if Carry               |
| 1111 |JAL       |JMP       | Jump and Link / Jump                                 |
| 0010 |CMP       |**CFG**   | Compare / Swap Configuration                         |
| 0110 |RACC      |RRS       | Rotate Accumulator/ Rotate Register Source 0         |
| 1010 |RSS       |RSA       | Rotate Stack Source/Address                          |
| 1110 |SS        |SA        | Swap Accumulator with Source/Address                 |
| 0100 |LDi       |**CLC**   | Load Immediate / Clear Carry                         |
| 1100 |XMEM      |**RSV**   | Extended Memory Operations / Reserved for extensions |
| 1000 |XOP       |**RSV**   | Extended Operations / Reserved for extensions        |
| 0000 |NOP       |**RSV**   | No Operation / Reserved for extensions               |

Notes:
- \* : Not mandatory instructions.
- **Bold**: Newly added / under review.
- **RACC/RRS**: In LK16 mode, their opcode is reused for **CSRLD/CSRST**, and no rotation is available at 16-bit width.
- **CLC**: The **CLC** instruction (previously **CC**) is under consideration for removal. With the introduction of the CI (Carry-In) flag in CFG, the architecture can define a default behavior where arithmetic operations ignore the carry flag unless explicitly enabled. When CI = 0, the carry-in is forced to zero, making arithmetic deterministic without requiring explicit flag-clearing instructions. This removes the need for a dedicated carry-clear opcode while preserving full support for multi-precision arithmetic when CI = 1. Equivalent software patterns (e.g., `LDi 0` followed by `SHL`) remain available if explicit carry manipulation is required.
- **CFG**: The **CFG** instruction is under review to be promoted from an extended opcode to a default instruction. The original motivation for keeping CFG in the extended space—preserving a fixed 16-bit encoding for alignment—proved weak, as the MISA-O ISA is fundamentally nibble-oriented and already encourages flexible instruction sizing. Promoting CFG to a default opcode simplifies the architectural model, reflects its central role in execution semantics, and reduces mental and implementation overhead without increasing hardware complexity.

### Special Instruction - LK16 Only

Since ACC/RS0 rotation would became useless at LK16 mode, in LK16 mode this instruction will have a special behavior of accessing CSRs.

| Mode |Binary| Type      | Name     | Description                                                     |
|------|------|-----------|----------|-----------------------------------------------------------------|
| LK16 | 0110 |*Default*  |**CSRLD** | *Load CSR*: loads CSR indexed by **#imm (0–15)** into **ACC**   |
| LK16 | 0110 |*Extended* |**CSRST** | *Store CSR*: writes **ACC** into CSR indexed by **#imm (0–15)** |

### Instruction Class Overview

The MISA-O instruction set is organized primarily by **semantic instruction classes**, rather than by encoding size, execution latency, or microarchitectural constraints. This organization aims to make the ISA easier to read, memorize, and hand-code, while keeping decoding logic simple and implementation-agnostic.

Although the opcode encoding does not enforce strict structural rules (such as immediate presence or instruction length), the opcode space is intentionally arranged to reflect the conceptual role of each instruction.

#### Arithmetic Operations

Arithmetic instructions form the foundation of the ALU and are presented first. These operations modify numeric values and typically affect arithmetic flags.

* **ADD / SUB** – Addition and subtraction
* **INC / DEC** – Increment and decrement

These instructions represent the most common numeric operations and are therefore prioritized in the opcode map.

#### Logical Operations

Logical instructions perform boolean operations on registers or operands, operating at the bitwise level without implying numeric magnitude.

* **AND / INV** – Bitwise AND and inversion
* **OR / XOR** – Bitwise OR and exclusive OR

Logical operations are grouped separately from arithmetic operations, following common industry conventions.

#### Bit Manipulation Operations

Bit manipulation instructions operate on individual bits or bit positions. These instructions are frequently used to prepare conditions for control flow.

* **SHL / SHR** – Logical shift left and right
* **BTST / TST** – Bit test and general test

Shifts and tests are grouped together as low-level bit-oriented operations, often used in conjunction with conditional branches.

#### Control Flow Operations

Control flow instructions alter the program counter and define execution paths.

* **BEQz / BC** – Conditional branches
* **JAL / JMP** – Unconditional jumps and call-like control transfers

All instructions that may modify the program counter are grouped under the `x111` opcode pattern, making control-flow instructions easy to identify.

#### Architectural and Structural Operations

Instructions in this class affect architectural state, configuration, or execution structure rather than performing direct data processing.

* **CC / CFG** – Flag control and configuration manipulation
* **RACC / RRS**, **RSS / RSA**, **SS / SA** – Register, stack, and accumulator manipulation
* **LDi / CMP** – Immediate load and comparison
* **XMEM / RETI**, **XOP / SWI**, **NOP / WFI**

This class intentionally groups instructions that are more architectural or structural in nature.
Notably, **CMP** is placed alongside **LDi** due to encoding constraints, even though it semantically belongs to the comparison/test family. This placement is a pragmatic compromise and does not imply semantic equivalence between immediate loading and comparison.

#### Design Philosophy Note

The instruction class organization is intended to aid **human understanding and manual assembly**, not to impose microarchitectural constraints. Implementations are free to decode and execute instructions independently of their class grouping, and no assumptions about instruction length, latency, or internal pipeline behavior are implied by this classification.

## Main Instructions:
- **Not Mandatory / Custom Instructions**: Opcodes marked “not mandatory” may be used for custom extensions by implementers. Code that uses them is not compatible with baseline MISA-O cores.
- **INV**: `ACC ← ~ACC` within the active width W (4/8/16); *flags unchanged*.
- **ADD/ADDI**: `ACC ← ACC + OP2` within the active width W (4/8/16); updates `C` with carry-out; respect carry-in.
  - If `IMM = 0`: `OP2 = RS0`.
  - If `IMM = 1`: `OP2 = imm_W` (the immediate value zero-extended to W bits).
- **SUB/SUBI**: `ACC ← ACC - OP2` within the active width W (4/8/16); updates `C` with borrow; respect carry-in.
  - If `IMM = 0`: `OP2 = RS0`.
  - If `IMM = 1`: `OP2 = imm_W`.
- **AND/ANDI**: `ACC ← ACC & OP2` within the active width W (4/8/16); *flags unchanged*.
  - If `IMM = 0`: `OP2 = RS0`.
  - If `IMM = 1`: `OP2 = imm_W`.
- **OR/ORI**: `ACC ← ACC | OP2` within the active width W (4/8/16); *flags unchanged*.
  - If `IMM = 0`: `OP2 = RS0`.
  - If `IMM = 1`: `OP2 = imm_W`.
- **XOR/XORI**: `ACC ← ACC ^ OP2` within the active width W (4/8/16); *flags unchanged*.
  - If `IMM = 0`: `OP2 = RS0`.
  - If `IMM = 1`: `OP2 = imm_W`.
- **INC/DEC**: Increment/Decrement ACC by 1; updates `C` with carry-out/borrow; carry-in is always treated as 0.
- **SHL/SHR**: Shift ACC Left/Right by 1 bit; the outgoing bit goes to Carry, and the vacated side is filled with 0.
- **RACC/RRS**: Rotate Accumulator / Register Source - It rotates ACC/RS0 by W bits (4/8), wrapping around; in LK16 it has no effect (NOP).
- **RSS/RSA**: It will treat RS/RA as a stack and rotate it *(currently looks like a swap, but later on if more registers were added it will truly rotate)*.
- **SS**:  Swaps the contents of **ACC** *with* source operand register 0 (**RS0**), respecting the active **W** (word-size) configuration: `ACC ↔ RS0 (W-bits)`.
- **SA**:  Swaps the full contents of **ACC** *with* address register 0 (**RA0**) (full 16-bit), ignoring the **W** size configuration: `ACC ↔ RA0 (16-bits)`.
- **JAL/JMP**: All jumps will be based on register RA0, but linking would be saved on RA1.
  - **JAL**: `RA1 ← PC_next`; `PC ← RA0`
  - **JMP**: `PC ← RA0`
- **CFG #imm**: Loads the *immediate* (**#imm**) value into the **CFG** register. The **CFG** register can also be accessed at `CSR 0` for reading. *(Useful for changing link width (W) or enabling features without register overhead.)*
- **CMP**: Compares **ACC** with **RS0** by subtraction (respecting **W**), updates carry/borrow and an internal ZERO flag. If the next instruction is **BEQz**, it uses this ZERO flag instead of reading ACC directly. `ZERO` flag will clear itself if the next instruction is not BEQz.
- **Branches** (PC-relative): If (cond): **PC ← PC_next + ( *sign_extend*(BW ? imm8 : imm4) << (BRS ? 2 : 0) )**; Else: **PC ← PC_next**; *flags unchanged*. **ATTENTION**: **BEQz** has a special behaviour if it's executed after a **CMP** instruction.
  - **BEQz #imm**: If preceded by CMP: branch if `ZERO=1`. Else: branch if `ACC==0`. Always clears ZERO.
  - **BC   #imm**: Branch if `Carry C == 1`.
  - **BTST/BTSTI**:
    - If `IMM = 0`: `idx = RS0[3:0]`.
    - If `IMM = 1`: `idx = imm4` (low 4 bits of the immediate).
    - Then: tests bit `ACC[idx]`; sets `C = ACC[idx]`; `ACC` not written.
  - **TST/TSTI**:
    - If `IMM = 0`: `mask = RS0`.
    - If `IMM = 1`: `mask = imm_W` (immediate zero-extended to W bits).
    - Then: `tmp = ACC & mask`; sets `C = 1` if `tmp != 0`, else `C = 0`; `ACC` not written (limited by current link width).
- **XOP**: Executes next instruction as Extended Operation.
- **XMEM #f**: Extended Memory Operations (opcode 1100 + 4-bit function):
  - Function:
    - `f[3]`: **OP**: 0=Load, 1=Store
    - `f[2]`: **AM**: 0=none, 1=post-increment
    - `f[1]`: **DIR**:  0 = +stride (increment), 1 = −stride (decrement)
    - `f[0]`: **AR**: 0=RA0, 1=RA1
  - Semantics (width W from LINK, little-endian):
    - `addr` = `(AR ? RA1 : RA0) ; alias of the selected register`
    - `stride` = `(W == 16 ? 2 : 1) ; bytes (UL & LK8: 1B; LK16: 2B)`
    - **LD**: 
      - **LK16**: `ACC ← { [addr+1], [addr] } ; little-endian`
      - **LK8**: `ACC[7:0] ← [addr]`
      - **UL**: `ACC[3:0] ← [addr][3:0]`
    - **SW**:
      - **LK16**: `[addr] ← ACC[7:0]; [addr+1] ← ACC[15:8]`
      - **LK8**: `[addr] ← ACC[7:0]`
      - **UL**: `tmp ← [addr]; tmp[3:0] ← ACC[3:0]; [addr] ← tmp`
    - If `AM=1`: `addr ← addr + (DIR ? −stride : +stride)`
    - Flags: **unchanged**.
  - **CSRLD #imm**: Loads CSR into ACC (more details on CSR section).
  - **CSRST #imm**: Write ACC into CSR (more details on CSR section).

### **Carry Flag (C)**

The carry flag (C) is **always updated** by arithmetic and shift operations, but it is **consumed as carry-in when CI is enable**.

- **ADD / INC**: `C = carry-out`
- **SUB / DEC**: `C = NOT(borrow-out)`
- **SHL / SHR**: `C = expelled bit`

Its role as an arithmetic input is controlled by the **CI** flag in `CFG`.

* When `CI = 0` (default), carry-in is ignored and treated as zero.
* When `CI = 1`, carry-in is taken from the current value of `C`.

This design provides explicit, mode-controlled carry propagation without requiring additional arithmetic opcodes, while keeping the default behavior simple and deterministic.

### Branch:

- BW/BRS are global (from CFG). Keep them constant within a function.
- With imm4 and large scaling (e.g., <<2), targets should be aligned accordingly to avoid padding.
- Taking a branch does not modify flags and clears any pending XOP.
 
## CSR Bank (Control & Extensions)

MISA-O defines a small CSR (Control and Status Register) bank to expose core configuration, flags and optional extension state without bloating the general register file. The bank is addressed by a 4-bit index (0–15), each CSR being 16-bit wide.

Access is performed through two instructions:

- **CSRLD #idx**: `ACC ← CSR[idx]` (16-bit read into ACC)
- **CSRST #idx**: `CSR[idx] ← ACC` (16-bit write from ACC)

In **UL/LK8** modes, the opcodes `RACC` / `RRS` behave as rotate instructions as described earlier. In **LK16** mode, the same opcodes may be reassigned to `CSRLD` / `CSRST`, using an immediate nibble as CSR index.

### CSR implementation profiles

Two implementation profiles are envisaged:

- **Compact profile**: only the minimal CSR set is implemented (CSR0 is mandatory). All unimplemented CSRs read as `0` and ignore writes. This keeps area and complexity close to the original MISA-O core.

- **Full profile**: additional CSRs are implemented for richer interrupt handling, debugging and arithmetic extensions (MAD profile). Software must not rely on any CSR beyond CSR0 unless the target profile is explicitly known.

### CSR layout

The following layout is recommended, but only CSR0 is mandatory for baseline compliance:

| Idx | Name     | Description                                        | Profile   |
|-----|----------|----------------------------------------------------|-----------|
| 0   | CORECFG  | Core configuration and flags (CFG + C/Z/N/V)       | required  |
| 1   | TIMER    | Cycle/instruction counter (16-bit free-running).   | time      |
| 2   | TIMERCMP | Comparison value for the Timer.                    | full      |
| 3   | INTCTRL  | Unified control: Status, Masks, and Watchdog.      | required  |
| 4   | INTADDR  | Interrupt base page (IA alias)                     | interrupt |
| 5   | GPR1     | General-Purpose Register                           | extended  |
| 6   | GPR2     | General-Purpose Register                           | extended  |
| 7   | GPR3     | General-Purpose Register                           | extended  |
| 8   | CPUID    | CPUID                                              | required  |
| 9–15| RSV      | Reserved for extensions                            | —         |

#### CSR0 – CORECFG (Core Configuration)
Combines the architectural **CFG** register (Low Byte) with the read-only ALU flags (High Byte).

- **Bits [7:0] – CFG (R/W)**: maps directly to the core configuration (Branch Width, Scale, Interrupt Enable, Immediate Mode, Sign Mode, Link Mode).
- Bits [11:8] - ALU flags (RO):
  - [8]  `C` → Carry flag
  - [9]  `Z` → Zero flag
  - [10] `N` → Negative flag (MSB of the result according to W)
  - [11] `V` → Overflow flag (signed overflow for ADD/SUB)
- Bits [15:12] → reserved (read as 0, writes ignored).

#### CSR1 – TIMER (Cycle Counter)
A 16-bit free-running counter that increments once per **retired instruction** (recommended). Minimal implementations may instead increment once per clock cycle, but software must treat TIMER as an opaque monotonic counter.
* **Read**: Returns current counter value.
* **Write**: Loads a new value (e.g., to reset or create delayed events).
* **Overflow**: Wraps from 0xFFFF to 0x0000 silently.

#### CSR2 – TIMERCMP (Timer Compare)

Holds the comparison value for the system timer.

- On each increment of TIMER, if the value transitions from `TIMER != TIMERCMP` to `TIMER == TIMERCMP`, hardware sets the T_P (Timer Pending) bit in INTCTRL.
- T_P remains set until cleared by software (write-1-to-clear).
- Changing TIMERCMP does not automatically clear T_P.

On a match event:

1. If INTCTRL.WDOG = 1, the core performs a watchdog reset.
2. Else, if INTCTRL.T_IE = 1 and CFG.IE = 1, a timer interrupt is raised
   (T_P is set and the core vectors to the ISR).

#### CSR3 – INTCTRL (Interrupt Control & Watchdog)

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

#### CSR4 – INTADDR (Interrupt Base Address)

Alias of the architectural IA register.

- Bits [7:0]  – IA (Interrupt Address page MSB).
- Bits [15:8] – Reserved.

CSRLD #4 reads IA; CSRST #4 writes IA using ACC[7:0]. No extra physical register is required.

#### CSR5-7 – GPR

CSRs 5–7 define up to three **Generic Purpose Registers (GPR1–GPR3)**.

These registers are intended to assist calling conventions, reduce memory traffic, and enable more efficient compilation of non-leaf functions. They are accessed exclusively through CSR instructions and do not alter the core register file or datapath.

Implementations may omit these registers in compact profiles; unimplemented GPR CSRs read as zero and ignore writes.

| Idx | Name     | Description                                        | Profile   |
|-----|----------|----------------------------------------------------|-----------|
| 5   | GPR1     | General-Purpose Register                           | extended  |
| 6   | GPR2     | General-Purpose Register                           | extended  |
| 7   | GPR3     | General-Purpose Register                           | extended  |

#### CSR8 – CPUID

**CSR8** is reserved as **CPUID**.

It provides implementation identification and capability discovery. Writes are ignored. The encoding and meaning of CPUID values are implementation-defined.

#### CSR9-15 - RSV

Reserved CSRs for profiles, extension and design freedom.

---

# Profiles

## Interrupt Profile:

Not mandatory profile to implement interrupt.

### Instructions:
| Mode |Binary| Type      | Name     | Description                                |
|------|------|-----------|----------|--------------------------------------------|
| ALL  | 1100 |*Extended* |**RETI**  | Return from Interrupt                      |
| ALL  | 1000 |*Extended* |**SWI**   | Software Interrupt                         |
| ALL  | 0000 |*Extended* |**WFI**   | Wait-For-Interrupt                         |

### Mapping:
| Offset    | Description                | Width |
| --------- | -------------------------- | ----- |
| 0x00      | PC_next low/high           | 16b   |
| 0x02      | CFG snapshot               | 8b    |
| 0x03      | FLAGS snapshot             | 8b    |
| 0x04–0x0F | Registers and ISR metadata | —     |

### Description:
  - **Interrupts**: *ia* holds the *Interrupt Service Routine* (ISR) page *Most Significant Byte* (MSB). On interrupt:
    - The CPU **stores PC_next, CFG/FLAGS, ACC, RS0/RS1, RA0/RA1** at fixed offsets in page `ia` (see layout below),
    - latches `IAR ← IA`, **clears IE**, clears any pending **XOP**, and
    - **jumps to** `IA<<8 + 0x10` (the ISR entry).
    - Interrupt address register (`IA`) is mapped at `CSR 1`.
  - **WFI\***: Wait-For-Interrupt makes the processor sleep until an interrupt sign is received.
  - **SWI\***: Triggers a software interrupt; flow identical to an external IRQ: autosave on the ia page, latches `IAR←IA`, clears IE (`IE←0`) and jumps to `IA<<8 + 0x10`.
  - **RETI\***: Restores state from the *IAR* page and resumes execution.
    - Base address: **base = IAR << 8**
    - Hardware restores:
      - **PC** ← [base+0x00..0x01]        ; PC_next snapshot
      - **RA1** ← [base+0x0C..0x0D]       ; link/return register
      - **IA**  ← [base+0x0E]             ; interrupt page MSB
      - **IAR** ← [base+0x0F]             ; previous latched page (for nested unwinding)
      - **CFG** ← [base+0x02]             ;
      - **FLAGS** ← [base+0x03]           ;
    - **Not restored by RETI**: **ACC**, **RS0**, **RS1**, **RA0** — the ISR must restore them in software before RETI.
    - After RETI, **IE** follows the IE bit of the active **CFG** (restored or left as set by the ISR).
  - Fixed layout within the ia page:
```
; IA page:
; Saved on interrupt entry:      base = IA  << 8
; RETI reads/restores from page: base = IAR << 8
      +0x00 : PC_next[7:0]
      +0x01 : PC_next[15:8]
      +0x02 : CFG snapshot (8-bit)
      +0x03 : FLAGS snapshot (8-bit)
      +0x04 : ACC (16-bit)
      +0x06 : RS0 (16-bit)
      +0x08 : RS1 (16-bit)
      +0x0A : RA0 (16-bit)
      +0x0C : RA1 (16-bit)
      +0x0E : IA (8-bit)
      +0x0F : IAR (8-bit)
      +0x10 : ISR entry (first instruction executed on entry)
```

---

## Debug Profile

MISA-O does not define a dedicated debug mode or external debug port. Instead, debugging is built on top of the existing **SWI** mechanism and the interrupt context save on the `IA` page.

A typical debug monitor runs as a software ISR (usually the SWI vector) and uses the interrupt frame at `IA<<8` plus the CSR bank to inspect and modify the machine state.

#### Single-step via CORECFG.DBGSTEP

For implementations that support the Debug Profile, bit **DBGSTEP** (bit 12) of `CORECFG` enables **single-step execution**:

- When `DBGSTEP = 1`, `CFG.IE = 1` and the core is **not** currently inside an ISR (`INTCTRL.IN_ISR = 0`), the hardware behaves as follows:
  1. A normal instruction retires (user code).
  2. Before fetching the next instruction, the core triggers a **SWI** (software interrupt), performing the usual context save on the `IA` page.
  3. On entry to this SWI, the hardware **automatically clears DBGSTEP**.

This allows a software debug monitor to implement classic single-step:

- **One-shot step**:
  - In the debug handler, set `DBGSTEP = 1` in `CORECFG` and return with `RETI`.
  - The next user instruction executes, then a SWI brings control back to the monitor.

- **Continuous stepping**:
  - In the debug handler, re-arm `DBGSTEP = 1` before `RETI` to trap again after every instruction.

Cores that do not implement the Debug Profile must treat `DBGSTEP` as read-as-zero / write-ignored and never trigger SWI from it.

#### Using SWI as a software breakpoint

The `SWI` instruction itself remains the preferred software breakpoint primitive: inserting `SWI` in code forces a trap into the debug monitor whenever that instruction is executed.

Combining SWI breakpoints with `DBGSTEP` provides a minimal yet powerful debug facility without additional opcodes or privilege levels.

---

## MAD Profile (Multiply-Add & Derivatives)

The **MAD Profile** is an **optional execution profile** that extends MISA-O with lightweight multiply-accumulate and comparison helpers, targeting fixed-point workloads such as graphics, audio, and DSP-style inner loops.

The profile is **only active when LINK mode = `2’b11` (SPE)**.
In all other link modes, MAD profile opcodes are treated as **NOP**.

To be **MAD Profile compliant**, an implementation must support:

* the **SPE link mode**,
* the **MAD opcode remapping** defined in this section, and
* the architectural semantics described below.

No additional architectural registers are introduced.
All control is encoded **per-instruction** via the immediate nibble, while observable status is limited to existing architectural mechanisms (notably the **Carry flag**).

---

### Non-MAD instructions in SPE mode

All opcodes **not explicitly defined** by the MAD Profile **retain their LK16 architectural semantics** when executed in SPE mode.

In particular:

* CSR access instructions (`CSRLD` / `CSRST`) remain available and behave identically to LK16.
* Memory, control-flow, and non-MAD arithmetic instructions are unaffected.
* SPE imposes **no additional restrictions** beyond MAD opcode remapping.

---

### Operand model

* Multiply operands are taken from **RS0** and **RS1**.
* The accumulator and destination is **ACC**.
* When operating in SPE mode, each source register provides **two independent 8-bit lanes**:

  * **Lane 0**: bits `[7:0]`
  * **Lane 1**: bits `[15:8]`
* Accumulation is always performed in **16-bit precision**.
* Signedness follows the global **`SIGN`** flag in `CFG`.

---

### Instructions

| Mode |Binary| Type       | Name     | Description                               |
|------|------|------------|----------|-------------------------------------------|
| SPE  | 1100 | *Extended* | **MAD**  | Multiply-Add                              |
| SPE  | 1000 | *Extended* | **MAX**  | Maximum                                   |
| SPE  | 0000 | *Extended* | **MIN**  | Minimum                                   |

---

### Instruction semantics

- **MAD #imm**: `ACC ← SAT( ( ACC + (OP1 × OP2) ) >> SHIFT )`; where:
  - `OP1` = selected 8-bit lane of `RS0`
  - `OP2` = selected 8-bit lane of `RS1`
  - Signed or unsigned multiplication follows `SIGN`
  - Accumulation is 16-bit
  - Post-operation shift and saturation are controlled by `#imm`
  - The Carry flag (`C`) reflects the carry-out of the 16-bit accumulation prior to shift and saturation.
  - Saturation or internal overflow conditions may update **implementation-defined** status bits exposed via `CORECFG`
  - Saturation is based on SIGN flag from CFG. If:
    - `SAT=1 & SIGN=Unsigned`: clamp result to [0, 0xFFFF]
    - `SAT=1 & SIGN=Signed`: clamp result to [-32768, +32767]
- **MAX**: `ACC ← max( ACC , RS0 )`; operates on the full 16-bit value. Flags unchanged.
- **MIN**: `ACC ← min( ACC , RS0 )`; operates on the full 16-bit value. Flags unchanged.
- **Others**
  All non-MAD opcodes executed in SPE mode **retain LK16 architectural behavior**, including CSR access.

---

### Immediate format (MAD-exclusive)

The immediate nibble controls MAD operation:

- imm[3:2] — **SHIFT** - Post-operation right shift:
  - `00` = no shift
  - `01` = >> 1
  - `10` = >> 2
  - `11` = >> 4
- imm[1] — **SAT** - Saturation enable:
  - `0` = wrap
  - `1` = saturate
- imm[0] — **LANE** - Operand lane select:
  - `0` = low 8-bit lane
  - `1` = high 8-bit lane

Right shifts are **arithmetic** when `SIGN=1` and **logical** when `SIGN=0`.

---

### Notes and design rationale

* The MAD Profile **does not require a dedicated control CSR**.
* The profile relies exclusively on existing architectural registers (`ACC`, `RS0`, `RS1`).
* Per-instruction immediates enable aggressive inner-loop optimization without global state changes.
* `SIGN` semantics are consistent with the base ISA.
* The `IMM` flag is ignored by `MAD`, as the immediate nibble is always consumed as control.
* Multi-cycle MAD implementations may expose a `BUSY` indication via implementation-defined bits in `CORECFG`; single-cycle implementations may hard-wire it to zero.
* Implementations may internally fuse MAD or decompose it into multiply and add steps, provided architectural results are preserved.
* Unlike MAD, MAX/MIN operate on the full 16-bit scalar value and are intended as clamp helpers rather than lane-wise SIMD operations.
* The SPE link mode is designed as a functional overlay rather than a closed execution state, allowing seamless interleaving of MAD-optimized code and standard LK16 control paths.

---

# Development

The table below lists **candidate instructions** that are *not part of the baseline ISA* but are being evaluated for future inclusion.
These entries **do not represent actual opcode encodings**; the binary field is merely a placeholder layout used to ease migration when promoting candidates into official instructions.

Implementers must **not** rely on these encodings.
When promoted, each instruction will receive a proper unique opcode assignment within the official map.

| Binary (placeholder) | Instruction | Notes                                                             |
| -------------------- | ----------- | ----------------------------------------------------------------- |
| 0000                 | **CLR**     | Proposed *Clear* ACC instruction.                                 |
| 0000                 | **SDI**     | *Send/Signal Interrupt* — software-triggered signaling mechanism. |

**Purpose:**
This table serves only as a **staging area** for instructions under evaluation.
Entries may be changed, merged, promoted or removed without affecting ISA compatibility.
## Reference Implementation
The reference implementation (located at "/design/misa-o_ref.sv") is not made to be performant, efficient, optimal or even synthesizable; its main purpose is to be simple to interpret while also serving as a playground to test the ISA instructions.

### How to run
To run you must have installed icarus verilog (iverilog) and GTKWAVE, open terminal on root directory, from there execute run_tb.bat (windows) or run_tb.sh (linux).

#### Scripts
- misa-o_b.sh: Build script, utilized to see if the project is currently building.
- misa-o_r.sh: Build & Run script, utilized to run the test and to see the results in GTKWAVE, there you can visualize the behavior.

#### Dependencies
- Icarus Verilog (iverilog).
- GTKWAVE (gtkwave).

## Registers Overview

          |-------------------| 
      CFG | 0 0 0 0   0 0 0 0 | 
          |-------------------| 

          |-------------------| 
       IA | 0 0 0 0   0 0 0 0 | 
          |-------------------| 
      IAR | 0 0 0 0   0 0 0 0 | 
          |-------------------| 

          |---------------------------------------| 
       PC | 0 0 0 0   0 0 0 0   0 0 0 0   0 0 0 0 | 
          |---------------------------------------| 

          |---------------------------------------| 
      RA1 | 0 0 0 0   0 0 0 0   0 0 0 0   0 0 0 0 | 
          |---------------------------------------| 
      RA0 | 0 0 0 0   0 0 0 0   0 0 0 0   0 0 0 0 | 
          |---------------------------------------| 

          |--- r3 ------ r2 ------ r1 ------ r0 --| 
      ACC | 0 0 0 0 | 0 0 0 0 | 0 0 0 0 | 0 0 0 0 | 
          |---------------------------------------|

          |---------------------------------------|
      RS0 | 0 0 0 0   0 0 0 0   0 0 0 0   0 0 0 0 |
          |---------------------------------------|
      RS1 | 0 0 0 0   0 0 0 0   0 0 0 0   0 0 0 0 |
          |---------------------------------------| 

## Final Considerations
**NEG**: Started with NEG/Negated instructions/behavior, but was replaced with a more default behavior (**XOP**) that only affects the next instruction, this change allowed for a better compression and a more stable behavior, this will also help on the compiler construction.

**LK**: Link was demoted to be replaced by a more versatile "Swap Configuration", now it's possible to enable auto-increment when reading/writing from/to memory with the advantage of also be able to secure a known working state for the functions.

**Branches**: Planned to be based on RA0, under some consideration it was changed to immediate value. Because of the small quantity of registers this seems more reasonable, but could be changed back to utilize RA0.

**SS/SA & CFG**: SS and SA was initially designed for quick register swapping, this design was adjusted to allow partial swaps respecting **W** (useful for endianness control). To complement this, **CFG** now supports immediate loading, easing state management and reducing register pressure. **SA** remains a full 16-bit swap for address manipulation, as partial swaps provide little benefit in this context.

**OPCODE Changes**: Although freezing the opcode map early would be desirable, during core design it became clear that some instructions could be organized in a more intuitive way. These changes are not intended to improve performance nor simplify decoding logic but to improve semantic grouping and readability of the ISA. By consistently separating common ALU-like operations (`xxx1`) from control, configuration, and architectural instructions (`xxx0`), the instruction set becomes easier to reason about, memorize, and hand-code in assembly. Given the small scope of the project, prioritizing clarity and interpretability over rigid opcode stability was considered a reasonable trade-off.

**Multiply**: The area/power cost of a hardware multiplier is high for this class of core, and the **base opcode map is full**. Comparable minimal CPUs also omit MUL. Software emulation (shift-add) handles 4/8/16-bit cases well, so the practical impact is low. But there is a plan to create an extension (CFG reserved = 1) that will replace non-mandatory instructions by new ones, like **MAD**, DIV, Vector MAD or other arithmetic operations. The idea behind having MUL instruction is to keep open the possibility of an implementation that could run DOOM.

**CSR Bank (Control & Extensions)**: To support richer control, debugging and future extensions, MISA-O also reserves space for a small CSR bank (up to 16 × 16-bit registers, 32 bytes total), exposed via optional `CSRLD`/`CSRST` instructions that reuse the RACC/RRS opcodes in LK16 and use the instruction’s immediate nibble as CSR index (0–15). This CSR bank can host core control bits, extended interrupt state or configuration for the MAD profile and other vendor-specific features, without bloating the baseline register file. As with the arithmetic extensions, CSR access is initially treated as a custom/optional feature to be prototyped and validated before being committed to the core specification.

**MAD Profile**: The *MAD Profile (Multiply-Add & Derivatives)* is an optional execution profile that extends the arithmetic capabilities of MISA-O without impacting the baseline datapath or register model.

The profile introduces a compact multiply-accumulate unit (8-bit × 8-bit → 16-bit accumulate), along with lightweight arithmetic helpers such as MIN and MAX, specifically targeting fixed-point inner loops common in graphics, audio and DSP-style workloads.

MAD operates exclusively in the SPE link mode and relies solely on existing architectural registers (ACC, RS0, RS1), with all control encoded per-instruction via the immediate nibble. The MAD instructions themselves do not require any additional architectural state or control registers.

As an optional profile, MAD allows implementers to trade silicon area and latency for higher arithmetic throughput. Implementations may range from simple multi-cycle designs to fully pipelined units, provided architectural semantics are preserved. The profile is considered architecturally stable and may be adopted independently of other optional execution profiles.
