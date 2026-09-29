# SPDX-License-Identifier: Apache-2.0
#
# Zephyr workspace, builds, and FPGA runs.
# Included by the root Makefile; see it for the shared settings.

ZEPHYR_WORKSPACE ?= $(TOOLS_DIR)/zephyrproject
ZEPHYR_BASE ?= $(ZEPHYR_WORKSPACE)/zephyr
# The app zephyr-build compiles: CoreJack's demo by default, or any Zephyr app
# directory (set ZEPHYR_APP too, which names its build directory).
ZEPHYR_APP_DIR ?= $(CURDIR)/sw/zephyr
# fpga-zephyr-shell: Zephyr's shell sample, left running for this many seconds.
ZEPHYR_SHELL_APP_DIR ?= $(ZEPHYR_BASE)/samples/subsys/shell/shell_module
ZEPHYR_SHELL_TIMEOUT ?= 3600
ZEPHYR_BOARD ?= corejack_$(CORE)_$(BOARD)
ZEPHYR_BUILD_DIR ?= $(CURDIR)/sw/build/zephyr/$(ZEPHYR_BOARD)/$(ZEPHYR_APP)
ZEPHYR_ELF ?= $(ZEPHYR_BUILD_DIR)/zephyr/zephyr.elf
ZEPHYR_BIN ?= $(ZEPHYR_BUILD_DIR)/zephyr/zephyr.bin

zephyr-init: ## initialize/update project-local Zephyr workspace
	@test -x "$(VENV_PY)" || { echo "Error: venv not found. Run: source ./sourceme.sh"; exit 1; }
	@mkdir -p "$(ZEPHYR_WORKSPACE)/corejack"
	@cp -a "$(CURDIR)/sw/zephyr/." "$(ZEPHYR_WORKSPACE)/corejack/"
	@if [ ! -d "$(ZEPHYR_WORKSPACE)/.west" ]; then \
		cd "$(ZEPHYR_WORKSPACE)" && "$(VENV_PY)" -m west init -l corejack; \
	fi
	@cd "$(ZEPHYR_WORKSPACE)" && "$(VENV_PY)" -m west update

zephyr-python-deps: ## install Zephyr build Python requirements into venv
	@test -x "$(VENV_PY)" || { echo "Error: venv not found. Run: source ./sourceme.sh"; exit 1; }
	@test -d "$(ZEPHYR_BASE)" || { echo "Error: Zephyr tree not found: $(ZEPHYR_BASE). Run: make zephyr-init"; exit 1; }
	@"$(VENV_PY)" -m pip install \
		-r "$(ZEPHYR_BASE)/scripts/requirements-base.txt" \
		-r "$(ZEPHYR_BASE)/scripts/requirements-build-test.txt"

zephyr-check: ## check Zephyr workspace/tooling assumptions
	@test -x "$(VENV_PY)" || { echo "Error: venv not found. Run: source ./sourceme.sh"; exit 1; }
	@"$(VENV_PY)" -m west --version
	@test -d "$(ZEPHYR_BASE)" || { echo "Error: Zephyr tree not found: $(ZEPHYR_BASE). Run: make zephyr-init"; exit 1; }
	@test -x "$(RISCV_TOOLCHAIN_PREFIX)/bin/riscv64-unknown-elf-gcc" || { echo "Error: RISC-V toolchain not found. Run: make toolchain-riscv"; exit 1; }
	@"$(VENV_PY)" -c 'import jsonschema' >/dev/null 2>&1 || { echo "Error: Zephyr Python build requirements missing. Run: make zephyr-python-deps"; exit 1; }

