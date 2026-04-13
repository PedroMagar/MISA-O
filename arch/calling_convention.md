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
| **RA0** | TEMP | Address calculation | Temporary address register |
| **RA1** | LR | Link Register | Return address (set by JAL) |
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
3. **Prepare target address** in RA0
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
    
    ; If caller needs RA1 later, save it:
    ; [save RA1 to stack or GPR]
    
    ; Prepare target address (LK16: LDi loads full 16-bit address)
    LDi #callee             ; ACC ← callee address (16-bit)
    SA                      ; RA0 ← callee addr,  ACC ← old_RA0
    
    ; Call
    JAL                     ; RA1 ← PC_next, PC ← RA0
    
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

    RSA                     ; RA0 ← RA1 (return address)
    JMP                     ; PC ← RA0

; Prologue: 0 instructions ✅
; Epilogue: 2 instructions (RSA + JMP)
```

##### B. **Non-Leaf Function** (Calls Others)

Must save **RA1** (link register) because it will be overwritten by nested JAL:

```assembly
; Non-leaf function: complex(a, b)
; Args: RS0=a, RS1=b
; Calls: add() and mul()
complex:
    ; === PROLOGUE ===
    ; Save RA1 (link register). Requires LK16 mode (CFG.W = 10).
    CSRLD #2                ; ACC ← SP
    SA                      ; RA0 ← SP,           ACC ← old_RA0
    RSA                     ; RA0 ← return_addr,  RA1 ← SP
    SA                      ; ACC ← return_addr,  RA0 ← old_RA0
    RSA                     ; RA0 ← SP,           RA1 ← old_RA0 (caller's RA0)
    XMEM #0b1110            ; pre-dec push: RA0--, [RA0] ← return_addr (stride=2)
    SA                      ; ACC ← new_SP,       RA0 ← return_addr
    CSRST #2                ; SP ← new_SP

    ; Save a (RS0) → GPR2 (scratch — no save/restore needed)
    SS                      ; ACC ← a, RS0 ← old_ACC
    CSRST #3                ; GPR2 ← a
    ; Save b (RS1) → GPR3 (callee-saved — must be restored before return)
    RSS                     ; RS0 ← b, RS1 ← old_RS0
    SS                      ; ACC ← b, RS0 ← a
    CSRST #4                ; GPR3 ← b
    
    ; === BODY ===
    ; Call add(a, b)
    ; Reload b → RS1 first
    CSRLD #4                ; ACC ← b (GPR3)
    SS                      ; RS0 ← b, ACC ← old_RS0
    RSS                     ; RS1 ← b, RS0 ← old_RS1
    ; Reload a → RS0
    CSRLD #3                ; ACC ← a (GPR2)
    SS                      ; RS0 ← a, ACC ← old_RS0
    ; Result: RS0=a, RS1=b
    
    LDi #add                ; ACC ← add address (LK16: full 16-bit)
    SA                      ; RA0 ← add addr, ACC ← old_RA0
    JAL                     ; Call add
    
    ; ACC has add result, save it
    ; [use GPR or stack]
    
    ; Call mul(a, b)
    ; [similar setup]
    ; JAL
    
    ; Combine results
    ; ...
    
    ; === EPILOGUE === (requires LK16 mode)
    CSRLD #2                ; ACC ← SP
    SA                      ; RA0 ← SP,           ACC ← old_RA0
    XMEM #0b0010            ; post-inc pop: ACC ← [RA0], RA0++ (stride=2)
    SA                      ; ACC ← new_SP,        RA0 ← return_addr
    CSRST #2                ; SP ← new_SP
    JMP                     ; PC ← RA0 (return_addr)

; Prologue: ~7 bytes, ~6 instructions
; Epilogue: ~7 bytes, ~7 instructions
```

##### C. **Function Using Callee-Saved Registers**

If a function modifies GPR1 or GPR3, it must save and restore them. GPR2 is caller-saved and may be used freely without save/restore.

```assembly
func:
    ; === PROLOGUE ===
    ; Save RA1 and update SP (PROLOGUE_NONLEAF or inline, ~8 instructions)
    ; [as above]
    
    ; Save GPR3 before modifying it (callee-saved)
    CSRLD #4                ; ACC ← GPR3 (original value)
    PUSH_ACC                ; [SP] ← GPR3 (saved)
    
    ; === BODY ===
    ; Use GPR3 as a local variable
    CSRST #4                ; GPR3 ← local_var
    ; GPR2 (#3) is scratch — use freely
    
    ; === EPILOGUE ===
    ; Restore GPR3
    POP_ACC                 ; ACC ← saved GPR3 value
    CSRST #4                ; GPR3 ← restored value
    
    ; Restore RA1 from stack and return
    ; EPILOGUE_NONLEAF pops return_addr → RA0, restores SP, then JMPs.
    ; Do NOT add RSA+JMP after this — RA1 holds caller's RA0, not return_addr.
    ; [EPILOGUE_NONLEAF or inline, ~6 instructions + JMP]
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
- `SS` respects `CFG.W`; loading 16-bit arguments requires LK16.

**Convention:** CFG.W = LK16 (`CFG #0b00000010`) must be in effect at all function call boundaries. Functions may temporarily change W for arithmetic and must restore it before any stack operation or return.

#### Stack Operations

**PUSH ACC:**
```assembly
.macro PUSH_ACC
    ; Pushes ACC onto the stack.
    ; Requires: LK16 mode active (CFG.W = 10) — stride=2, CSRLD/CSRST valid.
    ; Clobbers: RA0, RS0 (both caller-saved).
    SS                      ; RS0 ← value,          ACC ← old_RS0
    CSRLD #2                ; ACC ← SP
    SA                      ; RA0 ← SP,             ACC ← old_RA0
    SS                      ; ACC ← value (RS0),    RS0 ← old_RA0
    XMEM #0b1110            ; pre-dec push: RA0 -= 2, [RA0] ← value
    SA                      ; ACC ← new_SP,         RA0 ← value
    CSRST #2                ; SP ← new_SP
.endm
```

**POP ACC:**
```assembly
.macro POP_ACC
    ; Pops top of stack into ACC.
    ; Requires: LK16 mode active (CFG.W = 10) — stride=2, CSRLD/CSRST valid.
    ; Clobbers: RA0 (left holding new_SP after macro).
    CSRLD #2                ; ACC ← SP
    SA                      ; RA0 ← SP,             ACC ← old_RA0
    XMEM #0b0010            ; post-inc pop: ACC ← [RA0], RA0 += 2
    SA                      ; ACC ← new_SP,         RA0 ← popped_value
    CSRST #2                ; SP ← new_SP
    SA                      ; ACC ← popped_value,   RA0 ← new_SP
.endm
```

**Typical Stack Frame:**
```
High Memory
┌────────────────┐
│ Arg 3+         │ ← Caller pushes extra args
├────────────────┤
│ Saved RA1      │ ← Callee saves link register
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

int main() {
    return add3(1, 2, 3);
}
```

**Caller:**
```assembly
main:
    ; Stack arg FIRST — PUSH_ACC clobbers RS0 (first instruction is SS: ACC↔RS0).
    ; Push before loading register args to avoid overwriting them.
    LDi #3
    PUSH_ACC                ; Stack ← 3 (c)

    ; Args 1-2 in registers (set after stack args are pushed)
    LDi #1
    SS                      ; RS0 ← 1 (a)
    LDi #2
    RSS
    SS                      ; RS0 ← 2, (paired with next RSS →) RS1 ← 2 (b)
    RSS                     ; RS0 ← 1 (a),   RS1 ← 2 (b)  ✓
    
    ; Call (LK16: LDi loads full 16-bit address)
    LDi #add3               ; ACC ← add3 address
    SA                      ; RA0 ← add3 addr, ACC ← old_RA0
    JAL
    
    ; Clean up stack (caller cleanup — LK16 PUSH used stride=2)
    CSRLD #2                ; ACC ← SP
    INC                     ; SP+1
    INC                     ; SP+2
    CSRST #2                ; SP ← SP+2
    
    ; Result in ACC
    RSA                     ; RA0 ← RA1 (return address)
    JMP                     ; Return from main
```

**Callee:**
```assembly
add3:
    ; a in RS0, b in RS1, c at [SP] (top of stack — no prologue, no RA1 push)
    
    ; ADD computes ACC+RS0. Load a into ACC first, then put b in RS0.
    SS                      ; ACC ← a (RS0), RS0 ← old_ACC
    RSS                     ; RS0 ← b (RS1), RS1 ← old_RS0
    ADD                     ; ACC ← a + b  ✓
    
    ; Save (a+b) to GPR2 temporarily (scratch).
    CSRST #3                ; GPR2 ← (a+b)
    
    ; Load c from [SP] — c is at top of stack (pushed last by caller, no prologue offset)
    CSRLD #2                ; ACC ← SP
    SA                      ; RA0 ← SP,  ACC ← old_RA0
    XMEM #0b0000            ; ACC ← [RA0] = c  (load, no auto-modify)
    
    ; Add c to (a+b)
    SS                      ; RS0 ← c (ACC), ACC ← b (old RS0 from earlier RSS)
    CSRLD #3                ; ACC ← (a+b)
    ADD                     ; ACC ← (a+b) + c  ✓

    RSA                     ; RA0 ← RA1 (return address)
    JMP                     ; PC ← RA0
```

---

### Return Values

| Type | Location | Notes |
|------|----------|-------|
| Scalars (≤16-bit) | ACC | Standard return register |
| Structs (>16-bit) | Memory | Pointer passed as hidden first arg |

**Example: Returning struct**
```c
struct Point {
    int x, y;
};

struct Point make_point(int x, int y) {
    struct Point p;
    p.x = x;
    p.y = y;
    return p;
}
```

**Compiled (struct return via pointer):**
```assembly
; make_point(result_ptr, x, y)
; RS0 = result_ptr (hidden arg), RS1 = x, [SP] = y
; Leaf function: RA1 = return address

make_point:
    ; SA swaps ACC↔RA0, not RS0→RA0. Must load result_ptr from RS0 into ACC first.
    SS                      ; ACC ← result_ptr (RS0), RS0 ← old_ACC
    SA                      ; RA0 ← result_ptr,       ACC ← old_RA0
    
    ; Store x (in RS1) to [RA0++] = [result_ptr], advance RA0 to result_ptr+2
    RSS                     ; RS0 ← x (RS1),          RS1 ← old_RS0 (junk)
    SS                      ; ACC ← x,                RS0 ← old_RA0 (junk)
    XMEM #0b1010            ; [RA0++] ← x   (p.x = x, RA0 = result_ptr+2)
    
    ; Load y from stack [SP] into ACC, keeping RA0 = result_ptr+2
    ; [... y → ACC, RA0 = result_ptr+2 preserved ...]
    
    ; Store y to [RA0] = [result_ptr+2]
    XMEM #0b1000            ; [RA0] ← y     (p.y = y)
    
    RSA                     ; RA0 ← RA1 (return address)
    JMP                     ; PC ← RA0
```

---

### Profile Requirements for C Compatibility

| Profile | GPR Support | C Support | Notes |
|---------|-------------|-----------|-------|
| **Baseline** | GPR1-3 | ✅ Yes | **Minimum for C** |
| **Baseline + Interrupt** | GPR1-3 + ISR | ✅ Yes | Full C + interrupts |

**Recommendation:** C toolchains should **require Baseline Profile** as minimum target.

---

### Code Density Comparison

| Function Type | MISA-O | ARM Thumb | RISC-V RVC |
|---------------|--------|-----------|------------|
| **Leaf** | 0-2 bytes | 0-2 bytes | 0-2 bytes |
| **Non-leaf (simple)** | 14 bytes | 8 bytes | 18 bytes |
| **Non-leaf (complex)** | 25-30 bytes | 16-20 bytes | 30-36 bytes |

**Analysis:**
- MISA-O is **competitive** with RISC-V
- ARM Thumb is **more compact** (dedicated PUSH/POP)
- MISA-O's **nibble encoding** provides good density for leaf functions

---

### Optimization Tips for Compilers

#### 1. **Minimize Prologue/Epilogue**

- **Leaf functions**: No prologue needed
- **Tail calls**: Replace JAL with JMP (skip epilogue)
- **Register windowing**: Use GPRs to avoid stack traffic

#### 2. **Leverage Post-Increment**

```assembly
; Efficient array/struct copy (requires LK16 mode for CSRLD)
; RA0 = source, RA1 = dest (swap as needed per iteration)
CSRLD #2                ; ACC ← source ptr
SA                      ; RA0 ← source,   ACC ← old RA0
CSRLD #3                ; ACC ← dest ptr
RSA                     ; RA1 ← dest,     RA0 ← source  (RSA swaps RA0↔RA1)
RSA                     ; RA0 ← source,   RA1 ← dest    (restore: RSA again)

loop:
    XMEM #0b0100        ; ACC ← [RA0], RA0++  (load + post-increment source)
    RSA                 ; RA0 ↔ RA1  (RA0 = dest)
    XMEM #0b1100        ; [RA0] ← ACC, RA0++  (store + post-increment dest)
    RSA                 ; RA0 ↔ RA1  (RA0 = source)
    ; [decrement counter, update flags]
    BRC #NE #loop       ; branch back while counter != 0 (PC-relative offset)
; Note: for bulk copies prefer MCPY (XOP;XMEM), which handles both pointers natively.
```

#### 3. **Use CFG.IMM for Constants**

```assembly
; Instead of:
LDi #5
ADD                     ; 3 bytes

; Use:
CFG #0x08               ; IMM=1
ADD #5                  ; 2 bytes (immediate mode)
CFG #0x00               ; IMM=0
; 5 bytes total, but reusable for multiple ops
```

#### 4. **Batch CFG Changes**

```assembly
; Set multiple flags at once:
; CFG layout: [7:6]=RSV, [5]=CI, [4]=IE, [3]=IMM, [2]=SIGN, [1:0]=W
; CI=1→bit5, IMM=1→bit3, LK8→bits[1:0]=01  →  0b00101001
CFG #0b00101001         ; CI=1, IMM=1, LK8
; Now multiple operations benefit from carry-in and immediate mode
ADD #5
SUB #3
; ...
CFG #0x00               ; Reset (UL, no CI, no IMM)
```

---

### Toolchain Integration

#### Assembler Macros

Provide standard macros for common patterns:

```assembly
; Calling convention helpers.
; All macros below require LK16 mode (CFG.W = 10) to be active.

.macro CALL target
    ; Requires: LK16 mode (LDi loads full 16-bit address; CSRLD/CSRST valid).
    LDi #target             ; ACC ← full 16-bit target address
    SA                      ; RA0 ← target,   ACC ← old_RA0
    JAL                     ; RA1 ← PC_next,  PC ← RA0 (target)
.endm

.macro RET
    ; Return from a leaf function (RA1 holds return address).
    RSA                     ; RA0 ← RA1 (return address)
    JMP                     ; PC ← RA0
.endm

.macro PROLOGUE_NONLEAF
    ; Push return address (RA1) onto the stack and update SP.
    ; Requires LK16 mode. Clobbers ACC, RA0; RA1 receives caller's RA0.
    CSRLD #2                ; ACC ← SP
    SA                      ; RA0 ← SP,          ACC ← old_RA0
    RSA                     ; RA0 ← return_addr, RA1 ← SP
    SA                      ; ACC ← return_addr, RA0 ← old_RA0
    RSA                     ; RA0 ← SP,          RA1 ← old_RA0
    XMEM #0b1110            ; pre-dec push: RA0 -= 2, [RA0] ← return_addr
    SA                      ; ACC ← new_SP,      RA0 ← return_addr
    CSRST #2                ; SP ← new_SP
.endm

.macro EPILOGUE_NONLEAF
    ; Pop return address from stack, restore SP, and jump to it.
    ; Requires LK16 mode. Clobbers ACC, RA0.
    CSRLD #2                ; ACC ← SP
    SA                      ; RA0 ← SP,          ACC ← old_RA0
    XMEM #0b0010            ; post-inc pop: ACC ← [RA0], RA0 += 2
    SA                      ; ACC ← new_SP,      RA0 ← return_addr
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
// Leaf function hint (no prologue needed)
__attribute__((leaf))
int add(int a, int b) {
    return a + b;
}

// Use GPR2 as scratch temp
__attribute__((register("GPR2")))
int temp;

// Use GPR3 as a persistent local across calls (callee-saved; save/restore in prologue/epilogue)
__attribute__((register("GPR3")))
int saved_local;

// Force inline (avoid call overhead)
__attribute__((always_inline))
inline int square(int x) {
    return x * x;
}
```

---

### Summary

MISA-O provides a **C-friendly calling convention** with:

✅ Clear **caller-saved** vs **callee-saved** semantics
✅ **GPR1/3** callee-saved + scratch for efficient register allocation
✅ **Standard stack operations** via SP (GPR1)
✅ **Competitive code density** (vs RISC-V)
✅ **Minimal prologue** for leaf functions (0 bytes!)
✅ **Macro-friendly** assembly (hide complexity)
