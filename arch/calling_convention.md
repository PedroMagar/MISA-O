## Calling Convention & Language Support

MISA-O is designed to support efficient compilation of high-level languages, particularly C, through a well-defined calling convention and architectural features that minimize overhead in function calls, stack management, and register allocation.

This section documents the **standard MISA-O calling convention**, register usage patterns, and best practices for language toolchains.

---

### Register Usage Convention

MISA-O defines a **caller-saved** and **callee-saved** register model to balance code density and performance across different function types.

#### Caller-Saved (Volatile) Registers

These registers are **not preserved** across function calls. The caller must save them if their values are needed after the call.

| Register | Alias | Purpose | Notes |
|----------|-------|---------|-------|
| **ACC** | — | Return value / scratch | Function result returned here |
| **RS0** | A0 | Argument 1 / scratch | First function argument |
| **RS1** | A1 | Argument 2 / scratch | Second function argument |
| **RA0** | LR | Jump / Link Register | Jump target and return address |
| **RA1** | BASE | Memory base address | Primary address register for XMEM |
| **GPR2** | T0 | Scratch / temp | CSR #3; free for any use across call |

**Rationale:** These registers are frequently modified and have short lifetimes. Requiring the callee to save them would increase prologue overhead unnecessarily. GPR2 is included as scratch to give compilers a fast temporary that avoids stack traffic in the common case.

#### Callee-Saved (Non-Volatile) Registers

These registers **must be preserved** by the callee if modified. The callee saves them in the prologue and restores them in the epilogue.

| Register | Alias | Purpose | CSR Index | Notes |
|----------|-------|---------|-----------|-------|
| **GPR1** | SP or S0 | Stack Pointer or saved register | #2 | See profile note below |
| **GPR3** | S1 | Saved register | #4 | General-purpose callee-saved |

**Profile Note:**
- **Baseline Profile** (required for C): GPR1-3 are available
- **Compact Profile**: GPRs may be unavailable (functions must use memory)

**Convention Recommendation:**
- **GPR1**: Stack Pointer (SP) by convention
- **GPR2**: Scratch / general-purpose temp
- **GPR3**: Callee-saved variable (save before use, restore before return)

---

### Function Call Sequence

#### 1. **Caller Responsibilities**

Before calling a function, the caller must:

1. **Place arguments** in RS0 and RS1 (first two args)
2. **Save caller-saved registers** if needed after the call
3. **Prepare target address** in RA0 via SA
4. **Execute JAL** to transfer control

**Example:**
```assembly
caller:
    ; Prepare arguments
    LDi #5
    SS                      ; RS0 ← 5 (arg1)
    LDi #10
    RSS
    SS                      ; RS1 ← 10 (arg2)
    RSS

    ; Prepare target address (LK16: LDi loads full 16-bit address)
    LDi #callee             ; ACC ← callee address (16-bit)
    SA                      ; RA0 ← callee addr,  ACC ← old_RA0

    ; JAL atomically: PC ← old_RA0 (callee); RA0 ← PC_next (link)
    JAL

    ; Result in ACC
```

**Arguments Beyond RS0/RS1:**
- Additional arguments are passed via **stack** (push before call, callee accesses via SP offset)

---

#### 2. **Callee Responsibilities**

##### A. **Leaf Function** (Does Not Call Others)

Minimal or no prologue needed:

```assembly
; Leaf function: add(a, b)
; Args: RS0=a, RS1=b
; Return: ACC=result
add:
    ; No prologue needed (doesn't call, doesn't use GPRs)

    ; ADD computes ACC+RS0. Load a from RS0 into ACC first, then put b in RS0.
    SS                      ; ACC ← a (RS0),  RS0 ← old_ACC
    RSS                     ; RS0 ← b (RS1),  RS1 ← old_RS0
    ADD                     ; ACC ← a + b  ✓

    JMP                     ; PC ← RA0 (return address)

; Prologue: 0 instructions ✅
; Epilogue: 1 instruction (JMP)
```

##### B. **Non-Leaf Function** (Calls Others)

On entry from JAL, **RA0 holds the return address** (link). The prologue must save it before JAL overwrites RA0 on the next inner call.

The key insight is that `CSRLD #2; SA` delivers the return address into ACC **for free**: SA swaps ACC↔RA0, and since RA0 enters holding the return address, the swap recovers it without extra instructions.

