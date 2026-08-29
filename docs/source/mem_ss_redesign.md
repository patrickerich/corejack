# Memory Subsystem Redesign

Living specification for the `soc_mem_ss` redesign. Requirements are owned by
the project maintainer; this document records them as stated and tracks the
design decisions that follow. Update it as the design evolves.

Status: **implemented and integrated into `soc_top` (option A, native 32-bit CPU
ports); promoted to the canonical `soc_mem_ss` name, replacing the original
bank-owned design in place. Verified standalone and in the SoC simulation
regressions; the `mem-ss-bench` throughput benchmark targets the new subsystem.
Running at 8 banks with the outstanding depths sized so neither a port nor a bank
caps below ~1 access/cycle.**

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
  !full`. Only the head is arbitrated -> per-port request order preserved. Depth
  2 is enough to sustain one grant per cycle; the outstanding count is bounded by
  the egress reorder buffer, not by this FIFO.
- **Address decode.** word `W = (addr-BaseAddr)>>3`; bank `= W % NumBanks`;
  in-bank word `= W / NumBanks`; 32-bit lane `= addr[2]`. Out-of-range -> error
  responder.
- **Per-bank fair round-robin arbiter** (R9/R13). Among ports whose head targets
  this bank **and** whose egress reorder buffer has a free slot, pick one fairly;
  advance the RR pointer so no port is starved.
- **Slice pipeline (elastic).** Per bank: an input buffer, the registered-read
  SRAM slice, and an output buffer. The input/output buffers are parameterizable
  FIFOs (`SliceInDepth`=2, `SliceOutDepth`=4) - the R8 timing-break stages - and
  they backpressure (slave upstream, master downstream). The non-stallable SRAM
  read is applied only when the output FIFO has room to catch the result. Both
  depths are sized so a bank accepts a request every cycle: the output side must
  hold `ReadLat + 2` claims to cover issue -> read -> drain, and the input side
  must be at least 2 because a depth-1 `fifo_v3` blocks its push while full.
- **Lane select.** For a 32-bit port, the requested 32-bit half is selected from
  the 64-bit slice word on the way into egress (reads); writes expand the 32-bit
  lane + 4-bit BE into the 64-bit word at the slice input.
- **Egress reorder buffer** (per port, depth `EgressDepth`=8). A slot is allocated
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

- **Latency is covered by depth, not removed.** The two slice timing-break
  stages put bank read latency at roughly request-reg -> slice-read ->
  output-reg, and the full reorder-buffer slot round trip - grant to slot
  release - is `ReadLat + 4` cycles (5 on the model slice, 6 on the 2-cycle
  Xilinx cell). Latency is a deliberate correctness/timing choice and stays; what
  the depths buy is the ability to keep enough requests in flight to hide it.
  Two independent ceilings follow, and both defaults are sized to ~1 access per
  cycle:
  - a **port** sustains `EgressDepth / (ReadLat + 4)` -> `EgressDepth` = 8;
  - a **bank** sustains `SliceOutDepth / (ReadLat + 2)` -> `SliceOutDepth` = 4,
    with `SliceInDepth` = 2 so the input FIFO can push and pop in the same cycle.

  **Measured** by `mem-ss-bench` at these defaults: a single disjoint port
  sustains **0.98 access/cycle**, scaling **linearly** to 1.95 / 3.91 at 2 / 4
  disjoint ports, while same-bank traffic is pinned at one slice's **0.99** no
  matter how many ports drive it - the multi-bank concurrency the redesign
  targets, now with the per-slice rate at the useful ceiling rather than a third
  of it. Writes match reads (3.91 at 4 ports). A random pattern reaches 2.72 at
  4 ports; the shortfall is genuine bank collision, not a subsystem limit.
- **The remaining lever is on the initiator side.** The subsystem no longer
  throttles anyone, so reclaiming that ~1 access/cycle in a real workload now
  depends on the *initiator* issuing enough outstanding requests. Ibex's
  instruction-fetch unit, for example, has a lower-level option to increase the
  number of outstanding fetches that is not exposed at its top-level parameter
  list, and the other cores likely expose something similar. Changing that means
  editing vendored core RTL and is deliberately not done here.

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
- Standalone self-checking testbench (`tb/tb_mem_ss.sv`, Verilator): 4 concurrent
  ports (2x32-bit + 2x64-bit) with random per-port backpressure, out-of-range
  errors, and per-port FIFO scoreboards, exercising never-drop + correctness,
  in-order delivery, two-way backpressure, error responses, and no-starvation.
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
- Verified in the SoC simulation regressions (`hello_world` across the supported
  cores, `self_check`, `dma_smoke`, `debug-sim`, the UART SRAM loader, and the
  retargeted `mem-ss-bench`) via `make axi-smoke`.
- **Cleanup pass (canonical name, no `_v2`):** renamed `soc_mem_ss_v2` ->
  `soc_mem_ss`, replacing the original bank-owned module in place (TB ->
  `tb/tb_mem_ss.sv`); removed the dead `rtl/bus/soc_obi_to_mem.sv`; retargeted
  `mem-ss-bench` to the new subsystem (64-bit port group, multi-outstanding,
  `NumPorts32 = 0`) and recalibrated its cocotb throughput floors to the measured
  default-depth profile - a single disjoint port ~0.33 access/cycle, scaling
  linearly to ~1.33 at 4 ports, same-bank pinned at ~0.33 (the scaling-*ratio*
  assertions are unchanged). Added a zero-sized-port-group width floor
  (`Np32`/`Np64` + tie-offs) so an all-one-width config elaborates without a
  `[-1:0]` range. Re-verified standalone on both slice models and via
  `mem-ss-bench` and `make axi-smoke`.
- **Throughput lever taken; bank count raised to the port count.** The default
  depths now cover the pipeline round trip on both slice models -
  `EgressDepth` 2 -> 8 (port ceiling), `SliceOutDepth` 1 -> 4 and `SliceInDepth`
  1 -> 2 (bank ceiling) - superseding the "default depth 2 / 1-deep slice
  buffers" of C3/C9, and `soc_top.MemNumBanks` went 4 -> 8 to match the seven
  ports driving the subsystem (`sw/Makefile NUM_BANKS` follows). Measured effect:
  a single port 0.33 -> 0.98 access/cycle, same-bank 0.33 -> 0.99, 4-port
  disjoint 1.33 -> 3.91. Re-verified by `tb/tb_mem_ss.sv` on both slice models at
  the shipping depths and by `make axi-smoke`.
- **Bank count reduced to one literal.** `mem_ss_pkg::MemNumBanksDefault` is now
  the single source of truth: `soc_top.MemNumBanks` defaults to it, and
  `sw/Makefile` derives its `NUM_BANKS` hex-split width from the same constant
  through `bin/validate_target.py --mem-num-banks` instead of restating it. This
  follows the existing `platform_pkg::core_type_e` -> `CORE_TYPE` precedent, and
  covers the simulation and FPGA paths with one mechanism because both take the
  `soc_top` default. `bin/tests/test_descriptor_tools.py` guards against a
  literal creeping back into either consumer.

## 9. Follow-ups

Still open:

- **Initiator-side outstanding requests** (see Section 5): the subsystem
  sustains ~1 access/cycle per port. For the iDMA this is now realized -
  `soc_axi_to_mem` was pipelined and `NumAxInFlight` raised to match, reaching
  ~85% of that ceiling (see [`axi4_fabric.md`](axi4_fabric.md)). For the CPUs
  the gap remains and is a core limit: the IFU outstanding-fetch options are
  vendored-RTL changes and are not taken here.
- **Per-board bank counts:** the count is now a single constant
  (`mem_ss_pkg::MemNumBanksDefault`), which removes the drift risk but keeps it
  global. Making it vary per board still needs the vlogparam plumbing through
  the FPGA wrapper and the simulation DUT - see [`roadmap.md`](roadmap.md) -
  and stays deferred until a second value is worth supporting.
