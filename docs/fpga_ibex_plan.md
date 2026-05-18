# Ibex FPGA Bring-Up Plan

This repository should grow towards a layered FPGA flow where core selection, board selection, and SoC composition remain orthogonal.

## Current Status

The first Ibex/AXKU5 hardware milestone is complete.

Validated baseline:

- AXKU5 bitstream builds and programs successfully.
- The default FPGA clock is a conservative, timing-clean `25 MHz`.
- OpenOCD can enumerate and examine the `riscv-dbg` target over external JTAG.
- GDB can load software into SRAM through the debug module SBA path.
- `hello_world` runs from SRAM and prints through the platform APB UART on the
  board UART pins at `115200` baud.

The known-good UART smoke output is:

```text
=== CoreJack SoC Demo ===
Target: fpga
Core: ibex
Board: axku5
UART base: 0x10000000
Clock: 25000000 Hz, baud: 115200
UART and JTAG debug path are alive.
```

The critical debug integration requirement is that accepted debug-window
requests remain ordered through the fabric. The current platform routes these
accesses through OBI-to-AXI adaptation, AXI address decode, and an AXI-to-DM
bridge before reaching `dm_top`; the registered debug-memory response is then
returned to the original requester.

The 50 MHz FPGA experiment generated a bitstream but failed routed timing by
about `4.7 ns` WNS on a route-dominated Ibex/fabric path. That is a future
timing-closure task, not a blocker for the current functional baseline.

## Initial Goal

Bring up a first FPGA target with:

- `corejack_ibex` as the CPU core
- `riscv-dbg` for external JTAG debug via OpenOCD/GDB
- `apb_uart` for a functional UART console
- one board target as the initial reference platform

This initial target is now the reference baseline. The intended user experience
going forward is:

1. select a core
2. select a board
3. build a bitstream
4. load software over debug or preinitialize memory
5. use both UART and JTAG debug during bring-up

## Recommended Architecture

Use three layers.

### 1. Generic platform / SoC layer

Keep `rtl/top/soc_top.sv` board-agnostic.

This layer should eventually own:

- address map
- core socket
- accelerator socket
- interconnect selection
- memory/peripheral decode

It should not contain:

- FPGA primitives
- board clocks and resets
- board pins
- vendor-specific clocking or IO logic

### 2. FPGA-oriented SoC assembly

Add a separate FPGA integration layer, for example:

- `rtl/platform/fpga/soc_fpga.sv`

This layer should instantiate:

- the selected core adapter
- block RAM / simple memory system
- `apb_uart`
- debug window and SBA plumbing for `riscv-dbg`
- simple bring-up status signals

This is the right place for a first minimal SoC that is practical on FPGA even before the fully generic platform is complete.

### 3. Board wrappers

Add one wrapper per board, for example:

- `rtl/platform/fpga/boards/<board>/<board>_wrap.sv`
- `rtl/platform/fpga/boards/<board>/<board>.xdc`

Board wrappers should own:

- input clock buffers
- PLL/MMCM/clock dividers
- reset synchronization
- LED/UART/JTAG pins
- any board-specific constraints

They should instantiate the generic FPGA SoC assembly, not the core directly.

## Core Integration Strategy

Do not wire Ibex directly into a board wrapper.

Instead add a core adapter layer, for example:

- `rtl/cores/corejack_ibex_socket_adapter.sv`

This adapter should translate from the generic `core_socket_if` contract to the concrete Ibex port set exposed by `rtl/cores/vendored/corejack_ibex/rtl/corejack_ibex_wrapper.sv`.

Minimum adapter responsibilities:

- reset / clock hookup
- boot address and hart ID
- interrupt mapping
- debug request
- instruction and data bus translation

## First FPGA Milestone

The first practical target was "single-hart Ibex bring-up with UART and JTAG
debug". That milestone is complete for AXKU5 at the current 25 MHz default.

### Required blocks

- Ibex core wrapper
- core adapter
- simple memory map
- BRAM-backed main memory
- APB UART peripheral
- `riscv-dbg` debug transport and debug module
- board wrapper

### Minimum memory map

Suggested first map:

- ROM or boot region at reset vector
- RAM / BRAM for program and data
- UART APB window
- debug APB or debug memory window

Exact addresses can remain configurable, but they should be stable enough for OpenOCD/GDB scripts and bare-metal examples.

## Debug Strategy

Use a split where board logic and debug transport remain separated cleanly:

- external JTAG transport via `dmi_jtag`
- `dm_top` from `riscv-dbg`
- one debug request line into the core
- SBA access into the SoC address space
- optional debug memory window if needed by the selected debug topology

This repo already depends on `riscv-dbg`, so the debug path should be based on that package rather than inventing a new one.

## UART Strategy

Use the standalone `pulp-platform/apb_uart` dependency.

Reasons:

- it is already packaged for Bender
- it is independent of CVA6-specific FPGA trees
- it matches the APB-centric bring-up style needed here

`apb_uart` pulls in these extra dependencies through its own Bender manifest:

- `apb`
- `obi`
- `obi_peripherals`
- `register_interface`

## Proposed Repository Layout

Suggested additions:

- `rtl/platform/fpga/`
- `rtl/platform/fpga/soc_fpga.sv`
- `rtl/platform/fpga/debug/`
- `rtl/platform/fpga/boards/axku5/`
- `rtl/platform/fpga/scripts/openocd.cfg`
- `rtl/platform/fpga/scripts/load_elf.sh`
- `rtl/platform/fpga/scripts/run_elf.sh`

