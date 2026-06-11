# About CoreJack

## Why This Project Exists

The open RISC-V hardware world has plenty of good CPU cores and plenty of
good FPGA/ASIC platforms, but they tend to be tightly bundled with each
other: a given platform is usually written *around* one core (or one
core family) and one toolchain mindset. Swapping the core, swapping the
fabric, or moving the same SoC from FPGA prototyping toward ASIC
integration typically means rewriting the integration layer.

CoreJack is the platform side of that pairing, written so the core is
the variable. The same generic `soc_top` is reused across every
supported RISC-V core through a thin per-core adapter, and across every
supported FPGA board through a thin board wrapper. The user-facing
selection is just `CORE=<core> BOARD=<board>`.

The fabric and integration choices are deliberately production-style
(AXI4 central interconnect, APB peripherals, `riscv-dbg`, CLINT, banked
SRAM with proper reset domains) so the same SoC structure is meaningful
beyond FPGA prototyping. CoreJack has not been taped out and does not
claim to be silicon-validated; it is *ASIC-aware* in the sense that the
RTL boundaries, reset domains, and bus contracts are the ones an ASIC
flow would expect, not FPGA-only shortcuts.

## Who It's For

- Hobbyists and engineers who want to evaluate several RISC-V cores
  against the same SoC, on a real FPGA, without rebuilding the
  integration layer for each one.
