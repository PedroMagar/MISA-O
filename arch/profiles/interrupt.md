## Interrupt Profile:

Not mandatory profile to implement interrupt.

### Interrupt context handling

MISA-O uses a **minimal, fixed interrupt frame** designed to keep hardware simple and give full control to software.

On interrupt entry, the processor saves **only the essential execution state** required to resume the interrupted code. All other architectural registers are explicitly managed by the interrupt service routine (ISR).

This model avoids implicit stack behavior and keeps interrupt latency and silicon cost low.

### Hardware-saved state (on interrupt entry)

When an interrupt is taken, the core automatically performs the following actions:

* Saves `PC_next`
* Saves `CFG`
* Saves `FLAGS`
* Saves `RA1` (link / return address)
* Saves `IA` and `IAR`
* Clears `CFG.IE`
* Clears any pending `XOP`
* Jumps to the ISR entry at `IA << 8 + 0x10`

Only this minimal state is guaranteed to be preserved by hardware.

### Software-managed state (ISR responsibility)

All other registers are **not preserved automatically** and must be saved and restored by software if required:

* `ACC`
* `RS0`, `RS1`
* Any additional GPRs or extension state

This gives ISRs full flexibility while keeping the core implementation small and deterministic.

Nested interrupts are only possible if the ISR explicitly re-enables `CFG.IE`.

### Return from interrupt (RETI)

The `RETI` instruction restores the same minimal state saved on interrupt entry:

* `PC`
* `CFG`
* `FLAGS`
* `RA1`
* `IA` and `IAR`

Registers not restored by `RETI` are assumed to have been handled by the ISR.

After `RETI`, interrupt enable (`CFG.IE`) follows the restored configuration state.

### Design rationale

This interrupt model:

* Minimizes hardware complexity
* Avoids hidden register side effects
* Makes ISR behavior explicit and auditable
* Fits both bare-metal and lightweight OS designs

The interrupt frame is intentionally minimal; software is expected to save only what it actually uses.


### Instructions:
| Mode |Binary| Type      | Name     | Description                                |
|------|------|-----------|----------|--------------------------------------------|
| ALL  | 1100 |*Extended* |**RETI**  | Return from Interrupt                      |
| ALL  | 1000 |*Extended* |**SWI**   | Software Interrupt                         |
| ALL  | 0000 |*Extended* |**WFI**   | Wait-For-Interrupt                         |

### Mapping:
| Offset    | Description                | Width |
| --------- | -------------------------- | ----- |
| 0x00      | PC_next low/high           | 16b   |
| 0x02      | CFG snapshot               | 8b    |
| 0x03      | FLAGS snapshot             | 8b    |
| 0x04      | IA                         | 8b    |
| 0x05      | IAR                        | 8b    |
| 0x06–0x07 | RA1                        | 16b   |
| 0x08–0x0F | Reserved for future use    | —     |

### Description:
  - **Interrupts**: *ia* holds the *Interrupt Service Routine* (ISR) page *Most Significant Byte* (MSB). On interrupt:
    - The CPU **stores only the minimal architectural state required for resumption: PC_next, CFG, FLAGS, RA1, IA and IAR** at fixed offsets in page `ia` (see layout below), all other registers are software-managed and must be explicitly saved by the ISR if needed,
    - latches `IAR ← IA`, **clears IE**, clears any pending **XOP**, and
    - **jumps to** `IA<<8 + 0x10` (the ISR entry).
    - Interrupt address register (`IA`) is mapped at `CSR 8`.
  - **WFI\***: Wait-For-Interrupt makes the processor sleep until an interrupt sign is received.
  - **SWI\***: Triggers a software interrupt; flow identical to an external IRQ: autosave on the ia page, latches `IAR←IA`, clears IE (`IE←0`) and jumps to `IA<<8 + 0x10`.
  - **RETI\***: Restores state from the *IAR* page and resumes execution.
    - Base address: **base = IAR << 8**
    - Hardware restores:
      - **PC** ← [base+0x00..0x01]        ; PC_next snapshot
      - **CFG** ← [base+0x02]             ;
      - **FLAGS** ← [base+0x03]           ;
      - **IA**  ← [base+0x04]             ; interrupt page MSB
      - **IAR** ← [base+0x05]             ; previous latched page (for nested unwinding)
      - **RA1** ← [base+0x06..0x07]       ; address register
    - **Not restored by RETI**: **ACC**, **RS0**, **RS1**, **RA0** or any GPR — the ISR must restore them in software before RETI.
    - After RETI, **IE** follows the IE bit of the active **CFG** (restored or left as set by the ISR).
  - Fixed layout within the ia page:
```
; IA page:
; Saved on interrupt entry:      base = IA  << 8
; RETI reads/restores from page: base = IAR << 8
      +0x00 : PC_next[7:0]
      +0x01 : PC_next[15:8]
      +0x02 : CFG snapshot (8-bit)
      +0x03 : FLAGS snapshot (8-bit)
      +0x04 : IA        (8-bit)
      +0x05 : IAR       (8-bit)
      +0x06 : RA1[7:0]  (8-bit)
      +0x07 : RA1[15:8] (8-bit)
      +0x08-0x0F : RSV  (reserved)
      +0x10 : ISR entry (first instruction executed on entry)
```
