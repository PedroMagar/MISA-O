# MISA-O Special Instructions Test Plan (Revised)

This document outlines the verification plan for `tb_special.sv`. Since `RSx` and `RAx` are not directly observable, all verifications must be performed by swapping values back to `ACC` (`test_data`).

**Key Verification Goals**:
1.  **Indirect Observation**: Verify `RS0`, `RS1`, `RA0`, `RA1` by swapping content to `ACC`.
2.  **Partial vs Full Swap**:
    -   **SS (UL)**: Verify only the lowest nibble is swapped, preserving high nibbles of `ACC`.
    -   **SA (UL)**: Verify the full 16-bit value is swapped regardless of Link Mode.
3.  **Stack Rotation**: Verify `RSS` and `RSA` by loading distinct values into index 0 and 1 registers and rotating them.

## Test Sequence

### Phase 1: Setup & Pattern Loading
**Goal**: Initialize `ACC` with a known 16-bit pattern (`0xAAAA`) to verify partial swaps later.
**Mode**: LK16.

| Step | Address | Byte Value | Opcode/Imm | Description | Expected State |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | `0x01` | `0x18` | `XOP`, `CFG` | Enable Extended, CFG Op. | |
| **2** | `0x02` | `0x4E` | `0xE`, `0x4` | Imm `0x4E` (LK16). | `CFG = LK16` |
| **3** | `0x03` | `0xA4` | `LDi`, `0xA` | Load `0xA`. | |
| **4** | `0x04` | `0xAA` | `0xA`, `0xA` | Load `0xA`, `0xA`. | |
| **5** | `0x05` | `0x0A` | `0xA`, `NOP` | Load `0xA`. Total `0xAAAA`. | `ACC = 0xAAAA` |

### Phase 2: SS (Swap Source) in UL Mode
**Goal**: Verify `SS` only swaps the lowest nibble in UL mode, leaving `ACC[15:4]` (`0xAAA`) intact.
**Mode**: Switch to UL.

| Step | Address | Byte Value | Opcode/Imm | Description | Expected State |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **6** | `0x06` | `0x18` | `XOP`, `CFG` | Enable Extended, CFG Op. | |
| **7** | `0x07` | `0x4C` | `0xC`, `0x4` | Imm `0x4C` (UL). | `CFG = UL` |
| **8** | `0x08` | `0x14` | `LDi`, `0x1` | `ACC[0] = 1`. `ACC` was `0xAAAA` -> `0xAAA1`. | `ACC = 0xAAA1` |
| **9** | `0x09` | `0xE0` | `NOP`, `SS` | Swap `ACC[0]` (`1`) <-> `RS0[3:0]` (`0`). <br> `ACC` becomes `0xAAA0`. `RS0` becomes `...1`. | `ACC = 0xAAA0` |
| **10** | `0x0A` | `0x24` | `LDi`, `0x2` | `ACC[0] = 2`. `ACC` -> `0xAAA2`. | `ACC = 0xAAA2` |
| **11** | `0x0B` | `0xE0` | `NOP`, `SS` | Swap `ACC[0]` (`2`) <-> `RS0[3:0]` (`1`). <br> `ACC` becomes `0xAAA1`. `RS0` becomes `...2`. | `ACC = 0xAAA1` |
| **CHECK** | | | | **Verify ACC is 0xAAA1** | |

### Phase 3: SA (Swap Address) in UL Mode
**Goal**: Verify `SA` swaps the FULL 16-bit value even in UL mode.
**Mode**: UL (Already set).

| Step | Address | Byte Value | Opcode/Imm | Description | Expected State |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **12** | `0x0C` | `0xE8` | `XOP`, `SA` | Swap `ACC` (`0xAAA1`) <-> `RA0` (`0`). <br> `ACC` -> `0x0000`. `RA0` -> `0xAAA1`. | `ACC = 0x0000` |
| **13** | `0x0D` | `0x54` | `LDi`, `0x5` | `ACC[0] = 5`. `ACC` -> `0x0005`. | `ACC = 0x0005` |
| **14** | `0x0E` | `0xE8` | `XOP`, `SA` | Swap `ACC` (`0x0005`) <-> `RA0` (`0xAAA1`). <br> `ACC` -> `0xAAA1`. `RA0` -> `0x0005`. | `ACC = 0xAAA1` |
| **CHECK** | | | | **Verify ACC is 0xAAA1** | |

