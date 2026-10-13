RISC-V Debug Integration Guide
==============================

This document describes the expected ``riscv-dbg`` integration pattern for the
CoreJack SoC. It is intended to be a stable design guide, not a debug log.

The current FPGA baseline uses:

-  ``dmi_jtag`` as the external JTAG-to-DMI transport
-  ``dm_top`` as the RISC-V debug module
-  Ibex as the hart
-  a core-visible debug memory window
-  the debug module System Bus Access, or SBA, master port for memory/peripheral
   access while the hart is halted or reset

Integration Model
-----------------

Keep debug transport, debug module, hart, and SoC fabric responsibilities
separate:

-  Board wrappers own physical JTAG pins, clock buffers, reset adaptation, and
   constraints.
-  ``dmi_jtag`` converts the external JTAG Debug Transport Module protocol into
   DMI requests and responses.
-  ``dm_top`` implements the debug module, debug ROM, abstract command support,
   program buffer support, and SBA master.
-  The hart receives ``debug_req_o`` from ``dm_top`` and fetches debug ROM code from
   the SoC debug memory window.
-  The SoC fabric routes core instruction/data traffic and SBA traffic to RAM,
   UART, debug memory, or an error response.

Do not reset the debug module with hart reset. The debug module must remain
available when the hart is in ``ndmreset``, otherwise a debugger cannot reliably
program memory, inspect state, or release the hart.

Address Map
-----------

The SoC must expose a debug memory window that is visible to the hart
instruction and data ports. The hart debug address parameters must match this
window:

-  ``DmHaltAddr``: debug halt entry address
-  ``DmExceptionAddr``: debug exception entry address

For the current CoreJack integration, the debug window is located at
``DebugBaseAddr``, and the halt/exception entry points are:

.. code:: text

   DmHaltAddr      = DebugBaseAddr + 0x800
   DmExceptionAddr = DebugBaseAddr + 0x810

The halt, resume, and exception flag offsets used inside the debug memory come
from ``dm_pkg``:

-  ``dm::HaltAddress``
-  ``dm::ResumeAddress``
-  ``dm::ExceptionAddress``

``dm_top.DmBaseAddress`` is not the same thing as the SoC decode base in this
integration. It is consumed by ``dm_mem`` when generating debug ROM behavior. Keep
the SoC-visible decode window and the hart debug address parameters aligned, and
set ``dm_top.DmBaseAddress`` deliberately for the selected ``riscv-dbg``
configuration.

Hart Info
---------

``dm_top`` needs a correct ``HartInfo`` structure for the selected core. For the
current Ibex integration:

-  ``nscratch`` is ``2``
-  Ibex implements ``dscratch0`` and ``dscratch1``
-  ``dataaccess`` is enabled
-  ``datasize`` and ``dataaddr`` match the ``riscv-dbg`` package constants

The debug ROM mode and the number of scratch CSRs must agree with the hart
implementation. A mismatch can lead to debug ROM execution failures even when
JTAG enumeration succeeds.

Debug Memory Timing
-------------------

The hart enters debug mode by fetching instructions from the debug memory window.
This path is latency tolerant, but each accepted request must be tracked until
exactly one matching response is returned.

Required sequence:

1. ``dm_top`` asserts ``debug_req_o``.
2. The hart redirects instruction fetch to ``DmHaltAddr``.
3. The core-side request is converted into an AXI transaction.
4. The AXI fabric decodes the address into the debug target window.
5. The AXI-to-DM bridge asserts ``dm_top.slave_req_i`` with the address offset
   relative to the debug window base.
6. For reads, the bridge captures the registered ``dm_top.slave_rdata_o`` value
   after presenting the slave request.
7. The bridge returns the AXI response, and the OBI-side adapter returns
   ``rvalid`` to the original requester.

The important rule is:

.. code:: text

   accepted debug-window requests must remain ordered until their response returns

Do not drop the accepted request context while traversing fabric stages. The
requester, address lane, and read/write attributes must remain associated with
the eventual response. Symptoms of broken ordering include OpenOCD being able to
enumerate the target but failing to halt the hart or read registers during GDB
attach.

Also do not return ``dm_top.slave_rdata_o`` in the same cycle that
``dm_top.slave_req_i`` is first asserted. The debug memory read data is registered;
return the response to the hart or SBA master after the registered read data is
available.

Request Arbitration
-------------------

The debug memory window can be accessed by:

-  hart instruction fetch
-  hart data access
-  debug module SBA access

The fabric must accept at most the number of outstanding debug-window accesses
that the downstream bridge can track and must return exactly one response per
accepted request.

