# CSR Bank (Control & Extensions)

MISA-O defines a small CSR (Control and Status Register) bank to expose core configuration, architectural state, and optional extension control without increasing the general-purpose register file or instruction encoding complexity.

CSRs are intended to be:

* **Low-frequency accessed** control and status registers
* **Architecturally stable** at the required and baseline levels
* **Extensible** through optional profiles without breaking baseline compatibility

The CSR bank is addressed by a 4-bit index (0–15), with each CSR being 16-bit wide.

Access is performed through two instructions:

* **CSRLD #idx**: `ACC ← CSR[idx]` (16-bit read into ACC)
* **CSRST #idx**: `CSR[idx] ← ACC` (16-bit write from ACC)

In **UL/LK8** modes, the opcodes `RACC` / `RRS` behave as rotate instructions. In **LK16** mode, the same opcode encodings are reassigned to `CSRLD` / `CSRST`, using an immediate nibble as the CSR index.

---

## Compatibility Rules

Software targeting MISA-O must observe the following CSR compatibility rules:

* CSRs marked as **required** must be implemented by all compliant cores.
* CSRs marked as **baseline** may be assumed present by hosted environments.
* CSRs belonging to optional profiles must be detected via **CPUID.PROFILES** before use.
* Reads from unimplemented CSRs return `0`.
* Writes to unimplemented CSRs are ignored.

---

## CSR Implementation Profiles

Three implementation profiles are defined:

* **Compact**: Implements only the *required* CSR set. Unimplemented CSRs read as `0` and ignore writes. Intended for minimal-area cores.

* **Baseline**: Recommended default for general-purpose software. Implements required and baseline CSRs. Software must not rely on any additional CSRs unless the target profile is explicitly known.

* **Complete**: Implements all CSRs defined by optional profiles (interrupt, debug, arithmetic extensions).

---

## CSR Map

| Idx  | Name     | Description                                  | Profile   |
| ---- | -------- | -------------------------------------------- | --------- |
| 0    | CPUID    | Implementation and capability identification | required  |
| 1    | CORECFG  | Core configuration and architectural flags   | required  |
| 2    | GPR1     | General-purpose register                     | baseline  |
| 3    | GPR2     | General-purpose register                     | baseline  |
| 4    | GPR3     | General-purpose register                     | baseline  |
| 5    | TIMER    | Free-running 16-bit counter                  | time      |
| 6    | TIMERCMP | Timer comparison value                       | time      |
| 7    | EVTCTRL  | Interrupt, event, and watchdog control       | baseline  |
| 8    | INTADDR  | Interrupt base address (IA alias)            | interrupt |
| 9–15 | RSV      | Reserved for extensions                      | -         |

Note: **EVTCTRL** is present in the baseline profile even if the Interrupt Profile is not implemented. Interrupt-related fields read as zero when the profile is absent.

---

### CSR0 – CPUID (Implementation Identification)

**CSR0** is reserved as **CPUID** and is read-only. Writes are ignored.

It provides implementation identification and capability discovery. Software typically reads CPUID at startup to adapt execution paths to the available features.

**Format:**

* **[15:12] VERSION** - Architecture version
  * `0x0`: MISA-O v0.x
  * `0x1`: MISA-O v1.x (future)
  * `0xF`: Experimental or custom

* **[11:8] PROFILES** - Optional profile support (1 = present)
  * [11] MAD Profile
  * [10] Debug Profile
  * [9]  Interrupt Profile
  * [8]  MMU Profile (reserved)

* **[7:4] VENDOR** - Vendor identifier
  * `0x0`: Reference or unspecified
  * `0x1`: Reserved for standardization
  * `0x2–0xE`: Vendor-specific
  * `0xF`: Experimental or academic

* **[3:0] IMPL** - Implementation-defined variant

  * May encode cache presence, pipeline depth, accelerators, or performance tier

Software must not rely on undocumented or vendor-specific encodings unless explicitly targeting a known implementation.

---

### CSR1 – CORECFG (Core Configuration and Flags)

Combines the architectural **CFG** register (low byte) with read-only ALU flags (high byte).

