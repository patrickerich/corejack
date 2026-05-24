# Repository Layout

This page is a quick map of the CoreJack source tree. For deeper context on a
specific area, follow the linked documentation.

## RTL

- `rtl/top/soc_top.sv` - generic SoC top: core region, AXI4 fabric, debug,
  APB UART, CLINT, banked SRAM, and the optional UART SRAM loader.
- `rtl/pkg/platform_pkg.sv` - shared enums (`core_type_e`, memory map style,
  memory technology, interconnect style).
- `rtl/pkg/soc_bus_pkg.sv` - central PULP bus typedefs (`APB`, `AXI`, `OBI`,
  register interface) used as the default typed interfaces.
- `rtl/pkg/mem_ss_pkg.sv` - memory subsystem types.
- `rtl/interfaces/` - core and accelerator socket interface contracts.
- `rtl/cores/` - core adapters and the multi-core `corejack_core_region`.
  Adapters exist for Ibex, CV32E40P, CV32E40S, CV32E40X, CVA6, SERV, PicoRV32,
  and CVW/Wally. See [`rtl/cores/README.md`](../rtl/cores/README.md).
- `rtl/bus/` - fabric building blocks (`soc_axi_arbiter`, `soc_axi_demux`,
  `soc_obi_to_axi`, `soc_axi_to_mem`, `soc_axi_to_apb`, `soc_axi_to_dm`,
  `soc_axi_to_reg`, `soc_axi_protocol_checker`).
- `rtl/mem/` - banked SRAM subsystem (`soc_mem_ss`), OBI memory buffer, and
  SRAM slice models/wrappers for behavioral and Xilinx targets.
- `rtl/platform/soc_uart_sram_loader.sv` - side-path UART SRAM loader.
- `rtl/platform/fpga/boards/<board>/` - per-board wrapper and XDC.
  Currently: `axku5/corejack_axku5_wrap.sv` and `axku5/axku5.xdc`.
- `rtl/platform/fpga/scripts/` - OpenOCD config, GDB load/run helpers, and
  Vivado utility scripts. See
  [`rtl/platform/fpga/scripts/README.md`](../rtl/platform/fpga/scripts/README.md).

## Descriptors And Configuration

- `cfg/cores/<core>.yaml` - per-core descriptors covering ISA, adapter,
  debug, Zephyr status, and board compatibility.
- `cfg/boards/<board>.yaml` - per-board descriptors covering FPGA part,
  clocks, pins, UART, debug transport, and programming flow.
- `cfg/vivado_warning_allowlist.txt` - reviewed Vivado warning IDs.
- `cfg/platform.example.yaml` - sample platform configuration consumed by
  the generator.

## Tooling And Build Glue

- `bin/` - Python helpers including `validate_target.py`, `platform_gen.py`,
  `uart_sram_load.py`, `fpga_debug_acceptance.sh`, and the optional
  toolchain/tool installers.
- `Bender.yml`, `Bender.lock` - external RTL dependency manifest and pins.
- `corejack.core`, `corejack_common.core`, `corejack_core_<core>.core`,
  `corejack_board_<board>.core` - FuseSoC platform target plus the per-core
  and per-board plugins.
- `Makefile` - user-facing targets for descriptor validation, FPGA build,
  software build, simulation, debug, and Zephyr.
- `sourceme.sh` - project virtual environment activation and tool path setup.

## Generated Artifacts

- `gen/rtl/addr_map_pkg.sv` - generated SoC address map package.
- `gen/rtl/soc_top_gen.sv` - generated top-level glue.

## Testbenches And Software

- `tb/` - cocotb harnesses and TB-only monitors: `soc_dut.sv`,
  `smoke_dut.sv`, `axi_adapter_dut.sv`, `uart_sram_loader_dut.sv`,
  `uart_apb_tx_monitor.sv`, `sim_ctrl_monitor.sv`,
  `axi_sim_ctrl_monitor.sv`, plus the cocotb tests
  `test_soc_sw.py`, `test_smoke.py`, `test_axi_adapters.py`,
  `test_debug_integration.py`, and `test_uart_sram_loader.py`.
- `sw/c/` - bare-metal apps (`hello_world`, `self_check`, `bench_smoke`,
  `timer_uart_smoke`) sharing `sw/common/link.ld` and the common runtime
  under `sw/c/common/`.
- `sw/zephyr/` - out-of-tree Zephyr boards, SoC definitions, devicetree
  fragments, and the CoreJack Zephyr smoke app.

## Build Outputs (Ignored)

- `build/fpga/<board>/<core>/fusesoc-fpga/` - FuseSoC and Vivado work root.
- `sw/build/<target>/<core>/<toolchain>/<app>/` - software build outputs;
  `<target>` is `fpga` or `sim`.
- `build/waves/` - optional Verilator FST/VCD traces.
- `.bender/`, `deps/` - Bender checkouts and stable symlinks.
- `TOOLS_DIR`/`.venv/` - optional project-local tools and Python venv;
  `TOOLS_DIR` defaults to `.tools`.

For the descriptor schema, see
[`core_board_descriptors.md`](core_board_descriptors.md). For how Bender and
FuseSoC interact, see
[`dependency_management.md`](dependency_management.md).
