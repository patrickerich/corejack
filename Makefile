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
VERILATOR_VERSION ?= v5.048
VERILATOR_COMMIT ?= d0aa828c217410fffc73d92077b6f4f54830357c
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
ZEPHYR_WORKSPACE ?= $(TOOLS_DIR)/zephyrproject
ZEPHYR_BASE ?= $(ZEPHYR_WORKSPACE)/zephyr
ZEPHYR_APP ?= corejack_hello
ZEPHYR_BOARD ?= corejack_$(CORE)_$(BOARD)
ZEPHYR_BUILD_DIR ?= $(CURDIR)/sw/build/zephyr/$(ZEPHYR_BOARD)/$(ZEPHYR_APP)
ZEPHYR_ELF ?= $(ZEPHYR_BUILD_DIR)/zephyr/zephyr.elf
ZEPHYR_BIN ?= $(ZEPHYR_BUILD_DIR)/zephyr/zephyr.bin
CVA6_REPO ?= https://github.com/openhwgroup/cva6.git
CVA6_REV  ?= f0c274cad66b84cd58379880741680351c7ce9ab
CVA6_PATCHES := patches/cva6/0001-fix-rv64-misa-mxl-width.patch

BENDER_DIR := $(TOOLS_DIR)/bender-v$(BENDER_VERSION)
BENDER_BIN := $(BENDER_DIR)/bender
BENDER     := $(TOOLS_DIR)/bender
VENV_PY    := $(CURDIR)/.venv/bin/python
FPGA_BUILD_DIR := $(CURDIR)/build/fpga
CORE           ?= ibex
BOARD          ?= axku5
NEW_BOARD      ?= $(BOARD)
NEW_CORE       ?= $(CORE)
FPGA_PART      ?=
BOARD_DISPLAY_NAME ?=
CORE_DISPLAY_NAME ?=
CORE_XLEN      ?= 32
CORE_MARCH     ?= rv32imc
CORE_MABI      ?= ilp32
CORE_TYPE      ?= 0
FPGA_TOP       ?= corejack_$(BOARD)_wrap
FPGA_TARGET    ?= fpga-$(BOARD)
FPGA_WORK_ROOT ?= $(FPGA_BUILD_DIR)/$(BOARD)/$(CORE)/fusesoc-$(FPGA_TARGET)
UART_LOADER    ?= 0
FPGA_XPR       ?= $(FPGA_WORK_ROOT)/corejack_corejack_platform_0.1.0.xpr
FPGA_PROJECT_TCL ?= $(FPGA_WORK_ROOT)/corejack_corejack_platform_0.1.0.tcl
FPGA_REPORT_DIR ?= $(FPGA_WORK_ROOT)/reports
FPGA_REPORT_TCL ?= rtl/platform/fpga/scripts/report_vivado_impl.tcl
FPGA_PATCH_PROJECT_TCL ?= rtl/platform/fpga/scripts/patch_vivado_project_tcl.sh
VIVADO_HOME ?= $(CURDIR)/.cache/vivado-home
VIVADO_WARNING_ALLOWLIST ?= cfg/vivado_warning_allowlist.txt
VIVADO_WARNING_LOGS ?= $(FPGA_WORK_ROOT)/corejack_corejack_platform_0.1.0.runs/synth_1/runme.log $(FPGA_WORK_ROOT)/corejack_corejack_platform_0.1.0.runs/impl_1/runme.log
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
FPGA_ACCEPT_CORES ?=
OPENOCD_CFG    ?= rtl/platform/fpga/scripts/openocd.cfg
SIM_TIMEOUT_CYCLES ?= 1000000
SIM_FUSESOC_WORK_ROOT ?= $(CURDIR)/build/sim/fusesoc/$(CORE)/$(SIM_FUSESOC_TARGET)
SIM_WAVES      ?= 0
SIM_WAVE_FORMAT ?= fst
SIM_WAVE_DIR   ?= $(CURDIR)/build/waves
SIM_WAVE_FILE  ?=
ALLOW_PLANNED  ?= 0
FLOW           ?= all
AXI_SMOKE_CORES ?= ibex cv32e40p cv32e40s cva6 serv picorv32 cvw

DRAWIO         ?= drawio
DRAWIO_SRC     ?= docs/media/corejack_soc.drawio
DRAWIO_SVG_DIR ?= docs/media

ifeq ($(ALLOW_PLANNED),1)
VALIDATE_PLANNED_ARG := --allow-planned
else
VALIDATE_PLANNED_ARG :=
endif

TARGET_CONFIG := $(shell $(PYTHON) bin/validate_target.py --core "$(CORE)" --board "$(BOARD)" --make --allow-planned 2>/dev/null)
$(eval $(TARGET_CONFIG))
FUSESOC_CORE_FLAGS ?= $(FUSESOC_CORE_FLAG)
FUSESOC_FLAGS ?= $(FUSESOC_CORE_FLAGS) $(FUSESOC_BOARD_FLAG)
FUSESOC_FLAG_ARGS := $(foreach flag,$(FUSESOC_FLAGS),--flag $(flag))
SIM_TRACE_FUSESOC_FLAGS :=
ifeq ($(SIM_WAVES),1)
ifeq ($(SIM_WAVE_FORMAT),fst)
SIM_TRACE_FUSESOC_FLAGS := --flag trace_fst
else ifeq ($(SIM_WAVE_FORMAT),vcd)
SIM_TRACE_FUSESOC_FLAGS := --flag trace_vcd
else
$(error Unsupported SIM_WAVE_FORMAT='$(SIM_WAVE_FORMAT)'. Use fst or vcd)
endif
endif