Possible future additions:

- `cfg/boards/<board>.yaml`
- `cfg/cores/<core>.yaml`
- generator support for selecting board/core combinations

## Build Flow Recommendation

Keep the current simulation flow intact, and add a separate FPGA flow.

Packaging/tooling note to revisit later:

- the current repo still uses a pragmatic mixed flow where `corejack.core` directly lists some `deps/...` sources fetched by Bender
- this works today, but it is not the desired long-term packaging boundary between Bender-managed dependencies and FuseSoC-managed cores
- after the current Ibex bring-up is more complete, the dependency/core packaging strategy should be revisited deliberately

Suggested Make targets:

- `make fpga-flist BOARD=<board> CORE=<core>`
- `make fpga-bit BOARD=<board> CORE=<core>`
- `make openocd BOARD=<board>`
- `make fpga-load-sw SW_APP=<app>`
- `make fpga-run-sw SW_APP=<app>`
- `make sim-run-sw SW_APP=<app>`

The Tcl build scripts should consume a generated flist and a board-local XDC.

## Completed Initial Implementation Steps

1. Added the standalone UART dependency path and verified checkout/symlink behavior.
2. Created the FPGA directory structure.
3. Added the AXKU5 board wrapper.
4. Added the Ibex socket adapter.
5. Added a minimal FPGA SoC assembly with SRAM, UART, and debug.
6. Added OpenOCD/GDB helper scripts parameterized for this repo.
7. Added bare-metal apps that can run in simulation or on FPGA.
8. Split software builds by `TARGET=sim|fpga` so simulation-only MMIO is not
   emitted into FPGA binaries.
9. Validated the OpenOCD/GDB load path and UART output on hardware.

## Current Bring-Up Checklist

Current validation status:

1. Build and program the AXKU5 bitstream successfully: done.
2. Verify that `riscv-dbg` is reachable from OpenOCD over the external debug JTAG link: done.
3. Verify GDB-controlled SRAM loading and execution through the SBA path: done.
4. Verify UART output on real hardware: done.
5. Verify the full Ibex integration on hardware with at least one software smoke test: done.
6. Verify the debug ROM fetch path in simulation: done.
7. Verify debug-module SBA RAM access in simulation while the core is held in
   reset: done.

Repeatable hardware smoke validation is documented in
[`docs/fpga_hardware_smoke.md`](fpga_hardware_smoke.md).

## Generic Software Simulation

The repo now has a generic cocotb-driven software simulation path:

- one HDL harness: `tb/soc_dut.sv`
- TB-side software observation split into `tb/uart_apb_tx_monitor.sv` and `tb/sim_ctrl_monitor.sv`
- one generic cocotb test: `tb/test_soc_sw.py`
- runtime app selection via `SW_APP`
- banked memory preload via `+MEM_PATH=<sw/build/<target>/<core>/<app>>`

Generic C tests should converge on a common contract:

- use `printf()` for diagnostic text
- report completion through the software-visible `sim_ctrl` MMIO store
- call `sim_ctrl_pass()` on success
- call `sim_ctrl_fail(<code>)` on failure

The intended boundary is:

- `soc_top` remains hardware-only
- testbench-only logic observes UART writes and the final `sim_ctrl` store
- cocotb consumes those monitor signals for logging and PASS/FAIL

This avoids app-specific Python tests while keeping pass/fail behavior explicit and machine-checkable.

## Memory Subsystem Note

The new `soc_mem_ss` scaffold is only a first structural placeholder.

Before it is integrated into `soc_top` as the real memory subsystem, it must be upgraded to use starvation-free per-bank round-robin arbitration.

This is a strict requirement:

- no initiator may be starved on a contended bank
- fixed-priority arbitration is not acceptable for the final design
- request persistence and/or ingress buffering should be added so losing requests remain pending until granted

## Longer-Term Roadmap

After the first Ibex-based hardware bring-up is stable, the repository should expand in these directions:

- support multiple selectable cores under the same SoC framework
- add more FPGA boards with a thin, repeatable board-wrapper pattern
- add a user-friendly custom core and custom board flow based on small
  descriptors plus predictable wrapper/adapter files
- continue converging the user-facing flow around simple `CORE=<core>` and
  `BOARD=<board>` selection backed by explicit descriptors
- revisit the current local SoC fabric and converge on a more general interconnect strategy
- evaluate AXI, TileLink, or other interconnect options without coupling that choice to board support
- keep the memory subsystem modular and multi-initiator capable regardless of the top-level SoC fabric choice
- improve the software stack beyond the current bare-metal flow
- consider Zephyr support once the hardware/debug/UART baseline is proven

Likely core expansion order:

- SERV as a very small-area reference core.
- CV32E40P as a practical 32-bit embedded-class core with a PULP ecosystem fit.
- CVA6 as a larger application-class integration target that will force a more
  serious interconnect, cache, and memory-system boundary.

Likely descriptor structure:

- `cfg/cores/<core>.yaml` for source/dependency selection, adapter module,
  reset/boot/debug contracts, bus protocol, ISA/toolchain defaults, and expected
  clock range.
- `cfg/boards/<board>.yaml` for clock input, reset polarity, pins,
  programming/debug transports, UART device notes, constraints, and
  board-local scripts.
