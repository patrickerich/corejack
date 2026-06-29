# Memory Subsystem Redesign

Living specification for the `soc_mem_ss` redesign. Requirements are owned by
the project maintainer; this document records them as stated and tracks the
design decisions that follow. Update it as the design evolves.

Status: **implemented, verified standalone, integrated into `soc_top` (option A),
and promoted to the canonical `soc_mem_ss` name (the original bank-owned design
replaced in place - no `_v2` in the tree). The throughput benchmark is retargeted
to the new subsystem; full `axi-smoke` regression green.**

## 1. Requirements (as specified)

R1. The memory subsystem is responsible for storing and retrieving data for
    multiple initiators.

R2. It consists of multiple SRAM banks/slices. The count is parameterizable;
    set to **8** for this redesign.

R3. The slices are used in an **interleaved** manner.

R4. Each slice is **64-bit** wide (preferably parameterizable; 64-bit is
    acceptable for now).

R5. The memory subsystem supports both **32-bit and 64-bit initiators**.

R6. Each initiator connects through a **dedicated port** (or multiple ports if
    the initiator has separate read/write channels).

R7. From the memory subsystem's perspective there is **no difference whatsoever
    between the ports** (nor the initiators driving them).

R8. Buffer registers are required inside the memory subsystem, especially around
    the SRAM slices, to **break the timing path** (timing closure) and to provide
    **elasticity**.

R9. All arbitration is **fair round-robin**.

R10. Internally the memory subsystem uses a **simple bus** structure (not full
     AXI) that still supports **two-way handshaking** and **backpressure**.

R11. **No requests or responses may ever be dropped** by the memory subsystem.

R12. Requests from initiators that do **not** support out-of-order responses must
     be returned **guaranteed in-order**.

R13. **No initiator may ever be starved.** (Guaranteed by the fair round-robin
     arbitration of R9.)

## 2. Clarifications (resolved with maintainer)

C1 (R4/R5/R7). Addresses are always **32-bit**. Ports come in **two types** — a
   32-bit-data type and a 64-bit-data type — each with a **parameterizable
   count** (`NumPorts32`, `NumPorts64`). A 32-bit access targets one 32-bit half
   of a 64-bit slice word, selected from `addr[2]`; writes use byte-enables.

C2 (R12). Start with **always in-order** delivery, with a per-port
   **`allows_ooo`** flag as a future hook (no OOO delivery built yet).

C3 (R8). Outstanding/buffer depth is **parameterizable, default 2**. Each port
   has **both** an in-order **ingress** (request) buffer and an in-order
   **egress** (response) buffer.

C4/C5 (R10/R11). Full two-way handshaking on both channels. Every request — read
   or write — returns a response (read data, write ack, or error). A
   **default/error responder** returns an `err` response for any out-of-range
   address (mapped to an AXI error outside the subsystem); never dropped.

C6 (R7). The UART-SRAM-loader and iDMA ports are **generic ports**, identical to
   all others.

C7 (R3). **64-bit-word interleaving**: 64-bit word *i* lives in bank *i* mod
   `NumBanks`. A 32-bit initiator therefore hits the **same** 64-bit slice
   **twice** (lanes `addr[2]`=0 then 1) on consecutive 32-bit addresses before
   advancing to the next slice.

