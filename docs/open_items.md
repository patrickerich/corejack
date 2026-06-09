# Open Items

A lightweight log of issues or improvements noticed during development but
deliberately **deferred** — things we decided not to solve immediately. This is
distinct from [`roadmap.md`](roadmap.md), which records intended direction;
open items are latent gaps, tech debt, or design decisions parked for later.

Add an entry when you choose not to fix something now; remove it once resolved.

- **Re-validate the AXKU5 board with the crossbar fabric.** The widened
  `axi_xbar` fabric is hardware-validated on the Arty A7-100T across all seven
  supported cores, but the AXKU5 has not been re-run since the fabric change -
  its last full `make fpga-accept` pass predates the crossbar. Re-run the
  acceptance regression (`make fpga-accept BOARD=axku5 UART_DEV=...`) when the
  AXKU5 is next connected; only one board can be attached to the build server
  at a time and the Arty currently occupies it.
- **Peripheral AXI adapters keep a single-initiator-only arbiter.**
  `soc_axi_to_apb`, `soc_axi_to_dm`, and `soc_axi_to_reg` still gate each
  AXI channel on the other's `valid` (`aw_ready = aw_valid && !ar_valid`,
  `ar_ready = !aw_valid && !w_valid`), which deadlocks if a read and a write
  are ever presented in the same cycle. This is safe today because only the
  single core data initiator reaches UART/CLINT/debug-regs (it never asserts
  `aw` and `ar` together). `soc_axi_to_mem` already got a starvation-free
  read/write arbiter because the crossbar lets multiple initiators reach RAM
  concurrently. Give the three peripheral adapters the same arbiter before any
  second initiator (e.g. the planned uDMA or a dual-port accelerator) can reach
  the APB peripheral subsystem. See [`roadmap.md`](roadmap.md).
