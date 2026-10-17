Open Items
==========

A lightweight log of issues or improvements noticed during development but
deliberately **deferred** — things we decided not to solve immediately. This is
distinct from :doc:`roadmap`, which records intended direction;
open items are latent gaps, tech debt, or design decisions parked for later.

Add an entry when you choose not to fix something now; remove it once resolved.

-  **CVW ``rdtime`` reads 0 (CSR time shadow not wired).** Wally shadows the
   CLINT's memory-mapped ``mtime`` into the ``time``/``timeh`` CSRs through its
   ``MTIME_CLINT`` core input, but the vendored PULP CLINT does not export its
   internal ``mtime`` counter, so ``corejack_cvw_ahb_adapter`` ties the port to
   zero and ``rdtime`` permanently returns 0 on CVW (with ``ZICNTR_SUPPORTED = 1``,
   ``rdcycle``/``rdinstret`` still work — they are core-internal). Software must
   use the memory-mapped ``mtime`` at ``0x0200_bff8`` instead. Fixing this
   properly needs either an mtime export added to (a wrapper of) the CLINT or
   a CLINT replacement; disabling ZICNTR would trade the silent zero for an
   illegal-instruction trap but also removes the working counters.
