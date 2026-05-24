# Tooling

This page collects host tool setup and diagnostics for CoreJack development.
The top-level README keeps only the quick-start path.

## Environment Activation

For interactive development shells, activate the project environment with:

```bash
source sourceme.sh
```

`source sourceme.sh` also prepends repo-local tool paths when they exist:

- default generic toolchain root: `.tools/riscv`
- default Verilator root: `.tools/verilator`
- default Verible root: `.tools/verible`
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

The repo can build an optional bare-metal multilib RISC-V GNU toolchain from
source into the local ignored `.tools/` directory:

```bash
make toolchain-riscv
```

The default install prefix is:

```text
.tools/riscv/
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

LLVM/Clang is a plausible future toolchain backend, but GCC/Newlib remains the
default for now. The current priority is a reliable bare-metal flow with
multilib support, predictable Newlib runtime libraries, binutils, and GDB for
OpenOCD-based FPGA bring-up. LLVM's RISC-V backend is active and strategically
important, but it should be added as an optional named toolchain only after the
GCC-based core/board flow is stable and after compile, simulation, ELF loading,
and debug behavior have been validated.

## Optional Local Verilator

The repo can build an optional pinned Verilator into the ignored `.tools/`
directory:

```bash
make tool-verilator
```

The default source checkout and install prefix are:

```text
.tools/src/verilator/
.tools/verilator/
```

The default pinned Verilator tag is `v5.048`. Override it when invoking the
target if needed:

```bash
make tool-verilator VERILATOR_VERSION=v5.048
```

The default tag is verified against commit
`d0aa828c217410fffc73d92077b6f4f54830357c` after checkout.

`source sourceme.sh` prepends `.tools/verilator/bin` when that local install is
present. If it is absent, the flow falls back to whichever `verilator` is
already available on `PATH`.

Building Verilator from source requires host build tools such as `git`,
`autoconf`, `flex`, `bison`, `help2man`, Perl, `make`, and a C++ compiler.
`make check-tools FLOW=sim` reports the active Verilator and these optional
source-build prerequisites.

## Optional Local Verible

The repo can install optional pinned Verible SystemVerilog lint/format tools
into the ignored `.tools/` directory:

```bash
make tool-verible
```

The default install prefix is:

```text
.tools/verible/
```

The default pinned Verible tag is `v0.0-4053-g89d4d98a`. Override it when
invoking the target if needed:

```bash
make tool-verible VERIBLE_VERSION=v0.0-4053-g89d4d98a
```

`source sourceme.sh` prepends `.tools/verible/bin` when that local install is
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
