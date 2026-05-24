# AXI4 Fabric

The CoreJack platform uses AXI4 as the central SoC fabric. Core sockets may use
their native protocol at the core boundary, but shared memory, UART, and debug
traffic are routed through one explicit AXI address-decode path.

## Architecture

Current RV32 cores expose separate instruction and data OBI-style interfaces.
The debug module exposes a system bus access path for GDB/OpenOCD memory loads.
Inside `soc_top`, these initiators become AXI initiators:

- instruction OBI through `soc_obi_to_axi`
- data OBI through `soc_obi_to_axi`
- debug SBA OBI through `soc_obi_to_axi`

The three AXI initiators enter `soc_axi_arbiter`. The selected transaction then
enters `soc_axi_demux`, which decodes the address and routes the request to one
of the fabric targets:

- RAM through `soc_axi_to_mem`
- UART through `soc_axi_to_apb`
- debug module register/ROM window through `soc_axi_to_dm`
- CLINT through `soc_axi_to_reg`

CVA6 is integrated as a native AXI core: its initiator port enters
`soc_axi_arbiter` directly instead of going through an OBI-to-AXI adapter.

The board wrapper does not own this policy. Board wrappers only adapt clocks,
resets, FPGA primitives, and physical IO pins.

## Address Map

`soc_top` builds the active AXI decode table from its address parameters:

| Target | Parameter | Default Base | Size |
| --- | --- | ---: | ---: |
| Debug module window | `DebugBaseAddr` | `0x00000000` | `0x00001000` |
| CLINT | `ClintBaseAddr` | `0x02000000` | `0x00010000` |
| UART | `UartBaseAddr` | `0x10000000` | `0x00001000` |
| RAM | `RamBaseAddr` | `0x80000000` | `RamWords * 4` |

The decode windows are exclusive at the upper bound: `[base, base + size)`.
The static address-map check (`make axi-addr-map-check`) verifies that these
windows are non-overlapping.

## Memory Width

The shared SRAM path is 64-bit wide. This is the baseline for future RV64 cores
and AXI-native memory integration.

RV32 cores keep a 32-bit core-facing contract. The local width adaptation uses
the byte address to select the low or high 32-bit lane of a 64-bit SRAM word,
and carries that lane selection until the response returns.

Simulation preload files use one 64-bit word per line.

## Protocol Checks

Simulation builds instantiate `soc_axi_protocol_checker` on the core-side AXI
ports, the central fabric port, and the target-side AXI ports. The checker
guards the subset used by this platform:

- payload stability while `valid` is asserted and `ready` is low
- stable read and write responses while the receiver applies backpressure
- single-beat transactions only: `len == 0` and `w.last == 1`

This is not a full AXI formal proof. It is a focused regression guard for the
current single-beat fabric.

## Current Scope

The current AXI adapters intentionally support the active platform use case:

- single-beat transfers
- one accepted transfer at a time per adapter
- 32-bit core-side instruction/data access for current RV32 cores
- 64-bit AXI/memory data width inside the platform

This is sufficient for the currently supported flows: the OBI-style RV32
cores (Ibex, CV32E40P, CV32E40S) and the small core-specific adapters used
by SERV, PicoRV32, and CVW/Wally all reach RAM, UART, CLINT, and debug
through the same shared fabric, and CVA6 enters that fabric as a native
single-beat AXI initiator. AXI-native initiators with bursts or richer
outstanding behavior should use a widened fabric implementation rather than
extending these small adapters ad hoc.

### Memory throughput is fabric-limited today, not bank-limited

The shared SRAM is already banked (see `MemNumBanks` on `soc_top`, default
4, and `soc_mem_ss`'s per-bank round-robin arbiter). Three independent
initiators reach the fabric today - core instruction fetch, core data
access, and debug SBA - and each one could in principle target a different
bank. In practice they don't run in parallel against the banks: the
`soc_axi_arbiter` is single-beat and single-outstanding, so it accepts at
most one transaction at a time and the bank fan-out behind it sees no
contention. The bottleneck is the fabric width, not the bank count.

Two natural follow-ups follow from this observation, independent of
accelerator integration:

- **Widening the AXI fabric** so it can forward multiple outstanding
  requests concurrently to the demux. The bank infrastructure underneath
  is already generic in `NumBanks` and ready to receive parallel traffic.
- **Revisiting the bank count** once a wider fabric (or an additional
  initiator on `accel_socket_if`, such as the planned uDMA) starts
  exploiting bank parallelism. `soc_top.MemNumBanks` is a parameter, so
  experiments at 8 or 16 banks need only an override at instantiation;
  `sw/Makefile` already responds to a matching `NUM_BANKS` value when
  regenerating hex preload files.

## Acceptance

Run the focused adapter regression:

```bash
make axi-adapter-sim
```

Run the full AXI fabric smoke:

```bash
make axi-smoke
```

`make axi-smoke` checks:

- AXI decode windows do not overlap
- OBI-to-AXI, AXI-to-memory, AXI-to-APB, AXI-to-DM, demux, arbiter, AXI
  protocol-checker, and 32-to-64-bit lane behavior through `axi-adapter-sim`
- debug-window and SBA behavior through `debug-sim`
- `hello_world` simulation on each supported core

The default supported-core simulation set is controlled by `AXI_SMOKE_CORES`
in the Makefile and currently covers `ibex`, `cv32e40p`, `cv32e40s`, `cva6`,
`serv`, `picorv32`, and `cvw`.

FPGA acceptance remains a separate hardware gate:

```bash
make fpga-accept BOARD=<board> UART_DEV=/dev/ttyUSBx
```

Debug-capable cores use OpenOCD/GDB in that gate. Supported cores without a
RISC-V debug interface use the UART SRAM loader.

## Future Work

The AXI fabric baseline is complete for the currently supported cores
(RV32 OBI sockets, native AXI for CVA6, and the small adapters used by
SERV, PicoRV32, and CVW/Wally). Future work is separate from the migration
closure:

- stress debug SBA and memory contention more heavily
- replace or widen the arbiter/demux path when AXI-native burst initiators are
  integrated
- add stress/burst coverage for additional AXI-native cores as they are
  added