```assembly
; Non-leaf function: complex(a, b)
; Args: RS0=a, RS1=b
; Calls: add() and mul()
complex:
    ; === PROLOGUE (7 instructions) ===
    ; Push return address (RA0) onto the stack and update SP.
    ; RA0 enters holding return_addr (set by caller's JAL).
    CSRLD #2                ; ACC ← SP
    SA                      ; RA0 ← SP,            ACC ← return_addr  ← free via SA swap
    RSA                     ; RA1 ← SP,            RA0 ← old_RA1 (junk)
    XMEM #0b1110            ; pre-dec push: RA1 -= 2, [RA1] ← return_addr (ACC)
    RSA                     ; RA0 ← new_SP (RA1),  RA1 ← junk
    SA                      ; ACC ← new_SP,         RA0 ← return_addr
    CSRST #2                ; SP ← new_SP
    ; Clobbers: ACC, RA0, RA1.  RS0/RS1 preserved.

    ; Save a (RS0) → GPR2 (scratch — caller-saved, no restore needed)
    SS                      ; ACC ← a, RS0 ← old_ACC
    CSRST #3                ; GPR2 ← a
    ; Save b (RS1) → GPR3 (callee-saved — must restore before return)
    RSS                     ; RS0 ← b, RS1 ← old_RS0
    SS                      ; ACC ← b, RS0 ← a
    CSRST #4                ; GPR3 ← b

    ; === BODY ===
    ; Call add(a, b)
    CSRLD #4                ; ACC ← b (GPR3)
    SS                      ; RS0 ← b, ACC ← old_RS0
    RSS                     ; RS1 ← b, RS0 ← old_RS1
    CSRLD #3                ; ACC ← a (GPR2)
    SS                      ; RS0 ← a, ACC ← old_RS0

    LDi #add                ; ACC ← add address
    SA                      ; RA0 ← add addr, ACC ← old_RA0
    JAL                     ; PC ← RA0 (add); RA0 ← PC_next — 1 instr cheaper than old convention

    ; ... call mul(), combine results ...

    ; === EPILOGUE (8 instructions, including JMP) ===
    ; Pop return address from stack into RA0, restore SP, jump.
    CSRLD #2                ; ACC ← SP
    SA                      ; RA0 ← SP,            ACC ← old_RA0
    RSA                     ; RA1 ← SP,            RA0 ← old_RA1
    XMEM #0b0010            ; post-inc pop: ACC ← [RA1], RA1 += 2 (new_SP)
    RSA                     ; RA0 ← new_SP (RA1),  RA1 ← junk
    SA                      ; ACC ← new_SP,         RA0 ← return_addr  ← return_addr via swap
    CSRST #2                ; SP ← new_SP
    JMP                     ; PC ← RA0 (return_addr)
    ; Clobbers: ACC, RA0, RA1.

; Prologue:  7 instructions  (was 8 in old convention: -1)
; Each CALL: 3 instructions  (was 4 in old convention: -1 per call site)
; Epilogue:  8 instructions  (was 7 in old convention: +1)
; Net: prologue+epilogue = 15 (unchanged), every inner CALL saves 1 instruction.
```

##### C. **Function Using Callee-Saved Registers**

If a function modifies GPR3, it must save and restore it. GPR2 is caller-saved and may be used freely.

```assembly
func:
    ; === PROLOGUE ===
    ; PROLOGUE_NONLEAF macro (7 instructions)

    ; Save GPR3 before modifying it (callee-saved)
    CSRLD #4                ; ACC ← GPR3 (original value)
    PUSH_ACC                ; [SP] ← GPR3 (saved)

    ; === BODY ===
    CSRST #4                ; GPR3 ← local_var
    ; GPR2 (#3) is scratch — use freely

    ; === EPILOGUE ===
    ; Restore GPR3
    POP_ACC                 ; ACC ← saved GPR3 value
    CSRST #4                ; GPR3 ← restored value

    ; EPILOGUE_NONLEAF macro (8 instructions including JMP)
```

---

### Stack Management

#### Stack Pointer Convention

**GPR1** serves as the **Stack Pointer (SP)** by convention:

- **Grows downward** (decrements on push, increments on pop)
- **Points to the last valid item** (full descending stack)
- **Not automatically updated** by hardware (software manages)

#### LK16 Mode Requirement

