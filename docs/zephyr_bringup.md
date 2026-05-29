# Zephyr Bring-Up

CoreJack's first Zephyr targets are the supported cores on AXKU5. The goal is
to reuse the validated FPGA hardware path and add a Zephyr software stack on top
of it.

Zephyr support is tracked in each core descriptor under
`software.zephyr.status`. The current supported AXKU5 cores are marked
`initial_supported`, meaning the Zephyr board target builds, the ELF can be
loaded through the accepted FPGA software loading flow for that core, and UART
prints the Zephyr/CoreJack timer-smoke output. Debug-capable cores use
OpenOCD/GDB. SERV uses the UART SRAM loader. This is intentionally not the same
as full RTOS platform support.

## Initial Target

- Zephyr release: `v4.4.0`, pinned in `sw/zephyr/west.yml` by commit
  `4f50f0ba8905f27b2f60123d0ee0934fda6fe134`
- Zephyr workspace: `TOOLS_DIR/zephyrproject`; `TOOLS_DIR` defaults to `.tools`
- Zephyr app and platform files: `sw/zephyr`
- Zephyr boards: `corejack_ibex_axku5`, `corejack_cv32e40p_axku5`,
  `corejack_cv32e40s_axku5`, `corejack_cva6_axku5`,
  and `corejack_serv_axku5`
- CoreJack core/board pairs: `CORE=ibex BOARD=axku5`,
  `CORE=cv32e40p BOARD=axku5`, `CORE=cv32e40s BOARD=axku5`,
  `CORE=cva6 BOARD=axku5`, `CORE=serv BOARD=axku5`
- SERV is loaded through the UART SRAM loader rather than OpenOCD/GDB
- executable image region: `0x80000000` to `0x8003ffff`
- Zephyr RAM region: `0x80040000` to `0x800fffff`
- UART: `0x10000000`, `115200` baud, `25 MHz`; NS16550-compatible register
  layout with `reg-shift = 2`
- CLINT: `0x02000000`, with `mtime` at `0x0200bff8` and hart 0
  `mtimecmp` at `0x02004000`
- Zephyr timer frequency: `12.5 MHz`

The Zephyr app uses out-of-tree board and SoC definitions. This follows
Zephyr's current hardware model, where board and SoC metadata are kept in
explicit `board.yml`, devicetree, and Kconfig files. The RV32 targets share the
same CoreJack RV32 SoC, memory, and UART definitions, with small per-core
devicetree files for CPU ISA details. CVA6 uses a separate CoreJack RV64 SoC and
sets `CONFIG_ROM_START_OFFSET=0x80` so the ELF entry point matches the platform
CVA6 boot address `0x80000080`.

CVA6 uses the platform `rv64imc/lp64` profile. The project-local RISC-V
toolchain must therefore include an `rv64imc-lp64` multilib; older local
toolchain builds may need to be rebuilt with `make toolchain-riscv`.

The FPGA memory is implemented as a single 1 MiB SRAM window at `0x80000000`.
For Zephyr, CoreJack models that window as two regions: an XIP-style
`zephyr,flash` region at `0x80000000` and a writable `zephyr,sram` region at
`0x80040000`. Both are physically SRAM in the current FPGA design. This split
keeps executable sections out of writable RAM and avoids RWX LOAD segments while
still using the same SRAM image layout for both OpenOCD/GDB and UART-loader
flows.

The platform includes a shared CLINT block outside the cores. Zephyr uses its
standard `riscv,machine-timer` driver with the CLINT `mtime`/`mtimecmp`
registers described in devicetree. The current FPGA CLINT RTC input toggles
from the `25 MHz` system clock, so the machine timer increments on a `12.5 MHz`
timebase.

The initial west manifest fetches only the Zephyr repository. Additional Zephyr
modules should be added later only when a concrete subsystem requires them.

## Commands

Create or update the local Zephyr workspace:

```bash
source sourceme.sh
make zephyr-init
make zephyr-python-deps
```

Check the workspace and toolchain:

```bash
make zephyr-check
```

Build the initial Zephyr application:

```bash
make zephyr-build CORE=ibex BOARD=axku5
make zephyr-build CORE=cv32e40p BOARD=axku5
make zephyr-build CORE=cv32e40s BOARD=axku5
make zephyr-build CORE=cva6 BOARD=axku5
make zephyr-build CORE=serv BOARD=axku5
```

The build passes `BOARD_ROOT`, `SOC_ROOT`, and `DTS_ROOT` to point Zephyr at
the out-of-tree CoreJack platform files in `sw/zephyr`.

Expected ELF:

```text
sw/build/zephyr/corejack_<core>_axku5/corejack_hello/zephyr/zephyr.elf
```

The initial build produces an RV32 ELF with entry point `0x80000000`, matching
the CoreJack SRAM base.

CV32E40X has an out-of-tree Zephyr board directory from earlier bring-up, but
it is not part of the supported Zephyr set. Keep it disabled until the upstream
core behavior around instruction fetch and interrupt vector handling is
resolved.

SERV has an out-of-tree Zephyr board and boots the CoreJack timer-smoke sample
through the UART SRAM loader:

```bash
make fpga-uart-load-zephyr \
  CORE=serv \
  BOARD=axku5 \
  UART_DEV=/dev/serial/by-id/<uart-device> \
  UART_LOADER_EXPECT="Machine timer interrupt path is alive."
```

SERV uses a board-specific idle override to avoid Zephyr's default RISC-V
`wfi` idle instruction. The upstream SERV Zephyr support uses the same approach
because SERV can trap or lock up on `wfi`.

PicoRV32 is not a supported Zephyr runtime target in the current CoreJack
integration. Zephyr's normal RISC-V port uses the standard privileged reset and
trap path, including CSR instructions such as `csrw mtvec,t0`. Upstream PicoRV32
uses a custom IRQ instruction interface instead of the standard privileged
CSR/trap model. Keep PicoRV32 Zephyr status unsupported unless a dedicated
PicoRV32 Zephyr port or a different core configuration provides the expected
trap/CSR behavior.

## Expected Console Output

The first Zephyr smoke app should print:

```text
=== CoreJack Zephyr Demo ===
Target: zephyr
Core: <core>
Board: axku5
UART and Zephyr console path are alive.
Machine timer interrupt path is alive.
```

## Current Bring-Up Limits

This is not yet a complete RTOS platform. Before promoting Zephyr support, the
following platform services must be validated or explicitly ruled out:

- automated FPGA timer-smoke acceptance coverage for every supported loading
  path
- Zephyr flash/debug runner integration
- simulation acceptance path
- broader FPGA OpenOCD/GDB load/run acceptance path

Debug-capable cores use the existing FPGA debug flow to load `zephyr.elf` into
SRAM and observe UART output. SERV uses the UART SRAM loader to load
`zephyr.bin`.
