<!-- SPDX-License-Identifier: Apache-2.0 -->

# AGENTS.md

Guidance for AI coding agents working in this repository, and a quick
orientation for human contributors. It is intentionally short: it points into
the canonical docs rather than duplicating them. Start here, then follow the
links.

- Full doc index: [`docs/README.md`](docs/README.md)
- Contribution workflow: [`CONTRIBUTING.md`](CONTRIBUTING.md)
- Source-tree map: [`docs/repository_layout.md`](docs/repository_layout.md)

## What CoreJack is

A starter SoC platform that treats the **RISC-V core as the variable**. One
generic `soc_top` (`rtl/top/soc_top.sv`) is reused across every supported core
through a thin per-core *adapter*, and across every supported FPGA board through
a thin board *wrapper*. The user-facing selection is just
`CORE=<core> BOARD=<board>`. The fabric is a production-style AXI4 crossbar with
APB peripherals, `riscv-dbg`, CLINT, PLIC, and banked SRAM — *ASIC-aware*, not
FPGA-only (but not silicon-validated). See [`docs/about.md`](docs/about.md).

## Environment and setup

```bash
source sourceme.sh                 # creates .venv, sets tool paths under .tools/
make check-tools FLOW=sim          # report tools missing for a given flow
make bender && make deps           # fetch external HDL dependencies (do this first)
```

`sourceme.sh` activates a project-local `.venv` (Python 3.10+, default
`python3.13`) and prepends repo-local tools from `.tools/` (Verilator, Verible,
RISC-V toolchain) to `PATH` when present. Different flows need different host
tools — use `FLOW=sim|fpga|debug`. See [`docs/tooling.md`](docs/tooling.md).

## Core / board selection model

The build is **descriptor-driven**. `cfg/cores/<core>.yaml` and
`cfg/boards/<board>.yaml` are the source of truth; `bin/validate_target.py`
resolves them into Make variables. Do not hand-edit scattered build logic to add
a combination — change the descriptor.

- Defaults: `CORE=ibex BOARD=axku5`.
- Cores: `ibex`, `cv32e40p`, `cv32e40s`, `cv32e40x`, `cva6` (RV64), `cvw`,
  `serv`, `picorv32`. Boards: `axku5`, `arty_a7_100t`.
- Scaffold new ones with `make new-core` / `make new-board` (they start as
  `planned`; the generated adapter/wrapper is a placeholder).

## Common commands

```bash
make smoke                         # cocotb+Verilator APB smoke; no RISC-V toolchain needed
make sim-run-sw SW_APP=hello_world # build a bare-metal app and run it in sim (needs toolchain)
make axi-smoke                     # full fabric/platform simulation regression set
make sw-build SW_APP=<app>         # build software only
make support-matrix                # regenerate docs/support_matrix.md from descriptors

# FPGA / debug (needs Vivado; debug needs OpenOCD + riscv gdb)
make fpga-bit CORE=<core> BOARD=<board>
make fpga-pgm
make openocd                       # terminal 1
make fpga-run-sw SW_APP=hello_world  # terminal 2
```

Before opening a PR, run the cheapest relevant checks (see
[`CONTRIBUTING.md`](CONTRIBUTING.md)):

```bash
make python-tests
make support-matrix-check
make board-check BOARD=axku5 && make target-check BOARD=axku5
make smoke                         # and `make axi-smoke` for platform-path changes
```

Run `make help` for the full target list.

## Pinned toolchain

Versions are pinned in the `Makefile` and should match what CI uses; do not
silently bump them. Build toolchains from prebuilt packages, not from source.

- Bender `0.31.0`, Verilator `v5.048`, Verible `v0.0-4053-g89d4d98a`
- RISC-V GNU toolchain: prefix `riscv64-unknown-elf-`, RV32/RV64 multilib
- Vivado `2025.2.1` (observed validation version), Zephyr `v4.4.0`

## Conventions for changes

- **RTL is 100% hand-written SystemVerilog.** Python under `bin/` is build glue,
  descriptor resolution, lint/check, scaffolding, and host runtime only — it
  **never** generates RTL.
