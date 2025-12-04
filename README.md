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
  - [7]: IMM - Immediate instruction mode (0: disable / 1: enable). Reset: 0 (disable).
  - [6]: BW - Branch immediate width. Reset: 0 (imm4).
    -  0: imm4 (4-bit total)
    -  1: imm8 (8-bit total)
  - [5]: BRS - Branch relative scale. Reset: 0 (<<0).
    - 0: shift by 0, 1-byte step (Default).
    - 1: shift by 2, 4-byte step.
  - [4]: IE: Interrupts (0: disable / 1: enable). Reset: 0 (disable).
  - [3]: CEN - Carry (1: enable / 0: disable). Reset: 0 (disable).
  - [2]: SIGN - Signed mode (1: signed / 0: unsigned). Reset: 0 (unsigned).
  - [1:0]: W - LINK - Link Mode:
    - 2b00: UL (Unlinked) - 4-bit mode (Default).
    - 2b01: LK8 (Link 8) - 8-bit mode.
    - 2b10: LK16 (Link 16) - 16-bit mode.
    - 2b11: Reserved - Future use.

#### CFG Table:
| Bit | Name     | Default | Description                                                  |
|-----|----------|---------|--------------------------------------------------------------|
|  7  | IMM      |    0    | Changes arithmetic operations to work with immediate values. |
|  6  | BW       |    0    | Branch immediate width: 0=imm4, 1=imm8                       |
|  5  | BRS      |    0    | Branch relative scale: 0=×1, 1=×4 (<<2)                      |
|  4  | IE       |    0    | Interrupt enable                                             |
|  3  | CEN      |    0    | Carry enable                                                 |
|  2  | SIGN     |    0    | Signed arithmetic mode                                       |
| 1:0 | W (LINK) |   00    | Accumulator link width: UL(4), LK8, LK16, reserved           |


## Instructions
The following table lists the architecture instructions:

|Binary|Default   |Extended  |Description                                         |
|------|----------|----------|----------------------------------------------------|
| 0001 |CC        |CFG       | Clear Carry / Swap Configuration                   |
| 0101 |AND       |INV       | AND / Invert                                       |
| 1001 |OR        |XOR       | OR / XOR                                           |
| 1101 |SHL       |SHR       | Shift Left / Right                                 |
| 0011 |ADD       |SUB       | Add / Sub                                          |
| 1011 |INC       |DEC       | Increment / Decrement                              |
| 0111 |BEQz      |BC        | Branch if Equal Zero / Branch if Carry             |
| 1111 |BTST      |TST       | Bit Test / Test                                    |
| 0010 |JAL       |JMP       | Jump and Link / Jump                               |
| 0110 |RACC      |RRS       | Rotate Accumulator/ Rotate Register Source 0       |
| 1010 |RSS       |RSA       | Rotate Stack Source/Address                        |
| 1110 |SS        |SA        | Swap Accumulator with Source/Address               |
| 0100 |LDi       |**CMP**   | Load Immediate / Compare                           |
| 1100 |XMEM      |RETI\*    | Extended Memory Operations / Return from Interrupt |
| 1000 |XOP       |SWI\*     | Extended Operations / Software Interrupt           |
| 0000 |NOP       |**WFI\*** | No Operation / Wait-For-Interrupt                  |

Notes:
- \* : Not mandatory instructions.
- **Bold**: Newly added / under review.
- **WFI**: Wait-For-Interrupt was promoted to keep consistency on all non-mandatory instructions, the **MAD** instruction that it replaced could be part of a new extension (CFG reserved = 1) together with DIV and others math operations.
- **SIA**: Swap Software Interrupt (SIA) was removed due to a need for a non-destructive compare, in order to keep the interrupt working, interrupt address will be memory mapped (like CFG) at address 1.
- **RACC/RRS**: In LK16 mode, RACC/RRS opcodes may be reassigned to CSRLD/CSRST, enabling direct access to up to 16 CSRs using its immediate nibble as index.