All stack operations — PUSH, POP, prologue, and epilogue — **require LK16 mode** (`CFG.W = 10`) to be active. This is because:

- `CSRLD` / `CSRST` are only available in LK16 mode (the same opcode executes `RACC`/`RRS` in UL/LK8).
- `XMEM` stride is **2 bytes** in LK16, which is required to correctly advance SP over 16-bit values (return addresses, saved GPRs).

**Convention:** CFG.W = LK16 (`CFG #0b00000010`) must be in effect at all function call boundaries. Functions may temporarily change W for arithmetic and must restore it before any stack operation or return.

#### Stack Operations

The `SA` double-swap trick: executing `SA; CSRLD/CSRST; SA` in sequence recovers a value that was in RA0, because the two SA swaps cancel each other for ACC while RA0 absorbs the intermediate value. PROLOGUE exploits this at function entry where RA0 = return_addr.

For PUSH and POP, the same principle applies to load the value to push through two SA calls.

**PUSH ACC:**
```assembly
.macro PUSH_ACC
    ; Pushes ACC onto the stack.
    ; Requires: LK16 mode active (CFG.W = 10).
    ; Clobbers: RA0, RA1.  RS0/RS1 preserved.
    SA                      ; RA0 ← value (ACC),  ACC ← old_RA0
    CSRLD #2                ; ACC ← SP
    SA                      ; RA0 ← SP,            ACC ← value  ← double-SA restores value
    RSA                     ; RA1 ← SP,            RA0 ← old_RA1
    XMEM #0b1110            ; pre-dec push: RA1 -= 2, [RA1] ← value (ACC)
    RSA                     ; RA0 ← new_SP (RA1),  RA1 ← junk
    SA                      ; ACC ← new_SP,         RA0 ← value
    CSRST #2                ; SP ← new_SP
.endm
```

**POP ACC:**
```assembly
.macro POP_ACC
    ; Pops top of stack into ACC.
    ; Requires: LK16 mode active (CFG.W = 10).
    ; Clobbers: RA0, RA1.  RS0/RS1 preserved.
    CSRLD #2                ; ACC ← SP
    SA                      ; RA0 ← SP,             ACC ← old_RA0
    RSA                     ; RA1 ← SP,             RA0 ← old_RA1
    XMEM #0b0010            ; post-inc pop: ACC ← [RA1], RA1 += 2 (new_SP)
    RSA                     ; RA0 ← new_SP (RA1),   RA1 ← junk
    SA                      ; ACC ← new_SP,          RA0 ← popped_value
    CSRST #2                ; SP ← new_SP
    SA                      ; ACC ← popped_value,    RA0 ← new_SP
.endm
```

**Typical Stack Frame:**
```
High Memory
┌────────────────┐
│ Arg 3+         │ ← Caller pushes extra args
├────────────────┤
│ Saved RA0      │ ← Callee saves link register (return addr)
├────────────────┤
│ Saved GPRs     │ ← Callee saves GPR1/GPR3 if used
├────────────────┤
│ Local Vars     │ ← Callee allocates space
├────────────────┤
│ ...            │
└────────────────┘ ← SP (current stack pointer)
Low Memory
```

---

### Argument Passing

| Argument | Location | Notes |
|----------|----------|-------|
| 1st      | RS0 (A0) | Caller-saved |
| 2nd      | RS1 (A1) | Caller-saved |
| 3rd+     | Stack    | Pushed by caller, accessed via SP offset |

**Example: 3-argument function**

```c
int add3(int a, int b, int c) {
    return a + b + c;
}
```

**Caller:**
```assembly
main:
    ; Stack arg FIRST (PUSH_ACC clobbers RA0, not RS0/RS1 in the new version)
    LDi #3
    PUSH_ACC                ; Stack ← 3 (c)

    ; Args 1-2 in registers
    LDi #1
    SS                      ; RS0 ← 1 (a)
    LDi #2
    RSS
    SS                      ; RS1 ← 2 (b)
    RSS                     ; RS0 ← 1, RS1 ← 2  ✓

    LDi #add3               ; ACC ← add3 address
    SA                      ; RA0 ← add3 addr
    JAL                     ; call add3

    ; Clean up stack (stride=2 in LK16)
    CSRLD #2                ; ACC ← SP
    INC                     ; SP+1
    INC                     ; SP+2
    CSRST #2                ; SP ← SP+2

    ; Result in ACC
    JMP                     ; PC ← RA0 (return address)
```