### Phase 4: RSS (Rotate Stack Source)
**Goal**: Verify `RSS` swaps `RS0` and `RS1`.
**Mode**: Switch to LK16 (for easier full-register loading).

| Step | Address | Byte Value | Opcode/Imm | Description | Expected State |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **15** | `0x0F` | `0x18` | `XOP`, `CFG` | | |
| **16** | `0x10` | `0x4E` | `0xE`, `0x4` | Imm `0x4E` (LK16). | `CFG = LK16` |
| **17** | `0x11` | `0xB4` | `LDi`, `0xB` | Load `0xBBBB`. | |
| **18** | `0x12` | `0xBB` | `0xB`, `0xB` | | |
| **19** | `0x13` | `0x0B` | `0xB`, `NOP` | `ACC = 0xBBBB`. | |
| **20** | `0x14` | `0xE0` | `NOP`, `SS` | Swap `ACC` <-> `RS0`. `RS0`=`0xBBBB`. `ACC`=`...2` (from Phase 2). | |
| **21** | `0x15` | `0xA0` | `NOP`, `RSS` | Rotate `RS0` (`0xBBBB`) <-> `RS1` (`0`). <br> `RS0`=`0`. `RS1`=`0xBBBB`. | |
| **22** | `0x16` | `0xC4` | `LDi`, `0xC` | Load `0xCCCC`. | |
| **23** | `0x17` | `0xCC` | `0xC`, `0xC` | | |
| **24** | `0x18` | `0x0C` | `0xC`, `NOP` | `ACC = 0xCCCC`. | |
| **25** | `0x19` | `0xE0` | `NOP`, `SS` | Swap `ACC` <-> `RS0`. `RS0`=`0xCCCC`. | |
| **26** | `0x1A` | `0xA0` | `NOP`, `RSS` | Rotate `RS0` (`0xCCCC`) <-> `RS1` (`0xBBBB`). <br> `RS0`=`0xBBBB`. `RS1`=`0xCCCC`. | |
| **27** | `0x1B` | `0xE0` | `NOP`, `SS` | Swap `ACC` <-> `RS0`. `ACC`=`0xBBBB`. | `ACC = 0xBBBB` |
| **CHECK** | | | | **Verify ACC is 0xBBBB** | |

### Phase 5: RSA (Rotate Stack Address)
**Goal**: Verify `RSA` swaps `RA0` and `RA1`.
**Mode**: LK16 (Already set).

| Step | Address | Byte Value | Opcode/Imm | Description | Expected State |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **28** | `0x1C` | `0x14` | `LDi`, `0x1` | Load `0x1111`. | |
| **29** | `0x1D` | `0x11` | `0x1`, `0x1` | | |
| **30** | `0x1E` | `0x01` | `0x1`, `NOP` | `ACC = 0x1111`. | |
| **31** | `0x1F` | `0xE8` | `XOP`, `SA` | Swap `ACC` <-> `RA0`. `RA0`=`0x1111`. | |
| **32** | `0x20` | `0xA8` | `XOP`, `RSA` | Rotate `RA0` (`0x1111`) <-> `RA1` (`0`). <br> `RA0`=`0`. `RA1`=`0x1111`. | |
| **33** | `0x21` | `0x24` | `LDi`, `0x2` | Load `0x2222`. | |
| **34** | `0x22` | `0x22` | `0x2`, `0x2` | | |
| **35** | `0x23` | `0x02` | `0x2`, `NOP` | `ACC = 0x2222`. | |
| **36** | `0x24` | `0xE8` | `XOP`, `SA` | Swap `ACC` <-> `RA0`. `RA0`=`0x2222`. | |
| **37** | `0x25` | `0xA8` | `XOP`, `RSA` | Rotate `RA0` (`0x2222`) <-> `RA1` (`0x1111`). <br> `RA0`=`0x1111`. `RA1`=`0x2222`. | |
| **38** | `0x26` | `0xE8` | `XOP`, `SA` | Swap `ACC` <-> `RA0`. `ACC`=`0x1111`. | `ACC = 0x1111` |
| **CHECK** | | | | **Verify ACC is 0x1111** | |

### Phase 6: RRS (Rotate Register Source)
**Goal**: Verify `RRS` rotates `RS0`.
**Mode**: Switch to UL (RRS is NOP in LK16).

