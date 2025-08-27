# MISA-O
**My ISA Version 0** is a 4-bit MISC ISA made to be functional.
>The specification is under review...

## Architecture
MISA-O is a 4-bit architecture, it consist of one program counter register, four 4-bit operand register, two 16-bit operator register and two 16-bit memory address register. Operand register can be linked to work as 2x8-bit or 1x16-bit besides the original 4x4-bit mode, while active operator will always provide values accordingly with operand size. Logic operations will primarily be on Operand register and store the result in itself, while memory operation will use active memory address register as address. The Operand register can be rotated Left or right in sets (like operation Shift rotate left/right by 4).

### Characteristics:
- 1x16-bit pc (Program Counter) register.
- 1x8-bit ia (Interrupt Address) register.
- 1x8-bit iar (Interrupt Address Return) register.
- 4x4-bit acc (Accumulator / Operand) register.
- 2x16-bit rs (Operator / Register Source) register.
- 2x16-bit ra (Address / Memory address) register.
  - ra0: Reference address.
  - ra1: Return address.
- 1x4-bit Configuration register.
  - [3]: Interrupts (1:enable/0:disable), default disable.
  - [2]: Sign (1:signed/0:unsigned), default signed.
  - [1:0]: Link Mode:
    - 2b00: UL (Unlinked) - 4-bit mode (Default).
    - 2b01: LK8 (Link 8) - 8-bit mode.
    - 2b10: LK16 (Link 16) - 16-bit mode.
    - 2b11: Reserved - Future use.

## Instructions
The following table lists the architecture instructions:

|Binary|Default   |Extended  |Description                                         |
|------|----------|----------|----------------------------------------------------|
| 0001 |AND       |NAND      |                                                    |
| 0101 |OR        |NOR       |                                                    |
| 1001 |XOR       |XNOR      |                                                    |
| 1101 |SHL       |SHR       | Shift Left / Right                                 |
| 0011 |ADD       |SUB       | Add / Sub                                          |
| 1011 |INC       |DEC       | Increment / Decrement                              |
| 0111 |BEQz      |BC        | Branch if Equal Zero / Branch if Carry             |
| 1111 |**BTST**  |**TST**   | Bit Test / Test                                    |
| 0010 |JAL       |JMP       | Jump and Link / Jump                               |
| 0110 |RR        |RL        | Rotate Accumulator (acc) Right/Left                |
| 1010 |RS        |RA        | Rotate Source/Address Registers                    |
| 1110 |SS        |SA        | Swap Source/Address Registers                      |
| 0100 |LDi       |**SIA**   | Load Immediate / Swap Interrupt Address            |
| 1100 |**XMEM**  |**RETI**  | Extended Memory Operations / Return from Interrupt |
| 1000 |**XOP**   |**CFG**   | Extended Operations / Load Configuration           |
| 0000 |NOP       |**SDI**   | No Operation / Send Interrupt                      |

Instructions review:
- \* : Not mandatory instructions.
- **Bold**: Newly added / under review.
- **IMUL**: Removed due to the need of a better Interrupt behaviour.

## Instructions Review:
- **RR/RL**: Rotate Accumulator - It will treat acc (Accumulator) as a single register and shift rotate it by "Operation mode" size.
- **RS/RA**: It will treat RS/RA as a stack and rotate it *(currently looks like a swap, but later on if more register where added it will truly rotate)*.
- **JAL/JMP**: All jumps will be based on register ra0, but linking would be saved on ra1.
- **CFG #f**: Loads the 4-bit constant f into the configuration register (bits: IE, SIGN, LINK[1:0]).
- **Branches**: If the condition is true, the **PC is updated by adding a signed 8-bit offset from ra0[7:0]**:
  - **BEQz**: Branch if `acc == 0`.
  - **BC**: Branch if `Carry C == 1`.
  - **BTST**: Tests bit `acc[idx]` where `idx = rs0[3:0]`; sets `C=bit`; `acc` not written.
  - **TST**: Utilizes rs0 as a mask to acc and compare (`tmp = acc & rs0`), acc not written.
    >*Branch* behaviour is under review to replace the use of ra0 by #imm4 or #imm8
