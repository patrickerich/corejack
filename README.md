# CoreJack

CoreJack is a starter platform for evaluating swappable RISC-V cores and
accelerators on a shared, ASIC-aware SoC. The same generic `soc_top` is reused
across cores and boards: a thin board wrapper provides clocks, resets, FPGA
primitives, and pin mapping, while per-core adapters translate each RISC-V
core into the shared CoreJack memory, AXI4 fabric, and debug contract.

Both FPGA board targets (`axku5` and `arty_a7_100t`) are hardware-validated
across the supported core set. Bitstreams build, software loads into SRAM
through OpenOCD/GDB or the side-path UART SRAM loader, and `hello_world`
prints over the platform APB UART.

📖 **Full documentation: <https://patrickerich.github.io/corejack/>**

The pages under `docs/source/` are reStructuredText built with Sphinx and are
meant to be read on the site above, not in the GitHub source view.

## Why CoreJack

- **Swappable cores under one platform.** Eight RISC-V cores ship today
  (Ibex, CV32E40P/S/X, CVA6, CVW/Wally, SERV, PicoRV32), and the platform
  is built to keep growing - `make new-core` scaffolds the next one.
- **ASIC-aware, not FPGA-first.** Production PULP-Platform IP (AXI4,
  APB, OBI, `riscv-dbg`, CLINT, `apb_uart`, `iDMA`), real reset domains, and
  thin board wrappers, so the same SoC structure is meaningful beyond
  prototyping.
- **SystemVerilog throughout.** 100% hand-written SV for everything
  that reaches the gates; Python is only build glue, descriptor
  resolution, lint/check, scaffolding, and host runtime - never RTL
  generation.
- **Descriptor-driven.** Small YAML files under `cfg/cores/` and
  `cfg/boards/` capture ISA, adapter, debug, clock, pin mapping, and
  programming flow. Adding a new core or board uses the `make new-core` /
  `make new-board` scaffolds.

For the full positioning story, target users, and a factual comparison
against Chipyard, LiteX, Rocket Chip, OpenTitan, and Cheshire/Carfield, see
[About CoreJack](https://patrickerich.github.io/corejack/about.html).

## Project Status

- FPGA boards: `axku5` (Alinx AXKU5, Kintex UltraScale+) and `arty_a7_100t`
  (Digilent Arty A7-100T, Artix-7, 256 KiB SRAM) - both validated across the
  supported core set
- Supported cores: Ibex, CV32E40P, CV32E40S, CVA6, SERV, PicoRV32, CVW/Wally
- SoC clock `25 MHz`; RAM at `0x80000000`; APB UART at `0x10000000`,
  `115200` baud
- iDMA system DMA is the first tenant of the accelerator socket; PLIC at
  `0x0C000000`; external JTAG debug through `riscv-dbg`

CV32E40X is intentionally excluded from default regressions; see
[CV32E40X boot issue](https://patrickerich.github.io/corejack/cv32e40x_boot_issue.html).

The descriptor-derived per-core/board status table is the
[support matrix](https://patrickerich.github.io/corejack/support_matrix.html)
(regenerate with `make support-matrix`). For the active direction across
cores, boards, and software, see the
[roadmap](https://patrickerich.github.io/corejack/roadmap.html).

## Getting Started

### Tool Prerequisites

Each flow needs a different subset of host tools. Run `make check-tools
FLOW=sim|fpga|debug` to see what is missing for the selected flow.

Always needed: Python (3.10+; default and CI-validated interpreter is
`python3.13`), plus `make`, `git`, and `curl`. `sourceme.sh` creates a
project-local `.venv` and installs the pinned Python dependencies. Beyond
that, `make smoke` needs Verilator and Bender only; running software needs a
RISC-V GNU toolchain; FPGA work needs Vivado; and FPGA debug needs OpenOCD
plus `riscv64-unknown-elf-gdb`.

Optional project-local tool installs go under `TOOLS_DIR` (default `.tools/`)
and are picked up automatically by `sourceme.sh`:

```bash
make tool-verilator      # pinned Verilator into TOOLS_DIR/verilator/
make toolchain-riscv     # bare-metal multilib GCC/Newlib/GDB into TOOLS_DIR/riscv/
make tool-verible        # pinned Verible lint/format tools into TOOLS_DIR/verible/
```

See [Tooling](https://patrickerich.github.io/corejack/tooling.html) for the
full setup, pinned versions, and observed validation versions.

### Quick Start

```bash
# 1) Activate the project virtual environment and pinned Python deps
source sourceme.sh

# 2) Fetch external HDL dependencies
make bender
make deps

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
the [UART SRAM loader](https://patrickerich.github.io/corejack/uart_sram_loader.html)
instead of OpenOCD/GDB. Check the descriptor matrix for a board with
`make target-check BOARD=axku5`.

The full simulation flow - cocotb + Verilator setup, simulation targets, and
waveform dumping - is documented under
[Simulation](https://patrickerich.github.io/corejack/simulation.html).

## Documentation

Everything else lives on the documentation site:
<https://patrickerich.github.io/corejack/>. It covers project orientation
(support matrix, repository layout, roadmap, tooling, dependency management,
descriptor schema, coding style, acceptance checklist), adding hardware (core
and board porting, AXI4 fabric, memory subsystem), simulation, FPGA and debug
flows, Zephyr bring-up, and core-specific notes.

Build it locally with `make docs` and read it with `make docs-serve`.

## License

CoreJack-original code is licensed under the Apache License, Version 2.0;
see [`LICENSE`](LICENSE). Third-party RTL and IP retain their upstream
licenses; see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
