# CoreJack

CoreJack is a starter platform for evaluating swappable RISC-V cores and
accelerators with an ASIC-aware architecture.

For the full documentation map, start at [`docs/README.md`](docs/README.md).
This top-level README is kept as the quick-start and current-status page.

## Project status

This repository is still in an early architecture phase, but the first FPGA
board target is now hardware-validated across the supported core set. The
platform can build bitstreams, program a board, load software over OpenOCD/GDB
through `riscv-dbg` for debug-capable cores or through the UART SRAM loader for
non-debug low-area cores, and print through the platform APB UART via the board
UART pins.

The current validated baseline is intentionally modest:

- validated FPGA board target: `axku5` (first board, not an architectural
  special case)
- cores: Ibex, CV32E40P, CV32E40S, CVA6, SERV, PicoRV32, and CVW/Wally
- core/peripheral clock: `25 MHz`
- RAM: SRAM at `0x80000000`
- UART: APB UART at `0x10000000`, `115200` baud
- CLINT machine timer: `0x02000000`, Zephyr timer frequency `12.5 MHz`
- debug: external JTAG through `riscv-dbg` (`dmi_jtag` + `dm_top`)
- Zephyr: `initial_supported` for the currently validated Zephyr-capable
  core/board pairs

This is now the reference point for adding more cores, boards, and cleaner
user-facing selection/configuration.

The descriptor-derived support matrix is generated in
[`docs/support_matrix.md`](docs/support_matrix.md). Regenerate it after changing
core or board descriptors:

```bash
make support-matrix
```

`initial_supported` Zephyr status means the out-of-tree Zephyr board target
builds, the ELF or binary loads through the accepted FPGA software loading flow
for that core, and UART prints the Zephyr/CoreJack timer-smoke output. Debug
capable cores use OpenOCD/GDB. SERV and PicoRV32 use the UART SRAM loader because
OpenOCD/GDB debug is unsupported for those cores. This does not yet claim a
complete RTOS platform; runner integration and broader regression coverage
remain explicit follow-up work.

Additional core support is being staged incrementally:

- CV32E40P now runs `hello_world` through the generic platform path in both
  simulation and on FPGA hardware. OpenOCD/GDB can load and run firmware
  through the debug/SBA path, and interactive halt/breakpoint/step debug has
  been validated.
- CV32E40X is currently demoted from the supported core set. It has shown
  instruction-fetch/vector behavior that differs from the other validated cores
  and is tracked upstream. Keep it out of default regressions until the upstream
  behavior is clarified or fixed.
- CV32E40S now runs `hello_world` through the generic platform path in
  simulation and on FPGA hardware. OpenOCD/GDB can examine the hart, load
  firmware through SBA, run through the normal reset/halt/load path, and
  single-step code.
- CVA6 runs `hello_world` through the AXI platform path in simulation and on
  FPGA hardware. OpenOCD/GDB can examine the hart, load firmware, run
  through the debug/SBA path, produce UART output, and single-step through the
  reset path.
- SERV runs bare-metal `hello_world` in simulation through a local socket
  adapter and on FPGA hardware through the optional UART SRAM loader. Zephyr
  also runs through the UART SRAM loader and uses the shared CoreJack CLINT
  timer path. OpenOCD/GDB debug support remains unsupported because SERV does
  not expose the same external debug contract as the debug-capable cores.
- PicoRV32 runs bare-metal `hello_world` in simulation through a local socket
  adapter around the core's native single memory interface and on FPGA hardware
  through the optional UART SRAM loader. OpenOCD/GDB debug support remains
  unsupported.
  Zephyr runtime support is unsupported because upstream PicoRV32 uses a
  custom IRQ model and does not provide the standard privileged CSR/trap model
  used by Zephyr's normal RISC-V port.
- CVW/Wally runs bare-metal `hello_world` in simulation through a local
  AHB-Lite adapter into the CoreJack memory/peripheral path and on FPGA
  hardware through the optional UART SRAM loader. External OpenOCD/GDB debug is
  not currently supported.

## Scope of this bootstrap

- Keep integration logic in human-authored SystemVerilog modules.
- Use a lightweight Python generator for top-level glue and generated address-map artifacts.
- Start with stable contracts: core/accelerator socket interfaces and shared platform enums.

