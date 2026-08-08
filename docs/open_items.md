# Open Items

A lightweight log of issues or improvements noticed during development but
deliberately **deferred** — things we decided not to solve immediately. This is
distinct from [`roadmap.md`](roadmap.md), which records intended direction;
open items are latent gaps, tech debt, or design decisions parked for later.

Add an entry when you choose not to fix something now; remove it once resolved.

- **The bank count is a pair of defaults that must agree.** `soc_top.MemNumBanks`
  and `sw/Makefile NUM_BANKS` are both 8 and have to stay in lockstep: the RTL
  reads back exactly the `bank_<n>.hex` split the software build wrote. A
  mismatch fails loudly (missing bank images, so the core boots from zeroed
  memory) rather than silently, which is why threading a single value through the
  board descriptor stayed deferred. Make it descriptor-driven when a second value
  is worth supporting. See the *Memory subsystem follow-up* in
  [`roadmap.md`](roadmap.md).
- **Sim UART printf is baud-throttled, inflating simulation cycle counts.** The
  cocotb harness captures printf passively by tapping the APB write to the UART
  THR (`tb/uart_apb_tx_monitor.sv`), so capture does not decode the serial pin.
  But the real `apb_uart` is still instantiated and `uart_putc`
  (`sw/c/common/uart.c`) busy-waits on its LSR THR-empty bit before every byte,
  so the CPU self-throttles to the programmed baud: divisor ~14 -> 16*14*~10
  ~= 2240 cycles per character. A few lines of output cost hundreds of thousands
  of cycles (this is why `dma_smoke` needs ~1.27M cycles, over the 1M
  `SIM_TIMEOUT_CYCLES` default). Functionally correct, just slow. When it starts
  to bite, the cleanest provision is a sim-only build knob that programs a tiny
  UART divisor (very high baud) so the real UART drains ~16 cycles/byte; the
  monitor captures from the APB write regardless of baud, so output is
  unchanged. Alternatives: a sim-only skip-the-LSR-poll fast path (adds
  sim/FPGA driver divergence), trimming printf volume, or just raising
  `SIM_TIMEOUT_CYCLES` for verbose apps.
- **CVW `rdtime` reads 0 (CSR time shadow not wired).** Wally shadows the
  CLINT's memory-mapped `mtime` into the `time`/`timeh` CSRs through its
  `MTIME_CLINT` core input, but the vendored PULP CLINT does not export its
  internal `mtime` counter, so `corejack_cvw_ahb_adapter` ties the port to
  zero and `rdtime` permanently returns 0 on CVW (with `ZICNTR_SUPPORTED = 1`,
  `rdcycle`/`rdinstret` still work — they are core-internal). Software must
  use the memory-mapped `mtime` at `0x0200_bff8` instead. Fixing this
  properly needs either an mtime export added to (a wrapper of) the CLINT or
  a CLINT replacement; disabling ZICNTR would trade the silent zero for an
  illegal-instruction trap but also removes the working counters.
