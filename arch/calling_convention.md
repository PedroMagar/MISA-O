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

**Rationale:** These registers are frequently modified and have short lifetimes. Requiring the callee to save them would increase prologue overhead unnecessarily.

#### Callee-Saved (Non-Volatile) Registers

These registers **must be preserved** by the callee if modified. The callee saves them in the prologue and restores them in the epilogue.

| Register | Alias | Purpose | CSR Index | Notes |
|----------|-------|---------|-----------|-------|
| **GPR1** | SP or S0 | Stack Pointer or saved register | #2 | See profile note below |
| **GPR2** | S1 | Saved register | #3 | General-purpose callee-saved |
| **GPR3** | S2 | Saved register | #4 | General-purpose callee-saved |

**Profile Note:**
- **Extended Profile** (required for C): GPR1-3 are available
- **Minimal Profile**: GPRs may be unavailable (functions must use memory)

**Convention Recommendation:**
- **GPR1**: Stack Pointer (SP) by convention
- **GPR2**: Staging / temp for prologue/epilogue
- **GPR3**: Link register preparation or saved variable

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
    
    ; Prepare target address
    LDi #(callee & 0xFF)
    SA                      ; RA0 ← &callee
    ; [high byte if needed]
    
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
    
    ADD                     ; ACC ← RS0 + RS1

    RSA                     ; RA0 ← RA1 (return address)
    JMP                     ; PC ← return address

; Prologue: 0 instructions ✅
; Epilogue: 0 instructions ✅
```

##### B. **Non-Leaf Function** (Calls Others)

Must save **RA1** (link register) because it will be overwritten by nested JAL:

```assembly
; Non-leaf function: complex(a, b)
; Args: RS0=a, RS1=b
; Calls: add() and mul()
complex:
    ; === PROLOGUE ===
    ; Save RA1 (link register)
    CSRLD #2                ; ACC ← SP
    SA                      ; RA0 ← SP,           ACC ← old_ACC
    RSA                     ; RA0 ← return_addr,  RA1 ← SP
    SA                      ; ACC ← return_addr,  RA0 ← old_ACC
    RSA                     ; RA0 ← SP,           RA1 ← return_addr (restored)
    XMEM #0b1110            ; pre-dec push: RA0--, [RA0] ← return_addr
    SA                      ; ACC ← new_SP
    CSRST #2                ; SP ← new_SP

    ; Save a (RS0) → GPR2
    SS                      ; ACC ← a, RS0 ← old_ACC
    CSRST #3                ; GPR2 ← a
    ; Save b (RS1) → GPR3
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
    
    LDi #(add & 0xFF)
    SA
    JAL                     ; Call add
    
    ; ACC has add result, save it
    ; [use GPR or stack]
    
    ; Call mul(a, b)
    ; [similar setup]
    ; JAL
    
    ; Combine results
    ; ...
    
    ; === EPILOGUE ===
    CSRLD #2                ; ACC ← SP
    SA                      ; RA0 ← SP,           ACC ← old_ACC
    XMEM #0b0010            ; post-inc pop: ACC ← [RA0], RA0++
    SA                      ; ACC ← new_SP,        RA0 ← return_addr
    CSRST #2                ; SP ← new_SP
    JMP                     ; PC ← return_addr

; Prologue: ~7 bytes, ~6 instructions
; Epilogue: ~7 bytes, ~7 instructions
```

##### C. **Function Using Callee-Saved Registers**

If a function modifies GPR1/2/3, it must save and restore them:

```assembly
func:
    ; === PROLOGUE ===
    ; Save RA1
    ; [as above, ~6 instructions]
    
    ; Save GPR2 if we'll modify it
    CSRLD #3                ; ACC ← GPR2
    ; [save to stack via RA0]
    
    ; === BODY ===
    ; Use GPR2 freely
    CSRST #3                ; GPR2 ← local_var
    
    ; === EPILOGUE ===
    ; Restore GPR2
    ; [load from stack]
    CSRST #3
    
    ; Restore RA1
    ; [as above, ~7 instructions]

    RSA                     ; RA0 ← RA1 (return address)
    JMP                     ; PC ← return address
```

---

### Stack Management

#### Stack Pointer Convention

**GPR1** serves as the **Stack Pointer (SP)** by convention:

- **Grows downward** (decrements on push, increments on pop)
- **Points to the last valid item** (full descending stack)
- **Not automatically updated** by hardware (software manages)

#### Stack Operations

**PUSH ACC:**
```assembly
.macro PUSH_ACC
    ; Pushes ACC onto the stack. Clobbers RA0, RS0 (both caller-saved).
    SS                      ; RS0 ← value, ACC ← old_RS0
    CSRLD #2                ; ACC ← SP
    SA                      ; RA0 ← SP,    ACC ← old_ACC
    SS                      ; ACC ← value (from RS0), RS0 ← old_ACC
    XMEM #0b1110            ; pre-dec push: RA0--, [RA0] ← value
    SA                      ; ACC ← new_SP
    CSRST #2                ; SP ← new_SP
