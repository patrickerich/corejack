# FPGA Hardware Smoke Checklist

This checklist defines the minimum repeatable hardware validation flow for an
FPGA board target. It is intended for board bring-up and for confirming that a
known-good core/board combination still works after RTL, build-flow, or software
changes.

For the full core promotion criteria, including simulation and debug support
status, see [`core_acceptance_checklist.md`](core_acceptance_checklist.md).

The current validated reference is:

- board: `axku5`
- core: `ibex`
- clock: `25 MHz`
- RAM base: `0x80000000`
- UART base: `0x10000000`
- UART baud: `115200`
- debug transport: external JTAG through `riscv-dbg`

## Prerequisites

Use a shell with the project environment active:

```bash
source sourceme.sh
```

For UART monitoring, identify the board UART using stable device paths when
possible:

```bash
ls -l /dev/serial/by-id/
```

Use the board UART device with `picocom`:

```bash
picocom -b 115200 /dev/ttyUSBx
```

The exact `/dev/ttyUSBx` name is host- and cable-order dependent.

## Build And Program

Build the selected FPGA target:

```bash
make fpga-bit CORE=ibex BOARD=axku5
```

This also runs the Vivado warning gate. To re-check an existing build without
rebuilding the bitstream, run:

```bash
make fpga-warning-check CORE=ibex BOARD=axku5
```

The warning gate fails on warning IDs that are not listed in
`cfg/vivado_warning_allowlist.txt`.

Program the FPGA:

```bash
make fpga-pgm CORE=ibex BOARD=axku5
```

Expected result:

- Vivado programming completes without errors.
- Board status LEDs match the board wrapper's documented idle/debug status.
- No UART output is required immediately after programming.

## OpenOCD Enumeration

Start OpenOCD in a dedicated terminal:

```bash
make openocd BOARD=axku5
```

Expected result:

- OpenOCD finds the JTAG TAP.
- OpenOCD examines the RISC-V target successfully.
- OpenOCD starts the GDB server on port `3333`.

For the current Ibex reference, useful success indicators include:

```text
JTAG tap: riscv.cpu tap/device found
[riscv.cpu] Examined RISC-V core
[riscv.cpu] Examination succeed
Listening on port 3333 for gdb connections
```

## GDB Load And Run

In another terminal, load and run the selected software image:

```bash
make fpga-run-sw SW_APP=hello_world GDB_TIMEOUT=10 CORE=ibex BOARD=axku5
```

Every other core whose descriptor reports OpenOCD/GDB debug as supported
uses the same flow. See [`support_matrix.md`](support_matrix.md) for the
current set; substitute the chosen core in `CORE=...`, for example:

```bash
make fpga-run-sw SW_APP=hello_world GDB_TIMEOUT=10 CORE=cv32e40p BOARD=axku5
```

Cores without a usable RISC-V debug interface use
`make fpga-uart-load-sw` instead; see
[`uart_sram_loader.md`](uart_sram_loader.md).

Expected result:

- GDB connects to OpenOCD.
- The ELF loads into SRAM through the debug module SBA path.
- Execution starts at the ELF `_entry_point`.
- The command exits by timeout or detach according to the selected run helper.

The expected `hello_world` UART output is:

```text
=== CoreJack SoC Demo ===
Target: fpga
Core: ibex
Board: axku5
UART base: 0x10000000
Clock: 25000000 Hz, baud: 115200
UART and JTAG debug path are alive.
```

The FPGA acceptance helper can capture and validate the same banner
automatically:

```bash
bin/fpga_debug_acceptance.sh --cores "cv32e40p" --board axku5 --uart /dev/ttyUSBx
```

To exercise every FPGA-supported core for the selected board in one
sweep, prefer the descriptor-driven Make wrapper, which builds the core
list from the board descriptor:

```bash
make fpga-accept BOARD=axku5 UART_DEV=/dev/ttyUSBx
```

The helper selects the correct software loading path per core. Debug-capable
cores use OpenOCD/GDB; non-debug cores use the UART SRAM loader.

The same capture path is available through Make:

```bash
make fpga-debug-accept CORE=cv32e40p BOARD=axku5 UART_DEV=/dev/ttyUSBx
```

## Interactive Debug Smoke

For interactive stepping, use:

```bash
make fpga-load-sw SW_APP=hello_world CORE=<core> BOARD=axku5
```

Then use GDB commands such as:

```gdb
break main
continue
stepi
info registers
detach
quit
```

Expected result:

- Breakpoints can be placed in SRAM-resident code.
- Single stepping advances the program counter as expected.
- Register reads complete without OpenOCD reporting a halt failure.

For the current per-core validation status (including which cores have
been exercised through this interactive debug smoke), see
[`support_matrix.md`](support_matrix.md).

See [`fpga_debug_stepping.md`](fpga_debug_stepping.md) for the detailed
interactive workflow.

## Failure Triage

If OpenOCD cannot examine the target:

- verify the debug JTAG adapter and cable orientation
- verify the programmed bitstream matches the selected board/core target
- check that the board wrapper exposes the expected debug JTAG pins

If GDB cannot load SRAM:

- verify OpenOCD is still running
- verify the debug module SBA path is present for the selected core/SoC target
- run `make debug-sim` to check the debug ROM and SBA simulation regressions

If UART output is missing:

- verify the UART cable and `/dev/serial/by-id/` mapping
- verify the UART terminal baud is `115200`
- verify the software was built with `TARGET=fpga`
- verify the board wrapper maps UART TX/RX to the expected pins

If UART output is garbled:

- confirm the terminal baud matches the hardware baud
- confirm the SoC clock used by software matches the actual FPGA clock
- check for stale software built against a different clock configuration
