# CoreJack Documentation

This directory holds the project documentation beyond the top-level
quick-start README. Documentation here should be usable on its own: avoid
private debug logs, temporary local paths, and references to external example
projects.

## Project Orientation

- [Top-level README](../README.md) - purpose, quick start, current status,
  and pointers back into this index.
- [About CoreJack](about.md) - motivation, target audience, what makes
  CoreJack different, and a factual comparison against Chipyard, LiteX,
  Rocket Chip Generator, OpenTitan, and Cheshire/Carfield.
- [Support matrix](support_matrix.md) - generated core/board support status
  from descriptors.
- [Repository layout](repository_layout.md) - quick map of the source tree
  and where each kind of artifact lives.
- [Roadmap](roadmap.md) - current baseline, per-core notes, and the active
  direction for cores, boards, fabric, and software.
- [Open items](open_items.md) - noticed-but-deferred issues and improvements
  (a lightweight tech-debt log, distinct from the roadmap).
- [Tooling](tooling.md) - host tool checks, optional repo-local tool
  installs, and observed validation versions.
- [Dependency management](dependency_management.md) - Bender/FuseSoC split,
  dependency classes, and the optional core checkout policy.
- [Core and board descriptors](core_board_descriptors.md) - descriptor
  schema and how the Make targets derive build variables from `CORE` and
  `BOARD`.
- [Core acceptance checklist](core_acceptance_checklist.md) - validation
  gates before marking a core supported.
- [Coding style](coding_style.md) - style intent for CoreJack-owned code
  and third-party dependency boundaries.

## Adding Hardware

- [Core porting guide](core_porting.md) - add a RISC-V core behind the
  CoreJack platform contract. Includes the conservative `make new-core`
  scaffold flow.
- [Board porting guide](board_porting.md) - add an FPGA board wrapper,
  constraints, board descriptor, and board FuseSoC core. Includes the
  `make new-board` scaffold flow.
- [AXI4 fabric](axi4_fabric.md) - current system fabric structure.
- [AXI4 fabric migration](axi4_fabric_migration.md) - historical migration
  notes and design rationale for moving to an AXI4-native fabric.

## Simulation

- [Simulation](simulation.md) - cocotb + Verilator simulation setup, the
  simulation targets, testbench structure, waveform dumping, and other knobs.

## FPGA And Debug

- [FPGA software flow](fpga_sw_flow.md) - build, program, load, and run
  software on FPGA.
- [FPGA debug stepping](fpga_debug_stepping.md) - OpenOCD/GDB stepping flow
  for debug-capable cores.
- [FPGA hardware smoke](fpga_hardware_smoke.md) - hardware validation flow
  and acceptance expectations.
- [RISC-V debug integration](riscv_dbg_integration.md) - design guidance for
  integrating `riscv-dbg`.
- [UART SRAM loader](uart_sram_loader.md) - fallback SRAM load path for
  cores without usable OpenOCD/GDB debug.
- [External JTAG wiring](jtag_wiring.md) - external-JTAG adapter selection and pin maps
  for the AXKU5 and Arty A7-100T boards.

## Software

- [Zephyr bring-up](zephyr_bringup.md) - Zephyr board/application setup and
  current support notes.

## Core-Specific Notes

- [CV32E40X boot issue](cv32e40x_boot_issue.md) - current reason CV32E40X is
  not part of the supported regression set.