The current platform routes the non-RAM instruction, data, and SBA traffic
through OBI-to-AXI adapters into the ``axi_xbar`` system crossbar (per-initiator
address decode, per-target round-robin arbitration, multiple outstanding
requests), which reaches the debug module through the AXI-to-DM bridge. The
crossbar replaced the earlier single-outstanding shared arbiter, so SBA traffic
no longer serializes against instruction and data accesses headed to other
targets. RAM-window instruction and data accesses bypass the crossbar on
native ``soc_mem_ss`` ports; SBA reaches RAM through the crossbar's RAM target.

SBA Integration
---------------

The ``dm_top.master_*`` port is an independent SoC bus master. Treat SBA like any
other initiator:

-  ``master_req_o`` remains asserted until ``master_gnt_i``
-  writes complete after grant and response
-  reads complete when ``master_r_valid_i`` is asserted
-  bus errors are reported through ``master_r_err_i``
-  access width, byte enables, and address alignment must be honored

SBA must be able to access RAM while the hart is held in ``ndmreset``. This is
what allows GDB/OpenOCD to load an ELF into RAM before releasing the hart.

In the current CoreJack integration:

-  SBA is a third AXI fabric initiator after OBI-to-AXI adaptation.
-  SBA can access RAM, UART, CLINT, PLIC, the DMA window, debug memory, and
   invalid addresses through the same explicit AXI decode path used by core
   non-RAM traffic; it is the initiator the crossbar's RAM target exists for.
-  The SRAM and fabric reset are driven by platform reset, not by ``ndmreset``.

Reset Requirements
------------------

Use separate reset domains intentionally:

-  ``dm_top.rst_ni``: platform/debug-module reset
-  hart/core reset: platform reset gated by ``ndmreset_o``
-  SRAM/fabric reset: platform reset only

``ndmreset_o`` should reset only the non-debug hart side. It must not reset the
debug module, DMI path, SRAM, or the fabric required for SBA.

``ndmreset_ack_i`` should indicate completion of an ``ndmreset``-initiated hart
reset. For the current ``riscv-dbg`` version, generate this as a pulse when the
core reset sequence has completed. Do not tie it permanently to a reset-done
level; doing so can repeatedly reassert reset-status state in the debug module.

If ``dmi_jtag.dmi_rst_no`` is used, connect it deliberately to the DMI-facing
debug reset path. If it is left unused, document why the DMI reset behavior is
still correct for the platform.

Who owns a transaction across a core reset
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Resetting only the hart raises a question the reset domains alone do not answer:
if the fabric has already accepted a transaction from the core, who completes
it? An orphaned response would sit on the crossbar's slave port with ``valid``
held and ``ready`` low, and could later land on the restarted core.

The RV32 cores never own a fabric transaction. Their OBI buffers and
``soc_obi_to_axi`` bridges sit on ``rst_ni``, so they survive the core reset and
finish the AXI side themselves; the buffers' core-facing ``s_rready_i`` is tied
high, so responses always retire whether or not the core is alive to take them.

**CVA6 is different: it is the AXI initiator itself**, so a core-only reset
lands in the middle of the AXI link. Two rules of the AXI specification (AMBA
AXI, ARM IHI 0022) matter here:

1. **Handshake** ("Handshake process"): once a source asserts ``VALID``, it
   keeps ``VALID`` asserted, and the information it qualifies stable, until the
   handshake (``VALID`` and ``READY`` both high at a rising clock edge).
2. **Reset** ("Reset"): while ``ARESETn`` is asserted, a manager drives
   ``ARVALID``, ``AWVALID`` and ``WVALID`` low, and a subordinate drives
   ``RVALID`` and ``BVALID`` low.

Rule 2 is the one sanctioned way for ``VALID`` to drop before its handshake,
and it assumes one reset per interface: both ends reset together and both
forget the half-finished transfer. ``ndmreset`` breaks that assumption on
purpose. CVA6 is reset (``core_rst_ni``) while the fabric is not (``rst_ni``),
because the debug module needs the fabric during the reset. CVA6 correctly
drops its valids under rule 2, but to the still-running fabric that is a rule-1
violation.

This is not hypothetical. A halted hart runs the riscv-dbg park loop, which
stores to the debug module on every pass, and CVA6's AXI shim has the AW of
each store accepted one cycle before its W. ``ndmreset`` landing in that gap
lost the W: the write never completed, the isolation stage waiting for its B
response never drained, and the hart never halted again. That was the
intermittent ``Unable to halt`` after ``reset halt`` on the AXKU5 (one failure
in 41 back-to-back resets in one measurement; a second ``ndmreset`` did not
recover it).

``soc_top`` therefore puts two stages on ``rst_ni`` in the CVA6 path, ahead of
its request router:

``soc_axi_reset_bridge`` makes the link compliant on **both** sides, each under
its own reset:

-  *Fabric side*, on ``rst_ni``, never reset by ``ndmreset``, so rule 1 binds.
   The bridge copies any request (AW, W or AR) presented to the fabric without
   its ``READY``, and from the next cycle drives that channel from the copy
   until the handshake. A core reset can then neither drop ``VALID`` nor change
   the payload, and a torn write completes with its own data. While isolated,
   the bridge presents no new request, so it never raises a ``VALID`` it might
   have to drop, and it forces ``BREADY`` and ``RREADY`` high so responses
   retire without the core.
-  *Core side*, in CVA6's reset domain, so rule 2 binds the bridge as the core's
   subordinate. While isolated, ``BVALID`` and ``RVALID`` toward the core are
   held low, and so are its ``READY`` signals. A core in reset, or just
   restarted, never sees a response to a request issued before its reset, nor
   an acknowledgement for a transfer the bridge completed on its behalf.

``axi_isolate`` counts the outstanding transactions and reports when the last
one has completed. The isolation window opens with the core reset (the same
cycle - the reset asserts asynchronously, so the bridge's copy must already be
in place) and closes only once that drain is complete, not merely when
``core_rst_ni`` releases. Anything the bridge holds is part of that drain, so it
always completes before the window closes.

The bridge's module header states its contract with ``soc_top``, and
simulation checks it: a protocol checker on the bridge's fabric side (rule 1
through every core reset) and assertions inside the bridge.

Measured behaviour, from ``make cva6-reset-sim``:

-  With CVA6 actively fetching, forcing ``ndmreset`` produces no fabric-side
   response activity at all: the reset synchroniser's delay exceeds the RAM
   response latency, so in-flight responses retire while CVA6 is still
   accepting them.
-  With the hart halted and ``ndmreset`` forced between a store's AW and W
   handshakes, three times in a row, the hart is back in debug mode 146 cycles
   after each release - the same as a reset with no write in flight.

On hardware, with the bridge in place, 1000 back-to-back ``reset halt``
commands from OpenOCD on a halted CVA6 all succeed, on both the AXKU5 and the
Arty A7. Before the fix, the AXKU5 first failed at the 41st.

The bridge's AW/AR hold and its core-side response masking are not exercised:
CVA6 does not leave an AW or AR waiting, or a response stalled toward itself,
when the reset lands. See :doc:`open_items`.

OpenOCD And GDB Flow
--------------------

The expected debugger flow is:

1. OpenOCD connects to the external JTAG transport.
2. OpenOCD enumerates the RISC-V DTM and debug module.
3. GDB connects to OpenOCD.
4. GDB/OpenOCD halts or resets and halts the hart.
5. GDB loads the ELF through the debug module memory access path.
6. GDB sets the PC to the ELF entry point.
7. GDB resumes execution.

The CoreJack helper scripts follow this shape:

.. code:: text

   target extended-remote localhost:3333
   monitor reset halt
   load
   set $pc = (unsigned int)&_entry_point
   continue

For RAM-resident FPGA firmware, set the PC to the linker-defined entry symbol,
not to the reset vector word and not to the value stored at the entry address.

Validation Checklist
--------------------

Minimum simulation checks:

-  Debug memory access returns the expected instruction word for a fetch at
   ``DmHaltAddr``.
-  A core debug-window request reaches ``dm_top.slave_req_i`` through the AXI
   fabric with the expected debug-window offset address.
-  The core receives ``rvalid`` and the registered debug memory data after the
   AXI-to-DM bridge captures the read data.
-  SBA can write and read RAM while the hart is held in reset.
-  Invalid SBA and core accesses complete with an error response rather than
   hanging.

Minimum hardware checks:

-  OpenOCD enumerates the TAP and examines the RISC-V target.
-  GDB can connect and read registers.
-  GDB can load an ELF into SRAM.
-  The hart starts from the expected ELF entry point.
-  UART output or another externally visible side effect confirms software
   execution.

Common Failure Modes
--------------------

OpenOCD can enumerate the target but GDB cannot halt or read registers:

-  Check the debug memory request/response ordering.
-  Confirm the hart fetches from ``DmHaltAddr``.
-  Confirm ``dm_top.slave_req_i`` sees the expected debug-window offset address.
-  Confirm the response is returned to the original requester after the
   registered ``dm_top.slave_rdata_o`` value is available.

ELF loading fails or memory reads return errors:

-  Check the SBA master path.
-  Confirm RAM and fabric are not reset by ``ndmreset``.
-  Confirm ``master_gnt_i``, ``master_r_valid_i``, and ``master_r_err_i`` obey the
   ``riscv-dbg`` contract.

The hart traps immediately after loading software:

-  Confirm the PC is set to the ELF entry symbol.
-  Confirm FPGA builds do not execute simulation-only MMIO writes.
-  Confirm the linked memory map matches the hardware RAM and peripheral map.

UART output is corrupted while debug works:

-  Confirm the hardware clock used by the UART matches the software platform
   constant.
-  Confirm the terminal baud rate matches the UART divisor configuration.
-  Confirm UART register accesses use the access width expected by the UART IP.
