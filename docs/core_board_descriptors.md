# Core And Board Descriptors

CoreJack should scale toward explicit core and board descriptors so that adding
a new RISC-V core or FPGA board does not require hand-editing scattered Makefile,
FuseSoC, and RTL integration logic.

The user-facing flow should remain simple:

```bash
make fpga-bit CORE=<core> BOARD=<board>
make fpga-pgm CORE=<core> BOARD=<board>
make fpga-run-sw SW_APP=<app> CORE=<core> BOARD=<board>
```

Descriptors should provide the metadata needed to derive wrapper names, source
sets, constraints, debug setup, software defaults, and validation expectations.
The current descriptor-derived settings can be inspected with:

```bash
make target-config CORE=ibex BOARD=axku5
```

Available cores, boards, and valid resolved combinations can be listed with:

```bash
make list-targets
```

Board descriptor structure and referenced local files can be checked with:

```bash
make board-check BOARD=axku5
```

Core descriptor structure and referenced local files can be checked with:

```bash
make core-check CORE=ibex
```

The full descriptor matrix for a board can be checked with:

```bash
make target-check BOARD=axku5
```

## Goals

- Keep core selection independent from board selection.
- Keep board wrappers thin and board-specific.
- Keep core adapters responsible for translating each core into the CoreJack
  SoC contract.
- Make new core/board bring-up reviewable through small descriptor files.
- Avoid duplicating target-specific logic across Make, FuseSoC, scripts, and
  documentation.

## Non-Goals

- Descriptors should not hide real RTL integration work.
- Descriptors should not replace core adapters or board wrappers.
- Descriptors should not describe third-party dependency internals in detail;
  dependency resolution should remain delegated to the package/dependency flow.

## Core Descriptor

A core descriptor should live at:

```text
cfg/cores/<core>.yaml
```

The current reference descriptor is
[`cfg/cores/ibex.yaml`](../cfg/cores/ibex.yaml).

Suggested fields:

```yaml
name: ibex
display_name: Ibex

integration:
  sim: supported
  fpga: supported
  debug: supported

adapter:
  module: corejack_ibex_socket_adapter
  file: rtl/cores/corejack_ibex_socket_adapter.sv

platform:
  core_type: 0
  integration: socket_region

wrapper:
  module: corejack_ibex_wrapper

fusesoc:
  sim_target: sw-sim
  core_flag: core_ibex

isa:
  xlen: 32
  march: rv32imcb
  mabi: ilp32

reset:
  boot_addr: 0x80000000
  mtvec_addr: 0x80000000

debug:
  supported: true
  hart_count: 1
  hartsel: 0
  halt_addr: 0x00000800
  exception_addr: 0x00000810

buses:
  instruction: obi
  data: obi

clocking:
  validated_min_hz: 25000000
  validated_max_hz: 25000000

software:
  default_target: fpga
  toolchain: riscv-multilib
  zephyr:
    status: initial_supported
```

The descriptor should capture contract-level information. It should not become
a substitute for the adapter RTL.

`fusesoc.sim_target` is the simulation target consumed by the Makefile through
`bin/validate_target.py --make`. Current cores use the shared `sw-sim` target.
`fusesoc.core_flag` is the FuseSoC flag that selects the core-specific RTL and
tool options inside that target. Keep these fields in the descriptor rather
than adding per-core target-selection logic to the Makefile.

`platform.core_type` is the numeric `platform_pkg::core_type_e` value used when
passing core selection into parameterized top-level RTL. Keep it aligned with
`rtl/pkg/platform_pkg.sv`.

`platform.integration` records how the core enters the generic platform. Current
values are:

- `socket_region`: the core is instantiated through `corejack_core_region`.
  The descriptor tooling derives the extra FuseSoC flag `core_region` for these
  cores.
- `native_axi`: the core connects through a native AXI integration path, as
  CVA6 does. These cores do not use `corejack_core_region`.

`software.toolchain` selects a named software toolchain flow. The only
currently supported value is `riscv-multilib`, which resolves to the
repo-local `TOOLS_DIR/riscv` install and uses the `riscv64-unknown-elf-*`
executable prefix (with RV32/RV64 multilib support).

LLVM/Clang support can be added later as another named toolchain, but core
descriptors should stay on the GCC/Newlib-based default until LLVM has matching
compile, simulation, ELF loading, and debug validation for the relevant core.

`software.zephyr.status` records Zephyr platform support separately from the
hardware integration gates. The currently used values are:

- `initial_supported`: the core has a Zephyr board target, the sample app
  builds, and the accepted FPGA software loading flow can load it and observe
  UART timer-smoke output. Debug-capable cores use OpenOCD/GDB; non-debug cores
  may use an accepted replacement flow such as the UART SRAM loader. Current
  targets also describe the shared CLINT machine timer in devicetree. This is
  still an initial platform level, not a complete RTOS platform.
- `supported`: reserved for a future complete Zephyr platform gate that includes
  FPGA timer acceptance, runner, and regression coverage.
- `planned`: support is intended but not validated yet.
- `unsupported`: Zephyr support is not expected with the current integration
  model.

`integration` records capability-specific support. Use separate `sim`, `fpga`,
and `debug` entries so a core can be simulation-ready before it is validated on
hardware. The currently used status values are:

- `supported`: this capability has been implemented and validated.
- `planned`: the descriptor records intent, but the capability is not validated
  yet.
- `unsupported`: the capability is not expected to work with the current core
  integration model.

FPGA-facing Make targets validate the `fpga` capability. Simulation targets can
use cores whose `sim` capability is supported even when `fpga` and `debug` are
still planned.

For intentional FPGA experiments, `ALLOW_PLANNED=1` lets FPGA-facing Make
targets proceed with a core whose `fpga` status is `planned`. This is an
explicit override for bring-up work; it should not be treated as validation.

The promotion criteria for each capability are defined in
[`core_acceptance_checklist.md`](core_acceptance_checklist.md).

Some cores do not naturally expose the split OBI-style socket used by the
current RV32 embedded-core path or the native AXI path used by CVA6. Their
descriptors should record the native bus contract explicitly and remain
`planned` for each capability until the adapter passes that capability's
acceptance flow. CVW/Wally is the current AHB-Lite example: simulation support
is promoted after its AHB-Lite adapter runs the normal `hello_world` simulation
acceptance, and FPGA support is promoted after the same software image runs on
board through the UART SRAM loader.

## Board Descriptor

A board descriptor should live at:

```text
cfg/boards/<board>.yaml
```

The current reference descriptor is
[`cfg/boards/axku5.yaml`](../cfg/boards/axku5.yaml).

Suggested fields:

```yaml
name: axku5
display_name: ALINX AXKU5

fpga:
  part: xcku5p-ffvb676-2-e
  top_template: corejack_{board}_wrap
  target: fpga
  work_root: build/fpga/{board}/{core}/fusesoc-fpga

fusesoc:
  board_flag: board_axku5

clock:
  input_hz: 200000000
  soc_hz: 25000000
  constraints_ports:
    p: sys_clk_p
    n: sys_clk_n

reset:
  polarity: active_low
  constraints_port: sys_rst_n

uart:
  baud: 115200
  tx_port: uart_tx
  rx_port: uart_rx

debug:
  transport: jtag
  # External JTAG probe for OpenOCD. The name selects
  # rtl/platform/fpga/scripts/openocd-<name>.cfg (a thin adapter wrapper
  # around the shared riscv-dbg target file). Override per invocation with
  # make ... JTAG_ADAPTER=<name>; see docs/jtag_wiring.md for adding a new
  # adapter wrapper.
  jtag_adapter: tigard

constraints:
  xdc: rtl/platform/fpga/boards/axku5/axku5.xdc

programming:
  flow: vivado
  bitstream_target: fpga-bit
  program_target: fpga-pgm

validation:
  smoke_app: hello_world
```

Board descriptors should describe physical and tool-flow facts. They should not
contain SoC policy that belongs in the generic platform integration.

The expected smoke-test UART text is deliberately *not* a board field. It is a
property of the firmware and of the software load path, identical across boards,
so it lives once in [`cfg/validation/uart_banners.yaml`](../cfg/validation/uart_banners.yaml)
and is resolved by `bin/validate_target.py --uart-banner`:

```bash
# full expected banner for a debug-capable core
bin/validate_target.py --core ibex --board axku5 --uart-banner --variant debug

# just the trailing "alive" line, as the UART SRAM loader waits for
bin/validate_target.py --core serv --board axku5 --uart-banner --variant loader --alive-only
```

`bin/fpga_debug_acceptance.sh` calls that resolver rather than carrying its own
copy, so the acceptance expectation cannot drift from the descriptor. Variants
are `sim`, `debug`, and `loader`; placeholders are `{core}`, `{board}`, and
`{target}`. Keep the file in step with `sw/c/hello_world/main.c` and
`sw/zephyr/src/main.c`, which are where the strings actually originate.

Two board fields are optional:

- `clock.constraints_ports.n` is only needed for a differential clock input.
  Omit it for a single-ended oscillator (e.g. the Arty A7-100T), and the board
  wrapper buffers the clock accordingly.
- `memory.ram_bytes` caps the shared SRAM for boards whose block RAM cannot hold
  the default 1 MiB (e.g. the Artix-7 100T at 256 KiB). When unset, the `soc_top`
  1 MiB default applies. It drives both the board wrapper's `RamWords` and the
  board-RAM-sized bare-metal linker (`sw/common/link.ld.in`).

For the practical core bring-up checklist, see
[`core_porting.md`](core_porting.md).

For the practical board bring-up checklist, see
[`board_porting.md`](board_porting.md).

## Derived Names

The current FPGA wrapper convention is:

```text
corejack_<board>_wrap
```

For example:

```text
corejack_axku5_wrap
```

Descriptors should follow this convention unless a board has a concrete reason
to use an explicit override. Core selection should be passed through the generic
SoC/core-region parameter path, not encoded in the board top-level module name.

## Validation Contract

Every new core/board combination should define or inherit:

- expected FPGA clock
- expected UART baud
- expected software smoke app
- expected OpenOCD configuration
- expected debug capability
- expected hardware smoke output

This keeps bring-up consistent and makes failures easier to localize.
Use [`core_acceptance_checklist.md`](core_acceptance_checklist.md) as the
required validation gate before changing descriptor support status to
`supported`.

## What The Descriptors Drive Today

Descriptor files currently exist for every supported core
(`cfg/cores/*.yaml`) and the `axku5` and `arty_a7_100t` boards
(`cfg/boards/*.yaml`). The
authoritative per-core/board status comes from these descriptors and is
rendered into [`support_matrix.md`](support_matrix.md) by
`make support-matrix`.

The Makefile and FuseSoC integration read the descriptors as follows:

- `CORE` and `BOARD` values are validated against descriptor names before
  any FPGA-facing target runs.
- FPGA build variables are derived from the selected descriptors:
  `FPGA_TOP`, `FPGA_TARGET`, `FPGA_WORK_ROOT`, `CORE_TYPE`,
  `FUSESOC_FLAGS`, and `OPENOCD_CFG`. `FPGA_WORK_ROOT` uses `{board}` and
  `{core}` placeholders so each board/core pair gets an independent
  FuseSoC/Vivado build tree.
- Software metadata (`MARCH`, `MABI`, `TOOLCHAIN`, `SOC_CLK_HZ`,
  `UART_BAUD`) is exposed for the bare-metal CMake build and for Zephyr,
  so toolchain selection, compiler ISA flags, and firmware-visible
  clock/UART defaults all come from the descriptors rather than from
  hand-edited Make variables.
- `make core-check CORE=<core>` validates descriptor structure, adapter
  files, core enum values, ISA/toolchain metadata, debug metadata, and
  reciprocal board compatibility before a core is promoted.
- `make board-check BOARD=<board>` validates board descriptor structure,
  wrapper files, constraints, OpenOCD configuration, programming metadata,
  and reciprocal core compatibility before a board is promoted.
- `make target-check BOARD=<board>` validates the selected board and every
  board-compatible core as one descriptor matrix before expensive
  simulation or FPGA regressions are started.

SERV is present as a low-area core descriptor with simulation and FPGA support.
Its local socket adapter validates reset, SRAM execution, simulated UART
output, and `sim_ctrl` completion. On FPGA, SERV uses the UART SRAM loader for
bare-metal and Zephyr software loading. OpenOCD/GDB debug support remains
unsupported because SERV does not expose the same external debug contract as
the debug-capable cores.

PicoRV32 is present as a low-area core descriptor with simulation and FPGA
support. Its local socket adapter bridges the core's native single memory
interface to the platform instruction/data paths. On FPGA, PicoRV32 uses the
UART SRAM loader for bare-metal software loading. OpenOCD/GDB debug support
remains unsupported unless a compatible RISC-V debug path is added later.
Zephyr support is unsupported because the current core integration does not
provide Zephyr's expected standard privileged CSR/trap model.

CVW/Wally is present as an AHB-Lite core descriptor with simulation and FPGA
support. Its local adapter bridges the core's AHB-Lite instruction/data traffic
into the platform fabric. On FPGA, CVW uses the UART SRAM loader for bare-metal
software loading. OpenOCD/GDB debug support remains unsupported.

The first implementation should prefer explicit, boring metadata over a complex
generator. The descriptor format can grow once there are multiple real cores and
boards to compare.