zephyr-build: zephyr-check validate-target ## build Zephyr hello app for ZEPHYR_BOARD
	@test "$(BOARD)" = "axku5" -o "$(BOARD)" = "arty_a7_100t" || { echo "Error: initial Zephyr support is BOARD=axku5 or BOARD=arty_a7_100t only"; exit 1; }
	@test "$(CORE)" = "ibex" -o "$(CORE)" = "cv32e40p" -o "$(CORE)" = "cv32e40s" -o "$(CORE)" = "cva6" -o "$(CORE)" = "serv" || { echo "Error: Zephyr support is CORE=ibex, CORE=cv32e40p, CORE=cv32e40s, CORE=cva6, or CORE=serv only"; exit 1; }
	@multilib_dir="$$("$(RISCV_TOOLCHAIN_PREFIX)/bin/riscv64-unknown-elf-gcc" -march=rv64imc -mabi=lp64 -print-multi-directory 2>/dev/null)"; \
	if [ "$(CORE)" = "cva6" ] && { [ -z "$$multilib_dir" ] || [ "$$multilib_dir" = "." ]; }; then \
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
		"$(ZEPHYR_APP_DIR)" \
		-- \
		--no-warn-unused-cli \
		-DBOARD_ROOT="$(CURDIR)/sw/zephyr" \
		-DSOC_ROOT="$(CURDIR)/sw/zephyr" \
		-DDTS_ROOT="$(CURDIR)/sw/zephyr" \
		-DCOREJACK_CORE="$(CORE)" \
		-DCOREJACK_BOARD="$(BOARD)" \
		-DDTS_EXTRA_CPPFLAGS="-DCOREJACK_RAM_BYTES=$(SOC_RAM_BYTES)"

fpga-run-zephyr: validate-target zephyr-build ## build/load/run Zephyr app for GDB_TIMEOUT seconds
	@COREJACK_GDB_ENTRY_SYMBOL="__start" \
	 COREJACK_GDB_RUN_MODE="$(FPGA_GDB_RUN_MODE)" \
	 rtl/platform/fpga/scripts/run_elf.sh "$(ZEPHYR_ELF)" "$(GDB_TIMEOUT)"

# Zephyr's shell sample on the board UART, loaded over JTAG like fpga-run-zephyr
# and left running for ZEPHYR_SHELL_TIMEOUT seconds (Ctrl-C ends it sooner).
fpga-zephyr-shell: validate-target ## build/load/run the Zephyr shell on the board UART (needs make openocd)
	@$(PY) bin/validate_target.py --core "$(CORE)" --board "$(BOARD)" --flow debug --quiet >/dev/null 2>&1 || \
		{ echo "Error: fpga-zephyr-shell loads over JTAG, and CORE=$(CORE) has no supported debug path on BOARD=$(BOARD)"; exit 1; }
	@$(MAKE) --no-print-directory fpga-run-zephyr ZEPHYR_APP=shell ZEPHYR_APP_DIR="$(ZEPHYR_SHELL_APP_DIR)" GDB_TIMEOUT="$(ZEPHYR_SHELL_TIMEOUT)"

fpga-uart-load-zephyr: validate-target zephyr-build ## build/load/run Zephyr through UART SRAM loader
	@test -n "$(UART_DEV)" || { echo "Error: UART_DEV is required, e.g. UART_DEV=/dev/serial/by-id/<uart>"; exit 1; }
	@test -f "$(ZEPHYR_BIN)" || { echo "Error: Zephyr binary not found: $(ZEPHYR_BIN)"; exit 1; }
	@extra_args=(); \
	if [ -n "$(UART_LOADER_EXPECT)" ]; then extra_args+=(--expect "$(UART_LOADER_EXPECT)"); fi; \
	$(PY) bin/uart_sram_load.py \
		--uart "$(UART_DEV)" \
		--baud "$(UART_BAUD)" \
		--bin "$(ZEPHYR_BIN)" \
		--addr "$(UART_LOADER_ADDR)" \
		--chunk-size "$(UART_LOADER_CHUNK_SIZE)" \
		--timeout "$(UART_LOADER_TIMEOUT)" \
		--capture-seconds "$(UART_CAPTURE_TIMEOUT)" \
		"$${extra_args[@]}"

.PHONY: zephyr-init zephyr-python-deps zephyr-build zephyr-check fpga-run-zephyr fpga-zephyr-shell fpga-uart-load-zephyr
