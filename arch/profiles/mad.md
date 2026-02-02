## MAD Profile (Multiply-Add & Derivatives)

The **MAD Profile** is an **optional execution profile** that extends MISA-O with lightweight multiply-accumulate and comparison helpers, targeting fixed-point workloads such as graphics, audio, and DSP-style inner loops.

The profile is **only active when LINK mode = `2'b11` (SPE)**.
In all other link modes, MAD profile opcodes are treated as **NOP**.

To be **MAD Profile compliant**, an implementation must support:

* the **SPE link mode**,
* the **MAD opcode remapping** defined in this section, and
* the architectural semantics described below.

No additional architectural registers are introduced.
All control is encoded **per-instruction** via the function nibble, while observable status is limited to existing architectural mechanisms (notably the **Carry flag**).

---

### RACC and RRS Behavior in SPE Mode

In SPE mode, `RACC` and `RRS` opcodes are **reinterpreted as rotate operations (LK8)** instead of their LK16 semantics (CSRLD/CSRST):

* **RACC** (opcode `0110` default): Rotates `ACC` **left by 8 bits**
  * Semantics: `ACC ← rotateLeft8(ACC)`
  * Purpose: Shift multiplicand to next 8-bit lane for iterative multiply
  * Example: `0xABCD → 0xCDAB`

* **RRS** (opcode `0110` extended → `XOP; 0010`): Rotates `RS0` **left by 8 bits** (optional, rarely needed)
  * Semantics: `RS0 ← rotateLeft8(RS0)`
  * Format: `XOP; 0010` (1B instruction)
  * Purpose: Shift multiplier if needed (usually not required with lane selection)
  * Note: Reserved for future use; most algorithms use LANE selection instead

**CSR Access in SPE Mode:**
* Direct CSR access via `CSRLD`/`CSRST` is **not available** while in SPE mode
* Workaround 1: Pre-load CSR values before entering SPE mode
* Workaround 2: Exit SPE mode (`CFG #0x02`), access CSR, re-enter SPE (`CFG #0x03`)
* Note: CSR access is typically a one-time initialization; hot loops should pre-compute constants

---

### Non-MAD Instructions in SPE Mode

All opcodes **not explicitly defined** by the MAD Profile **retain their LK16 architectural semantics** when executed in SPE mode.

In particular:

* Memory access, control-flow, and non-MAD arithmetic instructions are unaffected.
* SPE imposes **no additional restrictions** beyond MAD opcode remapping.
* CSR access is restricted (see RACC/RRS section above).

---

### Operand Model

**Key Change:** `RS0` multiplicand is **fixed at low 8 bits**, while `RS1` multiplier lane is **selected per instruction**.

* **Multiplicand**: Always `RS0[7:0]` (low 8 bits, **fixed**)
  * To multiply different parts of a 16-bit value, rotate `RS0` using `RACC`
  * Allows iterative 16×8 multiplication: 2 iterations = complete 16×8 product

* **Multiplier**: `RS1[LANE*8+7:LANE*8]` (**variable**, selected by func[0])
  * Lane 0: `RS1[7:0]` (low 8 bits)
  * Lane 1: `RS1[15:8]` (high 8 bits)

* **Accumulator**: `ACC` (16-bit, destination)
  * Accumulation is always 16-bit precision
  * Result may saturate or wrap depending on `func[1]`

* **Signedness**: Follows global `CFG.SIGN` flag
  * `SIGN=0`: Unsigned multiply, logical right shift
  * `SIGN=1`: Signed multiply, arithmetic right shift

---

### Instructions

| Mode |Binary | Type       | Name     | Description                                       |
|------|-------|------------|----------|---------------------------------------------------|
| SPE  | 0110  | *Default*  | **RACC** | Rotate ACC left 8 bits (multiplicand rotation)    |
| SPE  | 0110  | *Extended* | **RRS**  | Rotate RS0 left 8 bits                            |
| SPE  | 0100  | *Extended* | **MAD**  | Multiply-Add with lane selection                  |
| SPE  | 1000  | *Extended* | **MAX**  | Maximum value clamp                               |
| SPE  | 0000  | *Extended* | **MIN**  | Minimum value clamp                               |