- IP developers who want a ready-made vehicle to prototype and
  functionally validate a new block - accelerator, peripheral, memory
  controller, fabric experiment - against a real CPU. The platform's
  socket boundary lets you "jack in" the new IP, hit it from C code
  through a small test app, and exercise it both in simulation and on
  hardware. The same FPGA flow then doubles as a stage for turning
  that IP into a working application, not just a unit test. The
  accelerator socket is a validated contract: the iDMA system DMA is
  its first tenant (AXI memory, APB CSR, and PLIC-routed interrupt legs
  exercised in simulation and on hardware) - see
  [`roadmap.md`](roadmap.md#system-ip-and-accelerator-expansion).
- Researchers and educators who want a SystemVerilog-only platform that
  is small enough to read end-to-end in an afternoon.
- Engineers prototyping toward an ASIC integration who want the FPGA
  bring-up flow to use the same fabric, debug, and memory subsystem
  they intend to keep on silicon.

## What Makes It Different

1. **Swappable cores at a clean adapter boundary.** The current
   release ships adapters for eight RISC-V cores drawn from three
   upstream communities - lowRISC (Ibex); the OpenHW Group
   (CV32E40P, CV32E40S, CV32E40X, CVA6, and CORE-V-Wally); and the
   independent low-area cores SERV and PicoRV32. That set is a
   starting point, not a fixed list: the platform is built to keep
   growing, and `make new-core` scaffolds the descriptor, FuseSoC
   file, and adapter stub for a new candidate core. Each core keeps
   its native bus contract (OBI, AXI, AHB-Lite, or a custom
   single-port memory interface) inside its adapter; everything
   reaches shared memory and peripherals through the same AXI4
   fabric.
2. **ASIC-aware, not FPGA-first.** The platform uses production
   PULP-Platform IP (`axi`, `apb`, `obi`, `apb_uart`, `clint`,
   `riscv-dbg`) and a real AXI4 interconnect rather than a
   prototyping-only memory bus. FPGA board wrappers are kept thin so
   moving between boards (or eventually toward silicon) does not
   require rewriting the SoC.
3. **SystemVerilog throughout.** RTL is 100% hand-written
   SystemVerilog - no generators sit between you and the gates.
   This is a scope and directness choice, not a position against
   generators: Chisel, Migen/Amaranth, SpinalHDL, and similar
   generator flows are excellent tools where they pay for
   themselves. For CoreJack's "swap a core into a clear platform"
   goal the payoff is directness - every line of the SoC is
   readable in place, and what you read in the source is what
   reaches the gates. Python is used only for build glue,
   descriptor resolution (`CORE`/`BOARD` selection), lint/check
   tools, scaffolding helpers, and host-side runtime tools (such
   as the UART SRAM loader protocol). There is no Scala/Chisel or
   Migen/Python-HDL learning cliff.
4. **Descriptor-driven build flow.** Small YAML descriptors under
   `cfg/cores/` and `cfg/boards/` capture everything the build flow
   needs: ISA/ABI, adapter module, debug parameters, FPGA part, clock,
   pin mapping, programming command. Adding a new core or board is
   done through `make new-core` / `make new-board` scaffolds plus a
   real adapter and constraints file.
5. **Two software loading paths.** Debug-capable cores load through
   OpenOCD/GDB and `riscv-dbg` system-bus access. Low-area or
   non-debug cores (SERV, PicoRV32, CVW/Wally) load through an
   optional side-path UART SRAM loader that reuses the board UART
   pins. Both paths are validated in CI/hardware acceptance.
6. **Pinned, reproducible tooling.** Bender pins HDL dependencies,
   FuseSoC drives Verilator and Vivado, and the optional repo-local
   tool installs (Verilator, Verible, RISC-V GNU toolchain) use pinned
   versions with SHA-verified downloads or expected-commit checks.

## How CoreJack Compares To Other RISC-V Platforms

The table below is a factual map of where CoreJack sits in the
landscape; the other projects are excellent in their own targets, and
the "When to pick over CoreJack" column is the honest version of *not
this one*.

| Project | Primary language | Core focus | Fabric / integration style | When to pick it over CoreJack |
| --- | --- | --- | --- | --- |
| **Chipyard** | Scala / Chisel | BOOM, Rocket, plus generators | TileLink-centric; massive generator/test infrastructure | Generator-driven RTL with parameterised cache hierarchies, Berkeley-ecosystem flows |
| **Rocket Chip Generator** | Scala / Chisel | Rocket | TileLink, the reference Rocket flow | You specifically want Rocket and its surrounding generator stack |
| **LiteX** | Python / Migen / Amaranth | VexRiscv (default), CVA6, NaxRiscv, others | Wishbone-centric, very wide peripheral library | FPGA prototyping with a huge peripheral palette and Python flow |
| **OpenTitan** | SystemVerilog | Ibex (security-hardened) | Security-focused SoC, formally verified blocks | Building a secure root-of-trust |
| **Cheshire / Carfield (PULP)** | SystemVerilog | CVA6 | Production PULP CVA6 SoC, single-core focus | You want an already-validated CVA6 ASIC platform |
| **CoreJack** | SystemVerilog | Eight swappable cores (and growing) | AXI4-centric, PULP fabric IP, descriptor-driven CORE/BOARD selection | Comparing several cores on the same SoC, with an ASIC-aware integration boundary |

CoreJack's specific spot:

- Smaller and more approachable than Chipyard or OpenTitan — a
  hobbyist can read the whole platform RTL in one sitting.
- More ASIC-aware than LiteX — production AXI4 fabric, real reset
  domains, `riscv-dbg` integration, banked SRAM with starvation-free
  arbitration.
- More core-agnostic than Cheshire / Carfield — CoreJack treats the
  core as the variable rather than centering on one CPU.
- More SystemVerilog-native than Chipyard / LiteX — no Scala or
  Python HDL between you and the gates.

## When CoreJack Is *Not* The Right Choice

Being honest about scope avoids future surprises:

- **You want a turnkey RTOS platform today.** Zephyr is at
  `initial_supported` for the Zephyr-capable cores: the board target
  builds, the ELF loads, and the timer-smoke prints. Runner integration
  and broader regression coverage are explicit follow-up work — see
  [`zephyr_bringup.md`](zephyr_bringup.md).
- **You want a large peripheral library.** CoreJack ships exactly what
  the platform needs (APB UART, CLINT, banked SRAM, debug, and the iDMA
  system DMA). LiteX is
  much better suited if peripheral variety is the point.
- **You want generator-driven RTL.** CoreJack favours explicit,
  human-authored SystemVerilog over generators. Chipyard wins on that
  axis.
- **You want silicon-validated production hardware today.** OpenTitan
  and the PULP CVA6 platforms have actual silicon and ecosystem
  programs behind them. CoreJack is an integration platform, not a
  silicon product.

## Current Status

For the per-core/board support table, see
[`support_matrix.md`](support_matrix.md). For the active direction
across cores, boards, fabric, and software, see
[`roadmap.md`](roadmap.md).
