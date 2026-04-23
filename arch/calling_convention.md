## Calling Convention & Language Support

MISA-O is designed to support efficient compilation of high-level languages, particularly C, through a well-defined calling convention and architectural features that minimize overhead in function calls, stack management, and register allocation.

This document outlines the **standard MISA-O calling convention** for efficient function calls and stack management.

---

### Register Usage Convention

MISA-O uses a highly efficient register model centered around the native stack capabilities of `RA1`.

| Register | Alias | Purpose | Notes |
|----------|-------|---------|-------|
| **ACC**  | —     | Return value / Scratch | Function result returned here |
| **RA1**  | SP    | Stack Pointer | Primary address register for the call stack |
| **RA0**  | LR/FP | Link / Offset Register | Jump target, return address, and array/stack index |
| **RS0**  | A0    | Scratch / Temp | General use |
| **RS1**  | A1    | Scratch / Temp | General use |

**Rationale:** By dedicating `RA1` strictly as the Stack Pointer, MISA-O achieves 1-cycle push/pops via `XMEM` auto-modify features.

---

### Stack Management

**RA1** serves as the **Stack Pointer (SP)**:
- **Grows downward** (decrements on push, increments on pop)
- **Points to the last valid item** (full descending stack)
- Pushing/Popping is natively supported via `XMEM` without moving the SP to another register.

#### Push and Pop Operations

**PUSH ACC:**
```assembly
XMEM #0b1110    ; pre-dec push: RA1 -= W_bytes, [RA1] ← ACC
```

**POP ACC:**
```assembly
XMEM #0b0010    ; post-inc pop: ACC ← [RA1], RA1 += W_bytes
```

*(Note: In LK16 mode, the stride is automatically 2 bytes, making it perfect for pushing 16-bit values).*

---

### Function Call Sequence

#### 1. **Caller Responsibilities**

Before calling a function, the caller must:
1. **Push arguments** onto the stack (typically Right-to-Left or Left-to-Right depending on compiler ABI).
2. **Prepare target address** in `RA0` via `SA`.
3. **Execute JAL** to transfer control.

**Example:**
```assembly
caller:
    ; Prepare arguments
    LDi #10
    XMEM #0b1110            ; Push arg 2
    LDi #5
    XMEM #0b1110            ; Push arg 1

    ; Prepare target address
    LDi #add                ; ACC ← add address
    SA                      ; RA0 ← add addr
    JAL                     ; PC ← RA0; RA0 ← PC_next (link)

    ; Clean up stack (2 args = 2 pops)
    XMEM #0b0010
    XMEM #0b0010
```

#### 2. **Callee Responsibilities**

##### A. **Leaf Function**
Leaf functions do not call other functions and do not need to save `RA0` (the return address).

```assembly
add:
    ; Read args from stack via RA0 offset
    ; SP (RA1) + 0 = arg 1
    LDi #0
    SA                      ; RA0 = 0
    XMEM #0b0001            ; ACC ← [RA1 + RA0]
    SS                      ; RS0 ← arg 1

    ; SP (RA1) + 2 = arg 2
    LDi #2
    SA                      ; RA0 = 2
    XMEM #0b0001            ; ACC ← [RA1 + RA0]
    
    ADD                     ; ACC ← ACC + RS0
    JMP                     ; PC ← RA0 (return address)
```

##### B. **Non-Leaf Function**
On entry from `JAL`, **RA0 holds the return address** (link). The prologue must save it to the stack.

```assembly
complex:
    ; === PROLOGUE (3 instructions) ===
    SA                      ; ACC ← RA0 (return address)
    XMEM #0b1110            ; Push return address
    SA                      ; Restore ACC (optional)

    ; === BODY ===
    ; Allocate locals if needed: XMEM #0b1110 (push 0)
    ; ... function logic ...

    ; === EPILOGUE (4 instructions) ===
    SA                      ; Save ACC (return value) if needed
    XMEM #0b0010            ; Pop return address into ACC
    SA                      ; RA0 ← return address
    JMP                     ; PC ← RA0
```

---

### Profile Requirements for C Compatibility

| Profile | C Support | Notes |
|---------|-----------|-------|
| **Baseline** | ✅ Yes | Full re-entrant C support |
| **Complete** | ✅ Yes | Additional CSR extensions available |

`RA1` as the standard Stack Pointer fully supports re-entrant C compilation, nested loops, recursion, and variable spilling.

---

### Code Density Analysis

| Macro | Instructions |
|-------|-------------|
| **PUSH** | 1 |
| **POP** | 1 |
| **PROLOGUE_NONLEAF** | 3 |
| **EPILOGUE_NONLEAF** | 4 |

**Conclusion:** The `RA1` SP calling convention is the standard for MISA-O high-level language targeting, achieving minimal instruction overhead for stack operations.
