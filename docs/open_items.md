# Open Items

A lightweight log of issues or improvements noticed during development but
deliberately **deferred** — things we decided not to solve immediately. This is
distinct from [`roadmap.md`](roadmap.md), which records intended direction;
open items are latent gaps, tech debt, or design decisions parked for later.

Add an entry when you choose not to fix something now; remove it once resolved.

- **`soc_mem_ss` init ports assume single-outstanding clients.** Each bank
  arbitrates independently and holds one response register, but nothing stops
  one init port from having two requests outstanding to two *different* banks;
  the response collector would then present colliding (and possibly reordered)
  responses for that port. Safe today because every init-port client -
  `soc_axi_to_mem`'s read and write engines and the UART SRAM loader - issues
  one request at a time (the
  simulation preloader initializes the banks directly via `$readmemh`, not
  through an init port). Revisit before adding multi-outstanding clients (the
  planned direct CPU mem ports or DMA streams from
  [`roadmap.md`](roadmap.md)): either add per-port response ordering/merging in
  `soc_mem_ss` or document single-outstanding as a hard init-port contract.
- **No concurrent multi-initiator RAM bandwidth yet (single RAM funnel).** All
  fabric RAM traffic from every initiator is serialized onto one `axi_xbar`
  RAM master port. `soc_axi_to_mem` now splits into independent read and write
  engines on two `soc_mem_ss` init ports (done 2026-06-18), so a RAM read and a
  RAM write hit different banks in the same cycle and the lone-AW deadlock
  workaround is gone. But every initiator's reads still share that master port's
  single AR (and writes its single AW/W), so two initiators still cannot read
  two different banks in the same cycle, and `soc_mem_ss`'s per-bank parallelism
  is otherwise unused. The target is the banked-scratchpad model already drawn in the
  *Multi-Initiator Architecture (planned)* tab of
  [`media/corejack_soc.drawio`](media/corejack_soc.drawio): memory-heavy
  initiators (CPU instr/data, iDMA, accelerators) get dedicated `soc_mem_ss` init
  ports behind a per-initiator egress decoder (RAM vs CSR/peripheral), banks
  scaled to ~init-port count, so N initiators sustain ~1 access per slice per
  cycle. The topology is documented; what is **not** specified is the
  throughput-enabling memory-port contract: to keep one port's accesses to
  different banks in flight you need either fixed-latency / no-backpressure
  responses (TCDM style) or per-port response ordering - the same gap as the
  single-outstanding entry above. (The iDMA memcpy's own read+write concurrency
  is already covered by the read/write-engine split; the remaining work is the
  direct-per-initiator ports for N-initiator concurrency.) Revisit when a
  measured CPU+DMA (or multi-core) workload shows RAM bandwidth is the
  bottleneck. Full analysis: `logs/fabric_bandwidth_and_fpga_provisions.md`.
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
