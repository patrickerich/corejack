# RISC-V Debug Integration Guide

This document describes the expected `riscv-dbg` integration pattern for the
CoreJack SoC. It is intended to be a stable design guide, not a debug log.

The current FPGA baseline uses:

- `dmi_jtag` as the external JTAG-to-DMI transport
- `dm_top` as the RISC-V debug module
- Ibex as the hart
- a core-visible debug memory window
- the debug module System Bus Access, or SBA, master port for memory/peripheral
  access while the hart is halted or reset

## Integration Model

Keep debug transport, debug module, hart, and SoC fabric responsibilities
separate:

- Board wrappers own physical JTAG pins, clock buffers, reset adaptation, and
  constraints.
- `dmi_jtag` converts the external JTAG Debug Transport Module protocol into
  DMI requests and responses.
- `dm_top` implements the debug module, debug ROM, abstract command support,
  program buffer support, and SBA master.
- The hart receives `debug_req_o` from `dm_top` and fetches debug ROM code from
  the SoC debug memory window.
- The SoC fabric routes core instruction/data traffic and SBA traffic to RAM,
  UART, debug memory, or an error response.

Do not reset the debug module with hart reset. The debug module must remain
available when the hart is in `ndmreset`, otherwise a debugger cannot reliably
program memory, inspect state, or release the hart.

## Address Map

The SoC must expose a debug memory window that is visible to the hart
instruction and data ports. The hart debug address parameters must match this
window:

- `DmHaltAddr`: debug halt entry address
- `DmExceptionAddr`: debug exception entry address

For the current CoreJack integration, the debug window is located at
`DebugBaseAddr`, and the halt/exception entry points are:

```text
DmHaltAddr      = DebugBaseAddr + 0x800
DmExceptionAddr = DebugBaseAddr + 0x810
```

The halt, resume, and exception flag offsets used inside the debug memory come
from `dm_pkg`:

- `dm::HaltAddress`
- `dm::ResumeAddress`
- `dm::ExceptionAddress`

`dm_top.DmBaseAddress` is not the same thing as the SoC decode base in this
integration. It is consumed by `dm_mem` when generating debug ROM behavior. Keep
the SoC-visible decode window and the hart debug address parameters aligned, and
set `dm_top.DmBaseAddress` deliberately for the selected `riscv-dbg`
configuration.

## Hart Info

`dm_top` needs a correct `HartInfo` structure for the selected core. For the
current Ibex integration:

- `nscratch` is `2`
- Ibex implements `dscratch0` and `dscratch1`
- `dataaccess` is enabled
- `datasize` and `dataaddr` match the `riscv-dbg` package constants

The debug ROM mode and the number of scratch CSRs must agree with the hart
implementation. A mismatch can lead to debug ROM execution failures even when
JTAG enumeration succeeds.

## Debug Memory Timing

The hart enters debug mode by fetching instructions from the debug memory window.
This path is latency tolerant, but each accepted request must be tracked until
exactly one matching response is returned.

Required sequence:

1. `dm_top` asserts `debug_req_o`.
2. The hart redirects instruction fetch to `DmHaltAddr`.
3. The core-side request is converted into an AXI transaction.
4. The AXI fabric decodes the address into the debug target window.
5. The AXI-to-DM bridge asserts `dm_top.slave_req_i` with the address offset
   relative to the debug window base.
6. For reads, the bridge captures the registered `dm_top.slave_rdata_o` value
   after presenting the slave request.
7. The bridge returns the AXI response, and the OBI-side adapter returns
   `rvalid` to the original requester.

The important rule is:

```text
accepted debug-window requests must remain ordered until their response returns
```

Do not drop the accepted request context while traversing fabric stages. The
requester, address lane, and read/write attributes must remain associated with
the eventual response. Symptoms of broken ordering include OpenOCD being able to
enumerate the target but failing to halt the hart or read registers during GDB
attach.

Also do not return `dm_top.slave_rdata_o` in the same cycle that
`dm_top.slave_req_i` is first asserted. The debug memory read data is registered;
return the response to the hart or SBA master after the registered read data is
available.

## Request Arbitration

The debug memory window can be accessed by:

- hart instruction fetch
- hart data access
- debug module SBA access

The fabric must accept at most the number of outstanding debug-window accesses
that the downstream bridge can track and must return exactly one response per
accepted request.