## Repository layout

- `rtl/pkg/platform_pkg.sv` - shared enums and base types.
- `rtl/interfaces/` - core and accelerator socket interface contracts.
- `rtl/pkg/soc_bus_pkg.sv` - centralized PULP bus typedefs (`APB`/`AXI`/`OBI`) used as default typed interfaces.
- `docs/axi4_fabric_migration.md` - intended AXI4-native fabric and 64-bit SRAM migration path.
- `docs/board_porting.md` - checklist for adding a new FPGA board.
- `docs/core_porting.md` - checklist for adding a new RISC-V core.
- `docs/tooling.md` - host tools, optional project-local tool installs, and
  environment diagnostics.
- `docs/uart_sram_loader.md` - side-path UART SRAM loader design for cores
  without a usable RISC-V debug interface.
- `docs/zephyr_bringup.md` - initial Zephyr-on-Ibex bring-up notes.
- `cfg/platform.example.yaml` - sample platform configuration.
- `bin/platform_gen.py` - YAML-to-SystemVerilog glue generator.
- `gen/` - output directory for generated artifacts (e.g. `gen/rtl/*.sv`).
- `corejack.core` - FuseSoC core/target definitions.
- `docs/core_acceptance_checklist.md` - validation checklist for promoting
  core simulation, FPGA, and debug support.

## Get started

```bash
# 1) Create/use the project virtual environment and install pinned Python deps
source sourceme.sh

# 2) (Optional, when using external HDL deps) bootstrap pinned bender and fetch deps
make bender
make deps
make flist

# 3) Generate RTL artifacts from the example config
make gen

# 4) Run the FuseSoC + Verilator smoke simulation
make smoke
```

Check the host environment for the selected core/board and flow with:

```bash
make check-tools
make check-tools FLOW=sim
make check-tools FLOW=fpga
make check-tools FLOW=debug
```

See [`docs/tooling.md`](docs/tooling.md) for repo-local tool installs,
toolchain setup, Verilator/Verible setup, and observed validation versions.

Check a board descriptor before starting FPGA bring-up with:

```bash
make board-check BOARD=axku5
```

Check a core descriptor and its local adapter/wrapper contract with:

```bash
make core-check CORE=ibex
```

Check the descriptor matrix for a board and every compatible core before
starting longer FPGA regressions with:

```bash
make target-check BOARD=axku5
```

Run the full board-level FPGA/debug acceptance sweep with:

```bash
source sourceme.sh
make deps
make smoke
make fpga-accept BOARD=axku5 UART_DEV=/dev/serial/by-id/<uart-device>
```

`make fpga-accept` derives its default core list from the selected board
descriptor's `compatible_cores` list and filters out cores whose FPGA status is
not supported. It builds isolated per-core FPGA work roots and programs the
FPGA. Debug-capable cores load and run `hello_world` through OpenOCD/GDB.
Supported cores without debug support use the UART SRAM loader, so `UART_DEV`
is required for those cores. The flow prints a final summary of work roots,
bitstreams, UART logs, and pass/fail results.

## Dependency management

CoreJack uses Bender for external RTL/IP checkout and pinning, and FuseSoC for
top-level simulation/FPGA build orchestration.

Typical flow:

```bash
make bender
make deps
make flist
```

See [`docs/dependency_management.md`](docs/dependency_management.md) for the
dependency classes, optional core checkout model, and current CVA6 pinning
exception.

## System Bus Policy

The central CoreJack SoC fabric is AXI. Core-native buses are allowed at the
core adapter boundary, but they should be converted into the shared AXI fabric
before reaching RAM, UART, CLINT, debug-module windows, or other shared
peripherals.

Current core-side contracts:

- Ibex, CV32E40P, CV32E40S, and CV32E40X use split OBI-style instruction/data
  sockets that are buffered and converted to AXI.
- CVA6 uses a native AXI path.
- SERV and PicoRV32 use small core-specific adapters and then enter the same
  CoreJack memory/peripheral path.
- CVW/Wally uses a local AHB-Lite adapter into the CoreJack memory/peripheral
  path for simulation and the UART SRAM loader FPGA path.

