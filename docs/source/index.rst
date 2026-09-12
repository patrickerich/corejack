CoreJack Documentation
======================

CoreJack is a starter SoC platform that treats the RISC-V core as the
variable: one generic ``soc_top`` is reused across every supported core through a
thin per-core adapter, and across every supported FPGA board through a thin
board wrapper. Picking a target is just ``CORE=<core> BOARD=<board>``.

These pages cover the platform in depth - architecture, porting guides,
simulation, FPGA bring-up, and debug. The sections below group them by task.

Project Orientation
-------------------

-  :repofile:`README.md` - purpose, quick start, current status,
   and pointers back into this documentation.
-  :doc:`About CoreJack <about>` - motivation, target audience, what makes
   CoreJack different, and a factual comparison against Chipyard, LiteX,
   Rocket Chip Generator, OpenTitan, and Cheshire/Carfield.
-  :doc:`Support matrix <support_matrix>` - generated core/board support status
   from descriptors.
-  :doc:`Repository layout <repository_layout>` - quick map of the source tree
   and where each kind of artifact lives.
-  :doc:`Roadmap <roadmap>` - current baseline, per-core notes, and the active
   direction for cores, boards, fabric, and software.
-  :doc:`Open items <open_items>` - noticed-but-deferred issues and improvements
   (a lightweight tech-debt log, distinct from the roadmap).
-  :doc:`Tooling <tooling>` - host tool checks, optional repo-local tool
   installs, and observed validation versions.
-  :doc:`Dependency management <dependency_management>` - Bender/FuseSoC split,
   dependency classes, and the optional core checkout policy.
-  :doc:`Core and board descriptors <core_board_descriptors>` - descriptor
   schema and how the Make targets derive build variables from ``CORE`` and
   ``BOARD``.
-  :doc:`Core acceptance checklist <core_acceptance_checklist>` - validation
   gates before marking a core supported.
-  :doc:`Coding style <coding_style>` - style intent for CoreJack-owned code
   and third-party dependency boundaries.

Adding Hardware
---------------

-  :doc:`Core porting guide <core_porting>` - add a RISC-V core behind the
   CoreJack platform contract. Includes the conservative ``make new-core``
   scaffold flow.
-  :doc:`Board porting guide <board_porting>` - add an FPGA board wrapper,
   constraints, board descriptor, and board FuseSoC core. Includes the
   ``make new-board`` scaffold flow.
-  :doc:`AXI4 fabric <axi4_fabric>` - current system fabric structure.
-  :doc:`AXI4 fabric migration <axi4_fabric_migration>` - historical migration
   notes and design rationale for moving to an AXI4-native fabric.
-  :doc:`Memory subsystem redesign <mem_ss_redesign>` - port-owned,
   multi-outstanding banked SRAM subsystem and the arbitration it provides.

Simulation
----------

-  :doc:`Simulation <simulation>` - cocotb + Verilator simulation setup, the
   simulation targets, testbench structure, waveform dumping, and other knobs.

FPGA And Debug
--------------

-  :doc:`FPGA software flow <fpga_sw_flow>` - build, program, load, and run
   software on FPGA.
-  :doc:`FPGA debug stepping <fpga_debug_stepping>` - OpenOCD/GDB stepping flow
   for debug-capable cores.
-  :doc:`FPGA hardware smoke <fpga_hardware_smoke>` - hardware validation flow
   and acceptance expectations.
-  :doc:`RISC-V debug integration <riscv_dbg_integration>` - design guidance for
   integrating ``riscv-dbg``.
-  :doc:`UART SRAM loader <uart_sram_loader>` - fallback SRAM load path for
   cores without usable OpenOCD/GDB debug.
-  :doc:`External JTAG wiring <jtag_wiring>` - external-JTAG adapter selection and pin maps
   for the AXKU5 and Arty A7-100T boards.

Software
--------

-  :doc:`Zephyr bring-up <zephyr_bringup>` - Zephyr board/application setup and
   current support notes.

Core-Specific Notes
-------------------

-  :doc:`CV32E40X boot issue <cv32e40x_boot_issue>` - current reason CV32E40X is
   not part of the supported regression set.

.. toctree::
   :hidden:
   :caption: Project Orientation

   about
   support_matrix
   repository_layout
   roadmap
   open_items
   tooling
   dependency_management
   core_board_descriptors
   core_acceptance_checklist
   coding_style

.. toctree::
   :hidden:
   :caption: Adding Hardware

   core_porting
   board_porting
   axi4_fabric
   axi4_fabric_migration
   mem_ss_redesign

.. toctree::
   :hidden:
   :caption: Simulation

   simulation

.. toctree::
   :hidden:
   :caption: FPGA And Debug

   fpga_sw_flow
   fpga_debug_stepping
   fpga_hardware_smoke
   riscv_dbg_integration
   uart_sram_loader
   External JTAG wiring <jtag_wiring>

.. toctree::
   :hidden:
   :caption: Software

   zephyr_bringup

.. toctree::
   :hidden:
   :caption: Core-Specific Notes

   CV32E40X boot issue <cv32e40x_boot_issue>
