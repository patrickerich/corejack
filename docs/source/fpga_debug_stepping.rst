FPGA OpenOCD/GDB Debugging
==========================

This document describes how to load, run, halt, and step FPGA firmware through
the RISC-V debug path.

For the checklist used to promote a core's descriptor to
``integration.debug: supported``, see
:doc:`core_acceptance_checklist`.

The validated baseline is:

-  board: AXKU5
-  cores: every core whose descriptor reports OpenOCD/GDB debug as
   supported; the current set lives in
   :doc:`support_matrix`. Non-debug cores (SERV,
   PicoRV32, CVW/Wally) use the :doc:`UART SRAM loader <uart_sram_loader>`
   instead.
-  debug transport: external JTAG into ``riscv-dbg``
-  OpenOCD GDB port: ``3333``
-  firmware RAM base: ``0x80000000``
-  UART base: ``0x10000000``
-  UART baud: ``115200``

Prerequisites
-------------

Program a bitstream that includes the SoC debug path:

.. code:: bash

   source ./sourceme.sh
   make fpga-bit
   make fpga-pgm

Select a non-default supported core with ``CORE=<core> BOARD=<board>``, for
example:

.. code:: bash

   make fpga-bit CORE=cv32e40p BOARD=axku5
   make fpga-pgm CORE=cv32e40p BOARD=axku5

Start OpenOCD in one terminal:

.. code:: bash

   source ./sourceme.sh
   make openocd

A healthy OpenOCD connection reports that the JTAG tap was found and that the
RISC-V core was examined. The GDB server should listen on TCP port ``3333``.

Monitor UART from another terminal if the program prints output. Prefer the
stable ``/dev/serial/by-id/`` names when identifying the USB UART adapter:

.. code:: bash

   picocom -b 115200 /dev/ttyUSB1

The exact ``/dev/ttyUSBx`` number is host-dependent.

Build Firmware
--------------

Build an FPGA-targeted firmware image:

.. code:: bash

   source ./sourceme.sh
   make sw-build SW_APP=hello_world TARGET=fpga

The ELF is written under:

.. code:: text

   sw/build/fpga/<core>/riscv-multilib/hello_world/cmake/hello_world/hello_world

Use a different app by replacing ``hello_world`` with any directory listed by:

.. code:: bash

   make list-apps

Load And Stay In GDB
--------------------

Use the Make target when you want the repo to build the selected app and open an
interactive GDB session:

.. code:: bash

   source ./sourceme.sh
   make fpga-load-sw SW_APP=hello_world

This connects GDB to OpenOCD and loads the ELF through the debug module's system
bus access path.

Manual GDB Session
------------------

You can also start GDB directly:

.. code:: bash

   source ./sourceme.sh
   riscv64-unknown-elf-gdb sw/build/fpga/ibex/riscv-multilib/hello_world/cmake/hello_world/hello_world

Inside GDB:

.. code:: gdb

   target extended-remote localhost:3333
   monitor reset halt
   load
   set $pc = (unsigned int)_entry_point
   break main
   continue

At this point the core should stop at ``main``.

GDB Binary Selection
--------------------

The ``make fpga-load-sw`` and ``make fpga-run-sw`` targets pick a RISC-V GDB in
this order, using the first that is available:

1. ``$GDB``, if set
2. ``.tools/riscv/bin/riscv64-unknown-elf-gdb``, if present
3. ``$RISCV/bin/riscv64-unknown-elf-gdb``, if present
4. ``$RISCV/bin/riscv-none-elf-gdb``, if present
5. ``riscv64-unknown-elf-gdb`` from ``PATH``

If none are found, source ``./sourceme.sh`` or set ``GDB=/path/to/gdb``.

Stepping
--------

Instruction stepping is the most reliable first check:

.. code:: gdb

   x/8i $pc
   stepi
   info registers
   nexti

Source-level stepping also works when the firmware is built with debug
information:

.. code:: gdb

   break main
   continue
   step
   next
   finish

The default OpenOCD configuration forces hardware breakpoints. This is the
right default for FPGA RAM/debug flows because it avoids patching instruction
memory with software breakpoint instructions.

Useful Commands
---------------

Inspect the current PC and nearby instructions:

.. code:: gdb

   p/x $pc
   x/10i $pc

Inspect machine CSRs and common trap state:

.. code:: gdb

   p/x $mstatus
   p/x $mcause
   p/x $mepc
   p/x $mtval

Halt or resume the target:

.. code:: gdb

   monitor halt
   continue

Reload the program:

.. code:: gdb

   monitor reset halt
   load
   set $pc = (unsigned int)_entry_point

Detach from the target:

.. code:: gdb

   detach
   quit

Batch Run
---------

For a quick smoke run without interacting with GDB:

.. code:: bash

   source ./sourceme.sh
   make fpga-run-sw SW_APP=hello_world GDB_TIMEOUT=10

This target builds the app, loads it, runs for the timeout, interrupts the
target, and detaches. A timeout is not automatically a failure; it is the normal
completion mechanism for programs that keep running after printing.

Expected Smoke Output
---------------------

With UART connected at ``115200`` baud, ``hello_world`` prints:

.. code:: text

   === CoreJack SoC Demo ===
   Target: fpga
   Core: ibex
   Board: axku5
   UART base: 0x10000000
   Clock: 25000000 Hz, baud: 115200
   UART and JTAG debug path are alive.

OpenOCD should report a final halt reason of ``debug-request`` when GDB
interrupts a running target.

Troubleshooting
---------------

If GDB cannot read registers, confirm OpenOCD can examine the target before
connecting GDB. Reprogram the FPGA and restart OpenOCD if the target reports an
undefined halt reason.

If UART output is missing, verify the serial adapter by stable
``/dev/serial/by-id/`` path and confirm it is opened at ``115200`` baud.

If source-level stepping behaves unexpectedly, use ``stepi`` and ``nexti`` first.
Source-level behavior depends on compiler optimization and debug information in
the firmware ELF.
