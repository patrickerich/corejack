.. _cv32e40x-first-accepted-instruction-fetch-after-boot-is-boot_addr_i--4:

CV32E40X first accepted instruction fetch after boot is ``boot_addr_i + 4``
===========================================================================

Status: resolved. The cause was CoreJack's own ``cv32e40x_clock_gate`` shim, not
the CV32E40X core. Upstream issue
`#993 <https://github.com/openhwgroup/cv32e40x/issues/993>`_ reported this as a
possible core bug before the cause was known.

CV32E40X is now supported in simulation and runs in CoreJack's default
regressions. Its FPGA and debug support are still planned.

Symptom
-------

With ``boot_addr_i = 0x80000080``, the first fetch the memory accepted was
``0x80000084``, while the IF stage tracked the returned data as PC
``0x80000080``. Later fetches stayed one word off in the same way, so the adapter
carried a workaround that subtracted 4 from ``instr_addr_o``.

Cause
-----

The shim was a bare AND gate:

.. code:: systemverilog

   assign clk_o = clk_i & (en_i | scan_cg_en_i);

``en_i`` comes from flops in ``cv32e40x_sleep_unit`` that run on the ungated
clock, so it rises just after a rising clock edge, while ``clk_i`` is high. The
AND gate opens at that moment and gives the core a late rising edge, after the
rest of the SoC has already sampled that clock edge.

The first fetch request appears in that same gap:

.. code:: text

   clock edge N       memory samples  req=0
   late core edge     core samples    req=1 gnt=1 addr=0x80000080
   clock edge N+1     memory samples  req=1 gnt=1 addr=0x80000084

The core counts the fetch of ``boot_addr_i`` as granted, but the memory never saw
it. The core then has one outstanding transaction with no bus transaction behind
it, and that count never recovers:

-  Each response is matched to the fetch before the one that produced it, which
   is the one-word offset.
-  The alignment buffer allows two outstanding fetches, so only one real fetch
   can be in flight, which reduces fetch bandwidth.

The fetch is lost only if ``instr_gnt_i`` is high at the late edge. If the grant
comes a cycle later, the core holds its request and the memory still sees it.

Fix
---

``cv32e40x_clock_gate`` now passes the clock through, like the CV32E40P shim, and
the adapter connects ``instr_addr_o`` directly, with no address adjustment. Fetch
is also faster: CoreJack's software apps take 2-27% fewer simulated cycles.

A future real clock gate must not let ``clk_o`` rise while ``clk_i`` is high.
Upstream's simulation gate, ``bhv/cv32e40x_sim_clock_gate.sv``, uses a latch for
this reason, and it also runs correctly without the address adjustment.

Checking It
-----------

Setting ``COREJACK_CHECK_CV32E40X_IF_CONTRACT=1`` makes ``tb/test_soc_sw.py`` fail
if the IF stage delivers an instruction whose word was never accepted at the core
boundary. ``COREJACK_TRACE_CV32E40X_IF=1`` logs the fetches it compares.