The current platform routes instruction, data, and SBA initiators through
OBI-to-AXI adapters, a shared AXI arbiter, explicit AXI address decode, and the
AXI-to-DM bridge. If this logic grows or becomes more contended, replace the
current small arbiter with a wider starvation-free
policy.

## SBA Integration

The `dm_top.master_*` port is an independent SoC bus master. Treat SBA like any
other initiator:

- `master_req_o` remains asserted until `master_gnt_i`
- writes complete after grant and response
- reads complete when `master_r_valid_i` is asserted
- bus errors are reported through `master_r_err_i`
- access width, byte enables, and address alignment must be honored

SBA must be able to access RAM while the hart is held in `ndmreset`. This is
what allows GDB/OpenOCD to load an ELF into RAM before releasing the hart.

In the current CoreJack integration:

- SBA is a third AXI fabric initiator after OBI-to-AXI adaptation.
- SBA can access RAM, UART, debug memory, and invalid addresses through the
  same explicit AXI decode path used by core data/instruction traffic.
- The SRAM and fabric reset are driven by platform reset, not by `ndmreset`.

## Reset Requirements

Use separate reset domains intentionally:

- `dm_top.rst_ni`: platform/debug-module reset
- hart/core reset: platform reset gated by `ndmreset_o`
- SRAM/fabric reset: platform reset only

`ndmreset_o` should reset only the non-debug hart side. It must not reset the
debug module, DMI path, SRAM, or the fabric required for SBA.

`ndmreset_ack_i` should indicate completion of an `ndmreset`-initiated hart
reset. For the current `riscv-dbg` version, generate this as a pulse when the
core reset sequence has completed. Do not tie it permanently to a reset-done
level; doing so can repeatedly reassert reset-status state in the debug module.

If `dmi_jtag.dmi_rst_no` is used, connect it deliberately to the DMI-facing
debug reset path. If it is left unused, document why the DMI reset behavior is
still correct for the platform.

## OpenOCD And GDB Flow

The expected debugger flow is:

1. OpenOCD connects to the external JTAG transport.
2. OpenOCD enumerates the RISC-V DTM and debug module.
3. GDB connects to OpenOCD.
4. GDB/OpenOCD halts or resets and halts the hart.
5. GDB loads the ELF through the debug module memory access path.
6. GDB sets the PC to the ELF entry point.
7. GDB resumes execution.

The CoreJack helper scripts follow this shape:

```text
target extended-remote localhost:3333
monitor reset halt
load
set $pc = (unsigned int)&_entry_point
continue
```

For RAM-resident FPGA firmware, set the PC to the linker-defined entry symbol,
not to the reset vector word and not to the value stored at the entry address.

## Validation Checklist

Minimum simulation checks:

- Debug memory access returns the expected instruction word for a fetch at
  `DmHaltAddr`.
- A core debug-window request reaches `dm_top.slave_req_i` through the AXI
  fabric with the expected debug-window offset address.
- The core receives `rvalid` and the registered debug memory data after the
  AXI-to-DM bridge captures the read data.
- SBA can write and read RAM while the hart is held in reset.
- Invalid SBA and core accesses complete with an error response rather than
  hanging.

Minimum hardware checks:

- OpenOCD enumerates the TAP and examines the RISC-V target.
- GDB can connect and read registers.
- GDB can load an ELF into SRAM.
- The hart starts from the expected ELF entry point.
- UART output or another externally visible side effect confirms software
  execution.

## Common Failure Modes

OpenOCD can enumerate the target but GDB cannot halt or read registers:

- Check the debug memory request/response ordering.
- Confirm the hart fetches from `DmHaltAddr`.
- Confirm `dm_top.slave_req_i` sees the expected debug-window offset address.
- Confirm the response is returned to the original requester after the
  registered `dm_top.slave_rdata_o` value is available.

ELF loading fails or memory reads return errors:

- Check the SBA master path.
- Confirm RAM and fabric are not reset by `ndmreset`.
- Confirm `master_gnt_i`, `master_r_valid_i`, and `master_r_err_i` obey the
  `riscv-dbg` contract.

The hart traps immediately after loading software:

- Confirm the PC is set to the ELF entry symbol.
- Confirm FPGA builds do not execute simulation-only MMIO writes.
- Confirm the linked memory map matches the hardware RAM and peripheral map.

UART output is corrupted while debug works:

- Confirm the hardware clock used by the UART matches the software platform
  constant.
- Confirm the terminal baud rate matches the UART divisor configuration.
- Confirm UART register accesses use the access width expected by the UART IP.
