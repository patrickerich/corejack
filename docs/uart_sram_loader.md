# UART SRAM Loader

The UART SRAM loader is a side-path firmware loading mechanism for cores that
do not expose a usable RISC-V debug interface.

## Purpose

The normal FPGA software flow uses `riscv-dbg`, OpenOCD, and GDB to halt a hart
and load an ELF into SRAM through debug system bus access. That flow requires a
debug-capable core. Very small cores such as SERV can still be useful in the
CoreJack platform, but they need a different way to put code in SRAM before
execution starts.

The UART SRAM loader provides that path by using the existing board UART pins as
a temporary boot-time transport:

- keep the core held in reset while loading
- keep the SoC clock, SRAM, and UART transport alive
- write SRAM through a side memory-init port
- release the core after the host sends a run command
- hand the UART pins back to the normal SoC UART after release

This is not a replacement for OpenOCD/GDB. Debug-capable cores should keep using
the debug flow because it supports halt, breakpoints, stepping, and register
inspection.

## When To Use It

Use the UART SRAM loader for cores that can execute from the shared SRAM but do
not provide a compatible external RISC-V debug interface.

Do not enable it for the normal debug-capable FPGA flow. With the default
configuration, the loader is not instantiated and the physical UART pins connect
directly to the normal APB UART.

## Build-Time Control

The loader is controlled by the `EnableUartLoader` FuseSoC parameter. The
Makefile exposes this as:

```bash
UART_LOADER=1
```

Default:

```make
UART_LOADER ?= 0
```

With `UART_LOADER=0`:

- the loader RTL is not instantiated in `soc_top`
- the extra SRAM init port is tied off
- core reset is controlled only by normal reset/debug logic
- the board UART pins are routed to the APB UART
- OpenOCD/GDB behavior is unchanged

With `UART_LOADER=1`:

- the loader RTL is instantiated
- the selected core is held in reset while the loader is active
- the board UART pins are routed to the loader while active
- the loader writes SRAM through an additional `soc_mem_ss` init port
- the loader releases the core and returns the UART pins to the APB UART after
  the host sends the run command

Example SERV FPGA build:

```bash
make fpga-bit CORE=serv BOARD=axku5 UART_LOADER=1
make fpga-pgm CORE=serv BOARD=axku5
```

SERV FPGA support uses the UART SRAM loader path instead of the RISC-V debug
SBA path.

## Integration Model

When enabled, the board UART pins are muxed between two users:

```text
loader active:
  uart_rx -> UART SRAM loader
  uart_tx <- UART SRAM loader
  core reset is held asserted
  loader writes SRAM through soc_mem_ss init port

loader released:
  uart_rx -> normal APB UART
  uart_tx <- normal APB UART
  core reset follows normal reset/debug control
```

Only the core reset is held by the loader. The rest of the platform remains out
of reset so the UART loader and SRAM can operate.

The UART pin switch is controlled by the loader's `active_o` signal:

```systemverilog
assign uart_tx_o = uart_loader_active ? uart_loader_tx : apb_uart_tx;

.sin_i(uart_loader_active ? 1'b1 : uart_rx_i)
```

When `uart_loader_active` is high, the APB UART receives an idle RX line so it
does not consume loader traffic. When `uart_loader_active` goes low, the same
physical UART pins become the firmware console.

The loader waits until the final ACK byte has completed transmission before it
deasserts `active_o`. This prevents switching the physical TX pin back to the
APB UART in the middle of the release response.

## SRAM Write Path

The loader connects to `soc_mem_ss` through a second init/access port. The
normal AXI-to-memory path remains on init port 0. The loader uses init port 1.

The loader accepts absolute SoC addresses. For the current memory map, the SRAM
base is:

```text
0x80000000
```

Writes are byte writes into the shared 64-bit SRAM path. The loader selects the
proper byte lane from `addr[2:0]` and drives a one-hot byte enable, so payloads
do not need to be aligned to 64-bit words.

## Wire Protocol

The initial protocol is byte-oriented and intentionally small:

