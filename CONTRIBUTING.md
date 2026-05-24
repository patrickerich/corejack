# Contributing

CoreJack is still in an early architecture phase. Keep changes small,
descriptor-driven where possible, and validated with the cheapest relevant
checks before opening a pull request.

## Setup

Start from the project environment:

```bash
source sourceme.sh
make check-tools FLOW=sim
```

For FPGA or debug work, also check the corresponding host tools:

```bash
make check-tools FLOW=fpga
make check-tools FLOW=debug
```

## Fast Local Checks

Run these before submitting changes that touch descriptors, scripts,
documentation generation, or project plumbing:

```bash
make python-tests
make support-matrix-check
make board-check BOARD=axku5
make target-check BOARD=axku5
```

For a minimal simulation smoke check:

```bash
make smoke
```

For stronger simulation confidence across the supported AXI/platform paths:

```bash
make axi-smoke
```

## Adding A Board

Use the scaffold helper, then review and complete the generated wrapper and
constraints:

```bash
make new-board BOARD=myboard FPGA_PART=xc...
make board-check BOARD=myboard
make target-check BOARD=myboard
```

The scaffold creates a descriptor, wrapper, XDC placeholder, and board FuseSoC
core. It intentionally leaves board-specific pin constraints and clocking for
manual review.

See [`docs/board_porting.md`](docs/board_porting.md).

## Adding A Core

Use the conservative scaffold helper:

```bash
make new-core CORE=mycore
make core-check CORE=mycore
```

For RV64 cores, provide the ISA fields explicitly:

```bash
make new-core CORE=mycore CORE_XLEN=64 CORE_MARCH=rv64imc CORE_MABI=lp64
```

Generated cores start as `planned`. The generated adapter is only a placeholder;
replace it with a real protocol adapter before trying to promote simulation or
FPGA support.

See [`docs/core_porting.md`](docs/core_porting.md).

## Support Status Promotion

Do not mark descriptor status as `supported` until the corresponding acceptance
criteria have passed.

When changing support status:

```bash
make validate-target CORE=<core> BOARD=<board>
make list-targets
make support-matrix
make support-matrix-check
```

Commit the regenerated [`docs/support_matrix.md`](docs/support_matrix.md) with
the descriptor change.

Use [`docs/core_acceptance_checklist.md`](docs/core_acceptance_checklist.md) as
the promotion gate for simulation, FPGA, debug, and Zephyr status.

## FPGA And Hardware Work

FPGA acceptance requires real hardware and is not expected for every small
change. For hardware-facing changes, document what was run and which board/core
combination was validated.

Typical AXKU5 debug-capable flow:

```bash
make fpga-bit CORE=<core> BOARD=axku5
make fpga-pgm CORE=<core> BOARD=axku5
make openocd CORE=<core> BOARD=axku5
make fpga-run-sw CORE=<core> BOARD=axku5 SW_APP=hello_world
```

For cores without OpenOCD/GDB debug support, use the UART SRAM loader flow
documented in [`docs/uart_sram_loader.md`](docs/uart_sram_loader.md).

## Documentation

Documentation committed to the repository should be standalone project
documentation. Keep temporary investigation notes, local logs, and private
debug timelines in ignored local files such as `logs/`.

Use `logs/open_items.md` or another ignored file under `logs/` for local
planning notes. Promote stable, generally useful plans into committed
documentation such as `docs/` or `README.md`.

Start from [`docs/README.md`](docs/README.md) when adding or updating
documentation.

## Coding Style

CoreJack-owned RTL should follow the lowRISC/OpenTitan SystemVerilog coding
style as the default intent. See [`docs/coding_style.md`](docs/coding_style.md).

Do not reformat third-party, vendored, Bender-managed, or generated dependency
code just to match local style. Keep style cleanup scoped to CoreJack-owned
wrappers, adapters, packages, tests, scripts, and documentation.

## Versioning And Tagging

CoreJack uses the FuseSoC VLNV convention (`Vendor:Library:Name:Version`) for
the project version, and the conventional `v`-prefixed git tag for releases.
The two are kept in lockstep so a tagged commit always corresponds to a
single, consistent FuseSoC version across every `.core` file.

### Conventions

- VLNV in `.core` files is unprefixed SemVer: `corejack:corejack:platform:0.1.0`.
  FuseSoC's SemVer parser does not accept a leading `v`.
- Git tags use the `v` prefix: `v0.1.0`. This is the standard SemVer-meets-Git
  convention and is what `git describe` will surface in the bitstream
  manifest's `GIT_DESCRIBE_AT_MANIFEST` field.

### Checking for drift

Every `.core` file (and the scaffold templates that emit new ones) must agree
on a single VLNV version. Drift is caught by:

```bash
make version-check
```

This runs in CI on every push.

### Bumping and tagging

```bash
make version-check                  # confirm starting state is consistent
make bump-version VERSION=0.2.0     # rewrite every VLNV in lockstep
git commit -am "Bump CoreJack version to 0.2.0"
git tag -a v0.2.0 -m "CoreJack v0.2.0"
git push && git push --tags
```

A few notes on the git commands above:

- `git commit -am "..."`: `-a` (short for `--all`) auto-stages modified and
  deleted *tracked* files before committing. It does **not** stage new
  (untracked) files. `make bump-version` only edits already-tracked
  `.core` files and `bin/create_*.py` scaffolds, so `-am` captures the
  whole bump in one step. The `-m` supplies the commit message inline.
- `git tag -a vX.Y.Z -m "..."`: `-a` (short for `--annotate`) creates an
  **annotated tag** with a tagger, timestamp, and message stored as a
  full git object. This is required for `git describe` to report the tag
  name rather than falling back to a commit SHA; without it, the FPGA
  bitstream manifest's `GIT_DESCRIBE_AT_MANIFEST` would lose the
  human-readable version. Always use `-a` for release tags.

For the rationale behind the FuseSoC version constraint (and why it can't be
inherited from an environment variable), see
[`docs/dependency_management.md`](docs/dependency_management.md). For how the
bitstream manifest records build identity per-build, see
[`docs/fpga_sw_flow.md`](docs/fpga_sw_flow.md).

## Dependency Policy

Prefer descriptor-driven and Bender-managed dependencies. Manually vendored
code should be explicit, documented, and used only when the upstream dependency
flow is not directly compatible with CoreJack's build flow.

Third-party code remains under its upstream license. Update
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) when adding a new vendored
or externally fetched dependency family.
