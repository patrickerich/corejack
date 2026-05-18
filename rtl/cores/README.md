# Core Adapters

CoreJack should make RISC-V core swaps happen here, not in board wrappers.

The intended pattern is:

1. keep each concrete core in its own adapter module under `rtl/cores/`
2. translate that core's native instruction/data/debug/interrupt ports to the
   platform-visible contract used by `soc_top`
3. keep FPGA board wrappers focused on clocking, reset release, vendor
   primitives, constraints, and pins

The current concrete adapter is:

```text
rtl/cores/corejack_ibex_socket_adapter.sv
```

It wraps the vendored Ibex top and exposes simple instruction and data request
channels to the CoreJack memory/peripheral path. This adapter is now validated
on the AXKU5 FPGA baseline with SRAM, UART, and `riscv-dbg`.

Future adapters should follow the same boundary even if the core's native bus
is AXI, OBI, TileLink, or a custom local interface.

When a second core is added, the expected flow is:

- add `rtl/cores/corejack_<core>_socket_adapter.sv`
- add the source files/dependencies to `Bender.yml` and `corejack.core`
- add or parameterize the `soc_top` instantiation point
- keep `rtl/platform/fpga/boards/*/*_wrap.sv` board-specific only

Near-term candidate cores:

- SERV, to exercise an extremely small core integration.
- CV32E40P, to add a PULP-family embedded core with a practical debug/software path.
- CVA6, to force the larger AXI/cache/memory-system questions deliberately.

Longer term, each core should have a small descriptor such as
`cfg/cores/<core>.yaml` that records its adapter, dependency/source selection,
bus protocol, reset/boot/debug expectations, ISA/toolchain defaults, and any
known FPGA clock guidance.
