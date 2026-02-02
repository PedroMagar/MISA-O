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

### RACC Behavior in SPE Mode

In SPE mode, `RACC` **has a new opcode** `0010` and is **reinterpreted as rotate operation in *LK8*** instead of their **default**:

* **RACC** (opcode `0010`, custom): Rotates `ACC` **left by 8 bits**
  * Semantics: `ACC ← rotateLeft8(ACC)`
  * Example: `0xABCD → 0xCDAB`

**CSR Access in SPE Mode:**
* Direct CSR access via `CSRLD`/`CSRST` is **still available** while in SPE mode

---

### Non-MAD Instructions in SPE Mode

All opcodes **not explicitly defined** by the MAD Profile **retain their LK16 architectural semantics** when executed in SPE mode.

In particular:

* Memory access, control-flow (except for `RACC/RRS`), and non-MAD arithmetic instructions are unaffected.
* SPE imposes **no additional restrictions** beyond MAD opcode remapping.

---

### Operand Model

* **Multiplicand**: Always `RS0[LANE*8+7:LANE*8]` (**variable**, selected by func[0])
  * Lane 0: `RS0[7:0]` (low 8 bits)
  * Lane 1: `RS0[15:8]` (high 8 bits)

* **Multiplier**: `RS1[LANE*8+7:LANE*8]` (**variable**, selected by func[1])
  * Lane 0: `RS1[7:0]` (low 8 bits)
  * Lane 1: `RS1[15:8]` (high 8 bits)

* **Accumulator**: `ACC` (16-bit, destination)
  * Accumulation is always 16-bit precision
  * Result may saturate or wrap depending on `func[2]`

* **Signedness**: Follows global `CFG.SIGN` flag
  * `SIGN=0`: Unsigned multiply, logical right shift
  * `SIGN=1`: Signed multiply, arithmetic right shift

---

### Instructions

| Mode |Binary | Type       | Name     | Description                                       |
|------|-------|------------|----------|---------------------------------------------------|
| SPE  | 0010  | *Default*  | **RACC** | Rotate ACC left 8 bits                            |
| SPE  | 0100  | *Extended* | **MAD**  | Multiply-Add with lane selection                  |
| SPE  | 1000  | *Extended* | **MAX**  | Maximum value clamp                               |
| SPE  | 0000  | *Extended* | **MIN**  | Minimum value clamp                               |

---

### Instruction Semantics

- **MAD #func**: `ACC ← SAT( ACC + ((LANE_RS0 × LANE_RS1) >> SHIFT) )`; where:
  * `LANE_RS0` = selected 8-bit lane of RS0 (variable, controlled by func[0])
  * `LANE_RS1` = selected 8-bit lane of RS1 (variable, controlled by func[1])
  * `×` = multiply (signed/unsigned per CFG.SIGN)
  * `+` = 16-bit addition
  * `SAT()` = saturation (if enabled by func[2])
  * `>> SHIFT` = post-operation right shift (amount per func[3])
  * **Carry flag** (`C`) = carry-out of 16-bit accumulation
  * **Overflow**: Implementation-defined status bits may be exposed via `CORECFG` bits (for BUSY, SAT flags, etc)

- **RACC**: `ACC ← rotateLeft8(ACC)`
  * Rotates ACC left by 8 bits, wrapping around
  * Semantics identical to LK8 `RACC` instruction
  * Enables multi-byte iterative multiplication

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
func[3] — SHIFT — Post-operation right shift amount:
  0 = no shift       (>> 0)
  1 = shift right 4  (>> 4)

func[2] — SAT — Saturation enable:
  0 = wrap around (no saturation)
  1 = saturate to min/max

func[1] — LANE_RS1 — RS1 lane select:
  0 = low 8-bit lane  (RS1[7:0])
  1 = high 8-bit lane (RS1[15:8])

func[0] — LANE_RS0 — RS0 lane select:
  0 = low 8-bit lane  (RS0[7:0])
  1 = high 8-bit lane (RS0[15:8])
```

**Shift Semantics:**
* Right shifts are **logical** when `CFG.SIGN=0` (unsigned)
* Right shifts are **arithmetic** when `CFG.SIGN=1` (signed)
* `SHIFT=1` applies a logical right shift by 4 bits to the 16-bit product before accumulation, intended for fixed-point Q-format scaling and nibble-based packing.

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
