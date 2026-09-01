# AXI4 Fabric Migration

This document records the migration path that moved the CoreJack platform to an
AXI4-native central fabric. It is historical: the single-outstanding arbiter +
demux stage described below was itself later replaced by a PULP `axi_xbar`
system crossbar. The current supported architecture is documented in
[AXI4 fabric](axi4_fabric.md).

## Direction

The long-term SoC fabric boundary should be AXI4-native:

- use AXI4 as the central SoC interconnect protocol
- keep APB for simple low-bandwidth peripherals such as UART
- connect 32-bit OBI-style core sockets through OBI-to-AXI adapters
- connect AXI-native cores and IP directly where practical
- keep core-local quirks inside core wrappers or core-region adapters
- keep board wrappers limited to board clocking, reset, FPGA primitives, and
  pinout adaptation

The current 32-bit embedded cores still expose 32-bit instruction and data
interfaces at the platform socket. Those interfaces remain valid core-facing
contracts. Width and protocol adaptation belongs below that socket boundary.

## Memory Width

The shared SRAM path is moving to 64-bit words. This is the baseline width for
future 64-bit cores and AXI-native memory integration.

Current 32-bit cores access the 64-bit SRAM through a local width adapter:

- request byte address bit `[2]` selects the low or high 32-bit lane
- write data and byte enables are shifted into the selected 32-bit lane
- the response lane select is carried with the accepted request
- the core still receives a 32-bit response word

This keeps the existing RV32 software and debug flow working while avoiding a
future memory-system rewrite when an RV64 core is added.

## Preload Format

Simulation preload files must match the SRAM data width. For the 64-bit SRAM
path each `bank_N.hex` line contains one 64-bit word:

```text
bank = word64_index % NumBanks
```

The software build system emits this format.

## Migration Stages

1. Use 64-bit SRAM internally while preserving the existing 32-bit core socket.
2. Done: introduce explicit OBI-to-AXI and AXI-to-memory/peripheral adapters.
3. Done: replace the local memory/peripheral arbitration in `soc_top` with an AXI4
   interconnect.
4. Add AXI-native core/IP integration, starting with components that already
   expose compatible AXI ports.
5. Keep the FPGA debug acceptance flow as the support gate for each
   core/board combination.

## Current Adapter Baseline

The repository includes adapter RTL for the first AXI migration steps:

- `soc_obi_to_axi`: converts the current 32-bit OBI-like core socket contract
  into single-beat AXI4 transfers on the 64-bit platform AXI type
- `soc_axi_to_mem`: converts single-beat AXI4 reads and writes into the current
  SRAM request/response contract
- `soc_axi_demux`: decodes AXI addresses into explicit RAM, UART, and debug
  targets
- `soc_axi_to_apb`: converts single-beat AXI4 accesses into APB peripheral
  accesses for the UART
- `soc_axi_to_dm`: converts single-beat AXI4 accesses into the `riscv-dbg`
  debug-memory slave interface

The initial adapters intentionally support one outstanding transfer and
single-beat AXI transactions. This matches the current SRAM/debug use case and
keeps the correctness surface small.

The main `soc_top` RAM path now routes the instruction, data, and debug SBA
initiators through these adapters and a shared AXI arbitration point before
reaching the SRAM subsystem. The SRAM subsystem is therefore reached through one
AXI-to-memory target instead of through one memory adapter per initiator.

Non-RAM traffic now also enters the shared AXI fabric. The explicit address map
routes:

- RAM at `RamBaseAddr`
- UART at `UartBaseAddr` through the AXI-to-APB bridge
- the debug memory window at `DebugBaseAddr` through the AXI-to-DM bridge

The current AXI arbiter is intentionally scoped to the active platform use case:
single-beat accesses from the existing OBI-to-AXI adapters into one shared AXI
demux. It should be replaced or widened when AXI-native initiators require
bursts or richer outstanding transaction behavior.

Run the focused adapter regression with:

```bash
make axi-adapter-sim
```

The test covers 32-bit lane selection on a 64-bit AXI word, write strobes,
response backpressure, and error propagation.
