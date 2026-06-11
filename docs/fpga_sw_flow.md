# FPGA And Software Flow

This repo keeps the FPGA and software flow shaped around a generic CoreJack
platform:

- board-specific logic stays under `rtl/platform/fpga/boards/<board>/`
- reusable SoC hardware stays in `rtl/top/` and below
- RISC-V core-specific adaptation stays under `rtl/cores/`
- software tests live under `sw/c/<app>/`

The first concrete target is:

- board: AXKU5
- core adapter: `corejack_ibex_socket_adapter`
- debug: `riscv-dbg` over external JTAG
- UART: APB UART at `0x10000000`
- RAM: banked SRAM at `0x80000000`
- clock: `25 MHz`
- UART baud: `115200`

For every core listed in [`support_matrix.md`](support_matrix.md) as
FPGA-supported, this baseline has been validated on hardware: OpenOCD can
examine the target (for debug-capable cores) or the UART SRAM loader can
release the hart (for non-debug cores), software loads into SRAM, and
`hello_world` prints over UART. The interactive halt, register-read, and
single-step flow has been validated for the cores marked as
OpenOCD/GDB-supported in the same table.

## Build The Bitstream

Generate the FuseSoC/Vivado build tree:

```bash
make fpga-setup
```

Build the bitstream:

```bash
make fpga-bit
```

FPGA targets whose descriptor status is `planned` are intentionally blocked
unless the command opts in:

```bash
make fpga-bit CORE=<planned-core> BOARD=<board> ALLOW_PLANNED=1
```

Use this only for experimental synthesis/bring-up. A target should be promoted
to `supported` only after FPGA programming, software loading/running, and any
claimed debug flow have been validated.

The default target is derived from:

```text
CORE=ibex
BOARD=axku5
FPGA_TOP=corejack_$(BOARD)_wrap
```

That gives the current top `corejack_axku5_wrap`. Core selection is handled
below the board wrapper by the generic `soc_top` / core-region parameter path,
so adding another FPGA-capable core should not require a second AXKU5 wrapper.
The `CORE_TYPE` value comes from the selected core descriptor and is passed to
Vivado as the `CoreType` Verilog top-level parameter.

The Vivado project and bitstream are written under:

```text
build/fpga/<board>/<core>/fusesoc-fpga/
```

For the default target this resolves to:

```text
build/fpga/axku5/ibex/fusesoc-fpga/
```

`make fpga-bit` also writes `.corejack_bitstream_manifest` in the work root.
The manifest records the selected core/board, bitstream path, bitstream
timestamp and SHA-256, git commit information, dirty-tree status, a hash of the
tracked design inputs, and the Vivado version visible during manifest creation.
This lets later acceptance runs distinguish a current bitstream from a stale or
wrong-core bitstream before programming the FPGA.

`GIT_DESCRIBE_AT_MANIFEST` in the manifest carries the output of
`git describe --always --dirty --broken`. Once the repository has a release
tag (for example `v0.1.0`), this field gives a human-readable build identity
such as `v0.1.0` for a clean tagged build or `v0.1.0-3-gabc1234-dirty` for a
post-tag work-in-progress build. It is the recommended way to identify which
build of CoreJack produced a given bitstream.

To backfill provenance for an existing bitstream without rebuilding it, run:

```bash
make fpga-manifest CORE=<core> BOARD=<board>
```

Backfilled manifests use the bitstream modification time to choose a
best-effort git commit. Fresh `make fpga-bit` manifests use the exact current
`HEAD`.

Program the bitstream through the generated Vivado Makefile:

```bash
make fpga-pgm
```

Equivalently, after `make fpga-setup` or `make fpga-bit`, you can run the
generated target directly:

```bash
make -C build/fpga/axku5/ibex/fusesoc-fpga pgm
```

## Add A Software Test

Create a directory with a `main.c`:

```text
sw/c/my_test/main.c
```

Use the common runtime helpers:

```c
#include "printf.h"
#include "sim_ctrl.h"

int main(void) {
  printf("my_test\n");
  sim_ctrl_pass();
  return 0;
}
```

The CMake project auto-discovers app directories with `main.c`.

## Build Software

```bash
make sw-build SW_APP=my_test TARGET=fpga
```

This produces, under `sw/build/fpga/<core>/<toolchain>/my_test/`:

```text
cmake/my_test/my_test
my_test.bin
my_test.dis
bank_0.hex
bank_1.hex
bank_2.hex
bank_3.hex
```

For the default `CORE=ibex` and `TOOLCHAIN=riscv-multilib` selection this
resolves to `sw/build/fpga/ibex/riscv-multilib/my_test/`. The simulation
target writes to `sw/build/sim/<core>/<toolchain>/<app>/` instead.

