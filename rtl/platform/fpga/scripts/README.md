# FPGA Utility Scripts

These scripts provide the OpenOCD/GDB workflow for CoreJack FPGA targets. Run
commands from the repository root.

## OpenOCD

Start OpenOCD in one terminal:

```bash
make openocd
```

This uses:

```bash
rtl/platform/fpga/scripts/openocd.cfg
```

The config targets the AXKU5 external Tigard JTAG path and a single RISC-V hart
behind `riscv-dbg` (`dmi_jtag` + `dm_top`).

## Build Software

Applications live under `sw/c/<app>/main.c`. The CMake project auto-discovers
these app directories, so adding a new small test only requires:

```text
sw/c/my_test/main.c
```

Build any app with:

```bash
make sw-build SW_APP=my_test TARGET=fpga
```

Outputs are written under:

```text
sw/build/fpga/<core>/<toolchain>/my_test/
```

The build emits:

- `cmake/my_test/my_test` - ELF loaded by GDB/OpenOCD
- `my_test.bin` - flat binary
- `my_test.dis` - disassembly
- `bank_0.hex` ... `bank_3.hex` - RAM preload files for the current banked memory

## Load Or Run On FPGA

With OpenOCD already running, load an app and stay in GDB:

```bash
make fpga-load-sw SW_APP=my_test
```

For a batch-style run with a timeout:

```bash
make fpga-run-sw SW_APP=my_test GDB_TIMEOUT=10
```

The scripts select GDB in this order:

1. `$GDB`, if set
2. `.tools/riscv/bin/riscv64-unknown-elf-gdb`, if present
3. `$RISCV/bin/riscv64-unknown-elf-gdb`, if present
4. `$RISCV/bin/riscv32-unknown-elf-gdb`, if present
5. `$RISCV/bin/riscv-none-elf-gdb`, if present
6. `riscv64-unknown-elf-gdb` or `riscv32-unknown-elf-gdb` from `PATH`

## UART

The current FPGA wrapper routes the SoC UART to the AXKU5 board UART pins.
The validated FPGA image runs the UART from the 25 MHz SoC clock at 115200
baud. Monitor it with a local serial tool, for example:

```bash
picocom -b 115200 /dev/ttyUSB1
```

Adjust the `/dev/ttyUSBx` device to match the CP210x UART bridge on your host.
Using `/dev/serial/by-id/` is the most reliable way to distinguish the board
UART from the Digilent programming pod and any external JTAG adapter.

The known-good `hello_world` output is:

```text
=== CoreJack SoC Demo ===
Target: fpga
Core: ibex
Board: axku5
UART base: 0x10000000
Clock: 25000000 Hz, baud: 115200
UART and JTAG debug path are alive.
```

## LEDs

The AXKU5 user LEDs are stable board status indicators:

- LED1: SoC reset released
- LED2: debug module active
- LED3: live debug request
- LED4: core sleep state