- **XOP**: Executes next instruction as Extended Operation.
- **XMEM #f**: Extended Memory Operations (opcode 1100 + 4-bit function):
  - Function:
    - `f[3]`: **RSV**: reserved (0)
    - `f[2]`: **OP**: 0=Load, 1=Store
    - `f[1]`: **AM**: 0=none, 1=post-increment
    - `f[0]`: **AR**: 0=ra0, 1=ra1
  - Semantics (width W from LINK):
    - **LD**: 
      - **LK16**: `acc ← [ra0]`
      - **LK8**: `acc[7:0] ← [ra0]`
      - **UL**: `acc[3:0] ← [ra0]`
    - **SW**:
      - **LK16**: `[ra0] ← acc[7:0]; [ra0+1] ← acc[15:8]`
      - **LK8**: `[ra0] ← acc[7:0]`
      - **UL**: `tmp ← [ra0]; tmp[3:0] ← acc[3:0]; [ra0] ← tmp`
    - If `AM=1`: `addr += (W==16 ? 2 : 1)`
    - Flags: **unchanged**.
- **Interrupts**:
    - **Interrupts**: *ia* holds the *Interrupt Service Routine* (ISR) page *most significant byte* (MSB). On interrupt:
      - The CPU **stores PC_next, CFG/FLAGS, acc, RS0/RS1, RA0/RA1** at fixed offsets in page `ia` (see layout below),
      - latches `iar ← ia`, **clears IE**, clears any pending **XOP**, and
      - **jumps to** `ia<<8 + 0x10` (the ISR entry).
    - **SIA**: Swap lower *acc* data (acc[7:0]) with *ia* register (ia = acc[7:0] && acc[7:0] = ia).
    - **RETI**: Restore registers with data from *iar* location.
    - Fixed layout within the ia page:
```
      base = ia << 8
      +0x00 : PC_next[7:0]
      +0x01 : PC_next[15:8]
      +0x02 : CFG snapshot (1 byte)
      +0x03 : FLAGS snapshot (Z/C/N/V, 1B)
      +0x04 : ACC (16-bit)
      +0x06 : RS0 (16-bit)
      +0x08 : RS1 (16-bit)
      +0x0A : RA0 (16-bit)
      +0x0C : RA1 (16-bit)
      +0x0E : reserved (2 bytes)
      +0x10 : ISR entry (first instruction executed on entry)'
```
- **Carry**: Operations that will be affected the carry:
  - **ADD/INC**: Carry-out.
  - **SUB/DEC**: Borrow (C = 1).
  - **SHL/SHR**: Holds expeled bit.

### Development:
Currently there are some instructions that could became part of the ISA:
|Binary|Instruction |                                           |
|------|------------|-------------------------------------------|
| 0000 |**IMUL**\*  | Integer Multiplication                    |

## Reference Implementation
The reference implementation (located at "/design/misa-o_ref.sv") is not made to be performant, efficient, optimal or even synthesizable; its main purpose is to be simple to interpret while also serving as a playground to test the ISA instructions.

### How to run
To run you must have installed icarus verilog (iverilog) and GTKWAVE, open terminal on "/scripts", from there execute the scripts in it.

#### Scripts
- misa-o_b.sh: Build script, utilized to see if the project is currently building.
- misa-o_r.sh: Build & Run script, utilized to run the test and to see the results in GTKWAVE, there you can visualize the behaviour.

#### Dependencies
- Icarus Verilog (iverilog).
- GTKWAVE (gtkwave).

## Registers Overview

          |---------| 
      cfg | 0 0 0 0 | 
          |---------| 

          |-----------------| 
       ia | 0 0 0 0 0 0 0 0 | 
          |-----------------| 
      iar | 0 0 0 0 0 0 0 0 | 
          |-----------------| 

          |---------------------------------| 
       pc | 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 | 
          |---------------------------------| 

          |---------------------------------| 
      ra1 | 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 | 
          |---------------------------------| 
      ra0 | 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 | 
          |---------------------------------| 

          |---------------------------------| 
      acc | 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 | 
          |---------------------------------|

          |---------------------------------|
      rs0 | 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 |
          |---------------------------------|
      rs1 | 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 |
          |---------------------------------| 

## Finals Considerations
**NEG**:Started with NEG/Negated instructions/behaviour, but was replaced with a more default behaviour (**XOP**) of only affect the next instruction, this change allowed for a better compression and a more stable behaviour, this will also help in a compiler construction.

**LK**: Link was demoted to be replaced by a more versatile "Load Configuration", now it's possible to enable auto increment when reading/writing from/to memory with the advantage of also be able to secure a known working state for the functions.

**Alternate Branch**:
- **Branches**: If the condition is true, the **PC is updated by adding a signed 8-bit offset encoded in the instruction** (PC-relative).
  - **BEQz**: branch if **acc == 0** (Z=1).
  - **BC**: branch if **Carry C == 1**.
  - Helpers:
    - **BTST**: tests bit **acc[idx]** with `idx = rs0 & (W−1)`; sets `C=bit, Z=~C`; **acc not written**.
    - **TST**: computes `tmp = acc & rs0`; sets `Z=(tmp==0), N=tmp[W−1]`; **acc not written**.
