# MISA-O
**My ISA Version 0** is a 4-bit MISC ISA made to be functional.
>The specification is still under development...

## Architecture
MISA-O is a 4-bit architecture, it consist of one program counter register, four 4-bit operand register, two 16-bit operator register and two 16-bit memory address register. Operand register can be linked to work as 2x8-bit or 1x16-bit besides the original 4x4-bit mode, while active operator will always provide values accordingly with operand size. Logic operations will primarily be on Operand register and store the result in itself, while memory operation will use active memory address register as address. The Operand register can be rotated Left or right in sets (like operation Shift rotate left/right by 4).

### Characteristics:
- 1x16-bit PC (Program Counter) register.
- 4x4-bit rd (Operand / Register Destiny) register.
- 2x16-bit rs (Operator / Register Source) register.
- 2x16-bit addr (Address / Memory address) register.
  - addr0: Reference address.
  - add1: Return address.
- Link:
  - UL: 4-bit mode (Default - Unlink).
  - LK8: 8-bit mode (Link 8).
  - LK16: 16-bit mode (Link 16).
- Logic behaviour:
  - 0: Default behaviour.
  - 1: Inverse Logic behaviour (AND became NAND).
- RR (Rotate Register): It will treat Rd (Operand) as a single register and shift rotate it by "Operation mode" size.
- RS/RA: It will treat RS/RA as a stack and rotate it *(currently looks like a swap, but later on if more register where added it will truly rotate)*.
- JAL/JMP: All jumps will be based on register addr0, but linking would be saved on addr1
- LDc: 4-bit load where Loads CPU configuration, can be accessed by reading memory address 0: (from most to least significant)
  - b3: Auto-increment behaviour (default: 0, disable).
  - b2: Logic behaviour (default: 0, normal).
  - b1-0: Link mode (default: 00, Unlink).

## Instructions
The following table lists the architecture current instructions.

|Binary|Instruction |Negated     |Description                             |
|------|------------|------------|----------------------------------------|
| 0001 |AND         |NAND        |                                        |
| 0101 |OR          |NOR         |                                        |
| 1001 |XOR         |XNOR        |                                        |
| 1101 |SHL         |SHR         | Shift Left/Right                       |
| 0011 |ADDc        |SUBc        | Add/Sub with Carry                     |
| 1011 |INC         |DEC         | Increment/Decrement                    |
| 0111 |BEQz        |BC          | Branch if Equal Zero / Branch if Carry |
| 1111 |JAL         |JMP         | Jump and Link / Jump                   |
| 0010 |NEG         |NEG         | Negate                                 |
| 0110 |RR          |RL          | Rotate Register(rd) Right/Left         |
| 1010 |RS          |RA          | Rotate Source/Address Registers        |
| 1110 |**SS**      |**SA**      | Swap Source/Address Registers          |
| 0100 |LDi         |LD          | Load Immediate / Load word             |
| 1100 |SW          |SW          | Store Word                             |
| 1000 |**LDc**     |**LDc**     | Load Configuration                     |
| 0000 |NOP         |NOP         | No Operation                           |

Instructions under review:
- \* : Not mandatory instructions.
- **Bold**: Newly added / under review.
- **IMUL**: Feasibility/Usability of a Multiplication instruction is under review.
- **LK**: Link was demoted to be replaced by a more versatile "Load Configuration", now it's possible to enable auto increment when reading/writing from/to memory with the advantage of also be able to secure a known working state for the functions.

### Development:
Currently there are some instructions that could became part of the ISA:
|Binary|Instruction |Description                             |
|------|------------|----------------------------------------|
| 0000 |IMUL (!)    | Integer Multiplication                 |
| 0000 |**LK**      | Link Registers                         |

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

          |---------------------------------| 
       PC | 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 | 
          |---------------------------------| 

          |---------------------------------| 
    addr1 | 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 | 
          |---------------------------------| 
    addr0 | 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 | 
          |---------------------------------| 

          |---------------------------------| 
       rd | 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 | 
          |---------------------------------|

          |---------------------------------|
      rs0 | 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 |
          |---------------------------------|
      rs1 | 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 |
          |---------------------------------| 
