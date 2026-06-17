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
  `soc_axi_to_mem` and the UART SRAM loader - issues one request at a time (the
  simulation preloader initializes the banks directly via `$readmemh`, not
  through an init port). Revisit before adding multi-outstanding clients (the
  planned direct CPU mem ports or DMA streams from
  [`roadmap.md`](roadmap.md)): either add per-port response ordering/merging in
  `soc_mem_ss` or document single-outstanding as a hard init-port contract.
