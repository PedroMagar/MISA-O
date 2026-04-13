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

### RACC / RRS Behavior in SPE Mode

In SPE mode, `RACC` and `RRS` **retain their LK8 encodings** (opcode `0110`, Default and Extended respectively), overriding the LK16 `CSRLD`/`CSRST` assignment:

* **RACC** (opcode `0110`, Default): Rotates `ACC` **left by 8 bits**
  * Semantics: `ACC ← rotateLeft8(ACC)`
  * Example: `0xABCD → 0xCDAB`

* **RRS** (opcode `0110`, Extended — preceded by `XOP`): Rotates `RS0` **left by 8 bits**
  * Semantics: `RS0 ← rotateLeft8(RS0)`
  * Enables efficient byte-lane preparation for cross-term multiplication without exiting SPE mode

**CSR Access in SPE Mode:**
* `CSRLD`/`CSRST` are **not available** in SPE mode, as opcode `0110` is reassigned to `RACC`/`RRS`.
* To access CSRs, switch to LK16 mode first via the `CFG` instruction (opcode `0010` Default, unaffected by the MAD Profile).

---

### Non-MAD Instructions in SPE Mode

All opcodes **not explicitly defined** by the MAD Profile **retain their LK16 architectural semantics** when executed in SPE mode.

In particular:

* Memory access, control-flow (except for `RACC/RRS`), and non-MAD arithmetic instructions are unaffected.
* SPE imposes **no additional restrictions** beyond MAD opcode remapping.

---

### Operand Model

* **Multiplicand**: Always `RS0[LANE*8+7:LANE*8]` (**symmetric**, selected by func[0])
  * Lane 0: `RS0[7:0]` (low 8 bits)
  * Lane 1: `RS0[15:8]` (high 8 bits)

* **Multiplier**: `RS1[LANE*8+7:LANE*8]` (**symmetric**, same lane index as RS0, selected by func[0])
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

| Mode |Binary | Type         | Name     | Description                                       |
|------|-------|--------------|----------|---------------------------------------------------|
| SPE  | 0110  | *Default*    | **RACC** | Rotate ACC left 8 bits                            |
| SPE  | 0110  | *Extended*¹  | **RRS**  | Rotate RS0 left 8 bits                            |
| SPE  | 0010  | *Extended*¹  | **MAD**  | Multiply-Add with symmetric lane selection        |
| SPE  | 0100  | *Extended*¹  | **MAX**  | Maximum value clamp                               |
| SPE  | 1000  | *Extended*¹  | **MIN**  | Minimum value clamp                               |

¹ *Extended* instructions are preceded by the `XOP` prefix nibble.

---

### Instruction Semantics

- **MAD #func**: `ACC ← SAT( ACC + ((LANE_RS0 × LANE_RS1) >> SHIFT) )`; where:
  * `LANE_RS0` = `LANE_RS1` = selected 8-bit lane of RS0 and RS1 (symmetric, controlled by func[0])
  * `×` = multiply (signed/unsigned per CFG.SIGN)
  * `+` = 16-bit addition
  * `SAT()` = saturation (if enabled by func[1])
  * `>> SHIFT` = post-operation right shift (amount per func[3:2])
  * **Carry flag** (`C`) = carry-out of 16-bit accumulation
  * **Overflow**: Implementation-defined status bits may be exposed via `CORECFG` bits (for BUSY, SAT flags, etc)

- **RACC**: `ACC ← rotateLeft8(ACC)`
  * Rotates ACC left by 8 bits, wrapping around
  * Semantics identical to LK8 `RACC` instruction
  * Enables multi-byte iterative accumulation over 16-bit data

- **RRS**: `RS0 ← rotateLeft8(RS0)`
  * Rotates RS0 left by 8 bits, swapping the two byte lanes
  * Enables cross-term byte-lane access without exiting SPE mode
  * Useful for multi-step 16×16-bit multiplication using 8-bit MAD operations

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
  00 = no shift        (>> 0)   — raw accumulation
  01 = shift right 4   (>> 4)   — Q4 / nibble scaling
  10 = shift right 8   (>> 8)   — Q8 / byte scaling (8-bit operand norm)
  11 = shift right 12  (>> 12)  — Q12 / coefficient precision

func[1] — SAT — Saturation enable:
  0 = wrap around (no saturation)
  1 = saturate to min/max

func[0] — LANE — Byte-lane select (symmetric: same index applied to RS0 and RS1):
  0 = low 8-bit lane   ([7:0])
  1 = high 8-bit lane  ([15:8])
```

**Shift Semantics:**
* Right shifts are **logical** when `CFG.SIGN=0` (unsigned)
* Right shifts are **arithmetic** when `CFG.SIGN=1` (signed)
* The shift is applied to the 16-bit product **before** accumulation into ACC.
* `>> 8` is the canonical scaling for 8-bit operands in Q0.8 format, supporting up to 256 accumulations before saturation.

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
