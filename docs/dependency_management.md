# Dependency Management

CoreJack uses **Bender** and **FuseSoC** together, with a deliberate split of
responsibilities.

Bender is used for external RTL/IP dependency checkout and pinning:

- `Bender.yml` keeps external dependency intent explicit and reviewable.
- Bender provides reproducible dependency resolution through its
  lock/checkout workflow.
- `make deps` creates stable local symlinks under `deps/` to checked-out
  packages in `.bender/`.
- Bender checkouts and caches are local-only (`.bender*/`, `deps/`) and
  gitignored.

FuseSoC remains the top-level CoreJack design/build orchestration layer:

- `corejack.core` owns the CoreJack simulation and FPGA targets.
- `corejack_common.core` owns the always-on shared dependency filelists used by
  the platform.
- FuseSoC selects top-level build targets and drives Verilator/Vivado flows.
- Core/board selection is exposed through Make variables and descriptors such
  as `CORE=<core>` and `BOARD=<board>`.
- Project-local `.core` files describe shared dependency filelists and optional
  external core filelists, while `corejack.core` keeps the platform targets and
  depends on those files through common or selected `core_*` FuseSoC flags.

The preferred long-term dependency policy is:

- use Bender to fetch and pin external HDL repositories
- reuse upstream package metadata when it is clean and maintained
- for dependencies with good Bender manifests, consume their Bender-managed
  source selection
- for dependencies with good FuseSoC `.core` files, let FuseSoC consume those
  files from the Bender-managed checkout
- avoid vendoring external cores unless upstream packaging is incompatible with
  this repo's flow or the source must be locally adapted

Typical flow:

```bash
make bender
make deps
make flist
```

`make deps` fetches the shared base dependencies and the dependency for the
selected `CORE`. Use the more explicit targets when needed:

```bash
make deps-base
make deps-core CORE=cv32e40p
make deps-all
```

Normal dependency checkout consumes the committed `Bender.lock`. Do not refresh
the lockfile as part of routine setup. When intentionally updating HDL
dependency pins, use:

```bash
make deps-update
```

and review the resulting `Bender.lock` diff.

`deps-base` is the common SoC dependency set: AXI, APB, OBI, CLINT,
`riscv-dbg`, common cells, and related shared packages. Core repositories are
intended to be independent optional dependencies. A core port must not require
another core repository to be present.

Initial shared external dependency families in `Bender.yml` include:

- `pulp-platform/axi`
- `pulp-platform/riscv-dbg`
- `pulp-platform/apb`
- `pulp-platform/apb_uart`
- `pulp-platform/clint`
- `pulp-platform/obi`

The standalone UART dependency is intended to be used for FPGA bring-up rather
than reusing older UART implementations buried inside core-specific example
FPGA trees.

## Project Versioning

Every CoreJack `.core` file declares its own and its dependencies' versions
through FuseSoC's VLNV format (`Vendor:Library:Name:Version`), and FuseSoC
parses these strings verbatim - they cannot be inherited from an environment
variable, so the version must be kept in sync across every `.core` file and
across the scaffold templates that emit new ones.

The `bin/bump_version.py` helper performs this sync in one atomic sweep. It
refuses to operate when the `.core` files disagree on a version (`--check` is
how the CI `version-check` job catches drift), and it walks both the
top-level `.core` files and the `bin/create_core.py` / `bin/create_board.py`
scaffold templates so newly generated descriptors always start at the current
version.

For the user-facing bump-and-tag workflow, including the conventions for
unprefixed VLNV versions vs. `v`-prefixed git tags and why release tags must
be annotated, see the **Versioning And Tagging** section in
[`CONTRIBUTING.md`](../CONTRIBUTING.md).

For build-time provenance of an individual bitstream (commit SHA, dirty-tree
flag, and `git describe`), see the `.corejack_bitstream_manifest` produced by
`make fpga-bit`, described in [`fpga_sw_flow.md`](fpga_sw_flow.md). Once a
release tag exists, `GIT_DESCRIBE_AT_MANIFEST` in that manifest becomes the
recommended human-readable build identity for any bitstream.

## Reproducibility Notes