| Step | Address | Byte Value | Opcode/Imm | Description | Expected State |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **39** | `0x27` | `0x18` | `XOP`, `CFG` | | |
| **40** | `0x28` | `0x4C` | `0xC`, `0x4` | Imm `0x4C` (UL). | `CFG = UL` |
| **41** | `0x29` | `0x44` | `LDi`, `0x4` | `ACC[0] = 4`. | |
| **42** | `0x2A` | `0xE0` | `NOP`, `SS` | Swap `ACC[0]` <-> `RS0[3:0]`. <br> `RS0` was `...` (from Phase 4, `RS0` was `0xCCCC` swapped out, so `RS0` held old `ACC` which was `0xCCCC`? No, `SS` swapped `ACC`(`...`) with `RS0`(`0xCCCC`). So `RS0` is `...`. Let's assume we reset or just check rotation logic). <br> Let's just load `0x1` into `RS0` low nibble. | |
| **43** | `0x2B` | `0x14` | `LDi`, `0x1` | `ACC[0] = 1`. | |
| **44** | `0x2C` | `0xE0` | `NOP`, `SS` | `RS0[3:0] = 1`. | |
| **45** | `0x2D` | `0x68` | `XOP`, `RRS` | Rotate `RS0`. `0x...1` -> `0x1...`. | |
| **46** | `0x2E` | `0xE0` | `NOP`, `SS` | Swap `ACC[0]` <-> `RS0[3:0]`. `RS0` low nibble should be `0` (if rotated away). | `ACC[0] = 0` |
| **CHECK** | | | | **Verify ACC[0] is 0** | |

# MISA-O ALU Test Plan

This section outlines the verification plan for `tb_alu_full.sv`.

**Key Verification Goals**:
1.  **Arithmetic**: ADD, SUB, INC, DEC.
2.  **Logic**: AND, OR, XOR, INV.
3.  **Shifts**: SHL, SHR.
4.  **Carry Flag**: Verify `test_carry` output for all operations.
5.  **Link Modes**: Verify operations in UL (4-bit), LK8 (8-bit), and LK16 (16-bit) modes.

## Test Sequence

### Phase 1: UL Mode (4-bit) Arithmetic
**Mode**: UL (Default/Reset).

| Step | Address | Byte Value | Opcode/Imm | Description | Expected State |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | `0x01` | `0x18` | `XOP`, `CFG` | | |
| **2** | `0x02` | `0x4C` | `0xC`, `0x4` | Imm `0x4C` (UL, CEN=1). | `CFG = UL` |
| **3** | `0x03` | `0x54` | `LDi`, `0x5` | `ACC = 5`. | |
| **4** | `0x04` | `0xE0` | `NOP`, `SS` | `RS0 = 5`. | |
| **5** | `0x05` | `0x34` | `LDi`, `0x3` | `ACC = 3`. | |
| **6** | `0x06` | `0x30` | `NOP`, `ADD` | `ACC = 3 + 5 = 8`. | `ACC=0x0008`, `C=0` |
| **7** | `0x07` | `0x30` | `NOP`, `ADD` | `ACC = 8 + 5 = 13 (0xD)`. | `ACC=0x000D`, `C=0` |
| **8** | `0x08` | `0x30` | `NOP`, `ADD` | `ACC = 13 + 5 = 18 (0x12)`. <br> 4-bit overflow: `0x2`. Carry=1. | `ACC=0x0002`, `C=1` |
| **9** | `0x09` | `0x10` | `NOP`, `CC` | Clear Carry. | `C=0` |
| **10** | `0x0A` | `0xB0` | `NOP`, `INC` | `ACC = 2 + 1 = 3`. | `ACC=0x0003`, `C=0` |
| **11** | `0x0B` | `0x38` | `XOP`, `SUB` | `ACC = 3 - 5`. <br> `3 - 5 = -2 (0xE)`. Borrow=1. | `ACC=0x000E`, `C=1` |

### Phase 2: UL Mode Logic & Shifts
**Mode**: UL.

| Step | Address | Byte Value | Opcode/Imm | Description | Expected State |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **12** | `0x0C` | `0xC4` | `LDi`, `0xC` | `ACC = 0xC`. | |
| **13** | `0x0D` | `0xE0` | `NOP`, `SS` | `RS0 = 0xC`. | |
| **14** | `0x0E` | `0xA4` | `LDi`, `0xA` | `ACC = 0xA`. | |
| **15** | `0x0F` | `0x50` | `NOP`, `AND` | `ACC = 0xA & 0xC = 0x8`. | `ACC=0x0008` |
| **16** | `0x10` | `0x90` | `NOP`, `OR` | `ACC = 0x8 | 0xC = 0xC`. | `ACC=0x000C` |
| **17** | `0x11` | `0x98` | `XOP`, `XOR` | `ACC = 0xC ^ 0xC = 0x0`. | `ACC=0x0000` |
| **18** | `0x12` | `0x58` | `XOP`, `INV` | `ACC = ~0x0 = 0xF`. | `ACC=0x000F` |
| **19** | `0x13` | `0xD0` | `NOP`, `SHL` | `ACC = 0xF << 1 = 0xE`. Carry=1. | `ACC=0x000E`, `C=1` |
| **20** | `0x14` | `0xD8` | `XOP`, `SHR` | `ACC = 0xE >> 1 = 0x7`. Carry=0. | `ACC=0x0007`, `C=0` |

### Phase 3: LK8 Mode Arithmetic
**Mode**: LK8.

| Step | Address | Byte Value | Opcode/Imm | Description | Expected State |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **21** | `0x15` | `0x18` | `XOP`, `CFG` | | |
| **22** | `0x16` | `0x4D` | `0xD`, `0x4` | Imm `0x4D` (LK8). | `CFG = LK8` |
| **23** | `0x17` | `0x14` | `LDi`, `0x1` | `ACC = 0x01`. | |
| **24** | `0x18` | `0x00` | `0x0`, `NOP` | `ACC = 0x01`. | |
| **25** | `0x19` | `0xE0` | `NOP`, `SS` | `RS0 = 0x01`. | |
| **26** | `0x1A` | `0xF4` | `LDi`, `0xF` | `ACC = 0xFF`. | |
| **27** | `0x1B` | `0x0F` | `0xF`, `NOP` | `ACC = 0xFF`. | |
| **28** | `0x1C` | `0x30` | `NOP`, `ADD` | `ACC = 0xFF + 0x01 = 0x00`. Carry=1. | `ACC=0x0000`, `C=1` |

### Phase 4: LK16 Mode Arithmetic
**Mode**: LK16.

| Step | Address | Byte Value | Opcode/Imm | Description | Expected State |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **29** | `0x1D` | `0x18` | `XOP`, `CFG` | | |
| **30** | `0x1E` | `0x4E` | `0xE`, `0x4` | Imm `0x4E` (LK16). | `CFG = LK16` |
| **31** | `0x1F` | `0x14` | `LDi`, `0x1` | `ACC = 0x0001`. | |
| **32** | `0x20` | `0x00` | `0x0`, `0x0` | | |
| **33** | `0x21` | `0x00` | `0x0`, `NOP` | | |
| **34** | `0x22` | `0xE0` | `NOP`, `SS` | `RS0 = 0x0001`. | |
| **35** | `0x23` | `0xF4` | `LDi`, `0xF` | `ACC = 0xFFFF`. | |
| **36** | `0x24` | `0xFF` | `0xF`, `0xF` | | |
| **37** | `0x25` | `0x0F` | `0xF`, `NOP` | | |
| **38** | `0x26` | `0x30` | `NOP`, `ADD` | `ACC = 0xFFFF + 0x0001 = 0x0000`. Carry=1. | `ACC=0x0000`, `C=1` |

# MISA-O Control Instructions Test Plan

This section outlines the verification plan for `tb_control_branch.sv`.

**Key Verification Goals**:
1.  **Conditional Branches**: `BEQZ` (Zero), `BC` (Carry).
2.  **Unconditional Jumps**: `JMP`, `JAL` (Link).
3.  **Bit Tests**: `BTST` (Set Carry).
4.  **Relative Offsets**: Verify forward skipping.

## Test Sequence

### Phase 1: Conditional Branches (UL Mode)
**Mode**: UL (Default/Reset).

| Step | Address | Byte Value | Opcode/Imm | Description | Expected State |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | `0x01` | `0x18` | `XOP`, `CFG` | | |
| **2** | `0x02` | `0x4C` | `0xC`, `0x4` | Imm `0x4C` (UL, CEN=1). | `CFG = UL` |
| **3** | `0x03` | `0x04` | `LDi`, `0x0` | `ACC = 0`. | |
| **4** | `0x04` | `0x27` | `BEQZ`, `0x2` | `BEQZ +2`. `ACC=0`, so Taken. <br> Target = PC_next(0x05) + 2 = 0x07. | PC -> 0x07 |
| **5** | `0x05` | `0xF4` | `LDi`, `0xF` | Skipped. | |
| **6** | `0x06` | `0xF4` | `LDi`, `0xF` | Skipped. | |
| **7** | `0x07` | `0x14` | `LDi`, `0x1` | `ACC = 1`. | `ACC=0x0001` |
| **8** | `0x08` | `0x27` | `BEQZ`, `0x2` | `BEQZ +2`. `ACC=1`, Not Taken. | PC -> 0x09 |
| **9** | `0x09` | `0x24` | `LDi`, `0x2` | `ACC = 2`. | `ACC=0x0002` |

### Phase 2: Bit Test & Branch Carry
**Mode**: UL.

| Step | Address | Byte Value | Opcode/Imm | Description | Expected State |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **10** | `0x0A` | `0x34` | `LDi`, `0x3` | `ACC = 3 (0011)`. | |
| **11** | `0x0B` | `0x04` | `LDi`, `0x0` | `ACC = 0`. (Wait, need RS0 for BTST). <br> `BTST` uses `RS0[3:0]` as index. | |
| **12** | `0x0C` | `0x14` | `LDi`, `0x1` | `ACC = 1`. | |
| **13** | `0x0D` | `0xE0` | `NOP`, `SS` | `RS0 = 1`. | |
| **14** | `0x0E` | `0x34` | `LDi`, `0x3` | `ACC = 3 (0011)`. | |
| **15** | `0x0F` | `0xF1` | `BTST`, `0x1` | `BTST` bit 1 of `ACC`. `ACC[1]` is 1. <br> Sets Carry=1. Imm ignored? No, `BTST` is `1111`. Opcode is `F`. Imm is `1`? `BTST` format is `F` `imm`. Wait, `BTST` uses `RS0` as index? `README`: `BTST #imm`: Tests bit `acc[idx]` where `idx = rs0[3:0]`. Imm is unused? Or is it `BTST` opcode `F` and imm is... wait. <br> `BTST` is `1111`. If it's `BTST #imm`, the imm is likely the bit index if `RS0` isn't used? <br> README says: `BTST #imm`: Tests bit `acc[idx]` where `idx = rs0[3:0]`. This implies `imm` is NOT the index. `imm` might be unused or for branch? No, `BTST` is not a branch. <br> Let's assume `BTST` uses `RS0` as index and sets Carry. | `C=1` |
| **16** | `0x10` | `0x08` | `XOP`, `0x0` | XOP Prefix. | |
| **17** | `0x11` | `0x27` | `BC`, `0x2` | `BC +2`. `C=1`, Taken. <br> Target = 0x12 + 2 = 0x14. (Wait, PC_next is 12). | PC -> 0x14 |
| **18** | `0x12` | `0xF4` | `LDi`, `0xF` | Skipped. | |
| **19** | `0x13` | `0xF4` | `LDi`, `0xF` | Skipped. | |
| **20** | `0x14` | `0x54` | `LDi`, `0x5` | `ACC = 5`. | `ACC=0x0005` |

### Phase 3: Unconditional Jumps (JMP/JAL)
**Mode**: UL.

| Step | Address | Byte Value | Opcode/Imm | Description | Expected State |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **21** | `0x15` | `0xE4` | `LDi`, `0xE` | `ACC = E`. | |
| **22** | `0x16` | `0x14` | `LDi`, `0x1` | `ACC = 1E`. | |
| **23** | `0x17` | `0xE8` | `XOP`, `SA` | `RA0 = 0x001E`. | |
| **24** | `0x18` | `0x08` | `XOP`, `0x0` | XOP Prefix. | |
| **25** | `0x19` | `0x28` | `JMP`, `0x8` | `JMP RA0` (0x1E). | PC -> 0x1E |
| **26** | `0x1A` | `0xFF` | `0xF`, `0xF` | Skipped. | |
| **27** | `0x1B` | `0xFF` | `0xF`, `0xF` | Skipped. | |
| **28** | `0x1C` | `0xFF` | `0xF`, `0xF` | Skipped. | |
| **29** | `0x1D` | `0xFF` | `0xF`, `0xF` | Skipped. | |
| **30** | `0x1E` | `0x54` | `LDi`, `0x5` | `ACC = 5`. | `ACC=0x0005` |

### Phase 4: JAL Test
**Goal**: Verify `JAL` updates `RA1`.
**Mode**: UL.

| Step | Address | Byte Value | Opcode/Imm | Description | Expected State |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **31** | `0x1F` | `0x84` | `LDi`, `0x8` | `ACC = 8`. | |
| **32** | `0x20` | `0x24` | `LDi`, `0x2` | `ACC = 28`. | |
| **33** | `0x21` | `0xE8` | `XOP`, `SA` | `RA0 = 0x0028`. | |
| **34** | `0x22` | `0x02` | `JAL`, `0x0` | `JAL`. `PC` -> `RA0` (0x28). `RA1` -> 0x23. | PC -> 0x28 |
| **35** | `0x23` | `0xE8` | `XOP`, `SA` | Swap `ACC` <-> `RA0`. `RA0` was `0x28`. `ACC` becomes `0x28`. | |
| **36** | `0x24` | `0xA8` | `XOP`, `RSA` | Swap `RA0` <-> `RA1`. `RA0` becomes `0x23`. | |
| **37** | `0x25` | `0xE8` | `XOP`, `SA` | Swap `ACC` <-> `RA0`. `ACC` becomes `0x23`. | `ACC=0x0023` |
| **...** | | | | | |
| **40** | `0x28` | `0xE8` | `XOP`, `SA` | Swap `ACC` <-> `RA0`. `ACC` was `0x28`. | |
| **41** | `0x29` | `0xA8` | `XOP`, `RSA` | Swap `RA0` <-> `RA1`. `RA1` was `0x23`. `RA0` becomes `0x23`. | |
| **42** | `0x2A` | `0xE8` | `XOP`, `SA` | Swap `ACC` <-> `RA0`. `ACC` becomes `0x23`. | `ACC=0x0023` |

# MISA-O XMEM Test Plan

This section outlines the verification plan for `tb_mem_xmem.sv`.

**Key Verification Goals**:
1.  **UL Mode**: Verify nibble load/store (partial updates).
2.  **LK8 Mode**: Verify byte load/store.
3.  **LK16 Mode**: Verify word load/store.
4.  **Post-Increment**: Verify address update.
5.  **Direction**: Verify decrement.
6.  **Addressing**: Verify use of RA1.

## Test Sequence

### Phase 1: Setup (LK16)
**Goal**: Initialize RA0 and RA1.
**Mode**: LK16.

| Step | Address | Byte Value | Opcode/Imm | Description | Expected State |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | `0x01` | `0x18` | `XOP`, `CFG` | | |
| **2** | `0x02` | `0x4E` | `0xE`, `0x4` | Imm `0x4E` (LK16). | `CFG = LK16` |
| **3** | `0x03` | `0x84` | `LDi`, `0x8` | `ACC = 0x8`. | |
| **4** | `0x04` | `0x00` | `0x0`, `0x0` | | |
| **5** | `0x05` | `0x00` | `0x0`, `NOP` | `ACC = 0x0080`. | |
| **6** | `0x06` | `0xE8` | `XOP`, `SA` | `RA0 = 0x0080`. | |
| **7** | `0x07` | `0x94` | `LDi`, `0x9` | `ACC = 0x9`. | |
| **8** | `0x08` | `0x00` | `0x0`, `0x0` | | |
| **9** | `0x09` | `0x00` | `0x0`, `NOP` | `ACC = 0x0090`. | |
| **10** | `0x0A` | `0xE8` | `XOP`, `SA` | `RA0 = 0x0090`. | |
| **11** | `0x0B` | `0xA8` | `XOP`, `RSA` | `RA1 = 0x0090`. `RA0` restored to `0x0080`. | |

### Phase 2: UL Mode Store/Load
**Mode**: UL.

| Step | Address | Byte Value | Opcode/Imm | Description | Expected State |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **12** | `0x0C` | `0x18` | `XOP`, `CFG` | | |
| **13** | `0x0D` | `0x4C` | `0xC`, `0x4` | Imm `0x4C` (UL). | `CFG = UL` |
| **14** | `0x0E` | `0x54` | `LDi`, `0x5` | `ACC = 5`. | |
| **15** | `0x0F` | `0xCC` | `XMEM`, `0xC` | Store UL @RA0 (0x80), Post-Inc. <br> `[0x80]` = `0x05`. `RA0` -> `0x81`. | `[0x80]=0x05` |
| **16** | `0x10` | `0x34` | `LDi`, `0x3` | `ACC = 3`. | |
| **17** | `0x11` | `0x8C` | `XMEM`, `0x8` | Store UL @RA0 (0x81), No Inc. <br> `[0x81]` = `0x03`. | `[0x81]=0x03` |
| **18** | `0x12` | `0x0C` | `XMEM`, `0x0` | Load UL @RA0 (0x81). <br> `ACC` = `0x3`. | `ACC=0x0003` |

### Phase 3: LK8 Mode Store/Load
**Mode**: LK8.

| Step | Address | Byte Value | Opcode/Imm | Description | Expected State |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **19** | `0x13` | `0x18` | `XOP`, `CFG` | | |
| **20** | `0x14` | `0x4D` | `0xD`, `0x4` | Imm `0x4D` (LK8). | `CFG = LK8` |
| **21** | `0x15` | `0xB4` | `LDi`, `0xB` | `ACC = 0xB`. | |
| **22** | `0x16` | `0x55` | `0x5`, `0x5` | `ACC = 0x5B`. | |
| **23** | `0x17` | `0xCC` | `XMEM`, `0xC` | Store Byte @RA0 (0x81), Post-Inc. <br> `[0x81]` = `0x5B`. `RA0` -> `0x82`. | `[0x81]=0x5B` |
| **24** | `0x18` | `0x04` | `LDi`, `0x0` | `ACC = 0`. | |
| **25** | `0x19` | `0x00` | `0x0`, `0x0` | `ACC = 0`. | |
| **26** | `0x1A` | `0x8C` | `XMEM`, `0x8` | Store Byte @RA0 (0x82). `[0x82]=0`. | |
| **27** | `0x1B` | `0x4C` | `XMEM`, `0x4` | Load Byte @RA0 (0x82), Post-Inc. <br> `ACC` = `0`. `RA0` -> `0x83`. | `ACC=0x0000` |
| **28** | `0x1C` | `0x6C` | `XMEM`, `0x6` | Load Byte @RA0 (0x83), Post-Dec (DIR=1). <br> `ACC` = `0` (Empty). `RA0` -> `0x82`. | |

### Phase 4: LK16 Mode & RA1
**Mode**: LK16.

| Step | Address | Byte Value | Opcode/Imm | Description | Expected State |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **29** | `0x1D` | `0x18` | `XOP`, `CFG` | | |
| **30** | `0x1E` | `0x4E` | `0xE`, `0x4` | Imm `0x4E` (LK16). | `CFG = LK16` |
| **31** | `0x1F` | `0x14` | `LDi`, `0x1` | `ACC = 1`. | |
| **32** | `0x20` | `0x22` | `0x2`, `0x2` | | |
| **33** | `0x21` | `0x33` | `0x3`, `0x3` | | |
| **34** | `0x22` | `0x44` | `0x4`, `0x4` | `ACC = 0x1234`. | |
| **35** | `0x23` | `0xCD` | `XMEM`, `0xD` | Store Word @RA1 (0x90), Post-Inc (AR=1). <br> `[0x90]=0x34`, `[0x91]=0x12`. `RA1` -> `0x92`. | `[0x90]=0x34` |
| **36** | `0x24` | `0x04` | `LDi`, `0x0` | `ACC = 0`. | |
| **37** | `0x25` | `0x00` | `0x0`, `0x0` | | |
| **38** | `0x26` | `0x00` | `0x0`, `0x0` | | |
| **39** | `0x27` | `0x00` | `0x0`, `0x0` | | |
| **40** | `0x28` | `0x6D` | `XMEM`, `0x6` | Load Word @RA1 (0x92), Post-Dec (DIR=1, AR=1). <br> `RA1` -> `0x90`. Load from `0x90`. <br> `ACC` = `0x1234`. | `ACC=0x1234` |
