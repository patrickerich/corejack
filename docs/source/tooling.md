# Tooling

This page collects host tool setup and diagnostics for CoreJack development.
The top-level README keeps only the quick-start path.

## Environment Activation

For interactive development shells, activate the project environment with:

```bash
source sourceme.sh
```

`source sourceme.sh` also prepends repo-local tool paths when they exist.
`TOOLS_DIR` defaults to `.tools`:

- default generic toolchain root: `TOOLS_DIR/riscv`
- default Verilator root: `TOOLS_DIR/verilator`
- default Verible root: `TOOLS_DIR/verible`
- default descriptor-selected software toolchain: `riscv-multilib`
- shell setup can also select it via `COREJACK_TOOLCHAIN=riscv-multilib`
- optional machine-local overrides can live in ignored `sourceme.local.sh`
- a template is provided in `sourceme.local.example.sh`

Check the host environment for the selected core/board and flow with:

```bash
make check-tools
make check-tools FLOW=sim
make check-tools FLOW=fpga
make check-tools FLOW=debug
```

## Optional Generic RISC-V GNU Toolchain

The repo can build an optional bare-metal multilib RISC-V GNU toolchain into
`TOOLS_DIR`, which defaults to the ignored `.tools/` directory:

```bash
make toolchain-riscv
```

That target does three things in one pass: it builds from source, packages the
result into a relocatable tarball, and then installs by **unpacking that
tarball**. Installing from the package rather than from the raw build tree is
deliberate - it means a local `.tools/riscv` is byte-identical to the artifact
published for CI, so there is no gap between what a contributor tests with and
what CI downloads. See [Packaging a relocatable artifact](#packaging-a-relocatable-artifact).

The default install prefix is:

```text
TOOLS_DIR/riscv/
```

The resulting compiler prefix is normally `riscv64-unknown-elf-*`, even for
RV32 software builds. The selected `-march` and `-mabi` values still come from
the core descriptors.

The default project multilib generator is:

```text
rv32i-ilp32--;rv32imc-ilp32--;rv32imcb-ilp32--;rv64imc-lp64--;rv64gc-lp64d--
```

Override it when invoking the target if needed:

```bash
make toolchain-riscv RISCV_MULTILIB_GENERATOR="rv32i-ilp32--;rv32imc-ilp32--"
```

To use the local generic toolchain in a shell:

```bash
COREJACK_TOOLCHAIN=riscv-multilib source sourceme.sh
```

This is now the default descriptor-selected toolchain. To override a single
software build explicitly:

```bash
make sw-build SW_APP=hello_world TOOLCHAIN=riscv-multilib
```

This target is intentionally not part of `make deps`; building GCC/Newlib from
source is slow and requires host build dependencies.

The default RISC-V GNU toolchain source is pinned to the upstream
`2026.05.19` release tag and verified against commit
`96e1c125620ec403962c8536ecbbde20878c5e44` before building. If the tag ever
resolves to a different commit, the build stops instead of silently accepting
the changed source.

Upstream tags this repository as automated nightlies rather than curated
releases, so a pin bump buys no described fix - treat it as its own change with
its own validation, never as a rider on unrelated work.

### Packaging a relocatable artifact

```bash
make toolchain-riscv-dist                          # build, package, install, keep tarball
make toolchain-riscv-dist TOOLCHAIN_SKIP_BUILD=1   # re-package an existing build (~20 s)
```

`toolchain-riscv-dist` behaves exactly like `toolchain-riscv` but leaves the
tarball and its `.sha256` in `RISCV_TOOLCHAIN_DIST_DIR` (default
`.tools/dist/`) so it can be uploaded as a release asset. Use
`TOOLCHAIN_SKIP_BUILD=1` to skip the source build when a usable toolchain is
already installed; without it, retrieving an artifact you forgot to keep costs
a full rebuild.

GCC resolves its paths at runtime from the driver binary's own location, so the
**binaries** relocate unaided - the configure-time prefix embedded in them is
only an overridden fallback. Files read as **text** do not relocate, and those
are what break a naively copied toolchain. The packaging step normalises them:

| Carrier | Treatment |
| --- | --- |
| `ldscripts/*` | `SEARCH_DIR("<prefix>/...")` rewritten to `SEARCH_DIR("=/lib")`, ld's sysroot-relative form, which follows the `--sysroot` gcc computes from the driver |
| `*.la` | deleted; a bare-metal cross toolchain links the `.a` directly and never consults libtool archives |
| `*-gdb.py` | absolute paths recomputed from `__file__` |
| `configargs.h`, `mkheaders*` | prefix replaced with the inert placeholder `@TOOLCHAIN_PREFIX@`; nothing reads these at build time, and the substitution keeps the audit below strict rather than carrying an exception list |

Two gates then run, and **no tarball is emitted unless both pass**: an audit
that no text file still contains the build prefix, and a relocation self-test
that moves the tree to a throwaway path and compiles every multilib from there.

Each tarball carries a `MANIFEST` recording the upstream repo, ref, resolved
commit, multilib generator, and build timestamp. It doubles as the
corresponding-source pointer required when publishing GCC binaries under
GPLv3. With `TOOLCHAIN_SKIP_BUILD=1` the manifest records the pin as
`UNVERIFIED`, because skipping the build also skips the commit check - the
script additionally warns on stderr if the source tree has drifted from the
pin.

Finally, the run reports the artifact's host ABI floor (the minimum glibc a
machine needs to execute it), and says so only when that floor is too high to
publish.

