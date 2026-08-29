# Core Acceptance Checklist

This checklist defines when a RISC-V core integration may be marked
`supported` in `cfg/cores/<core>.yaml`.

Use the descriptor fields independently:

- `integration.sim`: software simulation support
- `integration.fpga`: FPGA hardware support for at least one board
- `integration.debug`: OpenOCD/GDB debug support on FPGA
- `software.zephyr.status`: Zephyr software-platform support

A core can be `supported` for simulation while FPGA or debug support remains
`planned` or `unsupported`.

## Descriptor Gate

Before running tests, the core descriptor must be complete enough for the
generic flow:

- `name` matches the selected `CORE=<core>` value.
- `integration` records `sim`, `fpga`, and `debug` status explicitly.
- `platform.core_type` matches `rtl/pkg/platform_pkg.sv`.
- `isa.march` and `isa.mabi` match the software compiler target.
- `reset.boot_addr` matches the core reset-entry behavior.
- `debug` records the halt and exception addresses when debug is supported.
- `buses` records the core-facing instruction and data bus protocols.
- `fusesoc.sim_target` and `fusesoc.core_flag` name the shared FuseSoC
  simulation target and the core-selection flag used by `make sim-run-sw`.
  Board descriptors provide the corresponding `fusesoc.board_flag` for FPGA
  wrapper and constraints selection.
- `software.toolchain` selects a known toolchain flow.
- `software.zephyr.status` records whether Zephyr is unsupported, planned,
  initially supported, or fully supported.
- `compatible_boards` lists every board where FPGA support is claimed.

The descriptor must validate:

```bash
make validate-target CORE=<core> BOARD=<board>
make target-config CORE=<core> BOARD=<board>
```

## Simulation Support

Mark `integration.sim: supported` only after all of the following pass:

```bash
make check-tools FLOW=sim CORE=<core> BOARD=<board>
make fpga-flist CORE=<core> BOARD=<board>
make sim-run-sw CORE=<core> SW_APP=hello_world SIM_TIMEOUT_CYCLES=1000000
```

Also run any core-specific simulation smoke tests required by the adapter.
Low-throughput cores may require a larger timeout; for example, SERV is
bit-serial and currently uses a larger cycle budget for `hello_world`.

Expected result:

- The selected core elaborates through the generic CoreJack core region.
- The firmware image is built using the descriptor-selected ISA and ABI.
- UART output identifies `Target: sim` and the selected core.
- The software test reaches `sim_ctrl_pass()`.
- No descriptor-specific build artifacts overwrite another core's outputs.

## AXI Fabric Compatibility

Every supported core must be compatible with the central AXI fabric described in
[`docs/axi4_fabric.md`](axi4_fabric.md). For the current RV32 cores this means
the core adapter keeps the core-facing instruction/data protocol local and lets
`soc_top` route shared RAM, UART, and debug traffic through the common AXI path.

Before promoting a core beyond experimental status, run:

```bash
make axi-smoke
```

Expected result:

- The static AXI address-map check passes.
- `axi-adapter-sim` passes, including protocol-checker coverage and directed
  32-bit core to 64-bit memory lane tests.
- `debug-sim` passes.
- `hello_world` simulation passes for the supported RV32 core set.

If a core requires an AXI-native initiator, burst support, wider data paths, or
more outstanding transactions than the current adapters provide, record that as
a fabric enhancement instead of hiding the requirement in a board wrapper.
CVA6 exercises this AXI-native path rather than the RV32 split
instruction/data OBI socket. Its simulation completion is observed through the
AXI `sim_ctrl` monitor because core data writes no longer pass through the RV32
OBI data monitor.

## FPGA Support

Mark `integration.fpga: supported` only after all of the following pass on a
real board listed in `compatible_boards`:

```bash
make check-tools FLOW=fpga CORE=<core> BOARD=<board>
make fpga-bit CORE=<core> BOARD=<board>
make fpga-warning-check CORE=<core> BOARD=<board>
make fpga-pgm CORE=<core> BOARD=<board>
make fpga-run-sw CORE=<core> BOARD=<board> SW_APP=hello_world GDB_TIMEOUT=10
```

For cores without a supported RISC-V debug interface, the software load/run
step may use the UART SRAM loader instead:

```bash
make fpga-bit CORE=<core> BOARD=<board> UART_LOADER=1
make fpga-pgm CORE=<core> BOARD=<board>
make fpga-uart-load-sw CORE=<core> BOARD=<board> SW_APP=hello_world \
  UART_DEV=/dev/serial/by-id/<uart-device>
```

Expected result:

- The bitstream builds without requiring `ALLOW_PLANNED=1`.
- Vivado synthesis and implementation logs contain no unreviewed warning IDs.
- The FPGA programs successfully.
- For debug-capable cores, OpenOCD can connect well enough for `fpga-run-sw`
  to load the ELF through the debug module SBA path.
- For non-debug cores, the UART SRAM loader writes the firmware image into SRAM
  and releases the core.
- UART prints the expected `hello_world` banner for the selected target, core,
  board, clock, and baud.

`make fpga-bit` runs `fpga-warning-check` automatically after report
generation. The explicit target is useful when reviewing an existing Vivado
build directory. Warning IDs are reviewed in `cfg/vivado_warning_allowlist.txt`;
new IDs must be investigated before being added.

Record the validated clock range in the descriptor:

```yaml
clocking:
  validated_min_hz: <hz>
  validated_max_hz: <hz>
```

For an initial single-frequency bring-up, `validated_min_hz` and
`validated_max_hz` may be the same value.

The hardware portion can be run with the acceptance helper:

```bash
bin/fpga_debug_acceptance.sh --cores "<core>" --board <board> --uart /dev/ttyUSBx
```

