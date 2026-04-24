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
| 2    | EVTCTRL  | Interrupt, event, and watchdog control       | baseline  |
| 3    | EVTADDR  | Event base addresses (IA alias + MMU fault)  | interrupt |
| 4    | TIMER    | Free-running 16-bit counter                  | time      |
| 5    | TIMERCMP | Timer comparison value                       | time      |
| 6    | PTBL01   | Page table entries for pages 0 and 1         | mmu       |
| 7    | PTBL23   | Page table entries for pages 2 and 3         | mmu       |
| 8–15 | RSV      | Reserved for extensions                      | -         |

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
  * [8]  MMU Profile

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

### CSR2 – EVTCTRL (Event, Interrupt, and Watchdog Control)

Consolidates interrupt enables, pending status, and watchdog policy.

**Low byte [7:0] - Configuration (R/W):**

* [0] SW_IE  - Software interrupt enable
* [1] EXT_IE - External interrupt enable
* [2] T_IE   - Timer interrupt enable
* [3] SS_IE  - Single-step enable (Debug Profile; RAZ/WI if Debug Profile absent)
* [4] MMU_IE - MMU fault interrupt enable (MMU Profile; RAZ/WI if MMU Profile absent)
* [7] WDOG   - Watchdog mode. When set, a timer match (TIMER == TIMERCMP) causes a core reset instead of raising a timer interrupt. Software must periodically execute `WDR` to reset TIMER before the match occurs.

**High byte [15:8] - Status (R / W1C):**

* [8]  IN_ISR - Core executing inside an ISR (hardware-managed)
* [9]  EXT_P  - External interrupt pending
* [10] T_P    - Timer interrupt pending
* [11] SW_P   - Software interrupt pending
* [12] SS_P   - Single-step pending (Debug Profile; RAZ if Debug Profile absent)
* [13] MMU_P  - MMU fault pending (MMU Profile; W1C; RAZ if MMU Profile absent)
* [14] MMU_IF - Instruction fetch fault: 1 = fault on PC fetch, 0 = data access (MMU Profile; RO; cleared with MMU_P; RAZ if MMU Profile absent)
* [15] reserved.

Pending bits are cleared by writing `1` to the corresponding bit position.

Interrupt delivery sequence:

1. Event occurs and sets a pending bit
2. If enabled and `CFG.IE = 1`, the core traps to the ISR
3. `IN_ISR` is set on trap entry
4. Software clears pending bits explicitly

---

### CSR3 – EVTADDR (Event Base Addresses)

Combines the architectural **IA** register with a read-only snapshot of the last MMU fault address.

* **[7:0]**  IA (R/W) — Interrupt base page (alias of the IA architectural register)
* **[15:8]** MFAH (R) — MMU Fault Address High byte: `addr[15:8]` of the address that triggered the most recent MMU fault. Updated by hardware on each MMU fault; writes are ignored. Reads as `0` when the MMU Profile is absent.

`CSRLD #3` reads both fields. `CSRST #3` writes `ACC[7:0]` into IA; the high byte is unaffected.

---

### CSR4 – TIMER (Monotonic Counter)

A 16-bit free-running counter intended for ordering, delays, and scheduling.

* **Read**: Returns the current value
* **Write**: Loads a new value
* **Overflow**: Wraps from `0xFFFF` to `0x0000`

Implementations may increment TIMER per retired instruction or per cycle. Software must treat TIMER as an opaque monotonic counter and must not assume a fixed relationship to wall-clock time.

---

### CSR5 – TIMERCMP (Timer Compare)

Holds the comparison value for TIMER.

When TIMER transitions to equality with TIMERCMP:

* The **T_P** (Timer Pending) bit in EVTCTRL is set
* If watchdog mode is enabled, a reset is triggered
* Otherwise, a timer interrupt may be raised if enabled

Pending status is cleared explicitly by software.

---

### CSR6 – PTBL01 (Page Table: Pages 0–1)

**MMU Profile.** Holds the page table entries for pages 0 and 1. Readable and writable only in supervisor mode (`CFG.SV = 1`); user-mode reads return `0` and writes are ignored.

| Bits   | Description                              |
|--------|------------------------------------------|
| [7:0]  | Page 0 entry (addresses 0x0000–0x3FFF)   |
| [15:8] | Page 1 entry (addresses 0x4000–0x7FFF)   |

Each byte encodes the page's protection attributes and physical mapping:

| Bit   | Name  | Description                                                                        |
|-------|-------|------------------------------------------------------------------------------------|
| [7]   | SV    | Supervisor Only. 1 = user-mode access causes a fault.                              |
| [6]   | XO    | Execute Only. 1 = data access forbidden.                                           |
| [5]   | WE    | Write Enable. 1 = writes permitted. 0 = read-only.                                |
| [4:0] | PPAGE | Physical Page Number. Byte address: `{ PPAGE[4:0], virt[13:1] }`; nibble select = `virt[0]`. Active for all privilege levels; supervisor skips protection flags only. |

On reset: `0x0100` — page 0 entry = `0x00` (PPAGE=0), page 1 entry = `0x01` (PPAGE=1); all protection flags clear. Identity-mapped by default.

---

### CSR7 – PTBL23 (Page Table: Pages 2–3)

**MMU Profile.** Holds the page table entries for pages 2 and 3. Same access rules and entry format as CSR6.

| Bits   | Description                              |
|--------|------------------------------------------|
| [7:0]  | Page 2 entry (addresses 0x8000–0xBFFF)   |
| [15:8] | Page 3 entry (addresses 0xC000–0xFFFF)   |

On reset: `0x0302` — page 2 entry = `0x02` (PPAGE=2), page 3 entry = `0x03` (PPAGE=3); all protection flags clear. Identity-mapped by default.

---

### CSR8–CSR15 – Reserved

Reserved for future profiles and implementation-defined extensions.

Unimplemented slots read as `0` and ignore writes.

---

## Summary

* Total CSR slots: **16** (indices 0–15)
* CSR width: **16-bit**
* Access mechanism: **CSRLD / CSRST (LK16 only)**
* Required CSRs: **CPUID, CORECFG**
* Baseline CSRs: **EVTCTRL**
* Profile-driven CSRs: **EVTADDR, TIMER, TIMERCMP, PTBL01, PTBL23**
