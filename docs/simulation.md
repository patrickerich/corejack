# Simulation

CoreJack's pre-silicon verification runs as [cocotb](https://www.cocotb.org/)
tests driving [Verilator](https://www.veripool.org/verilator/)-built models,
orchestrated by FuseSoC. The same generic `soc_top` is simulated across cores;
small testbench wrappers select the device under test for each flow.

## Overview

- **Verilator** compiles the RTL into a cycle-accurate C++ model.
- **cocotb** provides the Python testbench that stimulates and checks the
  model. The test logic lives under `tb/`.
- **FuseSoC** resolves the filesets and Verilator options for each simulation
  target and invokes the tool. Targets and their flags are defined in
  `corejack.core`.
- **Bender** provides the external HDL dependencies that FuseSoC consumes; the
  `make` simulation targets fetch the needed subset first (`deps-base` or
  `deps-core`).

The `smoke` flow exercises the `EnablePlatform=0` stub of `soc_top` and is pure
SystemVerilog/cocotb, so it needs **no RISC-V toolchain**. The software-driven
flows compile a bare-metal application and run it on the full platform, so they
additionally need a RISC-V GNU toolchain.

Simulation outputs are written under the ignored `build/` tree: the FuseSoC work
root is `build/sim/fusesoc/<core>/<target>/`, and optional waveforms land in
`build/waves/`.

## Prerequisites

- **Always needed:** Verilator and Bender, plus the project virtual environment
  (`source sourceme.sh`) that provides FuseSoC, cocotb, and pytest. See
  [`tooling.md`](tooling.md) for pinned versions and the optional repo-local
  Verilator install (`make tool-verilator`). `make check-tools FLOW=sim` reports
  what is missing.
- **Software-driven sims** (`make sim-run-sw`, `make axi-smoke`): additionally a
  RISC-V GNU toolchain (default prefix `riscv64-unknown-elf-*` with RV32/RV64
  multilib). `make toolchain-riscv` builds a project-local one.

## Simulation Targets

| Target | Purpose | DUT / cocotb test | RISC-V toolchain | Deeper doc |
| --- | --- | --- | --- | --- |
| `make smoke` | cocotb smoke against the `EnablePlatform=0` stub of `soc_top` | `smoke_dut` / `test_smoke` | no | — |
| `make sim-run-sw SW_APP=<app>` | build a bare-metal app and run it on the full platform | `soc_dut` / `test_soc_sw` | yes | [`fpga_sw_flow.md`](fpga_sw_flow.md) |
| `make debug-sim` | debug ROM and system-bus-access (SBA) regression | `soc_dut` / `test_debug_integration` | no | [`riscv_dbg_integration.md`](riscv_dbg_integration.md) |
| `make axi-adapter-sim` | AXI adapter, protocol checker, and 32-to-64-bit lane behavior | `axi_adapter_dut` / `test_axi_adapters` | no | [`axi4_fabric.md`](axi4_fabric.md) |
| `make uart-loader-sim` | UART SRAM loader protocol regression | `uart_sram_loader_dut` / `test_uart_sram_loader` | no | [`uart_sram_loader.md`](uart_sram_loader.md) |
| `make axi-smoke` | aggregate gate: address-map check, the three focused sims above, then `hello_world` on each supported core | (composite) | yes | [`axi4_fabric.md`](axi4_fabric.md) |

`make axi-smoke` runs `axi-adapter-sim`, `uart-loader-sim`, and `debug-sim`,
then `sim-run-sw` for each core in `AXI_SMOKE_CORES` (default `ibex cv32e40p
cv32e40s cva6 serv picorv32 cvw`). Unsupported cores are intentionally excluded;
see [`support_matrix.md`](support_matrix.md).

A typical first run, with no RISC-V toolchain required:

```bash
source sourceme.sh
make bender
make deps
make smoke
```

Run a bare-metal app on the full platform (needs the RISC-V toolchain):

```bash
make sim-run-sw SW_APP=hello_world
```

## Test And DUT Structure

The cocotb tests and testbench-only SystemVerilog live under `tb/`:

- **DUT wrappers** select the toplevel for each flow: `smoke_dut.sv` (stub),
  `soc_dut.sv` (full platform, used by both the software and debug flows),
  `axi_adapter_dut.sv`, and `uart_sram_loader_dut.sv`.
- **cocotb tests:** `test_smoke.py`, `test_soc_sw.py`,
  `test_debug_integration.py`, `test_axi_adapters.py`, and
  `test_uart_sram_loader.py`.
- **TB-only monitors:** `sim_ctrl_monitor.sv`, `axi_sim_ctrl_monitor.sv`, and
  `uart_apb_tx_monitor.sv`.

The toplevel and cocotb module for each target are wired in `corejack.core`. See
[`repository_layout.md`](repository_layout.md) for the full source-tree map.

## Waveforms

Waveform dumping is **off by default** and, when enabled, writes a single trace
file per run into the `build/` tree. The format defaults to **FST** (smaller
than VCD); VCD is available as an explicit opt-in.

| Variable | Default | Meaning |
| --- | --- | --- |
| `SIM_WAVES` | `0` | set to `1` to dump a waveform |
| `SIM_WAVE_FORMAT` | `fst` | `fst` or `vcd` |
| `SIM_WAVE_DIR` | `build/waves` | output directory |
| `SIM_WAVE_FILE` | (derived) | explicit output path override |

When `SIM_WAVES=1`, the build adds the matching Verilator flag (`--trace-fst`
for FST, `--trace` for VCD) and the run is directed to the trace file with
`--trace-file`. When `SIM_WAVE_FILE` is unset, the path is derived per target,
for example `build/waves/sw-sim-<core>-<app>.fst` or `build/waves/smoke.fst`.

```bash
# FST trace of the smoke run -> build/waves/smoke.fst
make smoke SIM_WAVES=1

# FST trace of a software run -> build/waves/sw-sim-<core>-<app>.fst
make sim-run-sw SW_APP=hello_world SIM_WAVES=1

# Opt into VCD instead, or choose an explicit path
make smoke SIM_WAVES=1 SIM_WAVE_FORMAT=vcd
make smoke SIM_WAVES=1 SIM_WAVE_FILE=build/waves/my_run.fst
```

All trace artifacts stay under `build/` and are covered by `.gitignore`
(`*.fst`, `*.vcd`, and `build/`).

## Other Knobs

- `SIM_TIMEOUT_CYCLES` (default `1000000`) bounds a software simulation; it is
  passed through to the testbench as the `COREJACK_TIMEOUT_CYCLES` cocotb
  environment variable.
- `SW_APP` selects the bare-metal application for `sim-run-sw`; `make list-apps`
  lists the available apps under `sw/c/`.
- `CORE` / `BOARD` select the descriptor-driven target; `AXI_SMOKE_CORES`
  overrides the core set covered by `make axi-smoke`.

The `test_soc_sw.py` flow also honours optional cocotb environment variables for
focused, in-test logging and expectations. The general-purpose ones are:

| Environment variable | Effect |
| --- | --- |
| `COREJACK_EXPECT_UART` | fail the test unless the given text appears on UART |
| `COREJACK_TRACE_BUS` | log fabric bus transactions |
| `COREJACK_TRACE_UART` | log UART byte traffic |
| `COREJACK_TRACE_AFTER_CYCLE` | arm tracing only after the given cycle |
| `COREJACK_TRACE_AFTER_UART` | arm tracing only after the given UART text appears |
| `COREJACK_TRACE_LIMIT` | cap the number of trace lines emitted |

Additional `COREJACK_*` variables exist for core-specific investigation (for
example the CV32E40X instruction-fetch contract checks and PC/memory
watchpoints); see `tb/test_soc_sw.py` for the full list.