The `bank_N.hex` files match the current interleaved SRAM layout. Each line
contains one 64-bit SRAM word:

```text
bank = word64_index % 4
```

## Run In Simulation

```bash
make sim-run-sw SW_APP=my_test
```

The simulation target rebuilds the selected app, passes the app build directory
as `+MEM_PATH=sw/build/sim/<core>/<toolchain>/<app>`, watches UART output, and uses
`sim_ctrl_pass()` / `sim_ctrl_fail(code)` as the completion signal.

The repository also includes `bench_smoke`, a deterministic benchmark-style
software smoke that exercises a repeatable integer workload and checks the final
state/checksum:

```bash
make sim-run-sw SW_APP=bench_smoke
```

For the iDMA system DMA there is `dma_smoke`, which drives aligned, unaligned,
and 1 KiB memory-to-memory copies through `sw/c/common/dma.h` and verifies the
destination buffers. Its UART output makes it slower than the default
simulation budget, so give it more cycles:

```bash
make sim-run-sw SW_APP=dma_smoke SIM_TIMEOUT_CYCLES=2000000
```

## Run On FPGA

Start OpenOCD:

```bash
make openocd
```

In another terminal, monitor the UART. The exact `/dev/ttyUSBx` assignment is
host-dependent; prefer `/dev/serial/by-id/` when identifying the CP210x UART
bridge. On the validated setup it was `/dev/ttyUSB1`:

```bash
picocom -b 115200 /dev/ttyUSB1
```

In another terminal, load the selected ELF into RAM and stay in GDB:

```bash
make fpga-load-sw SW_APP=my_test
```

For a one-command batch run with a timeout:

```bash
make fpga-run-sw SW_APP=my_test GDB_TIMEOUT=10
```

The ELF load path uses the debug module's system bus access path, so RAM can be
programmed after the bitstream is already running.

For interactive breakpoints and stepping, see
[`docs/fpga_debug_stepping.md`](fpga_debug_stepping.md).

Known-good smoke sequence:

```bash
source sourceme.sh
make fpga-bit
make fpga-pgm
make openocd
make fpga-run-sw SW_APP=hello_world GDB_TIMEOUT=10
```

For a repeatable board-level acceptance sweep across all cores listed in the
selected board descriptor:

```bash
source sourceme.sh
make deps
make smoke
make fpga-accept BOARD=axku5 UART_DEV=/dev/serial/by-id/<uart-device>
```

`make fpga-accept` runs `bin/fpga_debug_acceptance.sh` with the descriptor
core list. The flow builds each core in its own FPGA work root and programs the
board. Debug-capable cores use the OpenOCD/GDB firmware load path and optional
GDB step smoke. Supported cores without debug support use the UART SRAM loader,
which requires `UART_DEV`. The flow prints a final per-core summary with the
work root, bitstream path, UART log path, and result.

Expected UART output:

```text
=== CoreJack SoC Demo ===
Target: fpga
Core: ibex
Board: axku5
UART base: 0x10000000
Clock: 25000000 Hz, baud: 115200
UART and JTAG debug path are alive.
```

For UART-loader cores, the final line is:

```text
UART path is alive.
```

## Core Swapping Intent

The long-term core boundary is the `rtl/cores/` adapter layer, not the board
wrapper. A core adapter should translate from a concrete core's native ports to
the platform-visible instruction/data/debug/interrupt contract. The board wrapper
should remain limited to clock/reset, FPGA primitives, constraints, and physical
pin wiring. The AXKU5 wrapper exposes a `CoreType` parameter and passes it into
`soc_top`; the validated FPGA configuration currently leaves that parameter at
the descriptor-selected Ibex default.

The user-facing Make variables are `CORE` and `BOARD`. The Makefile
validates those selections and derives the FPGA build settings from the
descriptor files: `FPGA_TOP`, `FPGA_TARGET`, `FPGA_WORK_ROOT`, and
`OPENOCD_CFG`. It also derives `CORE_TYPE`, which drives the FPGA top-level
`CoreType` parameter. The descriptor resolver also exposes `MARCH`, `MABI`,
`TOOLCHAIN`, `SOC_CLK_HZ`, and `UART_BAUD`; these are visible through
`make target-config`. The software build consumes `TOOLCHAIN`, `MARCH`,
`MABI`, `SOC_CLK_HZ`, and `UART_BAUD` so toolchain selection, compiler ISA
flags, and firmware-visible clock/UART defaults come from the selected
core/board descriptors.

The FPGA build path is the FuseSoC/Vivado flow behind `make fpga-bit`.

See [`docs/core_board_descriptors.md`](core_board_descriptors.md) for the
descriptor direction.