.PHONY: help bender toolchain-riscv tool-verilator tool-verible zephyr-init zephyr-python-deps zephyr-build zephyr-check check-tools deps deps-update deps-base deps-core deps-vendor deps-all deps-serv deps-picorv32 deps-cvw deps-cv32e40p deps-cv32e40x deps-cv32e40s deps-cva6 new-board new-core support-matrix support-matrix-check version-check bump-version drawio-svg python-tests flist validate-target list-targets target-config board-check core-check target-check fpga-flist fpga-setup fpga-bit fpga-manifest fpga-report fpga-warning-check fpga-pgm fpga-debug-accept fpga-accept sw-build sw-build-hello list-apps sim-run-sw debug-sim axi-adapter-sim uart-loader-sim axi-addr-map-check axi-smoke openocd fpga-load-sw fpga-run-sw fpga-uart-load-sw fpga-uart-load-zephyr fpga-load-hello fpga-run-hello fpga-run-zephyr smoke plan clean distclean

help:
	@echo "Targets:"
	@printf '  %-18s %s\n' 'bender' 'fetch pinned bender binary into TOOLS_DIR'
	@printf '  %-18s %s\n' 'toolchain-riscv' 'build optional local RISC-V GNU multilib toolchain into TOOLS_DIR'
	@printf '  %-18s %s\n' 'tool-verilator' 'build optional local Verilator into TOOLS_DIR'
	@printf '  %-18s %s\n' 'tool-verible' 'install optional local Verible lint/format tools into TOOLS_DIR'
	@printf '  %-18s %s\n' 'zephyr-init' 'initialize/update project-local Zephyr workspace'
	@printf '  %-18s %s\n' 'zephyr-python-deps' 'install Zephyr build Python requirements into venv'
	@printf '  %-18s %s\n' 'zephyr-build' 'build Zephyr hello app for ZEPHYR_BOARD'
	@printf '  %-18s %s\n' 'zephyr-check' 'check Zephyr workspace/tooling assumptions'
	@printf '  %-18s %s\n' 'check-tools' 'report host tools for FLOW=all|sim|fpga|debug'
	@printf '  %-18s %s\n' 'deps' 'fetch base deps plus selected CORE dependency'
	@printf '  %-18s %s\n' 'deps-update' 'deliberately refresh Bender.lock, then checkout'
	@printf '  %-18s %s\n' 'deps-base' 'fetch shared base dependencies only'
	@printf '  %-18s %s\n' 'deps-core' 'fetch only the selected CORE dependency'
	@printf '  %-18s %s\n' 'deps-all' 'fetch all optional core dependencies'
	@printf '  %-18s %s\n' 'deps-serv' 'fetch SERV core dependency'
	@printf '  %-18s %s\n' 'deps-picorv32' 'fetch PicoRV32 core dependency'
	@printf '  %-18s %s\n' 'deps-cvw' 'fetch CVW/Wally core dependency'
	@printf '  %-18s %s\n' 'deps-cv32e40p' 'fetch CV32E40P core dependency'
	@printf '  %-18s %s\n' 'deps-cv32e40x' 'fetch CV32E40X core dependency'
	@printf '  %-18s %s\n' 'deps-cv32e40s' 'fetch CV32E40S core dependency'
	@printf '  %-18s %s\n' 'deps-cva6' 'fetch CVA6 core dependency'
	@printf '  %-18s %s\n' 'new-board' 'create descriptor/wrapper/XDC/FuseSoC scaffold for BOARD'
	@printf '  %-18s %s\n' 'new-core' 'create planned descriptor/adapter/FuseSoC scaffold for CORE'
	@printf '  %-18s %s\n' 'support-matrix' 'generate docs/support_matrix.md from descriptors'
	@printf '  %-18s %s\n' 'version-check' 'verify all .core files agree on a single VLNV version'
	@printf '  %-18s %s\n' 'bump-version' 'rewrite every CoreJack VLNV version (set VERSION=X.Y.Z)'
	@printf '  %-18s %s\n' 'drawio-svg' 'export each docs/media/corejack_soc.drawio tab to its own SVG'
	@printf '  %-18s %s\n' 'python-tests' 'run pytest coverage for Python utility scripts'
	@printf '  %-18s %s\n' 'flist' 'generate Bender flist at build/flist.f'
	@printf '  %-18s %s\n' 'list-targets' 'list descriptor-backed CORE and BOARD selections'
	@printf '  %-18s %s\n' 'target-config' 'show descriptor-derived config for CORE/BOARD'
	@printf '  %-18s %s\n' 'board-check' 'validate BOARD descriptor, wrapper, constraints, and debug config'
	@printf '  %-18s %s\n' 'core-check' 'validate CORE descriptor, adapter, enum, ISA, and board links'
	@printf '  %-18s %s\n' 'target-check' 'validate BOARD-compatible CORE descriptor matrix'
	@printf '  %-18s %s\n' 'fpga-flist' 'generate Vivado-oriented flist for CORE/BOARD'
	@printf '  %-18s %s\n' 'fpga-setup' 'generate the FuseSoC/Vivado build tree'
	@printf '  %-18s %s\n' 'fpga-bit' 'build the selected FPGA bitstream through FuseSoC/Vivado'
	@printf '  %-18s %s\n' 'fpga-manifest' 'backfill provenance manifest for an existing bitstream'
	@printf '  %-18s %s\n' 'fpga-report' 'write routed Vivado timing/route/utilization reports'
	@printf '  %-18s %s\n' 'fpga-warning-check' 'summarize Vivado warnings and fail on unreviewed IDs'
	@printf '  %-18s %s\n' 'fpga-pgm' 'program the selected bitstream through generated Vivado Makefile'
	@printf '  %-18s %s\n' 'fpga-debug-accept' 'run FPGA acceptance for CORE/BOARD'
	@printf '  %-18s %s\n' 'fpga-accept' 'run FPGA acceptance for board-compatible cores'
	@printf '  %-18s %s\n' '' 'set FW=baremetal|zephyr to select the firmware stack'
	@printf '  %-18s %s\n' '' 'set UART_DEV=/dev/ttyUSBx to capture/check expected UART output'
	@printf '  %-18s %s\n' '' 'set UART_LOADER=1 to enable the side-path UART SRAM loader in FPGA builds'
	@printf '  %-18s %s\n' '' 'use ALLOW_PLANNED=1 to intentionally try planned FPGA targets'
	@printf '  %-18s %s\n' 'sw-build' 'build SW_APP and emit ELF/bin/disassembly/banked RAM hex'
	@printf '  %-18s %s\n' '' 'select software platform with TARGET=fpga|sim'
	@printf '  %-18s %s\n' 'sw-build-hello' 'build the hello_world firmware image'
	@printf '  %-18s %s\n' 'list-apps' 'list C apps available via SW_APP=<name>'
	@printf '  %-18s %s\n' 'sim-run-sw' 'build TARGET=sim SW_APP and run cocotb software simulation'
	@printf '  %-18s %s\n' '' 'tests must use sim_ctrl_pass()/sim_ctrl_fail() and print via UART'
	@printf '  %-18s %s\n' '' 'set SIM_WAVES=1 SIM_WAVE_FORMAT=fst|vcd to dump optional waveforms'
	@printf '  %-18s %s\n' 'debug-sim' 'run debug-window and SBA integration regressions'
	@printf '  %-18s %s\n' 'axi-adapter-sim' 'run OBI-to-AXI and AXI-to-memory adapter regressions'
	@printf '  %-18s %s\n' 'uart-loader-sim' 'run side-path UART SRAM loader protocol regression'
	@printf '  %-18s %s\n' 'axi-addr-map-check' 'check AXI fabric address windows for overlap'
	@printf '  %-18s %s\n' 'axi-smoke' 'run AXI fabric regressions and supported-core SW sims'
	@printf '  %-18s %s\n' 'openocd' 'launch OpenOCD for the FPGA JTAG debug target'
	@printf '  %-18s %s\n' 'fpga-load-sw' 'build TARGET=fpga SW_APP, load ELF over OpenOCD/GDB, stay interactive'
	@printf '  %-18s %s\n' 'fpga-run-sw' 'build TARGET=fpga SW_APP, load/run ELF for GDB_TIMEOUT seconds'
	@printf '  %-18s %s\n' 'fpga-uart-load-sw' 'build/load/run SW_APP through UART SRAM loader'
	@printf '  %-18s %s\n' 'fpga-uart-load-zephyr' 'build/load/run Zephyr through UART SRAM loader'
	@printf '  %-18s %s\n' 'fpga-load-hello' 'load the hello_world ELF over OpenOCD/GDB, stay interactive'
	@printf '  %-18s %s\n' 'fpga-run-hello' 'load/run the hello_world ELF for GDB_TIMEOUT seconds'
	@printf '  %-18s %s\n' 'fpga-run-zephyr' 'build/load/run Zephyr app for GDB_TIMEOUT seconds'
	@printf '  %-18s %s\n' 'smoke' 'run FuseSoC cocotb+Verilator smoke target'
	@printf '  %-18s %s\n' 'plan' 'show the current CoreJack roadmap'
	@printf '  %-18s %s\n' 'clean' 'remove simulation and generated outputs'
	@printf '  %-18s %s\n' 'distclean' 'clean + remove tools and bender dependencies'