### Building the artifact in a container

```bash
make toolchain-riscv-container     # build + package + install, in Ubuntu 22.04
```

An artifact built natively links against the host's glibc and then refuses to
start on a CI runner with an older one - built on RHEL/AlmaLinux 10 it required
`GLIBC_2.38`, which no current GitHub runner provides. Building against Ubuntu
22.04 (glibc 2.35) instead brings the floor to `GLIBC_2.34`, low enough for
every runner and still fine on a newer development host, since glibc is
backward compatible.

Nothing about the packaging changes - the target runs the same
`make toolchain-riscv-dist` inside the container, with the repository
bind-mounted so the build tree and the tarball land on the host as usual. The
result was validated by compiling all 13 `sw/c` sources across all five
multilibs with both toolchains: the objects are byte-identical, so a different
host compiler (gcc 11.4 rather than 14.3.1) changes the ABI floor and nothing
else.

The recipe is [`bin/toolchain-builder.Containerfile`](../../bin/toolchain-builder.Containerfile).
It runs under **podman**, rootless - no daemon and no `sudo`, and it is the
supported container tool on RHEL-family hosts. Four details in it are
load-bearing:

| Detail | Why |
| --- | --- |
| base image pinned by **digest**, not by the `22.04` tag | the tag is rebuilt for security updates and so names different bytes over time; the same discipline as pinning the toolchain to a commit |
| `gettext` in the package list | not in upstream's documented prerequisites, but without `msgfmt` binutils and gcc fail their install step on missing `po/*.gmo` |
| `--userns=keep-id` on the run | rootless podman maps only the invoking user's uid and *primary* gid, so a repository owned by any other group appears as `nobody` inside and GCC's `install-headers-tar` cannot restore ownership |
| the repository bind-mounted from the host | the build tree reaches ~33 GB; inside container storage that lands on the wrong partition, and the clone would not persist between runs |

The published tarball still needs `libmpc.so.3` and `libmpfr.so.6` on the
machine that runs it. Both arrive with any C compiler, so runner images have
them, but CI installs them explicitly rather than relying on that.

To bump the base image deliberately:

```bash
podman pull docker.io/library/ubuntu:22.04
podman image inspect docker.io/library/ubuntu:22.04 --format '{{index .RepoDigests 0}}'
```

then edit the `FROM` line and rebuild.

### Some submodules are intentionally skipped

`riscv-gnu-toolchain` registers submodules for every target it can build, not
just the one CoreJack uses. `make newlib` reaches only binutils, gcc, newlib
and gdb; the rest belong to other top-level targets. Two are skipped outright,
because fetching them buys nothing and puts the build at the mercy of hosts
that are not GitHub.

**dejagnu** is the GNU test framework used by the `make check` test suite of
binutils, gcc, and gdb - **not** required for `make newlib`.

`dejagnu`'s upstream lives at `git.savannah.gnu.org` and periodically prunes
unadvertised commits. When that happens, a recursive submodule fetch fails
with:

```text
error: Server does not allow request for unadvertised object <sha>
fatal: Fetched in submodule path 'dejagnu', but it did not contain <sha>.
       Direct fetching of that commit failed.
```

**musl** is reachable only from upstream's separate `musl:` target, never from
`newlib:`. Its host `git.musl-libc.org` was unreachable on 2026-08-29 and the
clone timed out after 22 minutes of otherwise successful work:

```text
fatal: unable to access 'https://git.musl-libc.org/git/musl/':
       Failed to connect to git.musl-libc.org port 443 after 133828 ms
```

To keep the toolchain build robust against this kind of upstream churn,
`bin/build_riscv_toolchain.sh` carries a `skip_submodules` list - currently
`dejagnu` and `musl` - deinitializing each and passing
`submodule.<name>.update=none`, after clearing any half-broken state left by an
earlier attempt. The script prints a `note:` line per skipped submodule during
the submodule step so this is visible while building.

These skips are safe because CoreJack builds only the cross-compiler,
binutils, gdb, and newlib, and never runs the upstream test suite or targets a
Linux userland. If you ever want `make check` yourself, point
`submodule.dejagnu.url` at a working mirror and re-init it manually; that is
outside the standard CoreJack flow.

The remaining submodules - `llvm`, `qemu`, `spike`, `pk`, `uclibc-ng`, `glibc`
- are still cloned even though `make newlib` does not build them, and account
for most of the ~12 GB source tree. Trimming those is an open optimisation, not
a correctness issue.

LLVM/Clang is a plausible future toolchain backend, but GCC/Newlib remains the
default for now. The current priority is a reliable bare-metal flow with
multilib support, predictable Newlib runtime libraries, binutils, and GDB for
OpenOCD-based FPGA bring-up. LLVM's RISC-V backend is active and strategically
important, but it should be added as an optional named toolchain only after the
GCC-based core/board flow is stable and after compile, simulation, ELF loading,
and debug behavior have been validated.

## Optional Local Verilator

The repo can build an optional pinned Verilator into `TOOLS_DIR`, which defaults
to the ignored `.tools/` directory:

```bash
make tool-verilator
```

The default source checkout and install prefix are:

```text
TOOLS_DIR/src/verilator/
TOOLS_DIR/verilator/
```

The default pinned Verilator tag is `v5.048`. Override it when invoking the
target if needed:

```bash
make tool-verilator VERILATOR_VERSION=v5.048
```

The default tag is verified against commit
`d0aa828c217410fffc73d92077b6f4f54830357c` after checkout.

`source sourceme.sh` prepends `TOOLS_DIR/verilator/bin` when that local install is
present. If it is absent, the flow falls back to whichever `verilator` is
already available on `PATH`.

Building Verilator from source requires host build tools such as `git`,
`autoconf`, `flex`, `bison`, `help2man`, Perl, `make`, and a C++ compiler.
`make check-tools FLOW=sim` reports the active Verilator and these optional
source-build prerequisites.

## Optional Local Verible

The repo can install optional pinned Verible SystemVerilog lint/format tools
into `TOOLS_DIR`, which defaults to the ignored `.tools/` directory:

```bash
make tool-verible
```

The default install prefix is:

```text
TOOLS_DIR/verible/
```

The default pinned Verible tag is `v0.0-4053-g89d4d98a`. Override it when
invoking the target if needed:

```bash
make tool-verible VERIBLE_VERSION=v0.0-4053-g89d4d98a
```

`source sourceme.sh` prepends `TOOLS_DIR/verible/bin` when that local install is
present. If it is absent, the flow falls back to any Verible tools already
available on `PATH`.

Verible publishes prebuilt static Linux release archives, so CoreJack uses
those by default instead of building through Bazel. Override the archive
explicitly if needed:

```bash
make tool-verible VERIBLE_ARCHIVE_URL=https://...
```

Default Verible release archives are verified with pinned SHA256 digests. If
`VERIBLE_ARCHIVE_URL` is overridden, `VERIBLE_ARCHIVE_SHA256` must also be set.

The installer requires only `curl` and `tar`. `make check-tools FLOW=sim`
reports the active Verible tools and optional binary-install prerequisites.

## Observed Validation Versions

These are currently observed local tool versions used to validate this
repository. They are not all pinned by this repo, so recording them here helps
reproducibility:

- Verilator: repo-local `5.048`
- Verible: repo-local `v0.0-4053-g89d4d98a`
- GNU Make: `4.4.1`
- System Python used by setup: `3.13.13`
- FuseSoC from venv/requirements: `2.4.6`
- cocotb from venv/requirements: `2.0.1`
- pytest from venv/requirements: `9.0.3`
- Bender: `0.31.0`
- CMake: `3.30.5`
- Vivado: `2025.2.1`
- OpenOCD: `0.12.0+dev-02309-ga1c7cd4fe`
- local RISC-V GNU multilib toolchain: GCC/GDB `15.2.0`
