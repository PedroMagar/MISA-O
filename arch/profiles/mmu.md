## MMU Profile

Optional profile providing Supervisor/User privilege separation and page-level memory access control.

Supports Supervisor/User privilege separation, page-level memory protection, and virtual-to-physical address remapping. Each virtual page can be independently mapped to one of 32 physical pages, extending the physical byte address space to 18 bits (256 KB). PPAGE translation applies to all accesses regardless of privilege level. Supervisor mode bypasses only the protection checks (SV, XO, WE flags); address translation via PPAGE is always active.

---

### Address Space Partitioning

The 16-bit **virtual** nibble address space is divided into **four fixed pages** (8 KB / 16 K-nibble each) selected by the two most significant bits of the nibble address:

| addr[15:14] | Page | Range           |
|-------------|------|-----------------|
| `00`        | 0    | 0x0000–0x3FFF   |
| `01`        | 1    | 0x4000–0x7FFF   |
| `10`        | 2    | 0x8000–0xBFFF   |
| `11`        | 3    | 0xC000–0xFFFF   |

Page selection applies independently to:
- **Instruction fetches**: determined by `PC[15:14]`
- **Data accesses**: determined by the effective address of `XMEM` and `MCPY`

The physical address is always formed by replacing the virtual page index with the `PPAGE` field from the matching page table entry (see [Page Entry Format](#page-entry-format)). Supervisor mode skips the protection flag checks but not the translation.

---

### Privilege Levels

The MMU Profile introduces two privilege levels: **Supervisor** and **User**.

The active privilege level is controlled by **CFG bit 6 (SV)**:

| Bit | Name | Default | Description                                              |
|-----|------|---------|----------------------------------------------------------|
|  6  | SV   |    0    | Supervisor Mode. 0 = User mode. 1 = Supervisor mode.    |

When `SV = 1` (Supervisor mode), the processor bypasses all protection flag checks (SV, XO, WE) and may access any address without restriction. PPAGE translation still applies — the physical address is determined by the page table entry for the accessed virtual page.

When `SV = 0` (User mode), every instruction fetch and data access is checked against the active page table entry for that address.

**User-mode CFG write restrictions:** In user mode, the `CFG` instruction may update all bits **except** `SV`. Attempts to set `SV = 1` from user mode are silently ignored. `SV` is effectively read-only from user mode and is only set by hardware on interrupt/trap entry.

---

### Page Entry Format

Each of the four pages is described by one **byte** within the page table CSRs.

On reset, `PPAGE` defaults to the virtual page index (identity mapping) and all protection flags (SV, XO, WE) default to 0:

| Page | Reset entry | PPAGE | SV | XO | WE |
|------|-------------|-------|----|----|----|
| 0    | `0x00`      | 0     | 0  | 0  | 0  |
| 1    | `0x01`      | 1     | 0  | 0  | 0  |
| 2    | `0x02`      | 2     | 0  | 0  | 0  |
| 3    | `0x03`      | 3     | 0  | 0  | 0  |

| Bit   | Name  | Description                                                                         |
|-------|-------|-------------------------------------------------------------------------------------|
| [7]   | SV    | Supervisor Only. 1 = user-mode access causes a fault.                               |
| [6]   | XO    | Execute Only. 1 = data reads and writes forbidden.                                  |
| [5]   | WE    | Write Enable. 1 = writes permitted. 0 = read-only.                                 |
| [4:0] | PPAGE | Physical Page Number. User-mode byte address = `{ PPAGE[4:0], virt[13:1] }`; nibble select = `virt[0]`. |

Notes:
- `XO` restricts data access but **not** instruction fetches. A page marked `XO` can be freely executed but not read or written as data.
- `WE = 0` (read-only) does not prevent instruction fetches. Code in a read-only page executes normally.
- `SV = 1` constrains user mode only; supervisor bypasses all page table checks and translation regardless.
- `PPAGE` translation applies to all accesses (supervisor and user). Supervisor mode only skips the protection flag checks (SV, XO, WE). On reset, all `PPAGE` fields are `0` — all virtual pages initially map to physical page 0.

**Physical address construction:**

Every access — supervisor or user — goes through address translation. The 16-bit nibble address is decomposed as:

- `virt[15:14]` — virtual page index (replaced by PPAGE; not sent to memory)
- `virt[13:1]`  — 13-bit byte offset within page (sent to memory)
- `virt[0]`     — nibble select within byte (0 = low nibble `[3:0]`, 1 = high nibble `[7:4]`; not sent as address)

```
byte_addr[17:0] = { PPAGE[4:0], virt[13:1] }
nibble_sel      = virt[0]
```

This gives an 18-bit physical byte address space (32 pages × 8 KB = 256 KB).

**Common page entry values** (add `PPAGE` to the lower 5 bits for the desired physical mapping):

| Entry  | SV | XO | WE | Meaning                         |
|--------|----|----|----|---------------------------------|
| `0xC0` |  1 |  1 |  0 | Supervisor execute-only code    |
| `0xA0` |  1 |  0 |  1 | Supervisor read/write data      |
| `0x80` |  1 |  0 |  0 | Supervisor read-only data       |
| `0x40` |  0 |  1 |  0 | User execute-only code          |
| `0x20` |  0 |  0 |  1 | User read/write data            |
| `0x00` |  0 |  0 |  0 | User read-only data             |

Example: `0x42` = user execute-only mapped to physical page 2; `0x23` = user read/write mapped to physical page 3.

---

### CSR Additions

| Idx | Name   | Description                          | Access                      |
|-----|--------|--------------------------------------|-----------------------------|
|  6  | PTBL01 | Page table entries for pages 0 and 1 | Supervisor R/W; User RAZ/WI |
|  7  | PTBL23 | Page table entries for pages 2 and 3 | Supervisor R/W; User RAZ/WI |

#### CSR6 – PTBL01 (Page Table: Pages 0–1)

| Bits    | Description                             |
|---------|-----------------------------------------|
| [7:0]   | Page 0 entry (addresses 0x0000–0x3FFF)  |
| [15:8]  | Page 1 entry (addresses 0x4000–0x7FFF)  |

Readable and writable only in supervisor mode. User-mode reads return `0`; writes are ignored.

#### CSR7 – PTBL23 (Page Table: Pages 2–3)

| Bits    | Description                             |
|---------|-----------------------------------------|
| [7:0]   | Page 2 entry (addresses 0x8000–0xBFFF)  |
| [15:8]  | Page 3 entry (addresses 0xC000–0xFFFF)  |

Readable and writable only in supervisor mode. User-mode reads return `0`; writes are ignored.

### EVTCTRL Additions

When the MMU Profile is present, the following bits are added to **EVTCTRL (CSR2)**:

**Low byte [7:0] — Configuration (R/W):**

| Bit | Name   | Description             |
|-----|--------|-------------------------|
|  4  | MMU_IE | MMU fault interrupt enable |

**High byte [15:8] — Status (R / W1C):**

| Bit | Name   | Description                                                    |
|-----|--------|----------------------------------------------------------------|
| 13  | MMU_P  | MMU fault pending (W1C). Set by hardware on any MMU fault.     |
| 14  | MMU_IF | Instruction fetch fault. 1 = fault was on a fetch (PC). 0 = data access. Cleared with MMU_P. |

Cores that do not implement the MMU Profile must treat `MMU_IE` as RAZ/WI and `MMU_P`/`MMU_IF` as RAZ.

---

### Access Control Rules

When `SV = 0` (User mode), every memory access is checked against the page entry for the accessed address. **Supervisor mode bypasses all page table checks.**

| Access type           | Page entry SV=1   | Page entry XO=1      | Page entry WE=0   |
|-----------------------|-------------------|----------------------|-------------------|
| Instruction fetch     | **Fault**         | OK (fetch allowed)   | OK (WE irrelevant) |
| Data read (XMEM LD)   | **Fault**         | **Fault**            | OK (read allowed) |
| Data write (XMEM ST)  | **Fault**         | **Fault**            | **Fault**         |

**MCPY:** checks the source page (`RA1`) for data read access and the destination page (`RA0`) for data write access. Page boundary crossings during execution trigger checks for each newly entered page. If a fault occurs mid-transfer, `RA1`/`RA0` reflect progress up to the first faulting address and `RS1` reflects the remaining count.

---

### Fault Delivery

When a page check fails in user mode:

1. Hardware sets **MMU_P = 1** and **MMU_IF** in EVTCTRL.
2. The faulting access does **not** complete.
3. If `MMU_IE = 1`: a trap is delivered using the same mechanism as a hardware interrupt. **MMU faults are synchronous exceptions and bypass `CFG.IE`** — the global interrupt enable does not gate fault delivery. Only `MMU_IE` controls whether the trap fires:
   - Execution context saved on the `IA` page (PC, CFG including `SV=0`, FLAGS, ACC, RA0, IA, IAR).
   - Hardware sets `CFG.SV = 1` (switches to supervisor mode).
   - Hardware clears `CFG.IE`.
   - Execution jumps to `IA<<8 + 0x10`.
4. The ISR identifies an MMU fault by reading **EVTCTRL** and checking **MMU_P = 1**.
5. The ISR recovers the faulting address:
   - **High byte** (`addr[15:8]`): available immediately from **EVTADDR[15:8]** (CSR3) for any fault type. This is sufficient to identify the faulting page without any further reads.
   - **Fetch fault** (`MMU_IF = 1`): full address is the saved PC at `IAR<<8 + 0x00..0x01`.
   - **Data fault** (`MMU_IF = 0`): for single `XMEM` ops, `RA1` (live, unmodified) provides the base address; for indexed mode (`IDX=1`), the effective address is `RA1 + RA0` where `RA0` is available from the saved frame at `IAR<<8 + 0x06..0x07`. For `MCPY` mid-transfer faults, `EVTADDR[15:8]` reflects the exact faulting byte's high address while `RA1`/`RA0` reflect progress up to that point.
6. Before returning, the ISR clears **MMU_P** (W1C).
7. **RETI** restores CFG (including `SV = 0`), returning to user mode.

If `MMU_IE = 0` at the time of a fault, behavior is implementation-defined. Compliant software must ensure `MMU_IE = 1` is set before entering user mode. `CFG.IE` has no effect on MMU fault delivery.

---

### Mode Transitions

#### Supervisor → User

Supervisor code explicitly drops privilege by writing CFG with `SV = 0`. The most straightforward method uses the `CFG` instruction to load a full 8-bit configuration:

```asm
; Enter user mode: MMUEN=0(N/A), SV=0, CI=0, IE=1, IMM=0, SIGN=0, LK16
CFG #0b00010010   ; [7:6]=00(SV=0), [5]=0, [4]=1(IE), [3:2]=00, [1:0]=10(LK16)
```

To preserve existing CFG bits while only clearing `SV`, use CSRLD/CSRST in LK16 mode:

```asm
; Clear only SV (bit 6) without disturbing other CFG bits
CSRLD #1          ; ACC ← CORECFG [15:0]
LDi #0x00BF       ; RS0 ← 0x00BF  (mask: clear bit 6 of low byte)
AND               ; ACC ← ACC & RS0
CSRST #1          ; CORECFG ← ACC  (SV cleared, all other bits preserved)
```

#### User → Supervisor

User mode cannot elevate privilege directly. The only paths to supervisor mode are:

- **`SWI`** — software interrupt (Interrupt Profile). Delivers a trap: hardware saves context, sets `SV = 1`, jumps to ISR. The ISR returns to user mode via `RETI`.
- **External interrupt** — same mechanism as SWI.
- **MMU fault** — same mechanism; ISR runs in supervisor.

This means `SWI` serves as the architectural **system call gate**: user code executes `SWI`, the supervisor ISR handles the request, and `RETI` returns with privilege restored.

---

### Interaction with Other Profiles

The MMU Profile **requires the Interrupt Profile** to be present for correct operation. Without the Interrupt Profile:
- Fault delivery is undefined.
- There is no architectural mechanism for user code to re-enter supervisor mode.

On any interrupt entry (Interrupt Profile), the full CFG register — including `SV` — is saved to the IA page at offset `+0x02`. Hardware sets `SV = 1` as part of trap entry. `RETI` restores CFG, including `SV`, from the IAR page. This means:
- The ISR always runs as supervisor.
- After `RETI`, the CPU returns to whatever privilege level was active before the trap.

The MMU Profile is independent of the **MAD** and **Debug** profiles.

---

### Typical Initialization

```asm
; (Supervisor mode, LK16)
; Reset state: PTBL01=0x0100, PTBL23=0x0302 — identity-mapped, all protection flags clear.
; The code below reconfigures the table for a kernel/user split.

; Page layout (identity-mapped: virtual page N → physical page N):
;   Page 0 (0x0000–0x3FFF): supervisor execute-only code  → SV=1, XO=1, WE=0, PPAGE=0 = 0xC0
;   Page 1 (0x4000–0x7FFF): supervisor read/write data    → SV=1, XO=0, WE=1, PPAGE=1 = 0xA1
;   Page 2 (0x8000–0xBFFF): user execute-only code        → SV=0, XO=1, WE=0, PPAGE=2 = 0x42
;   Page 3 (0xC000–0xFFFF): user read/write data          → SV=0, XO=0, WE=1, PPAGE=3 = 0x23

LDi #0xA1C0       ; ACC = (page1=0xA1)<<8 | (page0=0xC0)
CSRST #6          ; PTBL01 ← ACC

LDi #0x2342       ; ACC = (page3=0x23)<<8 | (page2=0x42)
CSRST #7          ; PTBL23 ← ACC

; Configure ISR and enable interrupts + MMU faults before dropping privilege
; ... (set up IA, EVTCTRL with IE=1, MMU_IE=1) ...

; Drop to user mode and jump to user entry point
CFG #0b00010010   ; SV=0, IE=1, LK16
; (next instruction executes as user)
```

---

### Summary

| Aspect              | Details                                                  |
|---------------------|----------------------------------------------------------|
| Privilege levels    | Supervisor (SV=1) and User (SV=0)                        |
| SV control bit      | CFG[6]                                                   |
| Page granularity    | 4 pages × 8 KB (16 K-nibble), selected by addr[15:14]    |
| Page entry size     | 1 byte (SV, XO, WE flags + PPAGE[4:0])                   |
| Physical address    | { PPAGE[4:0], virt[13:1] } = 18-bit byte address (256 KB)|
| Page table CSRs     | PTBL01 (CSR6), PTBL23 (CSR7)                             |
| Fault address       | High byte in EVTADDR[15:8]; low byte from frame/RA1      |
| Fault signaling     | EVTCTRL.MMU_P / MMU_IF / MMU_IE                          |
| Supervisor access   | Bypasses protection checks (SV, XO, WE) only; PPAGE always active |
| Privilege elevation | Via SWI / interrupt only (hardware-controlled)           |
| Required profiles   | Interrupt Profile                                        |
| CPUID bit           | CPUID.PROFILES[8]                                        |