Current FPGA bring-up direction:

- first reference target: `corejack_ibex` + `riscv-dbg` + `apb_uart`
- `soc_top` should contain the real SoC hardware, including the core, memory subsystem, debug, UART, and other SoC-visible blocks
- FPGA wrappers should stay separate from the generic SoC/platform RTL and only provide board/fabric adaptation such as clock/reset generation, FPGA primitives, and board pin wiring
- see [`docs/fpga_ibex_plan.md`](docs/fpga_ibex_plan.md) for the validated
  baseline and the next core/board expansion plan
- see [`docs/fpga_debug_stepping.md`](docs/fpga_debug_stepping.md) for
  interactive OpenOCD/GDB loading, breakpoints, and stepping on FPGA
- see [`docs/fpga_hardware_smoke.md`](docs/fpga_hardware_smoke.md) for the
  repeatable FPGA hardware smoke checklist
- see [`docs/core_board_descriptors.md`](docs/core_board_descriptors.md) for
  the descriptor-driven core/board selection direction

Generated files:

- `gen/rtl/addr_map_pkg.sv`
- `gen/rtl/soc_top_gen.sv`

Hand-authored starter integration:

- `rtl/top/soc_top.sv` - minimal top using typed/parametrizable APB/AXI/OBI request/response structs.
- `tb/smoke_dut.sv` - test harness wrapper for cocotb signal driving.
- `tb/test_smoke.py` - cocotb smoke test module used by FuseSoC (`cocotb_module` target flow).

FuseSoC + cocotb + Verilator smoke run:

```bash
make smoke
```

Generic software simulation run:

```bash
make sim-run-sw SW_APP=hello_world
```

Example self-check run:

```bash
make sim-run-sw SW_APP=self_check
```

Example deterministic benchmark-smoke run:

```bash
make sim-run-sw SW_APP=bench_smoke
```

Alternative pass/fail control:

- use `SIM_TIMEOUT_CYCLES=<n>` to relax or tighten the cycle budget

This uses:

- one generic HDL harness: `tb/soc_dut.sv`
- one generic cocotb runner: `tb/test_soc_sw.py`
- runtime-selected software images via `SW_APP`
- a generic software-visible sim-control MMIO register for PASS/FAIL reporting

## FPGA bring-up

The FPGA flow is descriptor-driven through `CORE=<core>` and `BOARD=<board>`.
The first validated board target is `axku5`.

Example validated target:

- core: `ibex`
- debug: `riscv-dbg` over external JTAG (`dmi_jtag` + `dm_top`)
- console: `apb_uart`
- board: `axku5`
- clock: `25 MHz`
- UART baud: `115200`

Architectural intent:

- `soc_top` is the hardware top of the system and should remain board-agnostic
- all real SoC hardware belongs in `soc_top`
- FPGA wrapper modules should only adapt `soc_top` to a concrete board by handling FPGA-specific clocking, reset release, vendor primitives, and physical IO pin mapping

Generate the FPGA file list:

```bash
make fpga-flist
```

Build the selected board bitstream with Vivado:

```bash
make fpga-bit
```

Planned FPGA targets are blocked by default. To intentionally try a target that
is recorded as planned but not yet validated, pass `ALLOW_PLANNED=1`:

```bash
make fpga-bit CORE=<planned-core> BOARD=<board> ALLOW_PLANNED=1
```

The default FPGA build selects `CORE=ibex` and `BOARD=axku5`, deriving the
board wrapper name `corejack_axku5_wrap`. Core selection is passed below the
board wrapper through the generic SoC/core-region parameter path; the numeric
`CORE_TYPE` descriptor value is forwarded as Vivado's `CoreType` top-level
parameter. The default bitstream path uses FuseSoC's Vivado flow and writes its
generated build tree under `build/fpga/<board>/<core>/fusesoc-fpga/`, for
example `build/fpga/axku5/ibex/fusesoc-fpga/`.

Generate the FuseSoC/Vivado build tree without running synthesis:

```bash
make fpga-setup
```

Program the generated bitstream through the FuseSoC-generated Vivado Makefile:

```bash
make fpga-pgm
```