# File target — only runs when the binary is missing
$(BENDER_BIN):
	@mkdir -p "$(TOOLS_DIR)"
	@set -e; \
	tmp="$$(mktemp -d)"; \
	trap 'rm -rf "$$tmp"' EXIT; \
	asset="$(BENDER_ASSET)"; \
	sha256="$(BENDER_SHA256)"; \
	if [ -z "$$asset" ]; then \
		os="$$(uname -s | tr '[:upper:]' '[:lower:]')"; \
		arch="$$(uname -m | tr '[:upper:]' '[:lower:]')"; \
		case "$$os:$$arch" in \
			linux:x86_64|linux:amd64) asset="bender-$(BENDER_VERSION)-x86_64-linux-gnu.tar.gz"; sha256="f2f3bdaa28e812c607d8031350cc6c279955ebc24c915c891da0e81ad5957da0" ;; \
			linux:aarch64|linux:arm64) asset="bender-$(BENDER_VERSION)-arm64-linux-gnu.tar.gz"; sha256="b96f586026bf20c04fc298221f25a3e134ce17319195a0b00571c284dba72717" ;; \
			*) echo "Unsupported bender binary platform: $$os/$$arch"; rm -rf "$$tmp"; exit 1 ;; \
		esac; \
	fi; \
	if [ -z "$$sha256" ]; then \
		echo "No SHA256 configured for bender asset: $$asset"; \
		echo "Install bender manually and place it at $(BENDER_BIN)."; \
		rm -rf "$$tmp"; \
		exit 1; \
	fi; \
	url="$(BENDER_URL)"; \
	if [ -z "$$url" ]; then \
		url="https://github.com/pulp-platform/bender/releases/download/v$(BENDER_VERSION)/$$asset"; \
	fi; \
	echo "Downloading $$url"; \
	curl -fsSL "$$url" -o "$$tmp/bender.tgz"; \
	printf '%s  %s\n' "$$sha256" "$$tmp/bender.tgz" | sha256sum -c -; \
	mkdir -p "$$tmp/unpack" "$(BENDER_DIR)"; \
	tar -xzf "$$tmp/bender.tgz" -C "$$tmp/unpack"; \
	bin_path="$$(find "$$tmp/unpack" -type f -name bender | head -n1)"; \
	if [ -z "$$bin_path" ]; then \
		echo "Bender binary not found in downloaded archive."; \
		rm -rf "$$tmp"; \
		exit 1; \
	fi; \
	install -m 755 "$$bin_path" "$(BENDER_BIN)"; \
	rm -rf "$$tmp"
	@ln -sfn "bender-v$(BENDER_VERSION)/bender" "$(BENDER)"
	@echo "Installed bender $$($(BENDER) --version)"

