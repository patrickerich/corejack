# CoreJack Zephyr Bring-Up

This directory contains the initial out-of-tree Zephyr application, board, and
SoC definitions for CoreJack. The first targets are intentionally narrow:

- cores: Ibex, CV32E40P, CV32E40S, CVA6, SERV
- board: AXKU5
- executable image region: `0x80000000` to `0x8003ffff`
- Zephyr RAM region: `0x80040000` to `0x800fffff`
- UART: `0x10000000`, NS16550-compatible register layout with `reg-shift = 2`
- clock: `25 MHz`
- baud: `115200`

Per-core Zephyr support is tracked in `cfg/cores/<core>.yaml` as
`software.zephyr.status`. The current supported AXKU5 cores are
`initial_supported`: they build this sample app and have passed the FPGA load
plus UART timer-smoke test. Debug-capable cores use OpenOCD/GDB. SERV uses the
UART SRAM loader. This does not yet claim complete RTOS platform support.

The initial goal is to build and run a Zephyr console/timer smoke application
through each core's accepted FPGA software loading flow. The RV32 board targets
share the same CoreJack RV32 SoC, memory, timer, and UART definitions. CVA6
uses a separate CoreJack RV64 SoC because it is an RV64 core and boots at
`0x80000080` in this platform.

The current FPGA has one 1 MiB SRAM window at `0x80000000`. Zephyr intentionally
models it as an XIP-style `zephyr,flash` region followed by a writable
`zephyr,sram` region. Both regions are physically SRAM; the split gives the
linker separate RX and RW LOAD segments and keeps runtime writes from aliasing
over executable code.

## Workspace

Initialize the project-local Zephyr workspace:

```bash
source sourceme.sh
make zephyr-init
make zephyr-python-deps
```

This creates or updates:

```text
.tools/zephyrproject/
```

The manifest intentionally fetches only the Zephyr repository for the first
bring-up. Additional Zephyr modules should be added only when a concrete
feature needs them.

Build the initial application:

```bash
make zephyr-build CORE=ibex BOARD=axku5
make zephyr-build CORE=cv32e40p BOARD=axku5
make zephyr-build CORE=cv32e40s BOARD=axku5
make zephyr-build CORE=cva6 BOARD=axku5
make zephyr-build CORE=serv BOARD=axku5
```

The Make target passes `BOARD_ROOT`, `SOC_ROOT`, and `DTS_ROOT` so Zephyr can
find the out-of-tree board, SoC, and devicetree files in this directory.

SERV hardware runs use the UART SRAM loader rather than OpenOCD/GDB:

```bash
make fpga-bit CORE=serv BOARD=axku5 UART_LOADER=1
make fpga-pgm CORE=serv BOARD=axku5 UART_LOADER=1
make fpga-uart-load-zephyr \
  CORE=serv \
  BOARD=axku5 \
  UART_DEV=/dev/serial/by-id/<uart-device> \
  UART_LOADER_EXPECT="Machine timer interrupt path is alive."
```

The ELF is expected at:

```text
sw/build/zephyr/corejack_<core>_axku5/corejack_hello/zephyr/zephyr.elf
```

The initial build produces an RV32 ELF with entry point `0x80000000`, matching
the CoreJack SRAM base.

CV32E40X board files are kept from earlier investigation, but CV32E40X is not
part of the supported Zephyr target set. Do not include it in default
regressions until the upstream core behavior is resolved.

Debug-capable cores use the same OpenOCD/GDB load path as the bare-metal FPGA
software flow. SERV uses the UART SRAM loader.

## Current Limits

This is a first bring-up skeleton. It deliberately avoids claiming a complete
RTOS platform until the missing platform services are explicit and validated:

- interrupt controller behavior
- Zephyr flash/debug runner integration
- simulation acceptance path
- FPGA acceptance path
