Repository Layout
=================

This page is a quick map of the CoreJack source tree. For deeper context on a
specific area, follow the linked documentation.

RTL
---

-  ``rtl/top/soc_top.sv`` - generic SoC top: core region, AXI4 fabric, debug,
   APB UART, CLINT, PLIC, iDMA socket, banked SRAM, and the optional UART SRAM
   loader.
-  ``rtl/pkg/platform_pkg.sv`` - shared enums (``core_type_e``, memory map style,
   memory technology, interconnect style).
-  ``rtl/pkg/soc_bus_pkg.sv`` - central PULP bus typedefs (``APB``, ``AXI``, ``OBI``,
   register interface) used as the default typed interfaces.
-  ``rtl/pkg/mem_ss_pkg.sv`` - memory subsystem types.
-  ``rtl/interfaces/`` - the accelerator socket contract (``accel_socket_if``, in
   use by the iDMA) and an aspirational core socket sketch (``core_socket_if``,
   not wired in).
-  ``rtl/cores/`` - core adapters and the multi-core ``corejack_core_region``.
   Adapters exist for Ibex, CV32E40P, CV32E40S, CV32E40X, CVA6, SERV, PicoRV32,
   and CVW/Wally, plus small per-core shims and renamed third-party overrides
   (e.g. the ``cvw_*`` copies that avoid module-name collisions).
-  ``rtl/bus/`` - fabric building blocks (``soc_obi_to_axi``, ``soc_axi_to_mem``,
   ``soc_axi_to_apb``, ``soc_axi_to_dm``, ``soc_axi_to_reg``,
   ``soc_axi_protocol_checker``). The system crossbar itself is the PULP
   ``axi_xbar`` from the Bender-managed ``axi`` dependency; see
   :doc:`axi4_fabric`.
-  ``rtl/mem/`` - banked, interleaved SRAM subsystem (``soc_mem_ss``) built from
   per-bank elastic pipes (``soc_mem_bank``) and per-port ingress/egress logic
   (``soc_mem_port``), the OBI memory buffer (``soc_obi_mem_buffer``), and SRAM slice
   models/wrappers for behavioral and Xilinx targets.
-  ``rtl/platform/soc_uart_sram_loader.sv`` - side-path UART SRAM loader.
-  ``rtl/platform/soc_idma.sv`` - PULP iDMA system DMA wrapper (register
   frontend, ND midend, AXI backend, burst splitter, fabric cuts), and
   ``rtl/platform/corejack_idma_socket_adapter.sv``, its accelerator-socket
   tenant: data path on dedicated ``soc_mem_ss`` ports, config window at
   ``DmaBaseAddr`` through the crossbar.
-  ``rtl/platform/fpga/boards/<board>/`` - per-board wrapper and XDC.
   Currently: ``axku5/`` and ``arty_a7_100t/`` (one wrapper module plus one
   constraints file each).
-  ``rtl/platform/fpga/scripts/`` - per-adapter OpenOCD configs (Tigard, Olimex) with a shared riscv-dbg target file, GDB load/run helpers, and
   Vivado utility scripts. See
   :doc:`fpga_debug_stepping`.

Descriptors And Configuration
-----------------------------

-  ``cfg/cores/<core>.yaml`` - per-core descriptors covering ISA, adapter,
   debug, Zephyr status, and board compatibility.
-  ``cfg/boards/<board>.yaml`` - per-board descriptors covering FPGA part,
   clocks, pins, UART, debug transport, and programming flow.
-  ``cfg/vivado_warning_allowlist.txt`` - reviewed Vivado warning IDs.

Tooling And Build Glue
----------------------

CoreJack does not generate any RTL. The Python under ``bin/`` covers
build orchestration, descriptor resolution, lint/check, scaffolding,
and host runtime - nothing that ends up as SystemVerilog.

