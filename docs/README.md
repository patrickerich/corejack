# CoreJack Documentation

This directory contains the project documentation beyond the top-level
quick-start README. Documentation in this repository should be usable on its
own: avoid private debug logs, temporary local paths, and references to
external example projects.

## Start Here

- [Top-level README](../README.md) - current project status, setup, common
  commands, and support matrix.
- [Support matrix](support_matrix.md) - generated core/board support status
  from descriptors.
- [Core and board descriptors](core_board_descriptors.md) - descriptor schema
  and how Make derives build variables from `CORE` and `BOARD`.
- [Tooling](tooling.md) - host tool checks, repo-local tool installs, and
  observed validation versions.
- [Dependency management](dependency_management.md) - Bender/FuseSoC split,
  dependency classes, and optional core checkout policy.
- [Core acceptance checklist](core_acceptance_checklist.md) - validation gate
  before marking a core supported.
- [Coding style](coding_style.md) - style intent for CoreJack-owned code and
  third-party dependency boundaries.

## Adding Hardware

- [Core porting guide](core_porting.md) - add a RISC-V core behind the CoreJack
  platform contract. Includes the conservative `make new-core` scaffold flow.
- [Board porting guide](board_porting.md) - add an FPGA board wrapper,
  constraints, board descriptor, and board FuseSoC core. Includes the
  `make new-board` scaffold flow.
- [AXI4 fabric](axi4_fabric.md) - current system fabric structure.
- [AXI4 fabric migration](axi4_fabric_migration.md) - migration notes and
  design rationale for the AXI4-native fabric.

## FPGA And Debug

- [FPGA software flow](fpga_sw_flow.md) - build, program, load, and run
  software on FPGA.
- [FPGA debug stepping](fpga_debug_stepping.md) - OpenOCD/GDB stepping flow for
  debug-capable cores.
- [FPGA hardware smoke](fpga_hardware_smoke.md) - hardware validation flow and
  acceptance expectations.
- [RISC-V debug integration](riscv_dbg_integration.md) - general guidance for
  integrating `riscv-dbg`.
- [UART SRAM loader](uart_sram_loader.md) - fallback SRAM load path for cores
  without usable OpenOCD/GDB debug.

## Software

- [Zephyr bring-up](zephyr_bringup.md) - Zephyr board/application setup and
  current support notes.

## Core-Specific Notes

- [CV32E40X boot issue](cv32e40x_boot_issue.md) - current reason CV32E40X is
  not part of the supported regression set.