# Convenience alias
bender: $(BENDER_BIN)

toolchain-riscv:
	@RISCV_TOOLCHAIN_PREFIX="$(RISCV_TOOLCHAIN_PREFIX)" \
	 RISCV_GNU_TOOLCHAIN_SRC="$(RISCV_GNU_TOOLCHAIN_SRC)" \
	 RISCV_GNU_TOOLCHAIN_REF="$(RISCV_GNU_TOOLCHAIN_REF)" \
	 RISCV_GNU_TOOLCHAIN_COMMIT="$(RISCV_GNU_TOOLCHAIN_COMMIT)" \
	 RISCV_MULTILIB_GENERATOR="$(RISCV_MULTILIB_GENERATOR)" \
	 RISCV_TOOLCHAIN_JOBS="$(RISCV_TOOLCHAIN_JOBS)" \
	 bin/build_riscv_toolchain.sh

tool-verilator:
	@VERILATOR_REF="$(VERILATOR_VERSION)" \
	 VERILATOR_COMMIT="$(VERILATOR_COMMIT)" \
	 VERILATOR_PREFIX="$(VERILATOR_PREFIX)" \
	 VERILATOR_SRC="$(VERILATOR_SRC)" \
	 VERILATOR_JOBS="$(VERILATOR_JOBS)" \
	 bin/build_verilator.sh

tool-verible:
	@VERIBLE_REF="$(VERIBLE_VERSION)" \
	 VERIBLE_PREFIX="$(VERIBLE_PREFIX)" \
	 VERIBLE_ARCHIVE_URL="$(VERIBLE_ARCHIVE_URL)" \
	 VERIBLE_ARCHIVE_SHA256="$(VERIBLE_ARCHIVE_SHA256)" \
	 VERIBLE_SHA256_LINUX_X86_64="$(VERIBLE_SHA256_LINUX_X86_64)" \
	 VERIBLE_SHA256_LINUX_ARM64="$(VERIBLE_SHA256_LINUX_ARM64)" \
	 bin/build_verible.sh

zephyr-init:
	@test -x "$(VENV_PY)" || { echo "Error: venv not found. Run: source ./sourceme.sh"; exit 1; }
	@mkdir -p "$(ZEPHYR_WORKSPACE)/corejack"
	@cp -a "$(CURDIR)/sw/zephyr/." "$(ZEPHYR_WORKSPACE)/corejack/"
	@if [ ! -d "$(ZEPHYR_WORKSPACE)/.west" ]; then \
		cd "$(ZEPHYR_WORKSPACE)" && "$(VENV_PY)" -m west init -l corejack; \
	fi
	@cd "$(ZEPHYR_WORKSPACE)" && "$(VENV_PY)" -m west update

zephyr-python-deps:
	@test -x "$(VENV_PY)" || { echo "Error: venv not found. Run: source ./sourceme.sh"; exit 1; }
	@test -d "$(ZEPHYR_BASE)" || { echo "Error: Zephyr tree not found: $(ZEPHYR_BASE). Run: make zephyr-init"; exit 1; }
	@"$(VENV_PY)" -m pip install \
		-r "$(ZEPHYR_BASE)/scripts/requirements-base.txt" \
		-r "$(ZEPHYR_BASE)/scripts/requirements-build-test.txt"

zephyr-check:
	@test -x "$(VENV_PY)" || { echo "Error: venv not found. Run: source ./sourceme.sh"; exit 1; }
	@"$(VENV_PY)" -m west --version
	@test -d "$(ZEPHYR_BASE)" || { echo "Error: Zephyr tree not found: $(ZEPHYR_BASE). Run: make zephyr-init"; exit 1; }
	@test -x "$(RISCV_TOOLCHAIN_PREFIX)/bin/riscv64-unknown-elf-gcc" || { echo "Error: RISC-V toolchain not found. Run: make toolchain-riscv"; exit 1; }
	@"$(VENV_PY)" -c 'import jsonschema' >/dev/null 2>&1 || { echo "Error: Zephyr Python build requirements missing. Run: make zephyr-python-deps"; exit 1; }

zephyr-build: zephyr-check validate-target
	@test "$(BOARD)" = "axku5" -o "$(BOARD)" = "arty_a7_100t" || { echo "Error: initial Zephyr support is BOARD=axku5 or BOARD=arty_a7_100t only"; exit 1; }
	@test "$(CORE)" = "ibex" -o "$(CORE)" = "cv32e40p" -o "$(CORE)" = "cv32e40s" -o "$(CORE)" = "cva6" -o "$(CORE)" = "serv" || { echo "Error: Zephyr support is CORE=ibex, CORE=cv32e40p, CORE=cv32e40s, CORE=cva6, or CORE=serv only"; exit 1; }
	@if [ "$(CORE)" = "cva6" ] && ! "$(RISCV_TOOLCHAIN_PREFIX)/bin/riscv64-unknown-elf-gcc" -march=rv64imc -mabi=lp64 -print-libgcc-file-name | grep -q '/rv64imc/lp64/libgcc.a$$'; then \
		echo "Error: CVA6 Zephyr requires the rv64imc/lp64 multilib."; \
		echo "Rebuild the local toolchain with: make toolchain-riscv"; \
		exit 1; \
	fi
	@ZEPHYR_BASE="$(ZEPHYR_BASE)" \
	 ZEPHYR_TOOLCHAIN_VARIANT=cross-compile \
	 CROSS_COMPILE="$(RISCV_TOOLCHAIN_PREFIX)/bin/riscv64-unknown-elf-" \
	 CCACHE_DISABLE=1 \
	 "$(VENV_PY)" -m west -z "$(ZEPHYR_BASE)" build \
		-p always \
		-b "$(ZEPHYR_BOARD)" \
		-d "$(ZEPHYR_BUILD_DIR)" \
		"$(CURDIR)/sw/zephyr" \
		-- \
		-DBOARD_ROOT="$(CURDIR)/sw/zephyr" \
		-DSOC_ROOT="$(CURDIR)/sw/zephyr" \
		-DDTS_ROOT="$(CURDIR)/sw/zephyr" \
		-DCOREJACK_CORE="$(CORE)" \
		-DCOREJACK_BOARD="$(BOARD)"