-  ``bin/validate_target.py`` - resolves ``cfg/cores/*.yaml`` and
   ``cfg/boards/*.yaml`` into Make variables (``FPGA_TOP``, ``CORE_TYPE``,
   ``MARCH``, ``MABI``, ``TOOLCHAIN``, ``SOC_CLK_HZ``, ``UART_BAUD``, ...). The
   authoritative bridge between descriptors and the build flow.
-  ``bin/render_support_matrix.py`` - regenerates ``docs/source/support_matrix.rst``
   from descriptors (``make support-matrix``).
-  ``bin/create_core.py``, ``bin/create_board.py`` - scaffolds behind
   ``make new-core`` and ``make new-board``.
-  ``bin/check_axi_addr_map.py``, ``bin/check_tools.py``,
   ``bin/check_vivado_warnings.py`` - lint and acceptance checks run
   from ``make``.
-  ``bin/deps_core.py`` - Bender checkout-to-``deps/<name>`` symlink helper.
-  ``bin/vivado_tcl_to_flist.py`` - Vivado project TCL -> flist helper.
-  ``bin/uart_sram_load.py`` - host side of the UART SRAM loader protocol
   (talks to ``rtl/platform/soc_uart_sram_loader.sv``).
-  ``bin/fpga_debug_acceptance.sh``, ``bin/build_*.sh``,
   ``bin/write_bitstream_manifest.sh`` - shell helpers for FPGA
   acceptance and optional tool builds.
-  ``Bender.yml``, ``Bender.lock`` - external RTL dependency manifest and pins.
-  ``corejack.core``, ``corejack_common.core``, ``corejack_core_<core>.core``,
   ``corejack_board_<board>.core`` - FuseSoC platform target plus the per-core
   and per-board plugins.
-  ``Makefile`` - user-facing targets for descriptor validation, FPGA build,
   software build, simulation, debug, and Zephyr.
-  ``sourceme.sh`` - project virtual environment activation and tool path setup.

Testbenches And Software
------------------------

-  ``tb/`` - cocotb harnesses and TB-only monitors: ``soc_dut.sv``,
   ``smoke_dut.sv``, ``axi_adapter_dut.sv``, ``uart_sram_loader_dut.sv``,
   ``plic_dut.sv``, ``mem_ss_bench_dut.sv``, ``uart_apb_tx_monitor.sv``,
   ``sim_ctrl_monitor.sv``, ``axi_sim_ctrl_monitor.sv``, the self-checking
   SystemVerilog benches ``tb_mem_ss.sv`` and ``tb_axi_to_mem.sv``
   (``make sv-tb``), plus the cocotb tests
   ``test_soc_sw.py``, ``test_smoke.py``, ``test_axi_adapters.py``,
   ``test_debug_integration.py``, ``test_uart_sram_loader.py``,
   ``test_plic.py``, ``test_mem_ss_bench.py``, and
   ``test_cva6_reset_isolation.py``.
-  ``sw/c/`` - bare-metal apps (``hello_world``, ``self_check``, ``bench_smoke``,
   ``timer_uart_smoke``, ``dma_smoke``, ``plic_smoke``, ``mem_bw_smoke``) sharing
   ``sw/common/link.ld.in`` (the board-RAM-sized linker template) and the
   common runtime under ``sw/c/common/`` (UART, printf, sim_ctrl, and the
   iDMA and PLIC drivers ``dma.{c,h}`` / ``plic.{c,h}``).
-  ``sw/zephyr/`` - out-of-tree Zephyr boards, SoC definitions, devicetree
   fragments, and the CoreJack Zephyr smoke app.

Build Outputs (Ignored)
-----------------------

-  ``build/fpga/<board>/<core>/fusesoc-fpga/`` - FuseSoC and Vivado work root.
-  ``sw/build/<target>/<core>/<toolchain>/<app>/`` - software build outputs;
   ``<target>`` is ``fpga`` or ``sim``.
-  ``build/flist.f`` - optional Bender flist output of ``make flist``.
-  ``build/waves/`` - optional Verilator FST/VCD traces.
-  ``.bender/``, ``deps/`` - Bender checkouts and stable symlinks.
-  ``TOOLS_DIR``/``.venv/`` - optional project-local tools and Python venv;
   ``TOOLS_DIR`` defaults to ``.tools``.

For the descriptor schema, see
:doc:`core_board_descriptors`. For how Bender and
FuseSoC interact, see
:doc:`dependency_management`.