C8 (R12/R13). **Head-of-line blocking is accepted** for now (only the ingress
   head is arbitrated; a port's stalled head holds its later requests). Because
   the current initiators do not natively support OOO responses anyway, this
   costs nothing real today. Round-robin guarantees no starvation (R13). The
   future `allows_ooo` path is where bypass + reorder would live.

C9 (R8). Timing closure via **one register at the slice input and one at the
   slice output**, implemented as **1-deep elastic buffers** (1-deep FIFOs)
   where practical, so they also carry the two-way handshake.

## 3. Port interface

One parameterized simple-bus port, instantiated `NumPorts32` times at
`DataWidth=32` and `NumPorts64` times at `DataWidth=64`. Per port:

Request channel (initiator -> subsystem), `req`/`gnt`:
- `req`, `gnt`, `we`, `addr` (32-bit byte address), `wdata` (32/64), `be` (4/8)

Response channel (subsystem -> initiator), `rvalid`/`rready`:
- `rvalid`, `rready`, `rdata` (32/64), `err` (1 = out-of-range)

Static per-port attribute: `allows_ooo` (future; when set, the egress reorder
buffer is replaced by a plain FIFO and responses may return out of order).

## 4. Internal architecture

```
        ingress FIFO      per-bank RR arbiter    slice in/out 1-deep      egress FIFO
 init ->[req queue]--+--> ( bank 0 )------------> [reg]->slice0->[reg] -+->[rsp queue]-> init
 (port) in-order, d=2|    ( bank 1 )------------> [reg]->slice1->[reg]  |  in-order, d=2
                     +--> ( ...    )                                    |
                     +--> ( bank 7 )------------> [reg]->slice7->[reg] -+
                     +--> ( error / default responder )-----------------+
```

- **Ingress buffer** (per port, in-order FIFO, depth `IngressDepth`=2). `gnt =
  !full`. Only the head is arbitrated -> per-port request order preserved.
- **Address decode.** word `W = (addr-BaseAddr)>>3`; bank `= W % NumBanks`;
  in-bank word `= W / NumBanks`; 32-bit lane `= addr[2]`. Out-of-range -> error
  responder.
- **Per-bank fair round-robin arbiter** (R9/R13). Among ports whose head targets
  this bank **and** whose egress reorder buffer has a free slot, pick one fairly;
  advance the RR pointer so no port is starved.
- **Slice pipeline (elastic).** Per bank: an input buffer, the registered-read
  SRAM slice, and an output buffer. The input/output buffers are parameterizable
  FIFOs (default depth 1) - the R8 timing-break stages - and they backpressure
  (slave upstream, master downstream). The non-stallable SRAM read is applied
  only when the output FIFO has room to catch the result.
- **Lane select.** For a 32-bit port, the requested 32-bit half is selected from
  the 64-bit slice word on the way into egress (reads); writes expand the 32-bit
  lane + 4-bit BE into the 64-bit word at the slice input.
- **Egress reorder buffer** (per port, depth `EgressDepth`=2). A slot is allocated
  in request order at grant and its index tags the request; the completing
  response (from any bank, any time) fills its reserved slot; the buffer delivers
  slots in order. For an `allows_ooo` port this is a plain FIFO instead.

### Never-drop (R11) — by backpressure, no credit counters
Every buffer is elastic: full -> backpressure upstream, and it honours downstream
backpressure (slave upstream, master downstream). A request is granted only when
the target bank can accept it **and** the port's egress reorder buffer has a free
slot; otherwise the port is simply not granted. The non-stallable SRAM read lands
in the bank's output FIFO (a read is applied only when that FIFO has room).
Backpressure propagates end to end, so nothing is dropped - requests wait in the
ingress buffer, responses always have a reserved egress slot. No credit counters;
the gating is just the buffers' own full/empty.

### In-order (R12) — by the egress reorder buffer
A slot in the port's egress reorder buffer is allocated, in request order, when a
request is granted, and its index rides with the request as a tag through the
bank pipe. When the response completes - from any bank, at any time - it is
written into its reserved slot; the buffer delivers slots in allocation (=
request) order, waiting for the head slot to fill. In-order is therefore
independent of which bank finishes first: the bank pipes may be variable-latency
(elastic) and the error responder needs no latency matching. For an initiator
that accepts out-of-order responses (`allows_ooo`), the reorder buffer is
replaced by a plain FIFO.

### No starvation (R13)
Per-bank round-robin advances its pointer past the winner each grant, so every
contending port is served within at most `NumPorts` arbitration rounds per bank.

## 5. Consequences to note (not open questions)

- **Latency.** The two slice timing-break stages put bank read latency at roughly
  request-reg -> slice-read -> output-reg = ~3 cycles, plus ingress/egress FIFO
  stages. With the default outstanding depth of 2, sustained per-port throughput
  is therefore ~depth / latency. This is the deliberate
  correctness/timing-vs-throughput trade; raising the per-port depth (a
  parameter) toward the latency is how an initiator that supports more
  outstanding requests reclaims ~1 access/cycle. Aggregate cross-port throughput
  still scales with the number of active ports / banks. **Measured** by the
  retargeted `mem-ss-bench` (default depths): a single disjoint port sustains
  ~0.33 access/cycle (so the round-trip is ~6 cycles), scaling **linearly** to
  ~0.66 / ~1.33 at 2 / 4 disjoint ports, while same-bank traffic stays pinned at
  one slice's ~0.33 no matter how many ports drive it - exactly the multi-bank
  concurrency the redesign targets.
- **The latency lever is deferred but identified.** Reclaiming ~1/cycle is a
  later, separate task: it needs the initiator to issue more outstanding
  requests. For example Ibex's instruction-fetch unit has a lower-level option
  to increase the number of outstanding fetches (not exposed at the top-level
  parameter list), and the other cores likely expose something similar. Not in
  scope for this redesign.

## 6. Open questions

None outstanding - design is ready to implement.

## 7. Implementation plan

Build and verify standalone, then integrate (maintainer-approved order).

Module decomposition (new modules, alongside the existing `soc_mem_ss` until the
swap):

- `soc_mem_bank.sv` - one per bank. An **elastic** pipeline: input buffer ->
  registered-read SRAM slice -> output buffer, where the buffers are
  parameterizable FIFOs (default depth 1) that backpressure both ways, and a read
  is applied only when the output FIFO has room. Carries per-request metadata
  `{port_id, slot_id, lane, we}` from input to output so the response can be
  routed to the owning port's reorder-buffer slot and lane-selected. Latency may
  vary (the egress reorder buffer owns ordering, not this pipe).
- `soc_mem_port.sv` - one per port (instantiated `NumPorts32` at width 32,
  `NumPorts64` at width 64). Ingress FIFO (in-order, backpressures the initiator),
  egress **reorder buffer** (slot allocated in request order at grant; response
  drops into its tagged slot; drains in order; `allows_ooo` -> plain FIFO),
  32<->64 lane expand/select, address decode, and a local out-of-range error
  responder (fills its reorder slot directly - no latency matching needed).
- `soc_mem_ss` (new top) - instantiate ports + banks; one **fair round-robin
  arbiter per bank** (reuse `common_cells/rr_arb_tree`) over the ports whose
  ingress head targets that bank and hold egress credit; a request crossbar
  (port head -> target bank) and a response crossbar (bank output -> owning port,
  <=1 per port per cycle by construction).

Reuse from `common_cells`: `fifo_v3` (buffers), `rr_arb_tree` (fair RR).

Standalone verification (before any SoC integration): extend the `mem-ss-bench`
harness to drive 32- and 64-bit ports, and assert the hard guarantees directly -
never-drop (the existing-style assertion), in-order delivery, no starvation under
sustained contention, two-way backpressure on both channels, and error responses
for out-of-range addresses.

## 8. Changelog

- Initial requirements captured from maintainer specification.
- Clarifications C1-C6 folded in; port interface and internal architecture
  proposed.
- C7-C9 resolved; R13 (no starvation) added; slice timing-break stages and the
  latency/throughput consequence pinned down. Design finalized.
- Implementation plan + module decomposition added; Ibex IFU outstanding-fetch
  note recorded as the deferred latency lever; the earlier `improve/fabric`
  throughput changes reverted to start from clean state.
- RTL started: `rtl/mem/soc_mem_bank.sv` (first cut). Superseded design point
  below.
- Design corrected per maintainer: **no credit accounting** - every buffer is a
  plain elastic stage (slave upstream / master downstream) that backpressures
  when full. Per-port egress is a **reorder buffer** (option b): slot allocated
  in request order, response drops into its tagged slot, drains in order; a future
  `allows_ooo` port uses a plain FIFO instead. Consequences: the bank pipe is
  **elastic / variable-latency** (not fixed-latency) and the error responder
  needs no latency matching - the reorder buffer owns ordering. Slice input/output
  buffers are parameterizable FIFOs (default depth 1). `soc_mem_bank.sv` to be
  rebuilt elastic with a `slot_id` tag; then `soc_mem_port.sv` (ingress FIFO +
  egress reorder buffer), the top (fair-RR arbiter + crossbars), then the TB.
- RTL complete and lint-clean: `rtl/mem/soc_mem_bank.sv` (elastic), `soc_mem_port.sv`
  (ingress FIFO + egress reorder buffer + lane/decode/local error), `soc_mem_ss_v2.sv`
  (top: per-bank `rr_arb_tree` + request/response crossbars; the response crossbar
  arbitrates per port so two banks finishing for one port in a cycle backpressure
  rather than collide).
- **Standalone verification PASSES** (`tb/tb_mem_ss_v2.sv`, self-checking, Verilator
  `--binary`): 4 concurrent ports (2x32-bit + 2x64-bit), ~16k accesses/seed, random
  per-port backpressure, out-of-range errors, FIFO scoreboards. Verifies never-drop +
  correctness, in-order delivery, two-way backpressure, error responses, and
  no-starvation (all scoreboards drain, no timeout). Passes on 3 seeds.
- Integration findings (soc_top): the old `soc_mem_ss` has 7x 64-bit init ports with a
  `tag`/`rtag` that is **tied to 0** (unused) - so dropping the tag is safe. It also
  takes a `MemInitPath` simulation preload (loads the slices via the slice models);
  the new subsystem needs an equivalent preload hook before hello_world can run.
  Open integration choice: keep all 7 clients 64-bit (via the existing
  `soc_obi_to_mem` bridges) vs. wire the two RV32 CPU OBI ports as native 32-bit
  ports (drop their bridges). Pending maintainer preference.
- **Integrated into `soc_top` (option A, native 32-bit CPU ports).** The two RV32
  CPU OBI RAM ports now drive native 32-bit memory ports (the subsystem does the
  lane select; the `soc_obi_to_mem` bridges are gone); the xbar R/W, UART loader,
  and iDMA R/W stay on five 64-bit ports. Config `NumPorts32=2, NumPorts64=5`. The
  `tag`/`rtag` (was tied to 0) is dropped. Preload hook added to `soc_mem_bank`
  (`MemInitPath`/`BankId` -> per-bank `bank_<n>.hex`, same interleaving as before).
- **Slice-latency fix:** the Xilinx byte cell is a **2-cycle** registered read vs.
  the model's 1 cycle; `soc_mem_bank` now delays valid+metadata by a
  `MemImpl`-derived `ReadLat` so the response carries the right request. Verified
  on both paths standalone (16k accesses each).
- **SoC regression PASSES with the new subsystem:** `hello_world` on ibex (Xilinx
  SRAM), cv32e40p, cv32e40s, serv, picorv32; `self_check`; `dma_smoke` (iDMA 64-bit
  ports); `debug-sim` (SBA/debug, 2/2). No drops, overflows, or assertion failures.
- **Full `make axi-smoke` regression green** (exit 0): all groups pass, incl.
  `test_uart_sram_loader` (loader 64-bit port), `mem_ss_bench`, `debug_integration`
  (2/2), PLIC (5/5), and every `run_soc_software`.
- **Cleanup pass (canonical name, no `_v2`):** renamed `soc_mem_ss_v2` ->
  `soc_mem_ss`, replacing the original bank-owned module in place (TB ->
  `tb/tb_mem_ss.sv`); removed the dead `rtl/bus/soc_obi_to_mem.sv`; retargeted
  `mem-ss-bench` to the new subsystem (64-bit port group, multi-outstanding,
  `NumPorts32 = 0`) and recalibrated its cocotb throughput floors to the measured
  default-depth profile - a single disjoint port ~0.33 access/cycle, scaling
  linearly to ~1.33 at 4 ports, same-bank pinned at ~0.33 (the scaling-*ratio*
  assertions are unchanged). Added a zero-sized-port-group width floor
  (`Np32`/`Np64` + tie-offs) so an all-one-width config elaborates without a
  `[-1:0]` range. Re-verified: standalone `tb_mem_ss` PASSES on both slice models
  (16096 acc. each), `mem-ss-bench` PASSES (1/1), and `make axi-smoke` is green
  again (exit 0, all 12 groups).

## 9. Follow-ups

Done in the cleanup pass (no version-suffixed files left in the tree):

- Renamed `soc_mem_ss_v2` -> `soc_mem_ss`, replacing the original bank-owned
  module in place; TB renamed `tb/tb_mem_ss.sv`. Manifests (`corejack.core`,
  `Bender.yml`) updated; `soc_top` instantiates the canonical name.
- Removed the now-unused `rtl/bus/soc_obi_to_mem.sv` (option A's native 32-bit
  ports made the OBI->mem bridge dead) from the tree and both manifests.
- Retargeted `mem-ss-bench` to the new subsystem: the bench DUT drives the
  64-bit port group, multi-outstanding (request held until the budget is issued,
  throttled by req/gnt), with `NumPorts32 = 0`. Added the `common_deps` fileset
  and `-Wno-PINMISSING` to the fusesoc target (the new subsystem pulls in
  common_cells). Recalibrated the cocotb throughput floors to the new design's
  profile (the scaling-ratio assertions are unchanged; only the absolute floors
  moved, since per-bank rate is ~0.33 not ~1.0 access/cycle).
- Hardened `soc_mem_ss` for a zero-sized port group: a `Np32`/`Np64` width floor
  plus tie-offs so `NumPorts32 == 0` (or `NumPorts64 == 0`) elaborates without a
  `[-1:0]` reversed range.

Still open:

- Throughput/latency lever (deferred, see Section 5): raise per-port outstanding
  depth + core IFU outstanding-fetch options.