check-tools:
	@$(PYTHON) bin/check_tools.py --core "$(CORE)" --board "$(BOARD)" --flow "$(FLOW)"

deps: deps-base deps-core

deps-update: $(BENDER_BIN)
	@"$(BENDER)" update
	@"$(BENDER)" checkout

deps-base: $(BENDER_BIN)
	@"$(BENDER)" checkout
	@mkdir -p deps
	@for dep in axi apb apb_uart clint obi obi_peripherals register_interface riscv-dbg common_cells tech_cells_generic common_verification; do \
		path="$$("$(BENDER)" path "$$dep" 2>/dev/null || true)"; \
		if [ -n "$$path" ]; then ln -sfn "$$path" "deps/$$dep"; fi; \
	done

deps-core: deps-base
	@if [ "$(CORE)" = "cva6" ]; then \
		$(MAKE) deps-cva6; \
	else \
		$(PYTHON) bin/deps_core.py --core "$(CORE)"; \
	fi

deps-all: deps-base
	@if [ ! -f "$(CURDIR)/.bender/vendor/serv/serv.core" ] || \
	    [ ! -f "$(CURDIR)/.bender/vendor/picorv32/picorv32.v" ] || \
	    [ ! -f "$(CURDIR)/.bender/vendor/cvw/src/wally/wallypipelinedcore.sv" ] || \
	    [ ! -d "$(CURDIR)/.bender/vendor/cv32e40p/rtl" ] || \
	    [ ! -d "$(CURDIR)/.bender/vendor/cv32e40x/rtl" ] || \
	    [ ! -d "$(CURDIR)/.bender/vendor/cv32e40s/rtl" ]; then \
		"$(BENDER)" vendor init -n; \
	fi
	@ln -sfn "$(CURDIR)/.bender/vendor/serv" "deps/serv"
	@ln -sfn "$(CURDIR)/.bender/vendor/picorv32" "deps/picorv32"
	@rm -f "$(CURDIR)/.bender/vendor/picorv32/picorv32.core"
	@ln -sfn "$(CURDIR)/.bender/vendor/cvw" "deps/cvw"
	@ln -sfn "$(CURDIR)/.bender/vendor/cv32e40p" "deps/cv32e40p"
	@ln -sfn "$(CURDIR)/.bender/vendor/cv32e40x" "deps/cv32e40x"
	@ln -sfn "$(CURDIR)/.bender/vendor/cv32e40s" "deps/cv32e40s"

deps-vendor: deps-all

deps-serv: deps-base
	@$(PYTHON) bin/deps_core.py --core serv

deps-picorv32: deps-base
	@$(PYTHON) bin/deps_core.py --core picorv32

deps-cvw: deps-base
	@$(PYTHON) bin/deps_core.py --core cvw

deps-cv32e40p: deps-base
	@$(PYTHON) bin/deps_core.py --core cv32e40p

deps-cv32e40x: deps-base
	@$(PYTHON) bin/deps_core.py --core cv32e40x

deps-cv32e40s: deps-base
	@$(PYTHON) bin/deps_core.py --core cv32e40s

deps-cva6: deps-base
	@if [ ! -d "$(CURDIR)/.bender/vendor/cva6/.git" ]; then \
		git clone "$(CVA6_REPO)" "$(CURDIR)/.bender/vendor/cva6"; \
	fi
	@if ! git -C "$(CURDIR)/.bender/vendor/cva6" cat-file -e "$(CVA6_REV)^{commit}" 2>/dev/null; then \
		git -C "$(CURDIR)/.bender/vendor/cva6" fetch --tags --prune origin; \
	fi
	@git -C "$(CURDIR)/.bender/vendor/cva6" checkout --force "$(CVA6_REV)"
	@for patch in $(CVA6_PATCHES); do \
		echo "Applying CVA6 patch $$patch"; \
		git -C "$(CURDIR)/.bender/vendor/cva6" apply "$(CURDIR)/$$patch"; \
	done
	@ln -sfn "$(CURDIR)/.bender/vendor/cva6" "deps/cva6"

new-board:
	@test -n "$(FPGA_PART)" || { echo "Error: FPGA_PART is required, e.g. make new-board BOARD=myboard FPGA_PART=xc..."; exit 1; }
	@display_args=(); \
	if [ -n "$(BOARD_DISPLAY_NAME)" ]; then display_args+=(--display-name "$(BOARD_DISPLAY_NAME)"); fi; \
	$(PYTHON) bin/create_board.py \
		--board "$(NEW_BOARD)" \
		--part "$(FPGA_PART)" \
		"$${display_args[@]}"

new-core:
	@display_args=(); \
	if [ -n "$(CORE_DISPLAY_NAME)" ]; then display_args+=(--display-name "$(CORE_DISPLAY_NAME)"); fi; \
	$(PYTHON) bin/create_core.py \
		--core "$(NEW_CORE)" \
		--board "$(BOARD)" \
		--xlen "$(CORE_XLEN)" \
		--march "$(CORE_MARCH)" \
		--mabi "$(CORE_MABI)" \
		"$${display_args[@]}"

support-matrix:
	@$(PYTHON) bin/render_support_matrix.py

support-matrix-check:
	@$(PYTHON) bin/render_support_matrix.py --check

version-check:
	@$(PYTHON) bin/bump_version.py --check

