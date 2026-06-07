# Open Items

A lightweight log of issues or improvements noticed during development but
deliberately **deferred** — things we decided not to solve immediately. This is
distinct from [`roadmap.md`](roadmap.md), which records intended direction;
open items are latent gaps, tech debt, or design decisions parked for later.

Add an entry when you choose not to fix something now; remove it once resolved.

- **Refresh the AXI fabric SoC diagram for the crossbar.** The system fabric
  now uses a PULP `axi_xbar` in place of the `soc_axi_arbiter` + `soc_axi_demux`
  pair (see [`axi4_fabric.md`](axi4_fabric.md)), but
  [`media/corejack_soc.drawio`](media/corejack_soc.drawio) and the exported
  `media/corejack_soc_axi_fabric.svg` still draw the old arbiter/demux pair.
  Update the drawio source and re-export per the workflow in the diagram docs.
  Deferred because it is a manual drawio edit, not required for the RTL/sim
  change to be correct.
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