Software for FPGA bring-up now follows a shared CMake-based bare-metal layout:

- CMake project under `sw/c/`
- shared linker script in `sw/common/link.ld`
- shared startup code in `sw/c/common/crt0.S`
- app-specific directories such as `sw/c/hello_world/`
- test-style apps such as `sw/c/self_check/`

List available apps with:

```bash
make list-apps
```

List available descriptor-backed core/board targets:

```bash
make list-targets
```

Build a bare-metal firmware image with:

```bash
make sw-build SW_APP=hello_world TARGET=fpga
```

This generates:

- `sw/build/fpga/<core>/<toolchain>/hello_world/cmake/hello_world/hello_world`
- `sw/build/fpga/<core>/<toolchain>/hello_world/hello_world.bin`
- `sw/build/fpga/<core>/<toolchain>/hello_world/hello_world.dis`
- `sw/build/fpga/<core>/<toolchain>/hello_world/bank_0.hex` ... `bank_3.hex`

Use `TARGET=sim` for simulation firmware images. The build keeps FPGA and
simulation outputs separate under `sw/build/fpga/<core>/...` and
`sw/build/sim/<core>/...`; the concrete output path also includes the selected
toolchain name.
For simulation, `SIM_CTRL_ENABLE` is set so `sim_ctrl_pass()` and
`sim_ctrl_fail()` write the testbench-visible pass/fail register. For FPGA, the
same helpers compile to no-ops.

The `bank_N.hex` files are generated for the current full-interleaving memory layout:

- one 64-bit word per hex line by default
- bank select = `word64_index % NumBanks`

The example is linked for the current FPGA bring-up map:

- boot address: `0x80000000`
- UART base: `0x10000000`
- UART clock assumption: `25 MHz`
- UART baud: `115200`

For simulation, the banked memory subsystem can preload those files by either:

- passing `+MEM_PATH=/abs/path/to/sw/build/<target>/<core>/<app>`
- or setting the `soc_top`/`soc_mem_ss` `MemInitPath` parameter

The generic `make sim-run-sw` target automatically:

- rebuilds the selected app
- passes `+MEM_PATH=<sw/build/sim/<core>/<toolchain>/<app>>`
- monitors real UART traffic and `sim_ctrl` writes from the TB harness
- treats software PASS/FAIL writes to `sim_ctrl` as the completion signal

For reusable software tests, use the common sim-control helpers in:

- `sw/c/common/sim_ctrl.h`
- `sw/c/common/sim_ctrl.c`

The intended pattern for generic C tests is:

- print debug text with `printf()` if useful
- call `sim_ctrl_pass()` on success
- call `sim_ctrl_fail(<code>)` on failure

The simulation-specific observation lives in the testbench, not in `soc_top`:

- `soc_top` contains only hardware-facing UART/debug/memory integration
- `tb/uart_apb_tx_monitor.sv` observes APB writes to the UART transmit register
- `tb/sim_ctrl_monitor.sv` watches the final `sim_ctrl` PASS/FAIL store
- `tb/test_soc_sw.py` line-buffers UART text and handles the final status

Waveform dumping is opt-in for Verilator simulation targets. Standard
`make sim-run-sw` runs build with `VM_TRACE=0`, so normal regressions avoid the
compile/runtime overhead of tracing. To dump an FST waveform:

```bash
make sim-run-sw CORE=ibex SW_APP=hello_world SIM_WAVES=1
```

By default this writes to:

```text
build/waves/<fusesoc-target>-<core>-<app>.fst
```

The trace file can be overridden:

```bash
make sim-run-sw CORE=ibex SW_APP=hello_world SIM_WAVES=1 \
  SIM_WAVE_FILE=/tmp/ibex_hello.fst
```

VCD is also available for short compatibility traces:

```bash
make smoke SIM_WAVES=1 SIM_WAVE_FORMAT=vcd
```

FST is recommended for full-SoC traces because it is much smaller than VCD and
is supported by GTKWave. The same `SIM_WAVES=1` knob is available for
`smoke`, `debug-sim`, and `axi-adapter-sim`.

For FPGA hardware runs, start OpenOCD in one terminal:

```bash
make openocd
```