.endm
```

**POP ACC:**
```assembly
.macro POP_ACC
    ; Pops top of stack into ACC. Clobbers RA0.
    CSRLD #2                ; ACC ← SP
    SA                      ; RA0 ← SP,    ACC ← old_ACC
    XMEM #0b0010            ; post-inc pop: ACC ← [RA0], RA0++
    SA                      ; ACC ← new_SP, RA0 ← popped_value
    CSRST #2                ; SP ← new_SP
    SA                      ; ACC ← popped_value
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
│ Saved GPRs     │ ← Callee saves GPR2/3 if used
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
    ; Args 1-2 in registers
    LDi #1
    SS                      ; RS0 ← 1 (a)
    LDi #2
    RSS
    SS                      ; RS1 ← 2 (b)
    RSS
    
    ; Arg 3 on stack
    LDi #3
    PUSH_ACC                ; Stack ← 3 (c)
    
    ; Call
    LDi #(add3 & 0xFF)
    SA
    JAL
    
    ; Clean up stack (caller cleanup)
    CSRLD #2
    INC
    CSRST #2                ; SP++
    
    ; Result in ACC
    RSA                     ; RA0 ← RA1 (return address)
    JMP                     ; Return from main
```

**Callee:**
```assembly
add3:
    ; a in RS0, b in RS1, c at [SP+offset]
    
    ADD                     ; ACC ← a + b
    
    ; Save temp
    CSRST #3                ; GPR2 ← (a+b)
    
    ; Load c from stack
    CSRLD #2                ; ACC ← SP
    ; [adjust offset to reach arg c]
    SA                      ; RA0 ← &c
    XMEM #0b0000            ; ACC ← c
    
    ; Add c
    SS                      ; RS0 ← c
    CSRLD #3                ; ACC ← (a+b)
    ADD                     ; ACC ← (a+b) + c

    RSA                     ; RA0 ← RA1 (return address)
    JMP                     ; PC ← return address
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
; RS0 = result_ptr (hidden arg)
; RS1 = x
; Stack = y

make_point:
    ; result_ptr in RS0
    SA                      ; RA0 ← result_ptr
    
    ; Store x
    ; RS1 has x already
    SS
    SA                      ; ACC ← x
    XMEM #0b1010            ; [RA0++] ← x
    
    ; Load y from stack
    ; [...]
    
    ; Store y
    XMEM #0b1000            ; [RA0] ← y
    
    RSA                     ; RA0 ← RA1 (return address)
    JMP                     ; Return (result via pointer)
```

---

### Profile Requirements for C Compatibility

| Profile | GPR Support | C Support | Notes |
|---------|-------------|-----------|-------|
| **Baseline** | GPR1-3 | ✅ Yes | **Minimum for C** |
| **Baseline + Interrupt** | GPR1-3 + ISR | ✅ Yes | Full C + interrupts |

**Recommendation:** C toolchains should **require Extended Profile** as minimum target.

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
; Efficient array/struct copy
CSRLD #2                ; RA0 ← source
SA
CSRLD #3                ; RA1 ← dest
RSA

loop:
    XMEM #0b0010        ; ACC ← [RA0++]
    XMEM #0b1010        ; [RA1++] ← ACC
    ; [decrement counter]
    JAL #loop
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
CFG #0b10001010         ; CI=1, IMM=1, LK8
; Now multiple operations benefit
ADD #5
SUB #3
; ...
CFG #0x00               ; Reset
```

---

### Toolchain Integration

#### Assembler Macros

Provide standard macros for common patterns:

```assembly
; Calling convention helpers
.macro CALL target
    LDi #target             ; ACC ← full 16-bit target address (LK16)
    SA                      ; RA0 ← target
    JAL                     ; RA1 ← PC_next, PC ← target
.endm

.macro RET
    ; Return from a leaf function (RA1 holds return address).
    RSA                     ; RA0 ← RA1 (return address)
    JMP                     ; PC ← return address
.endm

.macro PROLOGUE_NONLEAF
    CSRLD #2
    SA
    RSA
    SA
    RSA
    XMEM #0b1110
    SA
    CSRST #2
.endm

.macro EPILOGUE_NONLEAF
    CSRLD #2
    SA
    XMEM #0b0010
    SA
    CSRST #2
    JMP
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

// Use GPR for local
__attribute__((register("GPR2")))
int temp;

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
✅ **GPR1-3** for efficient register allocation
✅ **Standard stack operations** via SP (GPR1)
✅ **Competitive code density** (vs RISC-V)
✅ **Minimal prologue** for leaf functions (0 bytes!)
✅ **Macro-friendly** assembly (hide complexity)