- **Style:** CoreJack-owned RTL follows the lowRISC/OpenTitan SV style — see
  [`docs/coding_style.md`](docs/coding_style.md). One module per file (filename
  matches the module name); `logic` over `wire`/`reg`; `always_ff`/`always_comb`
  (never plain `always`); `UpperCamelCase` for parameters/localparams/enum
  members; `ALL_CAPS_WITH_UNDERSCORES` reserved for `` `define `` macros only;
  2-space indent, ≤100-col lines (`.editorconfig`). CoreJack-owned files carry an
  `// SPDX-License-Identifier: Apache-2.0` header.
- **Do not reformat or refactor vendored, Bender-managed, or generated
  dependency code** to match local style. Keep edits scoped to CoreJack-owned
  wrappers, adapters, packages, tests, scripts, and docs.
- No lint is enforced in CI yet (Verible is the intended tool — `make
  tool-verible`). Still, flag any construct likely to lint poorly (inferred
  latches, incomplete sensitivity, implicit nets).
- Changing a descriptor's support status requires regenerating
  `docs/support_matrix.md` and committing it with the change; promote status
  only after [`docs/core_acceptance_checklist.md`](docs/core_acceptance_checklist.md)
  passes.
- Git, versioning (VLNV lockstep across `.core` files), and dependency policy
  are in [`CONTRIBUTING.md`](CONTRIBUTING.md). Update
  [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) when adding a vendored or
  externally fetched dependency.

## Architecture must-knows and gotchas

- System fabric is the PULP `axi_xbar` crossbar (48-bit addr / 64-bit data).
  RV32 cores reach it via split OBI → `soc_obi_to_axi`; CVA6 is AXI-native.
  See [`docs/axi4_fabric.md`](docs/axi4_fabric.md).
- **Single-beat AXI invariant:** all fabric traffic is `len == 0`, enforced by
  `rtl/bus/soc_axi_protocol_checker.sv`; the iDMA backend sits behind a burst
  splitter. Keep new initiators/targets single-beat unless the fabric is
  reworked.
- **`soc_mem_ss` is port-owned and multi-outstanding.** Each port — two native
  32-bit CPU ports (data, instruction) plus five 64-bit ports (xbar RAM
  read/write engines, UART SRAM loader, iDMA read/write) — gets loss-free,
  in-order, multi-outstanding access with per-bank fair round-robin. The live
  constraint is now the **bank count**: `soc_top` runs `MemNumBanks = 4` under
  seven ports, so raise it toward the port count for heavy concurrent RAM
  traffic. See [`docs/open_items.md`](docs/open_items.md).
- **CV32E40X is intentionally excluded** from default regressions — see
  [`docs/cv32e40x_boot_issue.md`](docs/cv32e40x_boot_issue.md). Do not re-enable
  it in regression sets without resolving that.
- External IP is fetched, not vendored-in-tree: PULP `axi`, `apb`,
  `common_cells`, `idma`, `clint`, `obi`, `apb_uart`, `riscv-dbg` via Bender;
  cores `serv`/`picorv32`/`cvw`/`cv32e40p`/`cv32e40x`/`cv32e40s` via Bender
  vendor packages; CVA6 fetched and patched by the `Makefile`. Always
  `make bender && make deps` before building.

### Memory map

| Region | Base | Notes |
| --- | --- | --- |
| Debug module | `0x0000_0000` | `riscv-dbg`, JTAG/SBA |
| iDMA CSR | `0x0100_0000` | APB CSR leg; IRQ status W1C at `+0xF00` |
| CLINT | `0x0200_0000` | machine timer / software IRQ |
| PLIC | `0x0C00_0000` | standard layout; src 1 = UART, src 2 = iDMA done |
| UART (APB) | `0x1000_0000` | 16550, 115200 baud; sim_ctrl magic at `0x1000_2000` |
| RAM | `0x8000_0000` | banked 64-bit SRAM (`soc_mem_ss`), board-sized |
