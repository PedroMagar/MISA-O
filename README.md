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
- **CFG #f**: Loads next instruction (4-bit) as CPU configuration.
- **Branches**: If true, will signal add lower 8-bit from ra[0] to PC:
  - **BEQz**: Branch if acc is Equal to Zero.
  - **BC**: Branch if Carry flag is currently filled as true.
  - **BTST**: BTST will test acc based on index apointed by rs0, acc is not written.
  - **TST**: Will utilize rs0 as a mask to acc and compare, acc is not written.
- **XOP**: Executes next instruction as Extended Operation.
- **XMEM #f**: Extended Memory Operations - Next instruction will be decoded as 4b0_0_0_0 where (from most to least significant bit):
  - 1-bit: Reserved:
    - 0: Default behavior.
    - 1: Future use.
  - 1-bit: Address flag:
    - 0: Utilizes ra0.
    - 1: Utilizes ra1.
  - 1-bit: Auto-increment flag:
    - 0: Disabled.
    - 1: Enabled.
  - 1-bit: Load/Store flag:
    - 0: Load.
    - 1: Store.
- **Interrupts**: Interrupts will work by storing the upper address on 'ia' (Interrupt Address) register, since 'ia' register is only 8-bit the address will be completed with zeros, when an interrupt arrives the cpu will then store all of it's registers at 'ia' location, update 'iar' (Interrupt Address Return), clear it's register (including configuration) and execute the instrucions after the stored data, when return arrives it will restore everything from 'iar' location. 
    - **SIA**: Will swap lower acc data with ia register (ia = acc[7:0] && acc[7:0] = ia).
    - **RETI**: Will restore registers from data on 'iar' location.
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

**CFG-R**: A way to read the configuration register is under consideration, currently a direct memory map would be the simplest.
