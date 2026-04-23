## Debug Profile

MISA-O does not define a dedicated debug mode or external debug port. Instead, debugging is built on top of the existing **SWI** mechanism and the interrupt context save on the `IA` page.

A typical debug monitor runs as the unified ISR entry (`IA<<8 + 0x10`) and uses the interrupt frame at `IA<<8` plus the CSR bank to inspect and modify the machine state.

#### Single-step via EVTCTRL.SS_IE / SS_P

For implementations that support the Debug Profile, two bits in `EVTCTRL` (CSR 2) control single-step execution:

| Bit | Name  | Byte      | Access | Description                          |
|-----|-------|-----------|--------|--------------------------------------|
|  3  | SS_IE | low byte  | R/W    | Single-step enable                   |
| 12  | SS_P  | high byte | R/W1C  | Single-step pending (set by hardware) |

Cores that do not implement the Debug Profile must treat `SS_IE` as RAZ/WI and `SS_P` as RAZ.

When `SS_IE = 1`, `CFG.IE = 1` and the core is **not** currently inside an ISR (`EVTCTRL.IN_ISR = 0`), the hardware behaves as follows:

1. A normal instruction retires (user code).
2. Before fetching the next instruction, the core sets `SS_P = 1` and delivers a trap using the same mechanism as SWI — context save on the `IA` page, entry at `IA<<8 + 0x10`. `SW_P` is **not** set; only `SS_P` is.
3. `SS_IE` is **not** automatically cleared — the handler controls whether stepping continues.

**XOP atomicity**: the single-step trap follows the same rule as all other interrupts — if an `XOP` prefix has been fetched but its extended instruction has not yet retired, the trap is held until the `XOP`+instruction pair completes as an atomic unit. A single-step trap will never fire between `XOP` and its paired instruction. See the Interrupt Profile for the full atomicity rule.

**CFG.IE requirement**: because single-step is delivered as a SWI, it requires `CFG.IE = 1` to fire. Code running with interrupts disabled (e.g. a critical section) cannot be single-stepped with this mechanism; the trap is silently suppressed until `CFG.IE` is re-enabled.

The handler identifies a single-step trap by checking `SS_P` in `EVTCTRL` (as opposed to `SW_P`, which is set by the `SWI` instruction). Both bits may be set simultaneously if a `SWI` instruction is reached while single-stepping; the handler should clear whichever are relevant before returning.

This allows a software debug monitor to implement classic single-step:

- **One-shot step**: clear `SS_P` (W1C) and clear `SS_IE` (write 0), then `RETI`. User code resumes normally until the monitor re-enables `SS_IE`.
- **Continuous stepping**: leave `SS_IE = 1`, clear `SS_P` (W1C) on each entry, then `RETI`. The monitor traps after every user instruction until it clears `SS_IE`.

#### Using SWI as a software breakpoint

The `SWI` instruction itself remains the preferred software breakpoint primitive: inserting `SWI` in code forces a trap into the debug monitor whenever that instruction is executed.

Combining SWI breakpoints with `SS_IE`/`SS_P` single-step provides a minimal yet powerful debug facility without additional opcodes or privilege levels.