Multiple cores can be checked in one run. The cleanest way is the
descriptor-driven Make wrapper, which derives the core list from the
selected board descriptor and filters out unsupported FPGA targets:

```bash
make fpga-accept BOARD=axku5 UART_DEV=/dev/ttyUSBx
```

Equivalent direct invocation, passing an explicit core list:

```bash
bin/fpga_debug_acceptance.sh --cores "<space-separated core list>" --board axku5 --uart /dev/ttyUSBx
```

The helper chooses OpenOCD/GDB for debug-capable cores and the UART SRAM
loader for cores whose descriptor marks debug as unsupported.

The Make wrapper forwards the same UART capture setting:

```bash
make fpga-debug-accept CORE=cv32e40p BOARD=axku5 UART_DEV=/dev/ttyUSBx
```

For a faster rerun after a bitstream is already built or programmed, use the
script's `--skip-bit` and `--skip-pgm` options. If programming is still enabled,
`--skip-bit` requires the existing bitstream manifest to match the requested
core and board; otherwise the script stops before programming stale hardware.

## Debug Support

Mark `integration.debug: supported` only after the FPGA support gate has passed
and OpenOCD/GDB interactive debug has been checked.

Start OpenOCD:

```bash
make openocd CORE=<core> BOARD=<board>
```

OpenOCD must report:

- JTAG TAP found
- RISC-V target examined successfully
- XLEN and ISA information reported
- GDB server listening on port `3333`

In another terminal, run a GDB smoke equivalent to:

```bash
make sw-build CORE=<core> BOARD=<board> SW_APP=hello_world TARGET=fpga
riscv64-unknown-elf-gdb \
  sw/build/fpga/<core>/riscv-multilib/hello_world/cmake/hello_world/hello_world \
  -batch \
  -ex "target extended-remote localhost:3333" \
  -ex "monitor reset halt" \
  -ex "info registers pc" \
  -ex "load" \
  -ex "set \$pc = (unsigned int)&_entry_point" \
  -ex "hbreak main" \
  -ex "continue" \
  -ex "info registers pc" \
  -ex "stepi" \
  -ex "info registers pc" \
  -ex "delete breakpoints" \
  -ex "detach"
```

Expected result:

- GDB reads registers successfully.
- `load` writes the ELF to SRAM.
- A hardware breakpoint at `main` is accepted.
- `continue` stops at `main`.
- `stepi` advances the program counter into valid code.
- OpenOCD does not report halt, register-read, SBA, or undefined-debug-reason
  failures.

## Core-Specific Debug Notes

CV32E40X is currently excluded from the supported core set. Earlier bring-up
required a core-local instruction-fetch address adaptation, and later
Zephyr/timer testing exposed additional vector/interrupt behavior that does not
match the other supported cores. Keep it out of default regressions until the
upstream behavior is clarified or fixed.

CV32E40S reports a reset-status debug state through `debug_havereset_o`. The
adapter must pass this state into `dm_top.unavailable_i`; otherwise OpenOCD can
observe the hart as available before the core has completed its reset-status
transition. The acceptance test must include normal `monitor reset halt`,
`load`, breakpoint, continue, and `stepi` behavior.

CVA6 is integrated through the AXI-native core path and uses a 64-bit software
ABI. Its debug entry addresses are configured through the local CVA6 CoreJack
configuration package and must remain aligned with the shared `riscv-dbg` debug
ROM map. The acceptance test must include OpenOCD target examination as
`XLEN=64`, SRAM loading through SBA, UART output, and at least a reset-path
`stepi` smoke.

## Promotion Rule

Promote only the capabilities that have passed:

- If simulation passes but FPGA has not been run, mark `sim: supported` and
  keep `fpga: planned`.
- If FPGA UART/software execution passes but interactive stepping has not been
  run, mark `fpga: supported` and keep `debug: planned`.
- If OpenOCD/GDB stepping passes, mark `debug: supported`.
- Use `unsupported` only when the current integration model is not expected to
  provide that capability.

## Zephyr Support

Mark `software.zephyr.status: initial_supported` only after all of the following
pass for the selected core and board:

```bash
make zephyr-build CORE=<core> BOARD=<board>
```

Then load the resulting image through the accepted FPGA software loading flow
for that core and capture UART output. Debug-capable cores use OpenOCD/GDB to
load `zephyr.elf`. Non-debug cores may use an accepted replacement flow such as
the UART SRAM loader.

Expected result:

- The Zephyr board target builds with the descriptor-selected ISA and ABI.
- The ELF has separate executable and writable LOAD segments.
- The FPGA software loading flow loads the image into SRAM and starts at the
  expected entry address.
- UART output includes the Zephyr boot banner and CoreJack Zephyr demo message.
- UART output includes the timer-smoke confirmation after a Zephyr sleep.

`initial_supported` means minimal console-smoke support. Do not use
`software.zephyr.status: supported` until the RTOS-facing platform services are
validated, including at least FPGA timer behavior across supported cores,
runner integration or an accepted replacement flow, and regression coverage.

After promotion, rerun:

```bash
make validate-target CORE=<core> BOARD=<board>
make list-targets
make support-matrix
```

## Documentation Updates

When a core is promoted, update the relevant standalone documentation:

- `docs/support_matrix.md` by running `make support-matrix` (this is the
  authoritative per-core/board status table; the top-level README and
  `docs/roadmap.md` link to it rather than duplicating it).
- `docs/roadmap.md` if the per-core note needs to change.
- `docs/core_board_descriptors.md` if descriptor semantics changed.
- `docs/fpga_hardware_smoke.md` if board-level hardware expectations changed.
- `docs/fpga_debug_stepping.md` if debug procedure or commands changed.

Detailed investigation notes should stay in ignored local logs, not in
version-controlled documentation.