---

### Instruction Semantics

- **MAD #func**: `ACC ← SAT( ( ACC + (RS0[7:0] × RS1_LANE) ) >> SHIFT )`; where:
  * `RS0[7:0]` = low 8 bits of RS0 (fixed, always multiplicand)
  * `RS1_LANE` = selected 8-bit lane of RS1 (variable, controlled by func[0])
  * `×` = multiply (signed/unsigned per CFG.SIGN)
  * `+` = 16-bit addition
  * `SAT()` = saturation (if enabled by func[1])
  * `>> SHIFT` = post-operation right shift (amount per func[3:2])
  * **Carry flag** (`C`) = carry-out of 16-bit accumulation (before shift/saturation)
  * **Overflow**: Implementation-defined status bits may be exposed via `CORECFG` bits (for BUSY, SAT flags, etc)

- **RACC**: `ACC ← rotateLeft8(ACC)`
  * Rotates ACC left by 8 bits, wrapping around
  * Semantics identical to LK8 `RACC` instruction
  * Enables multi-byte iterative multiplication
  * Example: After RACC, next byte of RS0 is available in `RS0[7:0]`

- **RRS** (via `XOP; 0010`): `RS0 ← rotateLeft8(RS0)`
  * Rotates RS0 left by 8 bits (rarely used in MAD algorithms)
  * Optional instruction; implementations may omit
  * Useful for multi-lane multipliers; usually LANE selection is sufficient

- **MAX**: `ACC ← max( ACC , RS0 )`
  * 16-bit unsigned or signed comparison (per CFG.SIGN)
  * Clamps accumulator to maximum of two values
  * Useful for bounding results in DSP loops

- **MIN**: `ACC ← min( ACC , RS0 )`
  * 16-bit unsigned or signed comparison (per CFG.SIGN)
  * Clamps accumulator to minimum of two values
  * Useful for bounding results in DSP loops

---

### Function Format (MAD-Exclusive)

The function nibble controls MAD operation:

```
func[3:2] — SHIFT — Post-operation right shift amount:
  00 = no shift       (>> 0)
  01 = shift right 1  (>> 1)
  10 = shift right 2  (>> 2)
  11 = shift right 4  (>> 4)

func[1] — SAT — Saturation enable:
  0 = wrap around (no saturation)
  1 = saturate to min/max

func[0] — LANE — RS1 lane select:
  0 = low 8-bit lane  (RS1[7:0])
  1 = high 8-bit lane (RS1[15:8])
```

**Shift Semantics:**
* Right shifts are **logical** when `CFG.SIGN=0` (unsigned)
* Right shifts are **arithmetic** when `CFG.SIGN=1` (signed)

---

### Notes and Implementation Guidance

* The MAD Profile **does not require a dedicated control CSR**.
* Per-instruction function enable aggressive inner-loop optimization without global state changes.
* `CFG.SIGN` semantics are consistent with base ISA.
* The `CFG.IMM` flag is **ignored** by MAD; immediate nibble is always consumed as MAD control.
* Multi-cycle MAD implementations may expose a `BUSY` indication via implementation-defined bits in `CORECFG`; single-cycle implementations may hard-wire it to zero.
* Implementations may internally **fuse MAD or decompose** it into multiply and add steps, provided architectural results are preserved.
* Unlike MAD, MAX/MIN operate on the full 16-bit scalar value and are intended as clamp helpers rather than lane-wise SIMD operations.
* The SPE link mode is designed as a **functional overlay** rather than a closed execution state, allowing seamless interleaving of MAD-optimized code and standard LK16 control paths.
* **Rotation is critical for performance**: RACC should complete in 1 cycle (trivial logic); multi-cycle rotation would defeat the purpose.
