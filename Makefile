SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

BENDER_VERSION ?= 0.31.0
BENDER_ASSET ?=
BENDER_SHA256 ?=
BENDER_URL ?=
PYTHON        ?= python3.13
TOOLS_DIR  := $(CURDIR)/.tools
RISCV_TOOLCHAIN_PREFIX ?= $(TOOLS_DIR)/riscv
RISCV_GNU_TOOLCHAIN_SRC ?= $(TOOLS_DIR)/src/riscv-gnu-toolchain
RISCV_GNU_TOOLCHAIN_REF ?= 2026.05.19
RISCV_GNU_TOOLCHAIN_COMMIT ?= 96e1c125620ec403962c8536ecbbde20878c5e44
RISCV_MULTILIB_GENERATOR ?= rv32i-ilp32--;rv32imc-ilp32--;rv32imcb-ilp32--;rv64imc-lp64--;rv64gc-lp64d--
RISCV_TOOLCHAIN_JOBS ?= $(shell nproc 2>/dev/null || echo 4)
RISCV_TOOLCHAIN_DIST_DIR ?= $(TOOLS_DIR)/dist
VERILATOR_VERSION ?= v5.052
VERILATOR_COMMIT ?= ea338be98e1e838d3518809ce8899f85a009963c
VERILATOR_PREFIX ?= $(TOOLS_DIR)/verilator
VERILATOR_SRC ?= $(TOOLS_DIR)/src/verilator
VERILATOR_JOBS ?= $(shell nproc 2>/dev/null || echo 4)
VERIBLE_VERSION ?= v0.0-4053-g89d4d98a
VERIBLE_PREFIX ?= $(TOOLS_DIR)/verible
VERIBLE_ARCHIVE_URL ?=
VERIBLE_ARCHIVE_SHA256 ?=
VERIBLE_SHA256_LINUX_X86_64 ?= 1edc1f29c70d74213ed373e727183802d5a733e23f9ab9c74462f5b18b76f2c0
VERIBLE_SHA256_LINUX_ARM64 ?= e6184011e93eb843fe0b5f1ecc60dcb06eec0ca05784f5caff1a17814068bca1
ZEPHYR_VERSION ?= v4.4.0
ZEPHYR_APP ?= corejack_hello
CVA6_REPO ?= https://github.com/openhwgroup/cva6.git
CVA6_REV  ?= f0c274cad66b84cd58379880741680351c7ce9ab
CVA6_PATCHES := patches/cva6/0001-fix-rv64-misa-mxl-width.patch

BENDER_DIR := $(TOOLS_DIR)/bender-v$(BENDER_VERSION)
BENDER_BIN := $(BENDER_DIR)/bender
BENDER     := $(TOOLS_DIR)/bender
VENV_PY    := $(CURDIR)/.venv/bin/python
# Interpreter for the stdlib-only project scripts under bin/: prefer the venv's
# python by absolute path when present (activation-independent, no PATH
# substitution surprises), else fall back to the bootstrap interpreter so a
# bare clone can still run diagnostics like `make check-tools`. Package-driven
# flows (pytest, fusesoc, cocotb, west) bind to $(VENV_PY)/PATH directly.
PY         := $(if $(wildcard $(VENV_PY)),$(VENV_PY),$(PYTHON))
CORE           ?= ibex
BOARD          ?= axku5
CORE_TYPE      ?= 0
RAM_WORDS      ?= 262144
SOC_RAM_BYTES  ?= 1048576
SW_APP         ?= hello_world
FW             ?= baremetal
TARGET         ?= fpga
SW_BUILD_DIR   = $(CURDIR)/sw/build/$(TARGET)/$(CORE)/$(TOOLCHAIN)/$(SW_APP)
FW_ELF         = $(SW_BUILD_DIR)/cmake/$(SW_APP)/$(SW_APP)
FW_BIN         = $(SW_BUILD_DIR)/$(SW_APP).bin
GDB_TIMEOUT    ?= 5
FPGA_GDB_RUN_MODE ?= default
UART_DEV       ?=
UART_CAPTURE_TIMEOUT ?= 15
UART_LOADER_ADDR ?= 0x80000000
UART_LOADER_CHUNK_SIZE ?= 4096
UART_LOADER_TIMEOUT ?= 2
UART_LOADER_EXPECT ?=
AXI_SMOKE_CORES ?= ibex cv32e40p cv32e40s cva6 serv picorv32 cvw

TARGET_CONFIG := $(shell $(PY) bin/validate_target.py --core "$(CORE)" --board "$(BOARD)" --make --allow-planned 2>/dev/null)
$(eval $(TARGET_CONFIG))
FUSESOC_CORE_FLAGS ?= $(FUSESOC_CORE_FLAG)
FUSESOC_FLAGS ?= $(FUSESOC_CORE_FLAGS) $(FUSESOC_BOARD_FLAG)
FUSESOC_FLAG_ARGS := $(foreach flag,$(FUSESOC_FLAGS),--flag $(flag))

# The make logic lives in these fragments, one per area; this file holds the
# pinned versions, the descriptor-derived settings, and the settings more than
# one fragment uses. CI reads BENDER_VERSION and AXI_SMOKE_CORES from here.
include mk/tools.mk
include mk/deps.mk
include mk/sw.mk
include mk/sim.mk
include mk/lint.mk
include mk/fpga.mk
include mk/zephyr.mk
include mk/docs.mk
include mk/project.mk

.PHONY: help

# Help is generated from the fragments: a `## text` comment after a target's
# prerequisites describes it, and a line starting `## ` adds a note under the
# target above it.
help: ## list the targets
	@echo "Targets:"
	@awk '/^[A-Za-z0-9_.%-]+:.*## / { t = $$1; sub(/:.*/, "", t); d = $$0; sub(/^[^#]*## /, "", d); printf "  %-18s %s\n", t, d; next } \
	     /^## / { d = $$0; sub(/^## /, "", d); printf "  %-18s %s\n", "", d }' $(MAKEFILE_LIST)
