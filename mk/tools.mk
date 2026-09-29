# SPDX-License-Identifier: Apache-2.0
#
# Tool builds: the RISC-V toolchain, Verilator, and Verible under TOOLS_DIR.
# Included by the root Makefile; see it for the shared settings.

TOOLCHAIN_BUILDER_IMAGE ?= corejack-toolchain-builder
TOOLCHAIN_BUILDER_FILE ?= bin/toolchain-builder.Containerfile
PODMAN ?= podman
# Set to 1 to re-package an already-built toolchain instead of rebuilding.
TOOLCHAIN_SKIP_BUILD ?= 0

# The script builds, packages, and then installs by unpacking that package, so
# a local .tools/riscv is byte-identical to the artifact published for CI.
RISCV_TOOLCHAIN_ENV = \
	RISCV_TOOLCHAIN_PREFIX="$(RISCV_TOOLCHAIN_PREFIX)" \
	RISCV_GNU_TOOLCHAIN_SRC="$(RISCV_GNU_TOOLCHAIN_SRC)" \
	RISCV_GNU_TOOLCHAIN_REF="$(RISCV_GNU_TOOLCHAIN_REF)" \
	RISCV_GNU_TOOLCHAIN_COMMIT="$(RISCV_GNU_TOOLCHAIN_COMMIT)" \
	RISCV_MULTILIB_GENERATOR="$(RISCV_MULTILIB_GENERATOR)" \
	RISCV_TOOLCHAIN_JOBS="$(RISCV_TOOLCHAIN_JOBS)" \
	RISCV_TOOLCHAIN_DIST_DIR="$(RISCV_TOOLCHAIN_DIST_DIR)"
RISCV_TOOLCHAIN_ARGS = $(if $(filter 1,$(TOOLCHAIN_SKIP_BUILD)),--skip-build)

toolchain-riscv: ## build+package+install local RISC-V GNU multilib toolchain into TOOLS_DIR
	@$(RISCV_TOOLCHAIN_ENV) bin/build_riscv_toolchain.sh $(RISCV_TOOLCHAIN_ARGS)

toolchain-riscv-dist: ## same, but keep the tarball+sha256 in RISCV_TOOLCHAIN_DIST_DIR for upload
	@$(RISCV_TOOLCHAIN_ENV) bin/build_riscv_toolchain.sh --keep $(RISCV_TOOLCHAIN_ARGS)

# Containerised build. The native targets above are unchanged and remain the
# right choice for a local-only toolchain; this one exists to produce an
# artifact that also runs on older CI runners. See docs/source/tooling.rst.
#
# No "does the image exist" check: podman build is already idempotent. With an
# unchanged Containerfile it hits its layer cache and returns in ~1s, and when
# the file changes it rebuilds -- which a guard would defeat.
toolchain-builder-image:
	@$(PODMAN) build -t $(TOOLCHAIN_BUILDER_IMAGE) -f $(TOOLCHAIN_BUILDER_FILE) bin/

# Switching between native and containerised builds requires wiping
# $(RISCV_GNU_TOOLCHAIN_SRC) first -- a tree configured by one host compiler and
# re-entered by another carries stale configure results. Note also that this
# overwrites .tools/riscv and the tarball in $(RISCV_TOOLCHAIN_DIST_DIR); move
# any artifact you still need aside before running.
#
# --userns=keep-id is load-bearing: rootless podman maps only the invoking
# user's uid and primary gid, so a repo owned by any other group appears as
# nobody inside and GCC's install-headers-tar fails to restore ownership.
toolchain-riscv-container: toolchain-builder-image ## build the toolchain inside Ubuntu 22.04 (podman) for a portable artifact
	@$(PODMAN) run --rm --userns=keep-id -e HOME=/tmp \
	   -v "$(CURDIR):/repo:z" -w /repo $(TOOLCHAIN_BUILDER_IMAGE) \
	   make toolchain-riscv-dist RISCV_TOOLCHAIN_JOBS=$(RISCV_TOOLCHAIN_JOBS)

tool-verilator: ## build optional local Verilator into TOOLS_DIR
	@VERILATOR_REF="$(VERILATOR_VERSION)" \
	 VERILATOR_COMMIT="$(VERILATOR_COMMIT)" \
	 VERILATOR_PREFIX="$(VERILATOR_PREFIX)" \
	 VERILATOR_SRC="$(VERILATOR_SRC)" \
	 VERILATOR_JOBS="$(VERILATOR_JOBS)" \
	 bin/build_verilator.sh

tool-verible: ## install optional local Verible lint/format tools into TOOLS_DIR
	@VERIBLE_REF="$(VERIBLE_VERSION)" \
	 VERIBLE_PREFIX="$(VERIBLE_PREFIX)" \
	 VERIBLE_ARCHIVE_URL="$(VERIBLE_ARCHIVE_URL)" \
	 VERIBLE_ARCHIVE_SHA256="$(VERIBLE_ARCHIVE_SHA256)" \
	 VERIBLE_SHA256_LINUX_X86_64="$(VERIBLE_SHA256_LINUX_X86_64)" \
	 VERIBLE_SHA256_LINUX_ARM64="$(VERIBLE_SHA256_LINUX_ARM64)" \
	 bin/build_verible.sh

.PHONY: toolchain-riscv toolchain-riscv-dist toolchain-builder-image toolchain-riscv-container tool-verilator tool-verible