| Command | Payload | Response | Meaning |
| --- | --- | --- | --- |
| `?` (`0x3f`) | none | ACK (`0x06`) | host ping |
| `W` (`0x57`) | `addr[31:0]`, `len[15:0]`, then `len` data bytes, little-endian | ACK (`0x06`) after all bytes are written | write bytes to SRAM |
| `G` (`0x47`) | none | ACK (`0x06`) | release loader and start the core |

Invalid commands return NAK (`0x15`) and leave the loader active.

Example byte stream for writing two bytes, `0xa5` and `0x5a`, to
`0x80000003`:

```text
57                command: W
03 00 00 80       address: 0x80000003
02 00             length: 2
a5 5a             payload
```

The resulting SRAM writes are:

```text
addr=0x80000003, be=0x08, lane3=0xa5
addr=0x80000004, be=0x10, lane4=0x5a
```

After the host has loaded the complete image, it sends:

```text
47                command: G
```

The loader ACKs, releases the core, and returns the UART pins to the APB UART.

## Validation

The protocol-level simulation is:

```bash
make uart-loader-sim
```

This checks:

- host ping response
- unaligned byte writes into the 64-bit SRAM path
- ACK after write completion
- release after the `G` command

`make axi-smoke` also includes this regression.

## Host Loader Tool

The host-side loader tool is:

```bash
bin/uart_sram_load.py
```

It opens the selected UART, pings the loader, sends one or more `W` chunks,
sends `G`, and can then capture UART output from the released firmware.

Direct example:

```bash
bin/uart_sram_load.py \
  --uart /dev/serial/by-id/<uart-device> \
  --baud 115200 \
  --bin sw/build/fpga/serv/riscv-multilib/hello_world/hello_world.bin \
  --addr 0x80000000 \
  --capture-seconds 15 \
  --expect "UART"
```

The Make wrapper builds the selected bare-metal app first and then invokes the
same tool:

```bash
make fpga-uart-load-sw \
  CORE=serv \
  BOARD=axku5 \
  SW_APP=hello_world \
  UART_DEV=/dev/serial/by-id/<uart-device> \
  UART_LOADER_EXPECT="UART path is alive."
```

The Zephyr wrapper builds the selected Zephyr board first and then loads the
generated binary through the same UART transport:

```bash
make fpga-uart-load-zephyr \
  CORE=serv \
  BOARD=axku5 \
  UART_DEV=/dev/serial/by-id/<uart-device> \
  UART_LOADER_EXPECT="Machine timer interrupt path is alive."
```

Useful Make variables:

| Variable | Default | Meaning |
| --- | --- | --- |
| `UART_DEV` | empty | UART device path; required |
| `UART_CAPTURE_TIMEOUT` | `15` | seconds to capture firmware UART output after `G` |
| `UART_LOADER_ADDR` | `0x80000000` | SRAM load address |
| `UART_LOADER_CHUNK_SIZE` | `4096` | maximum bytes per `W` command |
| `UART_LOADER_TIMEOUT` | `2` | ACK/read timeout in seconds |
| `UART_LOADER_EXPECT` | empty | optional substring required in captured output |

## Status

The current implementation includes:

- RTL-side UART loader
- core-reset hold while loading
- SoC UART pin muxing between loader and normal APB UART
- SRAM writes through an additional `soc_mem_ss` init port
- `UART_LOADER=1` FuseSoC/Make parameter plumbing for FPGA builds
- `make uart-loader-sim` protocol regression for ping, byte writes, and release
- `bin/uart_sram_load.py` host loader
- `make fpga-uart-load-sw` bare-metal Make wrapper
- `make fpga-uart-load-zephyr` Zephyr Make wrapper
- SERV AXKU5 FPGA bring-up with `hello_world` loaded through the UART SRAM
  loader and firmware UART output observed
- SERV AXKU5 Zephyr timer-smoke sample loaded through the UART SRAM loader and
  firmware UART output observed
- PicoRV32 AXKU5 FPGA bring-up with `hello_world` loaded through the UART SRAM
  loader and firmware UART output observed
- CVW/Wally AXKU5 FPGA bring-up with `hello_world` loaded through the UART SRAM
  loader and firmware UART output observed
- automated FPGA acceptance integration through `make fpga-accept`, including
  non-debug UART-loader cores

Follow-up work:

- extend UART-loader acceptance to additional non-debug cores when they are
  added