* **[7:0] CFG (R/W)** - Core configuration bits
* **[11:8] Flags (RO)**:
  * [8]  `C` - Carry
  * [9]  `Z` - Zero
  * [10] `N` - Negative (MSB according to W)
  * [11] `V` - Signed overflow
* **[15:12]** Reserved (read as zero)

Writes to CORECFG take effect immediately after the instruction retires. No implicit pipeline flush or state reset is performed.

---

### CSR2–CSR4 – GPR (General-Purpose Registers)

CSRs 2–4 provide up to three general-purpose software-visible registers.

These registers are intended to assist calling conventions, reduce memory traffic, and enable more efficient compilation of non-leaf functions. They are accessed exclusively through CSR instructions and do not alter the core register file or datapath.

| Idx | Name     | Description                                        | Profile   |
|-----|----------|----------------------------------------------------|-----------|
| 2   | GPR1     | General-Purpose Register                           | baseline  |
| 3   | GPR2     | General-Purpose Register                           | baseline  |
| 4   | GPR3     | General-Purpose Register                           | baseline  |

**Typical Usage:**
- GPR1: Stack Pointer (SP) or callee-saved
- GPR2: Temp / staging register
- GPR3: Link Register (LR) or callee-saved

See **[Calling Convention](arch/calling_convention.md)** section for details.

---

### CSR5 – TIMER (Monotonic Counter)

A 16-bit free-running counter intended for ordering, delays, and scheduling.

* **Read**: Returns the current value
* **Write**: Loads a new value
* **Overflow**: Wraps from `0xFFFF` to `0x0000`

Implementations may increment TIMER per retired instruction or per cycle. Software must treat TIMER as an opaque monotonic counter and must not assume a fixed relationship to wall-clock time.

---

### CSR6 – TIMERCMP (Timer Compare)

Holds the comparison value for TIMER.

When TIMER transitions to equality with TIMERCMP:

* The **T_P** (Timer Pending) bit in EVTCTRL is set
* If watchdog mode is enabled, a reset is triggered
* Otherwise, a timer interrupt may be raised if enabled

Pending status is cleared explicitly by software.

---

### CSR7 – EVTCTRL (Event, Interrupt, and Watchdog Control)

Consolidates interrupt enables, pending status, and watchdog policy.

**Low byte [7:0] - Configuration (R/W):**

* [0] SW_IE  - Software interrupt enable
* [1] EXT_IE - External interrupt enable
* [2] T_IE   - Timer interrupt enable
* [7] WDOG   - Watchdog mode. When set, a timer match (TIMER == TIMERCMP) causes a core reset instead of raising a timer interrupt.

**High byte [15:8] - Status (R / W1C):**

* [8]  IN_ISR  - Core executing inside an ISR (hardware-managed)
* [9]  EXT_P   - External interrupt pending
* [10] T_P     - Timer interrupt pending
* [11] SW_P    - Software interrupt pending
* [12] DBGSTEP - Debug single-step (optional)
* [15:13] reserved.

Pending bits are cleared by writing `1` to the corresponding bit position.

Interrupt delivery sequence:

1. Event occurs and sets a pending bit
2. If enabled and `CFG.IE = 1`, the core traps to the ISR
3. `IN_ISR` is set on trap entry
4. Software clears pending bits explicitly

---

### CSR8 – INTADDR (Interrupt Base Address)

Alias of the architectural **IA** register.

* **[7:0]**  Interrupt base page
* **[15:8]** Reserved

CSRLD #8 reads IA; CSRST #8 writes IA using `ACC[7:0]`.

---

### CSR9–CSR15 – Reserved

Reserved for future profiles and implementation-defined extensions.

---

## Summary

* Total CSR slots: **16** (indices 0–15)
* CSR width: **16-bit**
* Access mechanism: **CSRLD / CSRST (LK16 only)**
* Required CSRs: **CPUID, CORECFG**
* Baseline CSRs: **GPR1–3, EVTCTRL**
* Profile-driven CSRs: **TIMER, TIMERCMP, INTADDR**
