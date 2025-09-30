# MISA-O
**My ISA Version 0** is a 4-bit MISC ISA made to be functional.
>The specification is under review...

## Architecture
MISA-O is a 4-bit MISC accumulator ISA with variable-length encoding (nibble/byte immediates) and an XOP prefix for extensions. Memory is accessed via a single XMEM class (load/store, optional post-inc). The architecture consists of one program counter register, four 4-bit accumulator registers, two 16-bit source registers and two 16-bit memory address registers. Accumulator registers can be linked to work as 2x8-bit or 1x16-bit besides the original 4x4-bit mode, while active source will always provide values accordingly with accumulator size. Logic operations will primarily be on accumulator register and store the result in itself, while memory operation will use active memory address register as address. The accumulator register can be rotated Left or right in sets (like operation Shift rotate left/right by the active width (W)).

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
    -  0: imm4 (1 byte total)
    -  1: imm8 (2 bytes total)
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

## Instructions
The following table lists the architecture instructions:

|Binary    |Default   |Extended  |Description                                         |
|----------|----------|----------|----------------------------------------------------|
| 000**1** |CC        |CFG       | Clear Carry / Swap Configuration                   |
| 010**1** |AND       |INV       | AND / Invert                                       |
| 100**1** |OR        |XOR       | OR / XOR                                           |
| 110**1** |SHL       |SHR       | Shift Left / Right                                 |
| 001**1** |ADD       |SUB       | Add / Sub                                          |
| 101**1** |INC       |DEC       | Increment / Decrement                              |
| 011**1** |BEQz      |BC        | Branch if Equal Zero / Branch if Carry             |
| 111**1** |BTST      |TST       | Bit Test / Test                                    |
| 00**10** |JAL       |JMP       | Jump and Link / Jump                               |
| 01**10** |RACC      |**RRS**   | Rotate Accumulator/ Rotate Register Source 0       |
| 10**10** |RS        |RA        | Rotate Stack Registers Source/Address              |
| 11**10** |SS        |SA        | Swap Registers Source/Address                      |
| 0**100** |LDi       |SIA\*     | Load Immediate / Swap Interrupt Address            |
| 1**100** |XMEM      |RETI\*    | Extended Memory Operations / Return from Interrupt |
| **1000** |XOP       |SWI\*     | Extended Operations / Software Interrupt           |
| **0000** |NOP       |**WFI\*** | No Operation / Wait-For-Interrupt                  |

Instructions review:
- \* : Not mandatory instructions.
- **Bold**: Newly added / under review.
- **WFI**: Wait-For-Interrupt was promoted to keep consistency on all non-mandatory instructions, the **MAD** instruction that it replaced could be part of a new extension (CFG reserved = 1) together with DIV and others math operations.
- **RRS**: Even though rotate rs0 only saves one instruction (from: SS → RACC → SS ; to: XOP → RRS), it was chosen to save a little bit of power from data migration to do so.

## Instructions Review:
- **Not Mandatory / Custom Instructions**: Opcodes marked “not mandatory” may be used for custom extensions by implementers. Code that uses them is not compatible with baseline MISA-O cores.
- **MAD** (integer, non-fused): Not mandatory, will *add* the result of *rs0 times rs1* to *acc* (can be replaced by a desired instruction).
  - Affected by configurations flags: W = 4/8/16 from LINK; SIGN selects unsigned/signed multiplication.
  - Product is 2W; the low W bits are added to `ACC: ACC ← ACC + (RS0 * RS1)[W-1:0]`.
  - Flags follow ADD (C carry-out; V signed overflow if SIGN=1).
- **INV**: `ACC ← ~ACC` within the active width W (4/8/16); *flags unchanged*.
- **RACC/RRS**: Rotate Accumulator / Register Source - It will treat acc/rs0 as a single register and shift rotate it by "Operation mode" size to the right; In LK16 mode, this instruction has no effect (NOP).
- **RS/RA**: It will treat RS/RA as a stack and rotate it *(currently looks like a swap, but later on if more register where added it will truly rotate)*.
- **JAL/JMP**: All jumps will be based on register ra0, but linking would be saved on ra1.
  - **JAL**: `ra1 ← PC_next`; `PC ← ra0`
  - **JMP**: `PC ← ra0`
- **CFG**: Swap CFG register with acc[7:0].
- **Branches** (PC-relative): If the condition is true: **PC ← PC_next + ( *sign_extend*(BW ? imm8 : imm4) << (BRS ? 2 : 0) )**; Else: **PC ← PC_next**. (Branches do not modify flags).
  - **BEQz**: Branch if `acc == 0`.
  - **BC**: Branch if `Carry C == 1`.
  - **BTST**: Tests bit `acc[idx]` where `idx = rs0[3:0]`; sets `C=bit`; `acc` not written.
  - **TST**: Utilizes **rs0** as a **mask** to **acc** and compare (`tmp = acc & rs0`); sets `C=bit`; `acc` not written. (Limited by link mode)
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
- **Interrupts**:
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
- **Carry**: CEN: when 1, ADD/SUB/INC/DEC use carry/borrow-in and update C; when 0, carry-in is forced to 0 (C still updated):
  - **ADD/INC**: Carry-out.
  - **SUB/DEC**: Borrow (C = 1).
  - **SHL/SHR**: Holds expelled bit.

### Notes:
- Branch
  - BW/BRS are global (from CFG). Keep them constant within a function.
  - With imm4 and large scaling (e.g., <<2), targets should be aligned accordingly to avoid padding.
  - Taking a branch does not modify flags and clears any pending XOP.

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
**NEG**:Started with NEG/Negated instructions/behavior, but was replaced with a more default behavior (**XOP**) that only affects the next instruction, this change allowed for a better compression and a more stable behavior, this will also help on the compiler construction.

**LK**: Link was demoted to be replaced by a more versatile "Swap Configuration", now it's possible to enable auto-increment when reading/writing from/to memory with the advantage of also be able to secure a known working state for the functions.

**Branches**: Planned to be based on ra0, under some consideration it was changed to immediate value. Because of the small quantity of registers this seems more reasonable, but could be changed back to utilize ra0.

**Multiply**: The area/power cost of a hardware multiplier is high for this class of core, and the **base opcode map is full**. Comparable minimal CPUs also omit MUL. Software emulation (shift-add) handles 4/8/16-bit cases well — especially with *CEN* and *CC* — so the practical impact is low. But there is a plan to create an extension (CFG reserved = 1) that will replace non-mandatory instructions by new ones, like **MAD**, DIV, Vector MAD or other arithmetic operations. The idea behind having MUL instruction is to keep open the possibility of an implementation that could run DOOM.