- `Makefile` pins `BENDER_VERSION`, selects deterministic Linux release assets,
  and verifies their SHA256 digests before installing into `TOOLS_DIR`.
- `Makefile` and `sourceme.sh` share the same Python selector (`PYTHON`,
  default `python3.13`).
- A stable symlink `TOOLS_DIR/bender` is used by `make deps`/`make flist`.
- Normal `make deps`/`make deps-base` uses `bender checkout` against the
  committed lockfile; `make deps-update` is the explicit lock-refresh path.
- `make deps-core CORE=<core>` creates only the selected core's `deps/<core>`
  symlink when that core has an external dependency.
- Optional source-built tools use readable release refs plus expected commits;
  the build scripts fail if a ref resolves to a different commit.
- Optional prebuilt binary tools use pinned SHA256 digests; custom archive URLs
  must provide matching custom digests.

## Dependency Classes

- **Manually vendored sources** are committed in this repository. Ibex is in
  this class because its upstream packaging is not compatible with the current
  CoreJack FuseSoC/Bender flow. These sources should be treated as local source
  code, but updates must be deliberate because re-vendoring can overwrite local
  integration files.
- **Bender vendor-package checkouts** live in ignored `.bender/vendor/<name>/`
  directories and are exposed through stable `deps/<name>` symlinks. They can
  be populated by `make deps-all` through Bender's vendor-copy flow, or by
  `make deps-core CORE=<core>` for just the selected core. CV32E40P, CV32E40X,
  CV32E40S, SERV, PicoRV32, and CVW/Wally currently use this model. Their
  upstream repository and exact revision are recorded in `Bender.yml` under
  `vendor_package`. This is used when a core can be pinned and fetched, but its
  upstream package metadata is not cleanly consumable as a normal Bender
  dependency in this repository.
- **Project-local dependency `.core` files** are thin FuseSoC wrappers around
  shared or optional dependency filelists. They keep `corejack.core` from
  directly listing dependency-internal `deps/...` paths. `corejack_common.core`
  wraps the always-on shared dependencies. Per-core `.core` files wrap optional
  core dependencies and must stay syntactically valid even when that optional
  checkout is absent; missing optional dependency source files should only
  affect builds that select that core.
- **Project-local pinned checkouts** are exact-revision Git checkouts created by
  a Make target under ignored `.bender/vendor/<name>/` and exposed through
  `deps/<name>`, but they are not resolved by Bender. CVA6 currently uses this
  temporary model via `make deps-cva6` because its upstream Bender manifest
  requires an older `pulp-platform/axi` version than CoreJack, while Bender's
  vendor-copy mode also trips over optional auxiliary upstream paths.

One known resolution conflict: `clint` and `apb_uart` declare
`register_interface ^0.3.x` upstream while `idma` requires `^0.4.3`. The
committed `Bender.lock` records `register_interface 0.4.x` (the reg-bus
typedefs and vendored lowRISC `prim_subreg*` files are source-compatible
across the bump, proven by the simulation and FPGA acceptance gates).
`bender checkout` follows the lock silently; only a deliberate
`make deps-update` re-resolves and will prompt interactively to pick the
`^0.4.3` requirement again.

The current CVA6 pin is implemented by these Makefile variables:

```make
CVA6_REPO ?= https://github.com/openhwgroup/cva6.git
CVA6_REV  ?= f0c274cad66b84cd58379880741680351c7ce9ab
```

The target:

```bash
make deps-cva6
```

clones or updates `.bender/vendor/cva6`, checks out `CVA6_REV`, and creates
`deps/cva6`. Bender is still used for the shared base dependency graph through
`deps-base`, but it does not manage CVA6 itself in this temporary mode.

As more cores and boards are added, dependency integration should converge
toward Bender-managed checkout plus clean upstream package metadata wherever
that is technically practical. Project-local pinned checkouts should remain
exceptional and should be replaced once the upstream dependency graph can be
made compatible with CoreJack's shared dependencies.

Simulation and FPGA FuseSoC targets are selected-core targets. Normal build
targets fetch `deps-base` plus the selected core dependency only; unrelated
core repositories are not required. Use `make deps-all` only for maintenance
work that intentionally wants every optional core checkout.
