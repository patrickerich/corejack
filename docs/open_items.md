# Open Items

A lightweight log of issues or improvements noticed during development but
deliberately **deferred** — things we decided not to solve immediately. This is
distinct from [`roadmap.md`](roadmap.md), which records intended direction;
open items are latent gaps, tech debt, or design decisions parked for later.

Add an entry when you choose not to fix something now; remove it once resolved.

## Per-board memory size has no single source of truth

A board's SRAM size is currently encoded in three places that must be kept in
sync by hand:

- `cfg/boards/<board>.yaml` &rarr; `memory.ram_bytes` — drives the bare-metal
  linker (`SOC_RAM_BYTES` &rarr; `sw/common/link.ld.in`).
- the board wrapper's `RamWords` localparam (e.g.
  `rtl/platform/fpga/boards/arty_a7_100t/corejack_arty_a7_100t_wrap.sv`) — sizes
  `soc_top` / `soc_mem_ss`.
- the per-board Zephyr devicetree `&flash0`/`&sram0` regions (e.g.
  `sw/zephyr/boards/corejack/corejack_ibex_arty_a7_100t/...dts`).

These agree today (256 KiB for Arty) only by convention and in-source comments.
Changing one without the others would silently mis-size RAM (e.g. a stack placed
outside physical SRAM). Boards that use the default 1 MiB are unaffected.

Possible resolutions: derive the wrapper `RamWords` and the Zephyr regions from
`memory.ram_bytes` (e.g. a FuseSoC parameter and a generated/overlaid DT), or at
minimum add a consistency check (e.g. in `make board-check`) that the three
values agree.

## Stale software build dirs survive the descriptor-driven linker change

Replacing the static `sw/common/link.ld` with the generated `link.ld.in`
(CMake `configure_file`) leaves pre-existing `sw/build/.../cmake` directories
with a cached linker flag pointing at the now-deleted script:

```
ld: cannot open linker script file .../sw/c/../common/link.ld: No such file
```

A one-time `make -C sw clean` fixes it; fresh checkouts and CI are unaffected
(`sw/build/` is gitignored). Surfaced during the Arty regression — every core
with a stale build dir failed `sw-build` until the dirs were cleaned. Consider
having the software build invalidate stale linker configuration automatically,
or documenting the clean step alongside the linker change.

