# MISA-O
**My ISA Version 0** is a 4-bit MISC ISA made to be functional.
>The specification is under review...

## Architecture
MISA-O is a compact 4-bit MISC accumulator ISA featuring variable-length encoding (nibble or byte immediates) and an **XOP** prefix for extensions.
It uses a unified **XMEM** class for memory access (load/store with optional post-increment).
The architecture includes one program counter, four 4-bit accumulators, two 16-bit source registers, and two 16-bit address registers.
Accumulators can be linked into wider configurations (2×8-bit or 1×16-bit), while logic and arithmetic operations act primarily on the active accumulator.

### Characteristics:
- 1x16-bit pc (Program Counter) register.
- 1x8-bit ia (Interrupt Address) register.
- 1x8-bit iar (Interrupt Address Return) register.
- 4x4-bit acc (Accumulator) register.
- 2x16-bit rs (Register Source) register.
- 2x16-bit ra (Address) register.
  - ra0: Active address.
  - ra1: Return address.
- 1x8-bit cfg (Configuration) register.
  - [7]: Reserved, (reads as 0; writes ignored).
  - [6]: BW - Branch immediate width. Reset: 1 (imm8).
    -  0: imm4 (4-bit total)
    -  1: imm8 (8-bit total)
  - [5]: BRS - Branch relative scale. Reset: 0 (<<0).
    - 0: shift by 0, 1-byte step (Default).
    - 1: shift by 2, 4-byte step.
  - [4]: IE: Interrupts (0: disable / 1: enable). Reset: 0 (disable).
  - [3]: CEN - Carry (1: enable / 0: disable). Reset: 1 (enable).
  - [2]: SIGN - Signed mode (1: signed / 0: unsigned). Reset: 1 (signed).
  - [1:0]: W - LINK - Link Mode:
    - 2b00: UL (Unlinked) - 4-bit mode (Default).
    - 2b01: LK8 (Link 8) - 8-bit mode.
    - 2b10: LK16 (Link 16) - 16-bit mode.
    - 2b11: Reserved - Future use.

#### CFG Table:
| Bit | Name     | Default | Description                                        |
|-----|----------|---------|----------------------------------------------------|
|  7  | Reserved |    0    | Reads as 0, writes ignored.                        |
|  6  | BW       |    1    | Branch immediate width: 0=imm4, 1=imm8             |
|  5  | BRS      |    0    | Branch relative scale: 0=×1, 1=×4 (<<2)            |
|  4  | IE       |    0    | Interrupt enable                                   |
|  3  | CEN      |    1    | Carry enable                                       |
|  2  | SIGN     |    1    | Signed arithmetic mode                             |
| 1:0 | W (LINK) |   00    | Accumulator link width: UL(4), LK8, LK16, reserved |


## Instructions
The following table lists the architecture instructions:

|Binary    |Default   |Extended  |Description                                         |
|----------|----------|----------|----------------------------------------------------|
| 000**1** |CC        |**CFG**   | Clear Carry / Swap Configuration                   |
| 010**1** |AND       |INV       | AND / Invert                                       |
| 100**1** |OR        |XOR       | OR / XOR                                           |
| 110**1** |SHL       |SHR       | Shift Left / Right                                 |
| 001**1** |ADD       |SUB       | Add / Sub                                          |
| 101**1** |INC       |DEC       | Increment / Decrement                              |
| 011**1** |BEQz      |BC        | Branch if Equal Zero / Branch if Carry             |
| 111**1** |BTST      |TST       | Bit Test / Test                                    |
| 00**10** |JAL       |JMP       | Jump and Link / Jump                               |
| 01**10** |RACC      |**RRS**   | Rotate Accumulator/ Rotate Register Source 0       |
| 10**10** |RSS       |RSA       | Rotate Stack Source/Address                        |
| 11**10** |**SS**    |**SA**    | Swap Accumulator with Source/Address               |
| 0**100** |LDi       |SIA\*     | Load Immediate / Swap Interrupt Address            |
| 1**100** |XMEM      |RETI\*    | Extended Memory Operations / Return from Interrupt |
| **1000** |XOP       |SWI\*     | Extended Operations / Software Interrupt           |
| **0000** |NOP       |**WFI\*** | No Operation / Wait-For-Interrupt                  |