Monitor the board UART in another terminal. The exact device name depends on
USB enumeration; on the currently validated setup the CP2102N UART bridge
enumerated as `/dev/ttyUSB1`:

```bash
picocom -b 115200 /dev/ttyUSB1
```

Then load or run the selected software ELF into FPGA RAM over GDB/OpenOCD:

```bash
make fpga-load-sw SW_APP=hello_world
make fpga-run-sw SW_APP=hello_world GDB_TIMEOUT=10
```

The durable workflow notes for this repository are captured in
[`docs/fpga_sw_flow.md`](docs/fpga_sw_flow.md) and
[`rtl/platform/fpga/scripts/README.md`](rtl/platform/fpga/scripts/README.md).

The helper scripts set the PC to the ELF `_entry_point` symbol, currently
`0x80000080` for the RAM-resident vector table.

The known-good `hello_world` hardware smoke prints:

```text
=== CoreJack SoC Demo ===
Target: fpga
Core: ibex
Board: axku5
UART base: 0x10000000
Clock: 25000000 Hz, baud: 115200
UART and JTAG debug path are alive.
```

## Roadmap

Current validated baseline:

- generic `soc_top` smoke simulation passes
- generic cocotb software simulation passes with compiled C tests
- Ibex, banked SRAM, UART, and `riscv-dbg` are integrated in `soc_top`
- the currently validated FPGA board build closes timing at the `25 MHz`
  default
- OpenOCD can enumerate and examine the RISC-V target over external JTAG
- GDB can load an ELF into SRAM through the debug module SBA path
- `hello_world` runs on hardware and prints through the platform APB UART at
  `115200`

Near-term priorities:

- keep one known-good core/board target as the stable regression baseline
- keep the debug ROM fetch and SBA simulation checks in the regression baseline
- keep board LED mappings as simple status, and add richer probes only
  when a specific debug investigation needs them
- keep `25 MHz` as the conservative FPGA default while treating higher clocks as a later timing-closure task
- keep the generic cocotb software test flow as the main pre-silicon validation path for bare-metal C tests
- keep Zephyr timer-smoke coverage as the initial software stack regression for
  supported core/board pairs
- keep CVW/Wally in the supported FPGA smoke set through the UART SRAM loader
  while treating external OpenOCD/GDB debug as unsupported
- keep SERV as a low-area firmware execution target through the UART SRAM
  loader, not as a requirement for OpenOCD/GDB stepping parity
- keep PicoRV32 on the same UART SRAM loader FPGA path used by non-debug
  low-area cores

Platform architecture follow-up:

- evolve the current local SoC fabric toward a more generic interconnect architecture
- evaluate AXI, TileLink, or other fabric choices for the long-term SoC integration boundary
- keep the memory subsystem modular and multi-initiator aware while making the top-level fabric choice orthogonal to board and core selection
- introduce explicit core and board descriptors so new combinations do not
  require hand-editing scattered build logic

Core and board expansion:

- add support for multiple selectable cores, starting from Ibex, CV32E40P,
  CV32E40S, CVA6, SERV, and PicoRV32, while keeping CV32E40X outside the default
  supported regression set
- add support for multiple FPGA boards while keeping board-specific logic isolated to thin wrapper layers
- make it easy to add custom boards through a predictable wrapper,
  constraints, clock/reset, UART/JTAG, and programming-script structure
- continue converging the user-facing flow around simple `CORE=<core>` and
  `BOARD=<board>` selection backed by explicit descriptors

Software ecosystem follow-up:

- continue improving the generic bare-metal software flow
- expand Zephyr beyond the current `initial_supported` timer-smoke level for
  the supported core/board pairs
- define the missing RTOS-facing platform pieces explicitly before promoting
  Zephyr beyond initial bring-up, especially runner behavior and broader
  regression coverage

See [`docs/fpga_ibex_plan.md`](docs/fpga_ibex_plan.md) for the more detailed implementation plan.

## CI

GitHub Actions workflow `.github/workflows/smoke.yml` runs the smoke test on every push to `main` (including merges).

## License

CoreJack-original code is licensed under the Apache License, Version 2.0; see
[`LICENSE`](LICENSE). Third-party code and hardware IP remain under their
original licenses; see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