## Main Instructions:
- **Not Mandatory / Custom Instructions**: Opcodes marked “not mandatory” may be used for custom extensions by implementers. Code that uses them is not compatible with baseline MISA-O cores.
- **INV**: `ACC ← ~ACC` within the active width W (4/8/16); *flags unchanged*.
- **ADD(i)**: `ACC ← ACC + ( RS0 | #imm)` within the active width W (4/8/16); Updates `C` with `Carry-out`.
- **SUB(i)**: `ACC ← ACC - ( RS0 | #imm)` within the active width W (4/8/16); Updates `C` with `Borrow`.
- **AND(i)**: `ACC ← ACC & ( RS0 | #imm)` within the active width W (4/8/16); *flags unchanged*.
- **OR(i)**: `ACC ← ACC | ( RS0 | #imm)` within the active width W (4/8/16); *flags unchanged*.
- **XOR(i)**: `ACC ← ACC ^ ( RS0 | #imm)` within the active width W (4/8/16); *flags unchanged*.
- **SHL/SHR**: Shift ACC Left/Right by 1 bit; the outgoing bit goes to Carry, and the vacated side is filled with 0.
- **RACC/RRS**: Rotate Accumulator / Register Source - It rotates ACC/RS0 by W bits (4/8), wrapping around; in LK16 it has no effect (NOP).
- **RSS/RSA**: It will treat RS/RA as a stack and rotate it *(currently looks like a swap, but later on if more registers were added it will truly rotate)*.
- **SS**:  Swaps the contents of **ACC** *with* source operand register 0 (**RS0**), respecting the active **W** (word-size) configuration: `ACC ↔ RS0 (W-bits)`.
- **SA**:  Swaps the full contents of **ACC** *with* address register 0 (**RA0**) (full 16-bit), ignoring the **W** size configuration: `ACC ↔ RA0 (16-bits)`.
- **JAL/JMP**: All jumps will be based on register RA0, but linking would be saved on RA1.
  - **JAL**: `RA1 ← PC_next`; `PC ← RA0`
  - **JMP**: `PC ← RA0`
- **CFG #imm**: Loads the *immediate* (**#imm**) value into the **CFG** register. The **CFG** register is also *memory-mapped* at address **0x00** for direct access. *(Useful for changing link width (W) or enabling features without register overhead.)*
- **CMP**: Compares **ACC** with **RS0** by subtraction (respecting **W**), updates carry/borrow and an internal ZERO flag. If the next instruction is **BEQz**, it uses this ZERO flag instead of reading ACC directly. `ZERO` flag will clear itself if the next instruction is not BEQz.
- **Branches** (PC-relative): If (cond): **PC ← PC_next + ( *sign_extend*(BW ? imm8 : imm4) << (BRS ? 2 : 0) )**; Else: **PC ← PC_next**; *flags unchanged*. **ATTENTION**: **BEQz** has a special behaviour if it's executed after a **CMP** instruction.
  - **BEQz #imm**: If preceded by CMP: branch if `ZERO=1`. Else: branch if `ACC==0`. Always clears ZERO.
  - **BC   #imm**: Branch if `Carry C == 1`.
  - **BTST(i)**  : Tests bit `ACC[idx]` where `idx = RS0[3:0] | #imm`; sets `C = ACC[idx]`; `ACC` not written.
  - **TST(i)**   : Uses **RS0** as a mask to **ACC**: `tmp = ACC & (RS0 | #imm)`; sets `C = 1` if `tmp != 0`, else `C = 0`; `ACC` not written (limited by current link width).
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
- **Carry**: CEN: when 1, ADD/SUB/INC/DEC use carry/borrow-in and update C; when 0, carry-in is forced to 0 (C still updated):
  - **ADD/INC**: Carry-out.
  - **SUB/DEC**: Borrow (C = 1).
  - **SHL/SHR**: Holds expelled bit.

### Notes:
- Branch
  - BW/BRS are global (from CFG). Keep them constant within a function.
  - With imm4 and large scaling (e.g., <<2), targets should be aligned accordingly to avoid padding.
  - Taking a branch does not modify flags and clears any pending XOP.
 
## Optional Instructions:

### Interrupts:

#### Mapping:
| Offset    | Description                | Width |
| --------- | -------------------------- | ----- |
| 0x00      | PC_next low/high           | 16b   |
| 0x02      | CFG snapshot               | 8b    |
| 0x03      | FLAGS snapshot             | 8b    |
| 0x04–0x0F | Registers and ISR metadata | —     |