Notes:
- \* : Not mandatory instructions.
- **Bold**: Newly added / under review.
- **WFI**: Wait-For-Interrupt was promoted to keep consistency on all non-mandatory instructions, the **MAD** instruction that it replaced could be part of a new extension (CFG reserved = 1) together with DIV and others math operations.
- **RRS**: Even though rotate rs0 only saves one instruction (from: SS → RACC → SS ; to: XOP → RRS), it was chosen to save a little bit of power from data migration to do so.

## Main Instructions:
- **Not Mandatory / Custom Instructions**: Opcodes marked “not mandatory” may be used for custom extensions by implementers. Code that uses them is not compatible with baseline MISA-O cores.
- **INV**: `ACC ← ~ACC` within the active width W (4/8/16); *flags unchanged*.
- **RACC/RRS**: Rotate Accumulator / Register Source - It will treat ACC/RS0 as a single register and shift rotate it by "Operation mode" size to the right; In LK16 mode, this instruction has no effect (NOP).
- **RSS/RSA**: It will treat RS/RA as a stack and rotate it *(currently looks like a swap, but later on if more register where added it will truly rotate)*.
- **SS**:  Swaps the contents of **ACC** *with* source operand register 0 (**RS0**), respecting the active **W** (word-size) configuration: `ACC ↔ RS0 (W-bits)`.
- **SA**:  Swaps the full contents of **ACC** *with* address register 0 (**RA0**) (full 16-bit), ignoring the **W** size configuration: `ACC ↔ RS0/RA0`.
- **JAL/JMP**: All jumps will be based on register ra0, but linking would be saved on ra1.
  - **JAL**: `ra1 ← PC_next`; `PC ← ra0`
  - **JMP**: `PC ← ra0`
- **CFG #imm**: Loads the *immediate* (**#imm**) value into the **CFG** register. The **CFG** register is also *memory-mapped* at address **0x00** for direct access. *(Useful for changing link width (W) or enabling features without register overhead.)*
- **Branches** (PC-relative): If (cond): **PC ← PC_next + ( *sign_extend*(BW ? imm8 : imm4) << (BRS ? 2 : 0) )**; Else: **PC ← PC_next**; *flags unchanged*.
  - **BEQz #imm**: Branch if `acc == 0`.
  - **BC   #imm**: Branch if `Carry C == 1`.
  - **BTST #imm**: Tests bit `acc[idx]` where `idx = rs0[3:0]`; sets `C=bit`; `acc` not written.
  - **TST  #imm**: Utilizes **rs0** as a **mask** to **acc** and compare (`tmp = acc & rs0`); sets `C=bit`; `acc` not written. (Limited by link mode)
- **XOP**: Executes next instruction as Extended Operation.
- **XMEM #f**: Extended Memory Operations (opcode 1100 + 4-bit function):
  - Function:
    - `f[3]`: **OP**: 0=Load, 1=Store
    - `f[2]`: **AM**: 0=none, 1=post-increment
    - `f[1]`: **DIR**:  0 = +stride (increment), 1 = −stride (decrement)
    - `f[0]`: **AR**: 0=ra0, 1=ra1
  - Semantics (width W from LINK, little-endian):
    - `addr` = `(AR ? ra1 : ra0) ; alias of the selected register`
    - `stride` = `(W == 16 ? 2 : 1) ; bytes (UL & LK8: 1B; LK16: 2B)`
    - **LD**: 
      - **LK16**: `acc ← { [addr+1], [addr] } ; little-endian`
      - **LK8**: `acc[7:0] ← [addr]`
      - **UL**: `acc[3:0] ← [addr][3:0]`
    - **SW**:
      - **LK16**: `[addr] ← acc[7:0]; [addr+1] ← acc[15:8]`
      - **LK8**: `[addr] ← acc[7:0]`
      - **UL**: `tmp ← [addr]; tmp[3:0] ← acc[3:0]; [addr] ← tmp`
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
    - The CPU **stores PC_next, CFG/FLAGS, acc, RS0/RS1, RA0/RA1** at fixed offsets in page `ia` (see layout below),
    - latches `iar ← ia`, **clears IE**, clears any pending **XOP**, and
    - **jumps to** `ia<<8 + 0x10` (the ISR entry).
  - **WFI\***: Wait-For-Interrupt makes the processor sleep until an interrupt sign is received.
  - **SWI\***: Triggers a software interrupt; flow identical to an external IRQ: autosave on the ia page, latches `iar←ia`, clears IE (`IE←0`) and jumps to `ia<<8 + 0x10`.
  - **SIA\***: Swap lower *acc* data (acc[7:0]) with *ia* register (ia = acc[7:0] && acc[7:0] = ia).
  - **RETI\***: Restores state from the *iar* page and resumes execution.
    - Base address: **base = iar << 8**
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
; Saved on interrupt entry:      base = ia  << 8
; RETI reads/restores from page: base = iar << 8
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

