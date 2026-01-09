# MISA-O

**My ISA Version 0** is a compact 4-bit MISC accumulator ISA with nibble-based variable-length encoding.
>The specification is under review.

## Main Docs

- **ISA design**: [README.md](README.md)
- **Calling convention**: [calling_convention.md](arch/calling_convention.md)
- **Design history / rationale**: [history.md](arch/history.md)

### Profiles

- [Interrupt](arch/profiles/interrupt.md)
- [Debug](arch/profiles/debug.md)
- [MAD](arch/profiles/mad.md)

## Reference Implementation

The reference implementation (see `design/misa-o_ref.sv`, under construction) is intentionally simple and may not be optimized or synthesizable. It exists to validate the ISA and serve as a playground for experiments.

## How to run

Dependencies:
- Icarus Verilog (`iverilog`)
- GTKWave (`gtkwave`)

From the repository root:
- Windows: `run_tb.bat`
- Linux: `run_tb.sh`

Scripts:
- `misa-o_b.sh`: build check
- `misa-o_r.sh`: build + run + open GTKWave

---

# Architecture

MISA-O is a compact 4-bit MISC accumulator ISA featuring variable-length encoding (nibble or byte immediates) and an **XOP** prefix for extensions.
It uses a unified **XMEM** class for memory access (load/store with optional post-increment).
The architecture includes one program counter, four 4-bit accumulators, two 16-bit source registers, and two 16-bit address registers.
Accumulators can be linked into wider configurations (2×8-bit or 1×16-bit), while logic and arithmetic operations act primarily on the active accumulator.

## Characteristics:

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

### CFG Table:

| Bit | Name     | Default | Description                                                                                           |
|-----|----------|---------|-------------------------------------------------------------------------------------------------------|
|  7  | CI       |    0    | Carry-in enable. When 0, arithmetic ignores C as input. When 1, arithmetic uses C as carry/borrow-in. |
|  6  | BW       |    0    | Branch immediate width: 0=imm4, 1=imm8                                                                |
|  5  | BRS      |    0    | Branch relative scale: 0=×1, 1=×4 (<<2)                                                               |
|  4  | IE       |    0    | Interrupt enable                                                                                      |
|  3  | IMM      |    0    | When set, selected ALU opcodes use an embedded immediate instead of RS0 as second operand.            |
|  2  | SIGN     |    0    | Signed arithmetic mode                                                                                |
| 1:0 | W (LINK) |   00    | Accumulator link width: 00=UL(4-bit), 01=LK8, 10=LK16, 11=SPE                                         |

# Instructions

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
| 0010 |CFG       |CMP       | Load Configuration / Compare                         |
| 0110 |RACC      |RRS       | Rotate Accumulator/ Rotate Register Source 0         |
| 1010 |RSS       |RSA       | Rotate Stack Source/Address                          |
| 1110 |SS        |SA        | Swap Accumulator with Source/Address                 |
| 0100 |LDi       |**RSV**   | Load Immediate / Reserved for extensions             |
| 1100 |XMEM      |**RSV**   | Extended Memory Operations / Reserved for extensions |
| 1000 |XOP       |**RSV**   | Extended Operations / Reserved for extensions        |
| 0000 |NOP       |**RSV**   | No Operation / Reserved for extensions               |

Notes:
- \* : Not mandatory instructions.
- **Bold**: Newly added / under review.
- **RACC/RRS**: In LK16 mode, their opcode is reused for **CSRLD/CSRST**, and no rotation is available at 16-bit width.

## Special Instruction - LK16 Only

Since ACC/RS0 rotation would became useless at LK16 mode, in LK16 mode this instruction will have a special behavior of accessing CSRs.

| Mode |Binary| Type      | Name     | Description                                                     |
|------|------|-----------|----------|-----------------------------------------------------------------|
| LK16 | 0110 |*Default*  |**CSRLD** | *Load CSR*: loads CSR indexed by **#imm (0–15)** into **ACC**   |
| LK16 | 0110 |*Extended* |**CSRST** | *Store CSR*: writes **ACC** into CSR indexed by **#imm (0–15)** |

## Instruction Encoding Reference

MISA-O uses **nibble-based encoding** with variable-length instructions:

|      Type      |          Format         | Size |                 Example                  |
|----------------|-------------------------|------|------------------------------------------|
| Simple         | 4-bit opcode            | 0.5B¹| `ADD`, `INC`, `JAL`                      |
| Extended       | XOP + opcode            | 1B   | `XOP; SUB`                               |
| Immediate      | (XOP)opcode + W-bit imm | 1-3B | `ADD #value` (W-dependent) (IMM=enabled) |
| Load immediate | 4-bit + W-bit imm       |1-2.5B| `LDi #value` (W-dependent)               |
| CFG Update     | 4-bit + 8-bit imm       | 1.5B | `CFG #imm` (paired)                      |
| CSR access     | 4-bit + 4-bit index     | 1B   | `CSRLD #5`                               |
| Memory         | 4-bit + 4-bit func      | 1B   | `XMEM #0b1010`                         |
| Branch         | 4-bit + imm4/8          | 1-2B | `BEQz #target` (BW-dependent)            |

¹ *Two 4-bit instructions pack into a single byte*

**Key Points:**
- Instructions are **nibble-aligned** (not byte-aligned).
- Nibble order within a byte is fixed as low first
- PC addresses instruction nibbles directly.
- Simple operations (ADD, SS, etc) can pair in 1 byte.
- Complex operations (CFG, LDi) use 2-3 bytes.
- When `CFG.IMM` is enable, relevant instructions (ADD, SUB, AND, OR, XOR, TST) will increase by W-size to accomodate such immediate (BTST will always increase by 4-bit because it's enough to accomodate the 16 positions of the register).

---

## Instruction Semantics:

- **Not Mandatory / Custom Instructions**: Opcodes marked “not mandatory” may be used for custom extensions by implementers. Code that uses them is not compatible with baseline MISA-O cores.
- **INV**: `ACC ← ~ACC` within the active width W (4/8/16); Updates `Z` and `N` from the result. Does not update `C` or `V`.
- **ADD/ADDI**: `ACC ← ACC + OP2` within the active width W (4/8/16); updates `C` with carry-out; respect carry-in.
  - If `IMM = 0`: `OP2 = RS0`.
  - If `IMM = 1`: `OP2 = imm_W` (the immediate value zero-extended to W bits).
- **SUB/SUBI**: `ACC ← ACC - OP2` within the active width W (4/8/16); updates `C` with borrow; respect carry-in.
  - If `IMM = 0`: `OP2 = RS0`.
  - If `IMM = 1`: `OP2 = imm_W`.
- **AND/ANDI**: `ACC ← ACC & OP2` within the active width W (4/8/16); Updates `Z` and `N` from the result. Does not update `C` or `V`.
  - If `IMM = 0`: `OP2 = RS0`.
  - If `IMM = 1`: `OP2 = imm_W`.
- **OR/ORI**: `ACC ← ACC | OP2` within the active width W (4/8/16); Updates `Z` and `N` from the result. Does not update `C` or `V`.
  - If `IMM = 0`: `OP2 = RS0`.
  - If `IMM = 1`: `OP2 = imm_W`.
- **XOR/XORI**: `ACC ← ACC ^ OP2` within the active width W (4/8/16); Updates `Z` and `N` from the result. Does not update `C` or `V`.
  - If `IMM = 0`: `OP2 = RS0`.
  - If `IMM = 1`: `OP2 = imm_W`.
- **INC/DEC**: Increment/Decrement ACC by 1; updates `C` with carry-out/borrow; carry-in is always treated as 0.
- **SHL/SHR**: Shift ACC Left/Right by 1 bit; the outgoing bit goes to Carry, and the vacated side is filled with 0. Updates `C` with the shifted-out bit and updates `Z`/`N` from the result. Does not update `V`.
- **RACC/RRS**: Rotate Accumulator / Register Source - It rotates ACC/RS0 by W bits (4/8), wrapping around; in LK16, the RACC/RRS opcode encoding is repurposed as Special Instructions (SI).
- **RSS/RSA**: Treat RS/RA as a stack and rotate it. Any implementation that extends these instructions to additional registers constitutes a non-standard extension and may break binary compatibility.
- **SS**:  Swaps the contents of **ACC** *with* source operand register 0 (**RS0**), respecting the active **W** (word-size) configuration: `ACC ↔ RS0 (W-bits)`.
- **SA**:  Swaps the full contents of **ACC** *with* address register 0 (**RA0**) (full 16-bit), ignoring the **W** size configuration: `ACC ↔ RA0 (16-bits)`.
- **JAL/JMP**: All jumps will be based on register RA0, but linking would be saved on RA1.
  - **JAL**: `RA1 ← PC_next`; `PC ← RA0`
  - **JMP**: `PC ← RA0`
- **CFG #imm**: Loads the *immediate* (**#imm**) value into the **CFG** register. The **CFG** register can also be accessed at `CSR1` for reading. *(Useful for changing link width (W) or enabling features without register overhead.)*
- **CMP**: Computes a subtraction of the form `tmp = ACC − OP2 − (CI ? C_in : 0)` using width `W`, **without modifying `ACC`**. The instruction updates flags as if a `SUB` had been executed:
  - `C = borrow-out`
  - `Z = (tmp == 0)`
  - `N = MSB(tmp)`
  - `V = signed overflow on subtraction`
- **Branches** (PC-relative): If (cond): **PC ← PC_next + ( *sign_extend*(BW ? imm8 : imm4) << (BRS ? 2 : 0) )**; Else: **PC ← PC_next**; *flags unchanged*.
  - **BEQz #imm**: Branch if `Z == 1`.
  - **BC   #imm**: Branch if `C == 1`.
  - **BTST/BTSTI**:
    - If `IMM = 0`: `idx = RS0[3:0]`.
    - If `IMM = 1`: `idx = imm4` (low 4 bits of the immediate).
    - Then: tests bit `ACC[idx]`; sets `C = ACC[idx]`; `ACC` not written. Updates Z to reflect whether the tested bit is zero.
  - **TST/TSTI**:
    - If `IMM = 0`: `mask = RS0`.
    - If `IMM = 1`: `mask = imm_W` (immediate zero-extended to W bits).
    - Then: `tmp = ACC & mask`; sets `C = 1` if `tmp != 0`, else `C = 0`; `ACC` not written (limited by current link width); updates `Z`/`N` from `tmp`, does not update `V`.
- **XOP**: Executes next instruction as Extended Operation.
- **XMEM #f**: Extended Memory Operations (opcode 1100 + 4-bit function):
  - Function:
    - `f[3]`: **OP**: 0=Load, 1=Store
    - `f[2]`: **AM**: Auto-Modify Mode (0=None, 1=Active)
    - `f[1]`: **DIR**: Direction (0=Increment, 1=Decrement)
    - `f[0]`: **AR**: Address Register (RA0 / RA1)
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
    - If AM=1: Enables Auto-Modify mode. The update timing corresponds to standard stack operations:
      - DIR=0 (Increment): Performs Post-Increment (Access [addr], then addr ← addr + stride).
      - DIR=1 (Decrement): Performs Pre-Decrement (addr ← addr - stride, then Access [addr]).
    - Flags: **unchanged**.
- **CSRLD #imm**: Loads CSR into ACC (more details on CSR section).
- **CSRST #imm**: Write ACC into CSR (more details on CSR section).

### **Carry Flag (C)**

The carry flag (C) is **always updated** by arithmetic and shift operations, but it is **consumed as carry-in when CI is enable**.

- **ADD / INC**: `C = carry-out`
- **SUB / DEC**: `C = borrow-out`
- **SHL / SHR**: `C = expelled bit`
- **SUB with carry-in enabled**: `ACC = ACC − OP2 − C_in`

Its role as an arithmetic input is controlled by the **CI** flag in `CFG`.

* When `CI = 0` (default), carry-in is ignored and treated as zero.
* When `CI = 1`, carry-in is taken from the current value of `C`.

This design provides explicit, mode-controlled carry propagation without requiring additional arithmetic opcodes, while keeping the default behavior simple and deterministic.

#### Carry propagation

Arithmetic and shift instructions always update the Carry flag based on their result.
Instructions that accept Carry-in use the current Carry value as an input, and generate a new Carry as output.
No instruction clears Carry implicitly; Carry is only modified as a result of arithmetic or shift execution.

#### Carry initialization (assembler idioms)

Since there is no dedicated *Clear Carry* instruction, software is expected to use well-defined instruction idioms to establish a known carry state before multi-precision arithmetic.

To **clear carry (`C = 0`)**:
```asm
LDi #0
SHL             ; ACC ← ACC << 1, C ← 0 (no carry)
```

To **set carry (`C = 1`)** (for example, to initialize subtraction with “no borrow”):
```asm
LDi #0xFFFF     ; in LK16 mode
SHL             ; ACC ← ACC << 1, C ← 1
```

These idioms are considered canonical and may be optimized by implementations. They provide a portable and explicit mechanism to control carry state without introducing additional opcodes.

### Flag update rules

The flags `C`, `Z`, `N`, and `V` are **architectural state**. Unless stated otherwise, instructions that produce an ALU result update a subset of these flags as described below.

**Definitions (width = W):**

* `Z = 1` iff the computed result equals zero.
* `N = MSB(result)` (bit `W-1`).
* `C` is operation-defined (carry-out for shifts/add; borrow-out for sub/dec).
* `V` indicates signed overflow for add/sub-style operations.

**Which instructions update flags:**

* **ADD / INC** update: `C`, `Z`, `N`, `V`.
* **SUB / DEC / CMP** update: `C`, `Z`, `N`, `V` where `C = borrow-out`.
* **SHL / SHR** update: `C`, `Z`, `N` (and do not update `V`).
* **AND / OR / XOR / INV / TST** update: `Z`, `N` (and do not update `C` or `V`).

**Branch and control-flow instructions never modify flags.**

### Multi-precision arithmetic (CI=1)

When the **CI (Carry-In)** flag is enabled, arithmetic instructions may be chained to implement **multi-precision arithmetic** across multiple words.

For **addition**, the carry-out (`C`) produced by an `ADD` instruction becomes the carry-in for the next higher word. Software must ensure that the carry flag is **cleared** before processing the least significant word. Subsequent words are processed sequentially, propagating carry automatically.

For **subtraction**, the carry flag represents borrow. When `CI = 1`, a `SUB` instruction subtracts an additional 1 if `C = 1`, allowing borrow to propagate naturally across words. Software must clear C before the least significant word subtraction.

Multi-precision operations are typically implemented by iterating over words from least significant to most significant, using `XMEM` loads/stores and standard arithmetic instructions, without requiring dedicated wide arithmetic opcodes.

### Branch:

- BW/BRS are global (from CFG). Keep them constant within a function.
- With imm4 and large scaling (e.g., <<2), targets should be aligned accordingly to avoid padding.
- Taking a branch does not modify flags.

---

## CSR Bank (Control & Extensions)

MISA-O defines a small CSR (Control and Status Register) bank to expose core configuration, flags and optional extension state without bloating the general register file. The bank is addressed by a 4-bit index (0–15), each CSR being 16-bit wide.

Access is performed through two instructions:

- **CSRLD #idx**: `ACC ← CSR[idx]` (16-bit read into ACC)
- **CSRST #idx**: `CSR[idx] ← ACC` (16-bit write from ACC)

In **UL/LK8** modes, the opcodes `RACC` / `RRS` behave as rotate instructions as described earlier. In **LK16** mode, the same opcodes are reassigned to `CSRLD` / `CSRST`, using an immediate nibble as CSR index.

### CSR implementation profiles

Two implementation profiles are envisaged:

- **Compact**: only the minimal *required* CSR set is implemented. All unimplemented CSRs read as `0` and ignore writes. This keeps area and complexity close to the original MISA-O core.

- **Baseline**: Default implementation to support rich sowtware stack. Software must not rely on any CSR beyond *required* and *baseline* unless the target profile is explicitly known. Baseline is the recommended minimum target for hosted or compiled languages.

- **Complete**: All profiles with additional CSRs are implemented for richer interrupt handling, debugging and arithmetic extensions.

### CSR Map

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

For a detailed description of the CSR bank, see **[csrs.md](arch/csrs.md)**.

---

# Profiles

The architecture defines a set of optional profiles that extend the baseline core with additional capabilities:
- **[Interrupt](arch/profiles/interrupt.md)** — Interrupt handling support.
- **[Debug](arch/profiles/debug.md)** — Debug and introspection facilities.
- **[MAD](arch/profiles/mad.md)** — Multiply-Add and related arithmetic extensions.

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

## Registers Overview

```
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

          |---------------------------------------|
     GPR1 | 0 0 0 0   0 0 0 0   0 0 0 0   0 0 0 0 |
          |---------------------------------------|
     GPR2 | 0 0 0 0   0 0 0 0   0 0 0 0   0 0 0 0 |
          |---------------------------------------| 
     GPR3 | 0 0 0 0   0 0 0 0   0 0 0 0   0 0 0 0 |
          |---------------------------------------| 
```
