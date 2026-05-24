# Roadmap

This document records the current direction for CoreJack across cores, boards,
software, and the SoC platform. For the descriptor-derived support table, see
[`support_matrix.md`](support_matrix.md). For the validation gates used to
promote a core, see [`core_acceptance_checklist.md`](core_acceptance_checklist.md).

## Current Baseline

The first FPGA board target `axku5` is hardware-validated across the
supported core set.

Platform pieces:

- The generic `soc_top` smoke simulation passes.
- The generic cocotb software simulation passes with compiled C tests.
- The central AXI4 fabric routes core instruction, core data, and debug SBA
  traffic into the shared SRAM, APB UART, debug module, and CLINT targets.
  See [`axi4_fabric.md`](axi4_fabric.md).
- The banked 64-bit SRAM (`soc_mem_ss`) uses per-bank round-robin
  arbitration and exposes a separate init port that the AXI fabric, the
  simulation preloader, and the optional UART SRAM loader share.
- `riscv-dbg` (`dmi_jtag` + `dm_top`) and CLINT are integrated in `soc_top`.
- The AXKU5 bitstream closes timing at the conservative `25 MHz` default.
- OpenOCD enumerates and examines the RISC-V target over external JTAG;
  GDB loads an ELF into SRAM through the debug module SBA path.
- `hello_world` runs from SRAM and prints through the platform APB UART at
  `115200` baud on every supported core.
- Zephyr `initial_supported` smoke runs on the Zephyr-capable supported
  cores; see [`zephyr_bringup.md`](zephyr_bringup.md).

The known-good `hello_world` UART output for debug-capable cores is:

```text
=== CoreJack SoC Demo ===
Target: fpga
Core: <core>
Board: axku5
UART base: 0x10000000
Clock: 25000000 Hz, baud: 115200
UART and JTAG debug path are alive.
```

UART-loader cores end with `UART path is alive.` instead.

A 50 MHz FPGA experiment generated a bitstream but missed routed timing by
about `4.7 ns` WNS on a route-dominated path. This remains a future
timing-closure task rather than a baseline blocker.

## Per-Core Notes

The authoritative descriptor-derived matrix lives in
[`support_matrix.md`](support_matrix.md). Notes per core:

- **Ibex** - reference baseline: simulation, FPGA, OpenOCD/GDB debug, Zephyr
  initial smoke.
- **CV32E40P** - simulation, FPGA, OpenOCD/GDB load/run with
  halt/breakpoint/step debug validated. Zephyr initial.
- **CV32E40S** - simulation, FPGA, OpenOCD/GDB load/run with single-step
  validated. The adapter passes core reset-status state into
  `dm_top.unavailable_i`; see
  [`core_acceptance_checklist.md`](core_acceptance_checklist.md). Zephyr
  initial.
- **CVA6** - native AXI core path; simulation, FPGA, OpenOCD/GDB
  load/run/single-step validated. Zephyr initial (RV64).
- **CV32E40X** - demoted from the supported set. Instruction-fetch and
  vector behavior diverge from the other cores and are tracked upstream
  in [`cv32e40x_boot_issue.md`](cv32e40x_boot_issue.md). It is intentionally
  excluded from default regressions until the upstream behavior is resolved.
- **SERV** - bit-serial low-area core. Bare-metal `hello_world` runs in
  simulation through a local socket adapter and on FPGA through the UART
  SRAM loader. Zephyr boots through the same loader path with a
  board-specific idle override to avoid `wfi`. OpenOCD/GDB debug is
  unsupported.
- **PicoRV32** - bare-metal `hello_world` runs in simulation through a local
  socket adapter and on FPGA through the UART SRAM loader. OpenOCD/GDB debug
  is unsupported. Zephyr is unsupported because PicoRV32's custom IRQ
  instruction interface does not match Zephyr's standard RISC-V trap/CSR
  model.
- **CVW/Wally** - bare-metal `hello_world` runs in simulation through a
  local AHB-Lite adapter and on FPGA through the UART SRAM loader.
  OpenOCD/GDB debug is unsupported.

## Near-Term Priorities

Hardware regression and stability:

- Keep at least one known-good core/board target as the stable regression
  baseline.
- Keep the debug ROM fetch and SBA simulation checks in the regression
  baseline.
- Keep board LED mappings as simple status; add richer probes only when a
  specific debug investigation needs them.
- Keep `25 MHz` as the conservative FPGA default and treat higher clocks as
  a later timing-closure task.

Software and validation flow:

- Keep the generic cocotb software test flow as the main pre-silicon
  validation path for bare-metal C tests.
- Keep Zephyr timer-smoke coverage as the initial software-stack regression
  for the supported core/board pairs.
- Keep the UART SRAM loader path as the supported FPGA load flow for the
  non-debug cores (SERV, PicoRV32, CVW/Wally).

## Platform Architecture Direction

- Treat AXI4 as the central SoC fabric. Core-native buses are allowed at
  the core adapter boundary but must reach RAM, UART, CLINT, debug, and
  other shared peripherals through the shared AXI fabric.
- Keep the memory subsystem modular and multi-initiator aware. The current
  arbiter is intentionally scoped to single-beat traffic; replace or widen
  it before adding AXI-native burst initiators.
- Keep `soc_top` board-agnostic. Board wrappers provide only clock/reset,
  FPGA primitives, constraints, and physical pin wiring.
- Continue evolving the descriptor-driven `CORE=<core>` / `BOARD=<board>`
  selection so new combinations do not require hand-editing scattered build
  logic.

## Core And Board Expansion

- Add more cores under the same socket and AXI fabric contract using
  [`core_porting.md`](core_porting.md) and the `make new-core` scaffold.
- Add more FPGA boards behind thin board wrappers using
  [`board_porting.md`](board_porting.md) and the `make new-board` scaffold.
- Use [`core_acceptance_checklist.md`](core_acceptance_checklist.md) as the
  promotion gate for `integration.sim`, `integration.fpga`, and
  `integration.debug`.

Planned next FPGA board target:

- **Digilent Arty A7-100T** (Xilinx Artix-7 `xc7a100tcsg324-1`) - a
  lower-cost reference target to complement the current AXKU5 baseline and
  to validate that the generic `soc_top` integration works on a smaller,
  non-UltraScale+ FPGA family. Bring-up will use the same `make new-board`
  scaffold and the standard descriptor / wrapper / XDC / board FuseSoC core
  structure documented in [`board_porting.md`](board_porting.md).

## Software Ecosystem

- Continue improving the generic bare-metal software flow under `sw/c/`.
- Expand Zephyr beyond the current `initial_supported` timer-smoke level
  for the supported core/board pairs.
- Define the missing RTOS-facing platform services explicitly before
  promoting any core to `software.zephyr.status: supported`. This includes
  automated FPGA timer-smoke acceptance, Zephyr flash/debug runner
  integration, a simulation acceptance path, and broader regression
  coverage.

## Longer-Term Direction

- Evaluate AXI vs. TileLink vs. other fabrics for the long-term SoC
  integration boundary while keeping that choice orthogonal to board and
  core selection.
- Stress the debug SBA and memory contention paths beyond the current
  single-beat regression set as more AXI-native initiators are added.
- Add an optional LLVM/Clang software toolchain alongside the current
  GCC/Newlib default once it has matching compile, simulation, ELF loading,
  and debug validation for the relevant cores.
