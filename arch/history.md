# Final Considerations

**NEG**: Started with NEG/Negated instructions/behavior, but was replaced with a more default behavior (**XOP**) that only affects the next instruction, this change allowed for a better compression and a more stable behavior, this will also help on the compiler construction.

**LK**: Link was demoted to be replaced by a more versatile "Swap Configuration", now it's possible to enable auto-increment when reading/writing from/to memory with the advantage of also be able to secure a known working state for the functions.

**Branches**: Early drafts considered branches based on **RA0** (and later a selectable mode), but this was replaced by a fully deterministic **PC-relative immediate** model. Branches are now encoded as a fixed **16-bit (2-byte)** `BRC`, with `func` acting as a **flag mask** `{N,Z,V,C}` and `imm8` providing the signed displacement relative to `PC_next`. This keeps control-flow uniform and toolchain-friendly: comparisons/tests (`CMP`, `TST`, `BTST`) *produce* flags, while `BRC` only *consumes* them. The previous scaling/mode concept (**BRS**) was removed to avoid ambiguous offset interpretation.

**SS/SA & CFG**: SS and SA was initially designed for quick register swapping, this design was adjusted to allow partial swaps respecting **W** (useful for endianness control). To complement this, **CFG** now supports immediate loading, easing state management and reducing register pressure. **SA** remains a full 16-bit swap for address manipulation, as partial swaps provide little benefit in this context.

**OPCODE Changes**: Although freezing the opcode map early would be desirable, during core design it became clear that some instructions could be organized in a more intuitive way. These changes are not intended to improve performance nor simplify decoding logic but to improve semantic grouping and readability of the ISA. By consistently separating common ALU-like operations (`xxx1`) from control, configuration, and architectural instructions (`xxx0`), the instruction set becomes easier to reason about, memorize, and hand-code in assembly. Given the small scope of the project, prioritizing clarity and interpretability over rigid opcode stability was considered a reasonable trade-off.

**CFG**: The original motivation for keeping CFG in the extended space—preserving a fixed 16-bit encoding for alignment—proved weak, as the MISA-O ISA is fundamentally nibble-oriented and already encourages flexible instruction sizing. Promoting CFG to a default opcode simplifies the architectural model, reflects its central role in execution semantics, and reduces mental and implementation overhead without increasing hardware complexity.

**Removed Instructions**: **CLC** was removed as the **CI** (Carry-In) flag in **CFG** renders explicit carry manipulation redundant for arithmetic determinism.

**Multiply**: The area/power cost of a hardware multiplier is high for this class of core, and the **base opcode map is full**. Comparable minimal CPUs also omit MUL. Software emulation (shift-add) handles 4/8/16-bit cases well, so the practical impact is low. But there is a plan to create an extension (CFG reserved = 1) that will replace non-mandatory instructions by new ones, like **MAD**, DIV, Vector MAD or other arithmetic operations. The idea behind having MUL instruction is to keep open the possibility of an implementation that could run DOOM.

**CSR Bank (Control & Extensions)**: To support richer control, debugging and future extensions, MISA-O also reserves space for a small CSR bank (up to 16 × 16-bit registers, 32 bytes total), exposed via optional `CSRLD`/`CSRST` instructions that reuse the RACC/RRS opcodes in LK16 and use the instruction’s immediate nibble as CSR index (0–15). This CSR bank can host core control bits, extended interrupt state or configuration for the MAD profile and other vendor-specific features, without bloating the baseline register file. As with the arithmetic extensions, CSR access is initially treated as a custom/optional feature to be prototyped and validated before being committed to the core specification.

**MAD Profile**: The *MAD Profile (Multiply-Add & Derivatives)* is an optional execution profile that extends the arithmetic capabilities of MISA-O without impacting the baseline datapath or register model.

The profile introduces a compact multiply-accumulate unit (8-bit × 8-bit → 16-bit accumulate), along with lightweight arithmetic helpers such as MIN and MAX, specifically targeting fixed-point inner loops common in graphics, audio and DSP-style workloads.

MAD operates exclusively in the SPE link mode and relies solely on existing architectural registers (ACC, RS0, RS1), with all control encoded per-instruction via the immediate nibble. The MAD instructions themselves do not require any additional architectural state or control registers.

As an optional profile, MAD allows implementers to trade silicon area and latency for higher arithmetic throughput. Implementations may range from simple multi-cycle designs to fully pipelined units, provided architectural semantics are preserved. The profile is considered architecturally stable and may be adopted independently of other optional execution profiles.
