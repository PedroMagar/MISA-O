## Debug Profile

MISA-O does not define a dedicated debug mode or external debug port. Instead, debugging is built on top of the existing **SWI** mechanism and the interrupt context save on the `IA` page.

A typical debug monitor runs as a software ISR (usually the SWI vector) and uses the interrupt frame at `IA<<8` plus the CSR bank to inspect and modify the machine state.

#### Single-step via CORECFG.DBGSTEP

For implementations that support the Debug Profile, bit **DBGSTEP** (bit 12) of `CORECFG` enables **single-step execution**:

- When `DBGSTEP = 1`, `CFG.IE = 1` and the core is **not** currently inside an ISR (`EVTCTRL.IN_ISR = 0`), the hardware behaves as follows:
  1. A normal instruction retires (user code).
  2. Before fetching the next instruction, the core triggers a **SWI** (software interrupt), performing the usual context save on the `IA` page.
  3. On entry to this SWI, the hardware **automatically clears DBGSTEP**.

This allows a software debug monitor to implement classic single-step:

- **One-shot step**:
  - In the debug handler, set `DBGSTEP = 1` in `CORECFG` and return with `RETI`.
  - The next user instruction executes, then a SWI brings control back to the monitor.

- **Continuous stepping**:
  - In the debug handler, re-arm `DBGSTEP = 1` before `RETI` to trap again after every instruction.

Cores that do not implement the Debug Profile must treat `DBGSTEP` as read-as-zero / write-ignored and never trigger SWI from it.

#### Using SWI as a software breakpoint

The `SWI` instruction itself remains the preferred software breakpoint primitive: inserting `SWI` in code forces a trap into the debug monitor whenever that instruction is executed.

Combining SWI breakpoints with `DBGSTEP` provides a minimal yet powerful debug facility without additional opcodes or privilege levels.