bump-version:
	@test -n "$(VERSION)" || { echo "Error: VERSION required, e.g. make bump-version VERSION=0.2.0"; exit 1; }
	@$(PYTHON) bin/bump_version.py --to "$(VERSION)"

drawio-svg:
	@command -v $(DRAWIO) >/dev/null 2>&1 || { echo "Error: $(DRAWIO) not found in PATH (install drawio-desktop)"; exit 1; }
	@test -f "$(DRAWIO_SRC)" || { echo "Error: $(DRAWIO_SRC) not found"; exit 1; }
	@mkdir -p "$(DRAWIO_SVG_DIR)"
	@set -e; set -o pipefail; \
	stem=$$(basename "$(DRAWIO_SRC)" .drawio); \
	pages=$$(grep -oE '<diagram [^>]*name="[^"]*"' "$(DRAWIO_SRC)" | sed -E 's/.*name="([^"]*)".*/\1/'); \
	test -n "$$pages" || { echo "Error: no <diagram> pages found in $(DRAWIO_SRC)"; exit 1; }; \
	idx=0; \
	printf '%s\n' "$$pages" | while IFS= read -r name; do \
		idx=$$((idx+1)); \
		slug=$$(printf '%s' "$$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/^_//; s/_$$//'); \
		out="$(DRAWIO_SVG_DIR)/$${stem}_$${slug}.svg"; \
		echo "  EXPORT  $$out (page $$idx: $$name)"; \
		"$(DRAWIO)" -x -f svg \
			-p "$$idx" \
			-b 20 \
			-s 1 \
			--embed-svg-images \
			--embed-svg-fonts true \
			--svg-theme light \
			--svg-links-target auto \
			-o "$$out" \
			"$(DRAWIO_SRC)" 2>&1 | awk '!/vaInitialize|vaapi_wrapper|libva/'; \
		$(PYTHON) bin/postprocess_drawio_svg.py "$$out"; \
	done

python-tests:
	@$(PYTHON) -m pytest bin/tests

flist: deps-base
	@mkdir -p build
	@"$(BENDER)" script flist -t all > build/flist.f
	@echo "Generated build/flist.f"

validate-target:
	@$(PYTHON) bin/validate_target.py --core "$(CORE)" --board "$(BOARD)" --quiet $(VALIDATE_PLANNED_ARG)

list-targets:
	@$(PYTHON) bin/validate_target.py --list

target-config:
	@$(PYTHON) bin/validate_target.py --core "$(CORE)" --board "$(BOARD)" --allow-planned

board-check:
	@$(PYTHON) bin/validate_target.py --board "$(BOARD)" --board-check

core-check:
	@$(PYTHON) bin/validate_target.py --core "$(CORE)" --core-check

target-check:
	@$(PYTHON) bin/validate_target.py --board "$(BOARD)" --target-check

fpga-flist: validate-target deps-core
	@mkdir -p "$(FPGA_BUILD_DIR)"
	@PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" \
		fusesoc --cores-root . run --clean --target "$(FPGA_TARGET)" --work-root "$(FPGA_WORK_ROOT)" $(FUSESOC_FLAG_ARGS) --setup corejack:corejack:platform --CoreType="$(CORE_TYPE)" --EnableUartLoader="$(UART_LOADER)"
	@$(FPGA_PATCH_PROJECT_TCL) "$(FPGA_PROJECT_TCL)"
	@$(PYTHON) bin/vivado_tcl_to_flist.py --tcl "$(FPGA_PROJECT_TCL)" --work-root "$(FPGA_WORK_ROOT)" --out "$(FPGA_BUILD_DIR)/$(FPGA_TOP).f"
	@printf '%s\n' "-incdir $(CURDIR)/deps/apb/include -incdir $(CURDIR)/deps/axi/include -incdir $(CURDIR)/deps/obi/include -incdir $(CURDIR)/deps/register_interface/include -incdir $(CURDIR)/rtl/cores/vendored/corejack_ibex/include" > "$(FPGA_BUILD_DIR)/$(FPGA_TOP)_incdirs.txt"
	@echo "Generated $(FPGA_BUILD_DIR)/$(FPGA_TOP).f"

fpga-setup: validate-target deps-core
	@PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" \
		fusesoc --cores-root . run --clean --target "$(FPGA_TARGET)" --work-root "$(FPGA_WORK_ROOT)" $(FUSESOC_FLAG_ARGS) --setup corejack:corejack:platform --CoreType="$(CORE_TYPE)" --EnableUartLoader="$(UART_LOADER)"
	@$(FPGA_PATCH_PROJECT_TCL) "$(FPGA_PROJECT_TCL)"
	@echo "FuseSoC FPGA work root: $(FPGA_WORK_ROOT)"

fpga-bit: validate-target deps-core
	@PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" \
		fusesoc --cores-root . run --clean --target "$(FPGA_TARGET)" --work-root "$(FPGA_WORK_ROOT)" $(FUSESOC_FLAG_ARGS) --setup corejack:corejack:platform --CoreType="$(CORE_TYPE)" --EnableUartLoader="$(UART_LOADER)"
	@$(FPGA_PATCH_PROJECT_TCL) "$(FPGA_PROJECT_TCL)"
	@mkdir -p "$(VIVADO_HOME)"
	@HOME="$(VIVADO_HOME)" $(MAKE) -C "$(FPGA_WORK_ROOT)"
	@bin/write_bitstream_manifest.sh --core "$(CORE)" --board "$(BOARD)" --core-type "$(CORE_TYPE)" --uart-loader "$(UART_LOADER)" --bitstream "$(FPGA_WORK_ROOT)/corejack_corejack_platform_0.1.0.bit" --manifest "$(FPGA_WORK_ROOT)/.corejack_bitstream_manifest"
	@echo "FuseSoC FPGA work root: $(FPGA_WORK_ROOT)"
	@$(MAKE) fpga-report
	@$(MAKE) fpga-warning-check

fpga-manifest: validate-target
	@bin/write_bitstream_manifest.sh --core "$(CORE)" --board "$(BOARD)" --core-type "$(CORE_TYPE)" --uart-loader "$(UART_LOADER)" --bitstream "$(FPGA_WORK_ROOT)/corejack_corejack_platform_0.1.0.bit" --manifest "$(FPGA_WORK_ROOT)/.corejack_bitstream_manifest" --best-effort-timestamp

fpga-report:
	@test -f "$(FPGA_XPR)" || { echo "Error: Vivado project not found: $(FPGA_XPR)"; exit 1; }
	@mkdir -p "$(VIVADO_HOME)"
	@HOME="$(VIVADO_HOME)" vivado -notrace -mode batch -source "$(FPGA_REPORT_TCL)" -tclargs "$(FPGA_XPR)" "$(FPGA_REPORT_DIR)"
	@echo "Vivado reports: $(FPGA_REPORT_DIR)"

fpga-warning-check:
	@$(PYTHON) bin/check_vivado_warnings.py --allowlist "$(VIVADO_WARNING_ALLOWLIST)" $(VIVADO_WARNING_LOGS)

fpga-pgm: validate-target
	@mkdir -p "$(VIVADO_HOME)"
	@HOME="$(VIVADO_HOME)" $(MAKE) -C "$(FPGA_WORK_ROOT)" pgm

fpga-debug-accept:
	@bin/fpga_debug_acceptance.sh --board "$(BOARD)" --cores "$(CORE)" --firmware "$(FW)" --app "$(SW_APP)" --zephyr-app "$(ZEPHYR_APP)" --gdb-timeout "$(GDB_TIMEOUT)" --uart "$(UART_DEV)" --uart-timeout "$(UART_CAPTURE_TIMEOUT)"

fpga-accept:
	@bin/fpga_debug_acceptance.sh --board "$(BOARD)" --cores "$(FPGA_ACCEPT_CORES)" --firmware "$(FW)" --app "$(SW_APP)" --zephyr-app "$(ZEPHYR_APP)" --gdb-timeout "$(GDB_TIMEOUT)" --uart "$(UART_DEV)" --uart-timeout "$(UART_CAPTURE_TIMEOUT)"

sw-build:
	@$(MAKE) -C sw APP="$(SW_APP)" TARGET="$(TARGET)" CORE="$(CORE)" BOARD="$(BOARD)" TOOLCHAIN="$(TOOLCHAIN)" MARCH="$(MARCH)" MABI="$(MABI)" SOC_CLK_HZ="$(SOC_CLK_HZ)" UART_BAUD="$(UART_BAUD)" SOC_RAM_BYTES="$(SOC_RAM_BYTES)"

sw-build-hello:
	@$(MAKE) sw-build SW_APP=hello_world

list-apps:
	@$(MAKE) -C sw list-apps

sim-run-sw: TARGET := sim
sim-run-sw: deps-core sw-build
	@wave_file="$(SIM_WAVE_FILE)"; \
	if [ -z "$$wave_file" ]; then wave_file="$(SIM_WAVE_DIR)/$(SIM_FUSESOC_TARGET)-$(CORE)-$(SW_APP).$(SIM_WAVE_FORMAT)"; fi; \
	run_options="+MEM_PATH=$(SW_BUILD_DIR)"; \
	if [ "$(SIM_WAVES)" = "1" ]; then \
		mkdir -p "$$(dirname "$$wave_file")"; \
		echo "Waveform: $$wave_file"; \
		run_options="$$run_options --trace --trace-file $$wave_file"; \
	fi; \
	PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" \
		COREJACK_TIMEOUT_CYCLES='$(SIM_TIMEOUT_CYCLES)' \
		CCACHE_DISABLE=1 \
		fusesoc --cores-root . run --clean --target "$(SIM_FUSESOC_TARGET)" --tool verilator --work-root "$(SIM_FUSESOC_WORK_ROOT)" $(FUSESOC_FLAG_ARGS) $(SIM_TRACE_FUSESOC_FLAGS) corejack:corejack:platform --run_options="$$run_options"

debug-sim: deps-base
	@wave_file="$(SIM_WAVE_FILE)"; \
	if [ -z "$$wave_file" ]; then wave_file="$(SIM_WAVE_DIR)/debug-sim.$(SIM_WAVE_FORMAT)"; fi; \
	extra_args=(); \
	if [ "$(SIM_WAVES)" = "1" ]; then \
		mkdir -p "$$(dirname "$$wave_file")"; \
		echo "Waveform: $$wave_file"; \
		extra_args+=(--run_options="--trace --trace-file $$wave_file"); \
	fi; \
	PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" CCACHE_DISABLE=1 \
		fusesoc --cores-root . run --clean --target debug-sim --tool verilator $(SIM_TRACE_FUSESOC_FLAGS) corejack:corejack:platform "$${extra_args[@]}"

axi-adapter-sim: deps-base
	@wave_file="$(SIM_WAVE_FILE)"; \
	if [ -z "$$wave_file" ]; then wave_file="$(SIM_WAVE_DIR)/axi-adapter-sim.$(SIM_WAVE_FORMAT)"; fi; \
	extra_args=(); \
	if [ "$(SIM_WAVES)" = "1" ]; then \
		mkdir -p "$$(dirname "$$wave_file")"; \
		echo "Waveform: $$wave_file"; \
		extra_args+=(--run_options="--trace --trace-file $$wave_file"); \
	fi; \
	PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" CCACHE_DISABLE=1 \
		fusesoc --cores-root . run --clean --target axi-adapter-sim --tool verilator $(SIM_TRACE_FUSESOC_FLAGS) corejack:corejack:platform "$${extra_args[@]}"

uart-loader-sim: deps-base
	@wave_file="$(SIM_WAVE_FILE)"; \
	if [ -z "$$wave_file" ]; then wave_file="$(SIM_WAVE_DIR)/uart-loader-sim.$(SIM_WAVE_FORMAT)"; fi; \
	extra_args=(); \
	if [ "$(SIM_WAVES)" = "1" ]; then \
		mkdir -p "$$(dirname "$$wave_file")"; \
		echo "Waveform: $$wave_file"; \
		extra_args+=(--run_options="--trace --trace-file $$wave_file"); \
	fi; \
	PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" CCACHE_DISABLE=1 \
		fusesoc --cores-root . run --clean --target uart-loader-sim --tool verilator $(SIM_TRACE_FUSESOC_FLAGS) corejack:corejack:platform "$${extra_args[@]}"

axi-addr-map-check:
	@$(PYTHON) bin/check_axi_addr_map.py

axi-smoke: axi-addr-map-check axi-adapter-sim uart-loader-sim debug-sim
	@for core in $(AXI_SMOKE_CORES); do \
		echo "AXI smoke: sim-run-sw CORE=$$core"; \
		$(MAKE) sim-run-sw CORE="$$core" SW_APP=hello_world SIM_TIMEOUT_CYCLES="$(SIM_TIMEOUT_CYCLES)"; \
	done

openocd: validate-target
	@openocd -f "$(OPENOCD_CFG)"

fpga-load-sw: TARGET := fpga
fpga-load-sw: validate-target sw-build
	@rtl/platform/fpga/scripts/load_elf.sh "$(FW_ELF)"

fpga-run-sw: TARGET := fpga
fpga-run-sw: validate-target sw-build
	@COREJACK_GDB_RUN_MODE="$(FPGA_GDB_RUN_MODE)" rtl/platform/fpga/scripts/run_elf.sh "$(FW_ELF)" "$(GDB_TIMEOUT)"

fpga-uart-load-sw: TARGET := fpga
fpga-uart-load-sw: validate-target
	@test -n "$(UART_DEV)" || { echo "Error: UART_DEV is required, e.g. UART_DEV=/dev/serial/by-id/<uart>"; exit 1; }
	@$(MAKE) sw-build TARGET="$(TARGET)" CORE="$(CORE)" BOARD="$(BOARD)" SW_APP="$(SW_APP)"
	@extra_args=(); \
	if [ -n "$(UART_LOADER_EXPECT)" ]; then extra_args+=(--expect "$(UART_LOADER_EXPECT)"); fi; \
	$(PYTHON) bin/uart_sram_load.py \
		--uart "$(UART_DEV)" \
		--baud "$(UART_BAUD)" \
		--bin "$(FW_BIN)" \
		--addr "$(UART_LOADER_ADDR)" \
		--chunk-size "$(UART_LOADER_CHUNK_SIZE)" \
		--timeout "$(UART_LOADER_TIMEOUT)" \
		--capture-seconds "$(UART_CAPTURE_TIMEOUT)" \
		"$${extra_args[@]}"

fpga-load-hello:
	@$(MAKE) fpga-load-sw SW_APP=hello_world

fpga-run-hello:
	@$(MAKE) fpga-run-sw SW_APP=hello_world

fpga-run-zephyr: validate-target zephyr-build
	@COREJACK_GDB_ENTRY_SYMBOL="__start" \
	 COREJACK_GDB_RUN_MODE="$(FPGA_GDB_RUN_MODE)" \
	 rtl/platform/fpga/scripts/run_elf.sh "$(ZEPHYR_ELF)" "$(GDB_TIMEOUT)"

fpga-uart-load-zephyr: validate-target zephyr-build
	@test -n "$(UART_DEV)" || { echo "Error: UART_DEV is required, e.g. UART_DEV=/dev/serial/by-id/<uart>"; exit 1; }
	@test -f "$(ZEPHYR_BIN)" || { echo "Error: Zephyr binary not found: $(ZEPHYR_BIN)"; exit 1; }
	@extra_args=(); \
	if [ -n "$(UART_LOADER_EXPECT)" ]; then extra_args+=(--expect "$(UART_LOADER_EXPECT)"); fi; \
	$(PYTHON) bin/uart_sram_load.py \
		--uart "$(UART_DEV)" \
		--baud "$(UART_BAUD)" \
		--bin "$(ZEPHYR_BIN)" \
		--addr "$(UART_LOADER_ADDR)" \
		--chunk-size "$(UART_LOADER_CHUNK_SIZE)" \
		--timeout "$(UART_LOADER_TIMEOUT)" \
		--capture-seconds "$(UART_CAPTURE_TIMEOUT)" \
		"$${extra_args[@]}"

smoke: deps-base
	@test -x "$(VENV_PY)" || { echo "Error: venv not found. Run: source ./sourceme.sh"; exit 1; }
	@wave_file="$(SIM_WAVE_FILE)"; \
	if [ -z "$$wave_file" ]; then wave_file="$(SIM_WAVE_DIR)/smoke.$(SIM_WAVE_FORMAT)"; fi; \
	extra_args=(); \
	if [ "$(SIM_WAVES)" = "1" ]; then \
		mkdir -p "$$(dirname "$$wave_file")"; \
		echo "Waveform: $$wave_file"; \
		extra_args+=(--run_options="--trace --trace-file $$wave_file"); \
	fi; \
	PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" CCACHE_DISABLE=1 \
		fusesoc --cores-root . run --clean --target smoke --tool verilator $(SIM_TRACE_FUSESOC_FLAGS) corejack:corejack:platform "$${extra_args[@]}"

plan:
	@sed -n '1,240p' docs/roadmap.md

clean:
	@rm -rf build sw/build tb/sim_build tb/results.xml deps

distclean: clean
	@rm -rf "$(TOOLS_DIR)" .bender