**Callee (leaf):**
```assembly
add3:
    ; a in RS0, b in RS1, c at [SP]
    SS                      ; ACC ← a (RS0)
    RSS                     ; RS0 ← b (RS1)
    ADD                     ; ACC ← a + b

    CSRST #3                ; GPR2 ← (a+b)

    ; Load c from [SP] via RA1
    CSRLD #2                ; ACC ← SP
    SA                      ; RA0 ← SP,  ACC ← old_RA0
    RSA                     ; RA1 ← SP,  RA0 ← old_RA1
    XMEM #0b0000            ; ACC ← [RA1] = c  (load, no auto-modify)

    SS                      ; RS0 ← c
    CSRLD #3                ; ACC ← (a+b)
    ADD                     ; ACC ← (a+b) + c  ✓

    JMP                     ; PC ← RA0 (return address)
```

---

### Return Values

| Type | Location | Notes |
|------|----------|-------|
| Scalars (≤16-bit) | ACC | Standard return register |
| Structs (>16-bit) | Memory | Pointer passed as hidden first arg |

---

### Profile Requirements for C Compatibility

| Profile | GPR Support | C Support | Notes |
|---------|-------------|-----------|-------|
| **Baseline** | GPR1-3 | ✅ Yes | **Minimum for C** |
| **Baseline + Interrupt** | GPR1-3 + ISR | ✅ Yes | Full C + interrupts |

---

### Code Density Analysis

#### Instruction count by macro

| Macro | Old convention (RA1=LR) | New convention (RA0=LR) | Delta |
|-------|------------------------|------------------------|-------|
| **CALL** (setup + JAL) | 4 | **3** | **−1** |
| **JMP** (return) | 1 | 1 | 0 |
| **PROLOGUE_NONLEAF** | 8 | **7** | **−1** |
| **EPILOGUE_NONLEAF** | 7 | 8 | +1 |
| **PUSH_ACC** | 7 | 8 | +1 |
| **POP_ACC** | 6 | 8 | +2 |

#### Net effect on non-leaf functions

Prologue + Epilogue combined: **15 instructions in both conventions** (8+7 old, 7+8 new). The overhead to support re-entrant calls is identical.

Every **CALL site inside the function body saves 1 instruction**. Therefore:

| Function type | Net delta |
|---------------|-----------|
| Leaf | 0 (unchanged) |
| Non-leaf, 1 call | −1 |
| Non-leaf, N calls | −N |
| Non-leaf with M pushed GPRs, N calls | −N + M (push cost) |

**Conclusion:** In code with frequent function calls — the common case in C — the new convention produces **strictly smaller code**. Only functions that push many callee-saved GPRs with few call sites may see a marginal increase; these are uncommon in real-world codebases.

#### Code Density Comparison

| Function Type | MISA-O | ARM Thumb | RISC-V RVC |
|---------------|--------|-----------|------------|
| **Leaf** | 0-1 bytes | 0-2 bytes | 0-2 bytes |
| **Non-leaf (1 call)** | 13 bytes | 8 bytes | 18 bytes |
| **Non-leaf (complex)** | 22-28 bytes | 16-20 bytes | 30-36 bytes |

MISA-O's nibble encoding competes with RISC-V RVC and beats it on call-heavy code.

---

### Optimization Tips for Compilers

#### 1. **Minimize Prologue/Epilogue**

- **Leaf functions**: No prologue needed (0 bytes)
- **Tail calls**: Replace JAL+prologue/epilogue with a plain JMP to the target after setting up RA0, skipping both
- **Register windowing**: Use GPRs to avoid stack traffic

#### 2. **SA Double-Swap Trick**

The sequence `SA; <load ACC>; SA` recovers the original ACC value while temporarily routing it through RA0. This is used in PROLOGUE to capture `return_addr` from RA0 without burning an extra register:

```assembly
; Entry: RA0 = return_addr, ACC = ?
CSRLD #2        ; ACC ← SP
SA              ; RA0 ← SP,  ACC ← return_addr  ← free recovery of return_addr
; Now ACC = return_addr, ready to store
```

Similarly used in PUSH_ACC to route a value through RA0 while loading SP.

#### 3. **Leverage Post-Increment**

