# CoreJack

CoreJack is a starter platform for evaluating swappable RISC-V cores and
accelerators on a shared, ASIC-aware SoC. The same generic `soc_top` is reused
across cores and boards: a thin board wrapper provides clocks, resets, FPGA
primitives, and pin mapping, while per-core adapters translate each RISC-V
core into the shared CoreJack memory, AXI4 fabric, and debug contract.

The first FPGA board target (`axku5`) is hardware-validated across the
supported core set. Bitstreams build, software loads into SRAM through
OpenOCD/GDB or the side-path UART SRAM loader, and `hello_world` prints over
the platform APB UART.

## Project Status

Validated baseline:

- FPGA board target: `axku5`
- supported cores: Ibex, CV32E40P, CV32E40S, CVA6, SERV, PicoRV32, and
  CVW/Wally
- SoC clock: `25 MHz`
- RAM: banked SRAM at `0x80000000`; UART: APB UART at `0x10000000`,
  `115200` baud
- CLINT machine timer at `0x02000000`; Zephyr timer frequency `12.5 MHz`
- debug transport: external JTAG through `riscv-dbg` (`dmi_jtag` + `dm_top`)
- Zephyr: `initial_supported` on the validated Zephyr-capable core/board
  pairs

CV32E40X is intentionally excluded from default regressions; see
[`docs/cv32e40x_boot_issue.md`](docs/cv32e40x_boot_issue.md).

The descriptor-derived per-core/board status table lives in
[`docs/support_matrix.md`](docs/support_matrix.md); regenerate it with
`make support-matrix`. For the active direction across cores, boards, and
software, see [`docs/roadmap.md`](docs/roadmap.md).

## Getting Started

### Tool Prerequisites

Each flow needs a different subset of host tools. Use `make check-tools
FLOW=sim|fpga|debug` to see what is missing for the selected flow.

- **Always needed:** Python (3.10+ satisfies the pinned deps; default and
  CI-validated interpreter is `python3.13`, overridable via the `PYTHON`
  env var), plus `make`, `git`, and `curl`. `sourceme.sh` creates a
  project-local `.venv` and installs the pinned FuseSoC, cocotb, west,
  pytest, and PyYAML packages from `requirements.txt`.
- **`make smoke`:** Verilator and Bender. Pure SystemVerilog/cocotb test
  against the `EnablePlatform=0` stub of `soc_top`; **no RISC-V toolchain
  required.**
- **`make sim-run-sw`, `axi-smoke`, `fpga-*` software loads:** additionally
  need a RISC-V GNU toolchain (default prefix `riscv64-unknown-elf-*` with
  RV32/RV64 multilib).
- **FPGA build/program:** Vivado (`2025.2.1` is the observed validation
  version).
- **FPGA debug (`openocd`, `fpga-run-sw`):** OpenOCD with RISC-V support
  and `riscv64-unknown-elf-gdb`.
- **Zephyr (`zephyr-*`):** an initialized west workspace; `make zephyr-init`
  bootstraps `.tools/zephyrproject`.

Optional project-local installs go under the ignored `.tools/` directory and
are picked up automatically by `sourceme.sh`:

```bash
make tool-verilator      # pinned Verilator into .tools/verilator/
make toolchain-riscv     # bare-metal multilib GCC/Newlib/GDB into .tools/riscv/
make tool-verible        # pinned Verible lint/format tools into .tools/verible/
```

See [`docs/tooling.md`](docs/tooling.md) for the full setup, pinned
versions, and observed validation versions.

### Quick Start

```bash
# 1) Activate the project virtual environment and pinned Python deps
source sourceme.sh

# 2) Fetch external HDL deps and generate RTL artifacts
make bender
make deps
make gen

# 3) Run the cocotb + Verilator smoke simulation (no RISC-V toolchain needed)
make smoke

# 4) Build and run a bare-metal app in simulation (needs RISC-V toolchain)
make sim-run-sw SW_APP=hello_world
```

For FPGA bring-up, build a bitstream, program the board, and load software
through OpenOCD/GDB:

```bash
make fpga-bit CORE=ibex BOARD=axku5
make fpga-pgm
make openocd                                            # terminal 1
make fpga-run-sw SW_APP=hello_world GDB_TIMEOUT=10      # terminal 2
```

For cores without a usable RISC-V debug interface (SERV, PicoRV32, CVW), use
the UART SRAM loader instead of OpenOCD/GDB; see
[`docs/uart_sram_loader.md`](docs/uart_sram_loader.md).

Check the descriptor matrix for a board with
`make target-check BOARD=axku5`.

## Documentation

The full documentation index is in [`docs/README.md`](docs/README.md). It
groups documentation by:

- project orientation - support matrix, repository layout, roadmap,
  tooling, dependency management, descriptor schema, coding style, core
  acceptance checklist;
- adding hardware - core porting, board porting, AXI4 fabric;
- FPGA and debug - software flow, hardware smoke, OpenOCD/GDB stepping,
  `riscv-dbg` integration, UART SRAM loader;
- software - Zephyr bring-up;
- core-specific notes.

## License

CoreJack-original code is licensed under the Apache License, Version 2.0;
see [`LICENSE`](LICENSE). Third-party RTL and IP retain their upstream
licenses; see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
