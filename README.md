# MISA-O
**My ISA Origin** is a 4-bit MISC ISA made to be functional.
>The specification is still in development and there is still a long way to go...

## Architecture
MISA-O is a 4-bit architecture, it consist of one program counter register, four 4-bit operand register, two 16-bit operator register and two 16-bit memory address register. Operand register can be linked to work as 2x8-bit or 1x16-bit besides the original 4x4-bit mode, while active operator will always provide values accordingly with operand size. Logic operations will primarily be on Operand register and store the result in itself, while memory operation will use active memory address register as address. The Operand register can be rotated Left or right in sets (like operation Shift rotate left/right by 4).

### Characteristics:
- 1x16-bit PC (Program Counter) register.
- 4x4-bit rd (Operand / Register Destiny) register.
- 2x16-bit rs (Operator / Register Source) register.
- 2x16-bit addr (Address / Memory address) register.
- Link/Operation mode:
  - UL: 4-bit mode (Default - Unlink).
  - LK8: 8-bit mode (Link 8).
  - LK16: 16-bit mode (Link 16).
- Logic behaviour:
  - 0: Default behaviour.
  - 1: Inverse Logic behaviour (AND became NAND).
- RR (Rotate Register): It will treat Rd (Operand) as a single register and shift rotate it by "Operation mode" size.

## Instructions
The following table lists the architecture current instructions.

|Binary|Instruction |Description                             |
|------|------------|----------------------------------------|
| 0001 |AND         |                                        |
| 0101 |OR          |                                        |
| 1001 |XOR         | Exclusive OR                           |
| 1101 |SHF         | Shift Left                             |
| 0011 |ADDc        | Add with Carry                         |
| 1011 |INC         | Increment                              |
| 0111 |BEQz        | Branch if Equal Zero                   |
| 1111 |JAL         | Jump and Link                          |
| 0010 |NEG         | Negate                                 |
| 0110 |RR          | Rotate Register (rd)                   |
| 1010 |SR / SA     | Swap Register / Swap Address           |
| 1110 |LK          | Link Registers                         |
| 0100 |LD          | Load word                              |
| 1100 |LDi         | Load Immediate                         |
| 1000 |SW          | Store Word                             |
| 0000 |NOP         | No Operation                           |

Instructions under review:
- \* : Not mandatory instructions.
- **Bold**: Newly added / under review.
- **LDi/LD/SW**: Name can change to DLi/DL/DW to keep a patern on 'Data' operations.
- **LD/LDi**: Candidate for unification to spare instruction (becames negate).
- **BEQz/JAL**: Candidate for unification to spare instruction (becames negate).
- **SR/SA**: Initialy separeted, became united to spare space for LK operation.

### Development:
Currently there are some instructions that could became part of the ISA:
|Binary|Instruction |Description                             |
|------|------------|----------------------------------------|
| 0100 |BEQz / JAL  | Branch if Equal Zero / Jump and Link   |
| 0100 |LDi / LD    | Load Immediate / Load word             |
| 0000 |BC          | Branch if Carry                        |
| 0000 |ADD         | Add without Carry                      |
| 0000 |CLR         | Clear                                  |
| 0000 |INV         | Invert Register                        |
| 0000 |CLR         | Clear                                  |
| 0000 |RRS         | Rotate Source Register (rs)            |