```assembly
; Efficient array/struct copy (requires LK16 mode for CSRLD)
; Setup: RA1 = source, RA0 = dest (via SA/RSA)
CSRLD #2                ; ACC ← source ptr
SA                      ; RA0 ← source,  ACC ← old_RA0
RSA                     ; RA1 ← source,  RA0 ← old_RA1
CSRLD #3                ; ACC ← dest ptr
SA                      ; RA0 ← dest,    ACC ← source (old RA0 from last SA)
; Now: RA1 = source, RA0 = dest

loop:
    XMEM #0b0100        ; ACC ← [RA1], RA1++  (load + post-increment source)
    RSA                 ; RA0 ↔ RA1  (RA1 = dest)
    XMEM #0b1100        ; [RA1] ← ACC, RA1++  (store + post-increment dest)
    RSA                 ; RA0 ↔ RA1  (RA1 = source)
    BRC #NE #loop
; Note: for bulk copies prefer MCPY (XOP;XMEM). MCPY: RA1=src, RA0=dst.
```

#### 4. **Use CFG.IMM for Constants**

```assembly
CFG #0x08               ; IMM=1
ADD #5                  ; immediate mode
CFG #0x00               ; IMM=0
```

---

### Toolchain Integration

#### Assembler Macros

```assembly
; Calling convention helpers.
; All macros below require LK16 mode (CFG.W = 10) to be active.

.macro CALL target
    ; Clobbers: RA0 (← PC_next after JAL), ACC (← old_RA0 after SA).
    LDi #target             ; ACC ← target address
    SA                      ; RA0 ← target,   ACC ← old_RA0
    JAL                     ; PC ← RA0 (atomic); RA0 ← PC_next (link)
.endm

.macro RET
    JMP                     ; PC ← RA0 (return address)
.endm

.macro PROLOGUE_NONLEAF
    ; Push return address (RA0) onto stack and update SP.
    ; Uses SA swap trick: CSRLD+SA delivers return_addr into ACC for free.
    ; Clobbers: ACC, RA0, RA1.  RS0/RS1 preserved.
    CSRLD #2                ; ACC ← SP
    SA                      ; RA0 ← SP,            ACC ← return_addr  (free via SA)
    RSA                     ; RA1 ← SP,            RA0 ← old_RA1
    XMEM #0b1110            ; pre-dec push: RA1 -= 2, [RA1] ← return_addr
    RSA                     ; RA0 ← new_SP (RA1),  RA1 ← junk
    SA                      ; ACC ← new_SP,         RA0 ← return_addr
    CSRST #2                ; SP ← new_SP
.endm

.macro EPILOGUE_NONLEAF
    ; Pop return address from stack into RA0, restore SP, and jump.
    ; Clobbers: ACC, RA0, RA1.
    CSRLD #2                ; ACC ← SP
    SA                      ; RA0 ← SP,            ACC ← old_RA0
    RSA                     ; RA1 ← SP,            RA0 ← old_RA1
    XMEM #0b0010            ; post-inc pop: ACC ← [RA1], RA1 += 2 (new_SP)
    RSA                     ; RA0 ← new_SP (RA1),  RA1 ← junk
    SA                      ; ACC ← new_SP,         RA0 ← return_addr
    CSRST #2                ; SP ← new_SP
    JMP                     ; PC ← RA0 (return_addr)
.endm

; Use:
my_func:
    PROLOGUE_NONLEAF
    ; ... body ...
    EPILOGUE_NONLEAF
```

#### Compiler Hints

```c
__attribute__((leaf))
int add(int a, int b) { return a + b; }   // no prologue

__attribute__((register("GPR2"))) int temp;        // scratch across calls
__attribute__((register("GPR3"))) int saved_local; // callee-saved local
__attribute__((always_inline)) inline int square(int x) { return x * x; }
```

---

### Summary

MISA-O provides a **C-friendly calling convention** with:

✅ Clear **caller-saved** vs **callee-saved** semantics  
✅ **Minimal prologue** for leaf functions (0 bytes)  
✅ **Efficient calls**: `LDi; SA; JAL` — 3 instructions (1 fewer than old convention)  
✅ **Neutral prologue/epilogue overhead**: combined 15 instructions in both conventions  
✅ **Net code reduction** in call-heavy code: every call site inside a non-leaf function saves 1 instruction  
✅ **SA double-swap trick** avoids extra moves when recovering register values  
✅ **Macro-friendly** assembly (hide complexity behind CALL/PROLOGUE/EPILOGUE)