### Development:
Currently there are some instructions that could became part of the ISA:
|Binary|Instruction |                                           |
|------|------------|-------------------------------------------|
| 0000 |CLR         | Clear                                     |
| 0000 |SDI         | Send Interrupt                            |
| 0000 |WFI         | Wait-For-Interrupt                        |

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
      cfg | 0 0 0 0   0 0 0 0 | 
          |-------------------| 

          |-------------------| 
       ia | 0 0 0 0   0 0 0 0 | 
          |-------------------| 
      iar | 0 0 0 0   0 0 0 0 | 
          |-------------------| 

          |---------------------------------------| 
       pc | 0 0 0 0   0 0 0 0   0 0 0 0   0 0 0 0 | 
          |---------------------------------------| 

          |---------------------------------------| 
      ra1 | 0 0 0 0   0 0 0 0   0 0 0 0   0 0 0 0 | 
          |---------------------------------------| 
      ra0 | 0 0 0 0   0 0 0 0   0 0 0 0   0 0 0 0 | 
          |---------------------------------------| 

          |--- r3 ------ r2 ------ r1 ------ r0 --| 
      acc | 0 0 0 0 | 0 0 0 0 | 0 0 0 0 | 0 0 0 0 | 
          |---------------------------------------|

          |---------------------------------------|
      rs0 | 0 0 0 0   0 0 0 0   0 0 0 0   0 0 0 0 |
          |---------------------------------------|
      rs1 | 0 0 0 0   0 0 0 0   0 0 0 0   0 0 0 0 |
          |---------------------------------------| 

## Final Considerations
**NEG**: Started with NEG/Negated instructions/behavior, but was replaced with a more default behavior (**XOP**) that only affects the next instruction, this change allowed for a better compression and a more stable behavior, this will also help on the compiler construction.

**LK**: Link was demoted to be replaced by a more versatile "Swap Configuration", now it's possible to enable auto-increment when reading/writing from/to memory with the advantage of also be able to secure a known working state for the functions.

**Branches**: Planned to be based on ra0, under some consideration it was changed to immediate value. Because of the small quantity of registers this seems more reasonable, but could be changed back to utilize ra0.

**SS/SA & CFG**: SS and SA was initially designed for quick register swapping, this design was adjusted to allow partial swaps respecting **W** (useful for endianness control). To complement this, **CFG** now supports immediate loading, easing state management and reducing register pressure. **SA** remains a full 16-bit swap for address manipulation, as partial swaps provide little benefit in this context.

**Multiply**: The area/power cost of a hardware multiplier is high for this class of core, and the **base opcode map is full**. Comparable minimal CPUs also omit MUL. Software emulation (shift-add) handles 4/8/16-bit cases well — especially with *CEN* and *CC* — so the practical impact is low. But there is a plan to create an extension (CFG reserved = 1) that will replace non-mandatory instructions by new ones, like **MAD**, DIV, Vector MAD or other arithmetic operations. The idea behind having MUL instruction is to keep open the possibility of an implementation that could run DOOM.