#### Instructions:
  - **Interrupts**: Not mandatory, *ia* holds the *Interrupt Service Routine* (ISR) page *Most Significant Byte* (MSB). On interrupt:
    - The CPU **stores PC_next, CFG/FLAGS, ACC, RS0/RS1, RA0/RA1** at fixed offsets in page `ia` (see layout below),
    - latches `IAR ← IA`, **clears IE**, clears any pending **XOP**, and
    - **jumps to** `IA<<8 + 0x10` (the ISR entry).
    - Interrupt address register (`IA`) is memory mapped at address 1 (0x0001).
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

### Development (Candidate Instructions)

The table below lists **candidate instructions** that are *not part of the baseline ISA* but are being evaluated for future inclusion.
These entries **do not represent actual opcode encodings**; the binary field is merely a placeholder layout used to ease migration when promoting candidates into official instructions.

Implementers must **not** rely on these encodings.
When promoted, each instruction will receive a proper unique opcode assignment within the official map.

| Binary (placeholder) | Instruction | Notes                                                                                                          |
| -------------------- | ----------- | -------------------------------------------------------------------------------------------------------------- |
| 0000                 | **CLR**     | Proposed *Clear* ACC instruction.                                                                              |
| 0000                 | **SDI**     | *Send/Signal Interrupt* — software-triggered signaling mechanism.                                              |
| 0000                 | **CSRLD**   | *Load CSR*: loads CSR indexed by **#imm (0–15)** into **ACC**; intended to reuse **RACC** opcode in **LK16**.  |
| 0000                 | **CSRST**   | *Store CSR*: writes **ACC** into CSR indexed by **#imm (0–15)**; intended to reuse **RRS** opcode in **LK16**. |

**Purpose:**
This table serves only as a **staging area** for instructions under evaluation.
Entries may be changed, merged, promoted or removed without affecting ISA compatibility.
## Reference Implementation
The reference implementation (located at "/design/misa-o_ref.sv") is not made to be performant, efficient, optimal or even synthesizable; its main purpose is to be simple to interpret while also serving as a playground to test the ISA instructions.

### How to run
To run you must have installed icarus verilog (iverilog) and GTKWAVE, open terminal on "/scripts", from there execute the scripts in it.

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

**Branches**: Planned to be based on ra0, under some consideration it was changed to immediate value. Because of the small quantity of registers this seems more reasonable, but could be changed back to utilize ra0.

**SS/SA & CFG**: SS and SA was initially designed for quick register swapping, this design was adjusted to allow partial swaps respecting **W** (useful for endianness control). To complement this, **CFG** now supports immediate loading, easing state management and reducing register pressure. **SA** remains a full 16-bit swap for address manipulation, as partial swaps provide little benefit in this context.

**Multiply**: The area/power cost of a hardware multiplier is high for this class of core, and the **base opcode map is full**. Comparable minimal CPUs also omit MUL. Software emulation (shift-add) handles 4/8/16-bit cases well — especially with *CEN* and *CC* — so the practical impact is low. But there is a plan to create an extension (CFG reserved = 1) that will replace non-mandatory instructions by new ones, like **MAD**, DIV, Vector MAD or other arithmetic operations. The idea behind having MUL instruction is to keep open the possibility of an implementation that could run DOOM.

**CSR Bank (Control & Extensions)**: To support richer control, debugging and future extensions, MISA-O also reserves space for a small CSR bank (up to 16 × 16-bit registers, 32 bytes total), exposed via optional `CSRLD`/`CSRST` instructions that reuse RACC/RRS opcodes in LK16 and use their immediate nibble as index. This CSR bank can host core control bits, extended interrupt state or configuration for the MAD profile and other vendor-specific features, without bloating the baseline register file. As with the arithmetic extensions, CSR access is initially treated as a custom/optional feature to be prototyped and validated before being committed to the core specification.

**MAD Profile**: A complementary *MAD Profile (Multiply-Add & Derivatives)* is under evaluation to extend the arithmetic capabilities of MISA-O without impacting the baseline datapath. This profile introduces a compact MAD unit (8-bit×8-bit → 16-bit accumulate) along with lightweight arithmetic helpers such as MIN/MAX, enabling more efficient inner loops for graphics, audio and fixed-point workloads. The profile may also integrate access to a small bank of CSRs to expose configuration, control or per-function state with lower software overhead. Both the MAD unit and the CSR mechanism remain optional and experimental: they are implemented as custom extensions first, allowing area/latency evaluation before deciding whether promotion into an official profile is justified.
