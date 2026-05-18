# Core Porting Guide

This document describes the minimum pieces needed to add a new RISC-V core to
CoreJack. A core port should keep core-specific protocol, reset, debug, and ISA
adaptation in the core adapter. Board wrappers should remain board-specific and
should not encode a fixed core choice.

## Files

Add a core descriptor:

```text
cfg/cores/<core>.yaml
```

Add a core adapter:

```text
rtl/cores/corejack_<core>_socket_adapter.sv
```

If the core has native AXI ports, the adapter name can reflect that contract,
for example:

```text
rtl/cores/corejack_<core>_axi_adapter.sv
```

If the core exposes another native bus, keep that contract explicit in the
descriptor and adapter name. For example, an AHB-Lite core should start with an
AHB adapter and remain `planned` until the adapter translates into the CoreJack
fabric and passes the normal simulation or FPGA acceptance criteria.

Add external dependencies through the project dependency flow. Prefer Bender for
fetching and pinning external RTL repositories. Use project-local pinned
checkouts only when the upstream dependency flow cannot be consumed directly by
the current CoreJack build.

Add a core-local FuseSoC core at the repository root:

```text
corejack_core_<core>.core
```

That core should describe the external dependency files and any CoreJack-local
adapter/helper RTL for the core. Keep core-plugin files named
`corejack_core_<core>.core`, board-plugin files named
`corejack_board_<board>.core`, shared dependency files in
`corejack_common.core`, and the platform top-level in `corejack.core`.

## Scaffold Helper

The scaffold helper creates the descriptor, placeholder adapter, core FuseSoC
file, platform enum value, reciprocal board compatibility entry, and minimal
shared `corejack.core` core-selection hooks:

```bash
make new-core CORE=mycore
```

Optionally set ISA fields:

```bash
make new-core CORE=mycore CORE_XLEN=64 CORE_MARCH=rv64imc CORE_MABI=lp64
```

The generated core starts with `integration.sim`, `integration.fpga`, and
`integration.debug` set to `planned`. The adapter is intentionally a placeholder
and is not wired into `corejack_core_region`; replace it with a real protocol
adapter before trying to promote simulation or FPGA support.

## Descriptor Template

Use this as the starting point for `cfg/cores/<core>.yaml`:

```yaml
name: mycore
display_name: My Core

integration:
  sim: planned
  fpga: planned
  debug: planned

dependency:
  manager: bender_vendor_package
  package: mycore
  path: deps/mycore
  upstream: https://example.com/mycore.git
  rev: <commit>

adapter:
  module: corejack_mycore_socket_adapter
  file: rtl/cores/corejack_mycore_socket_adapter.sv

platform:
  core_type: 5
  integration: socket_region

wrapper:
  module: corejack_mycore_wrapper

fusesoc:
  sim_target: sw-sim
  core_flag: core_mycore

isa:
  xlen: 32
  march: rv32imc
  mabi: ilp32

reset:
  boot_addr: 0x80000000
  mtvec_addr: 0x80000000

debug:
  supported: false

buses:
  instruction: obi
  data: obi

clocking:
  validated_min_hz: 0
  validated_max_hz: 0

software:
  default_target: sim
  toolchain: riscv-multilib

compatible_boards:
  - axku5
```

Also add a unique enum value to `rtl/pkg/platform_pkg.sv`:

```systemverilog
CORE_MYCORE = 5
```

The descriptor `platform.core_type` value must match this enum value.

Set `platform.integration` to the platform path used by the core:

- `socket_region`: the core is selected inside `corejack_core_region` and uses
  that module's split instruction/data socket boundary.
- `native_axi`: the core has a native AXI path into `soc_top` and does not use
  `corejack_core_region`.

The Makefile derives FuseSoC selection flags from this field. For example,
`socket_region` cores get both their core-specific flag and the shared
`core_region` flag.

## Adapter Checklist

The adapter should translate the concrete core into the CoreJack core boundary:

- reset and boot address handling
- instruction bus adaptation
- data bus adaptation
- interrupt tie-offs or wiring
- debug request, halt, resume, and exception address handling when supported
- any required core-local FPGA helper cells
- core-specific parameterization

The adapter should not contain board pin, clock input, UART pin, or programming
logic. Those belong in board wrappers and board descriptors.

## ISA And Software Checklist

The descriptor must provide:

- `isa.xlen`
- `isa.march`
- `isa.mabi`
- `software.toolchain`
- reset and trap-vector addresses

The `march`/`mabi` pair must match the core. For example, RV32 cores should use
an `rv32...` `march` and an `ilp32...` ABI. RV64 cores should use an `rv64...`
`march` and an `lp64...` ABI.

## Debug Checklist

If `integration.debug: supported`, the descriptor must provide:

- `debug.supported: true`
- `debug.hart_count`
- `debug.hartsel`
- `debug.halt_addr`
- `debug.exception_addr`

Do not mark debug support as `supported` until OpenOCD can examine the hart,
GDB can load software, UART output is observed for the smoke app, and direct
single-step behavior has been checked.

## Validation

Check the descriptor and referenced local files:

```bash
make core-check CORE=<core>
```

Check the board/core descriptor matrix:

```bash
make target-check BOARD=axku5
```

The checker validates:

- required descriptor fields
- integration status values
- adapter file and module name
- unique `platform.core_type`
- matching `platform_pkg::core_type_e` enum value
- platform integration style
- ISA and ABI sanity
- reset address alignment
- bus contract names
- software toolchain name
- debug fields when debug support is marked supported
- compatible board names and reciprocal board compatibility

After `core-check` passes, start with simulation:

```bash
make sim-run-sw CORE=<core> SW_APP=hello_world
```

Then move to FPGA hardware:

```bash
make fpga-bit CORE=<core> BOARD=axku5
make fpga-pgm CORE=<core> BOARD=axku5
make fpga-debug-accept CORE=<core> BOARD=axku5 UART_DEV=/dev/serial/by-id/<uart-device>
```

Promote `integration.sim`, `integration.fpga`, or `integration.debug` only
after the relevant acceptance criteria have passed.
