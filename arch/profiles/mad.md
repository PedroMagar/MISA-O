## MAD Profile (Multiply-Add & Derivatives)

The **MAD Profile** is an **optional execution profile** that extends MISA-O with lightweight multiply-accumulate and comparison helpers, targeting fixed-point workloads such as graphics, audio, and DSP-style inner loops.

The profile is **only active when LINK mode = `2’b11` (SPE)**.
In all other link modes, MAD profile opcodes are treated as **NOP**.

To be **MAD Profile compliant**, an implementation must support:

* the **SPE link mode**,
* the **MAD opcode remapping** defined in this section, and
* the architectural semantics described below.

No additional architectural registers are introduced.
All control is encoded **per-instruction** via the immediate nibble, while observable status is limited to existing architectural mechanisms (notably the **Carry flag**).

---

### Non-MAD instructions in SPE mode

All opcodes **not explicitly defined** by the MAD Profile **retain their LK16 architectural semantics** when executed in SPE mode.

In particular:

* CSR access instructions (`CSRLD` / `CSRST`) remain available and behave identically to LK16.
* Memory, control-flow, and non-MAD arithmetic instructions are unaffected.
* SPE imposes **no additional restrictions** beyond MAD opcode remapping.

---

### Operand model

* Multiply operands are taken from **RS0** and **RS1**.
* The accumulator and destination is **ACC**.
* When operating in SPE mode, each source register provides **two independent 8-bit lanes**:

  * **Lane 0**: bits `[7:0]`
  * **Lane 1**: bits `[15:8]`
* Accumulation is always performed in **16-bit precision**.
* Signedness follows the global **`SIGN`** flag in `CFG`.

---

### Instructions

| Mode |Binary| Type       | Name     | Description                               |
|------|------|------------|----------|-------------------------------------------|
| SPE  | 1100 | *Extended* | **MAD**  | Multiply-Add                              |
| SPE  | 1000 | *Extended* | **MAX**  | Maximum                                   |
| SPE  | 0000 | *Extended* | **MIN**  | Minimum                                   |

---

### Instruction semantics

- **MAD #imm**: `ACC ← SAT( ( ACC + (OP1 × OP2) ) >> SHIFT )`; where:
  - `OP1` = selected 8-bit lane of `RS0`
  - `OP2` = selected 8-bit lane of `RS1`
  - Signed or unsigned multiplication follows `SIGN`
  - Accumulation is 16-bit
  - Post-operation shift and saturation are controlled by `#imm`
  - The Carry flag (`C`) reflects the carry-out of the 16-bit accumulation prior to shift and saturation.
  - Saturation or internal overflow conditions may update **implementation-defined** status bits exposed via `CORECFG`
  - Saturation is based on SIGN flag from CFG. If:
    - `SAT=1 & SIGN=Unsigned`: clamp result to [0, 0xFFFF]
    - `SAT=1 & SIGN=Signed`: clamp result to [-32768, +32767]
- **MAX**: `ACC ← max( ACC , RS0 )`; operates on the full 16-bit value.
- **MIN**: `ACC ← min( ACC , RS0 )`; operates on the full 16-bit value.
- **Others**
  All non-MAD opcodes executed in SPE mode **retain LK16 architectural behavior**, including CSR access.

---

### Immediate format (MAD-exclusive)

The immediate nibble controls MAD operation:

- imm[3:2] — **SHIFT** - Post-operation right shift:
  - `00` = no shift
  - `01` = >> 1
  - `10` = >> 2
  - `11` = >> 4
- imm[1] — **SAT** - Saturation enable:
  - `0` = wrap
  - `1` = saturate
- imm[0] — **LANE** - Operand lane select:
  - `0` = low 8-bit lane
  - `1` = high 8-bit lane

Right shifts are **arithmetic** when `SIGN=1` and **logical** when `SIGN=0`.

---

### Notes and design rationale

* The MAD Profile **does not require a dedicated control CSR**.
* The profile relies exclusively on existing architectural registers (`ACC`, `RS0`, `RS1`).
* Per-instruction immediates enable aggressive inner-loop optimization without global state changes.
* `SIGN` semantics are consistent with the base ISA.
* The `IMM` flag is ignored by `MAD`, as the immediate nibble is always consumed as control.
* Multi-cycle MAD implementations may expose a `BUSY` indication via implementation-defined bits in `CORECFG`; single-cycle implementations may hard-wire it to zero.
* Implementations may internally fuse MAD or decompose it into multiply and add steps, provided architectural results are preserved.
* Unlike MAD, MAX/MIN operate on the full 16-bit scalar value and are intended as clamp helpers rather than lane-wise SIMD operations.
* The SPE link mode is designed as a functional overlay rather than a closed execution state, allowing seamless interleaving of MAD-optimized code and standard LK16 control paths.
