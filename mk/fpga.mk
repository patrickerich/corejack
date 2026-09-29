# SPDX-License-Identifier: Apache-2.0
#
# FPGA build, programming, debug, and acceptance.
# Included by the root Makefile; see it for the shared settings.

FPGA_BUILD_DIR := $(CURDIR)/build/fpga
FPGA_TOP       ?= corejack_$(BOARD)_wrap
FPGA_TARGET    ?= fpga-$(BOARD)
FPGA_WORK_ROOT ?= $(FPGA_BUILD_DIR)/$(BOARD)/$(CORE)/fusesoc-$(FPGA_TARGET)
UART_LOADER    ?= 0
# FuseSoC names the Vivado project after corejack.core's VLNV, so read the
# version from there: make bump-version rewrites only the .core files.
COREJACK_VERSION := $(shell sed -nE 's/^name: corejack:corejack:platform:([0-9.]+)$$/\1/p' corejack.core)
FPGA_PROJECT   := corejack_corejack_platform_$(COREJACK_VERSION)
FPGA_XPR       ?= $(FPGA_WORK_ROOT)/$(FPGA_PROJECT).xpr
FPGA_PROJECT_TCL ?= $(FPGA_WORK_ROOT)/$(FPGA_PROJECT).tcl
FPGA_REPORT_DIR ?= $(FPGA_WORK_ROOT)/reports
FPGA_REPORT_TCL ?= rtl/platform/fpga/scripts/report_vivado_impl.tcl
FPGA_PATCH_PROJECT_TCL ?= rtl/platform/fpga/scripts/patch_vivado_project_tcl.sh
VIVADO_HOME ?= $(CURDIR)/.cache/vivado-home
VIVADO_WARNING_ALLOWLIST ?= cfg/vivado_warning_allowlist.txt
VIVADO_CDC_ALLOWLIST ?= cfg/vivado_cdc_allowlist.txt
VIVADO_WARNING_LOGS ?= $(FPGA_WORK_ROOT)/$(FPGA_PROJECT).runs/synth_1/runme.log $(FPGA_WORK_ROOT)/$(FPGA_PROJECT).runs/impl_1/runme.log
FPGA_ACCEPT_CORES ?=
# External JTAG adapter for OpenOCD. The board descriptor provides the
# default (debug.jtag_adapter); set JTAG_ADAPTER=<name> on the command line
# to use a different probe, where rtl/platform/fpga/scripts/openocd-<name>.cfg
# must exist. OPENOCD_CFG remains overridable directly for fully custom files.
JTAG_ADAPTER   ?=
OPENOCD_CFG ?= rtl/platform/fpga/scripts/openocd-$(JTAG_ADAPTER).cfg

fpga-flist: validate-target deps-core ## generate Vivado-oriented flist for CORE/BOARD
	@mkdir -p "$(FPGA_BUILD_DIR)"
	@PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" \
		fusesoc --cores-root . run --clean --target "$(FPGA_TARGET)" --work-root "$(FPGA_WORK_ROOT)" $(FUSESOC_FLAG_ARGS) --setup corejack:corejack:platform --CoreType="$(CORE_TYPE)" --EnableUartLoader="$(UART_LOADER)" --RamWords="$(RAM_WORDS)"
	@$(FPGA_PATCH_PROJECT_TCL) "$(FPGA_PROJECT_TCL)"
	@$(PY) bin/vivado_tcl_to_flist.py --tcl "$(FPGA_PROJECT_TCL)" --work-root "$(FPGA_WORK_ROOT)" --out "$(FPGA_BUILD_DIR)/$(FPGA_TOP).f"
	@printf '%s\n' "-incdir $(CURDIR)/deps/apb/include -incdir $(CURDIR)/deps/axi/include -incdir $(CURDIR)/deps/obi/include -incdir $(CURDIR)/deps/register_interface/include -incdir $(CURDIR)/rtl/cores/vendored/corejack_ibex/include" > "$(FPGA_BUILD_DIR)/$(FPGA_TOP)_incdirs.txt"
	@echo "Generated $(FPGA_BUILD_DIR)/$(FPGA_TOP).f"

fpga-setup: validate-target deps-core ## generate the FuseSoC/Vivado build tree
	@PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" \
		fusesoc --cores-root . run --clean --target "$(FPGA_TARGET)" --work-root "$(FPGA_WORK_ROOT)" $(FUSESOC_FLAG_ARGS) --setup corejack:corejack:platform --CoreType="$(CORE_TYPE)" --EnableUartLoader="$(UART_LOADER)" --RamWords="$(RAM_WORDS)"
	@$(FPGA_PATCH_PROJECT_TCL) "$(FPGA_PROJECT_TCL)"
	@echo "FuseSoC FPGA work root: $(FPGA_WORK_ROOT)"

fpga-bit: validate-target deps-core ## build the selected FPGA bitstream through FuseSoC/Vivado
	@PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" \
		fusesoc --cores-root . run --clean --target "$(FPGA_TARGET)" --work-root "$(FPGA_WORK_ROOT)" $(FUSESOC_FLAG_ARGS) --setup corejack:corejack:platform --CoreType="$(CORE_TYPE)" --EnableUartLoader="$(UART_LOADER)" --RamWords="$(RAM_WORDS)"
	@$(FPGA_PATCH_PROJECT_TCL) "$(FPGA_PROJECT_TCL)"
	@mkdir -p "$(VIVADO_HOME)"
	@HOME="$(VIVADO_HOME)" $(MAKE) -C "$(FPGA_WORK_ROOT)"
	@bin/write_bitstream_manifest.sh --core "$(CORE)" --board "$(BOARD)" --core-type "$(CORE_TYPE)" --uart-loader "$(UART_LOADER)" --bitstream "$(FPGA_WORK_ROOT)/$(FPGA_PROJECT).bit" --manifest "$(FPGA_WORK_ROOT)/.corejack_bitstream_manifest"
	@echo "FuseSoC FPGA work root: $(FPGA_WORK_ROOT)"
	@$(MAKE) fpga-report
	@$(MAKE) fpga-warning-check
	@$(MAKE) fpga-cdc-check

fpga-manifest: validate-target ## backfill provenance manifest for an existing bitstream
	@bin/write_bitstream_manifest.sh --core "$(CORE)" --board "$(BOARD)" --core-type "$(CORE_TYPE)" --uart-loader "$(UART_LOADER)" --bitstream "$(FPGA_WORK_ROOT)/$(FPGA_PROJECT).bit" --manifest "$(FPGA_WORK_ROOT)/.corejack_bitstream_manifest" --best-effort-timestamp

fpga-report: ## write routed Vivado timing/route/utilization reports
	@test -f "$(FPGA_XPR)" || { echo "Error: Vivado project not found: $(FPGA_XPR)"; exit 1; }
	@mkdir -p "$(VIVADO_HOME)"
	@HOME="$(VIVADO_HOME)" vivado -notrace -mode batch -source "$(FPGA_REPORT_TCL)" -tclargs "$(FPGA_XPR)" "$(FPGA_REPORT_DIR)"
	@echo "Vivado reports: $(FPGA_REPORT_DIR)"

fpga-warning-check: ## summarize Vivado warnings and fail on unreviewed IDs
	@$(PY) bin/check_vivado_warnings.py --allowlist "$(VIVADO_WARNING_ALLOWLIST)" $(VIVADO_WARNING_LOGS)

fpga-cdc-check: ## summarize clock-domain crossings and fail on unreviewed ones
	@$(PY) bin/check_vivado_cdc.py --allowlist "$(VIVADO_CDC_ALLOWLIST)" "$(FPGA_REPORT_DIR)/cdc_crossings.tsv"

fpga-pgm: validate-target ## program the selected bitstream through generated Vivado Makefile
	@mkdir -p "$(VIVADO_HOME)"
	@HOME="$(VIVADO_HOME)" $(MAKE) -C "$(FPGA_WORK_ROOT)" pgm

fpga-debug-accept: ## run FPGA acceptance for CORE/BOARD
	@bin/fpga_debug_acceptance.sh --board "$(BOARD)" --cores "$(CORE)" --firmware "$(FW)" --app "$(SW_APP)" --zephyr-app "$(ZEPHYR_APP)" --gdb-timeout "$(GDB_TIMEOUT)" --uart "$(UART_DEV)" --uart-timeout "$(UART_CAPTURE_TIMEOUT)"

fpga-accept: ## run FPGA acceptance for board-compatible cores
	@bin/fpga_debug_acceptance.sh --board "$(BOARD)" --cores "$(FPGA_ACCEPT_CORES)" --firmware "$(FW)" --app "$(SW_APP)" --zephyr-app "$(ZEPHYR_APP)" --gdb-timeout "$(GDB_TIMEOUT)" --uart "$(UART_DEV)" --uart-timeout "$(UART_CAPTURE_TIMEOUT)"
## set FW=baremetal|zephyr to select the firmware stack
## set UART_DEV=/dev/ttyUSBx to capture/check expected UART output
## set UART_LOADER=1 to enable the side-path UART SRAM loader in FPGA builds
## use ALLOW_PLANNED=1 to intentionally try planned FPGA targets

openocd: validate-target ## launch OpenOCD for the FPGA JTAG debug target
	@openocd -f "$(OPENOCD_CFG)"

fpga-load-sw: TARGET := fpga
fpga-load-sw: validate-target sw-build ## build TARGET=fpga SW_APP, load ELF over OpenOCD/GDB, stay interactive
	@rtl/platform/fpga/scripts/load_elf.sh "$(FW_ELF)"

fpga-run-sw: TARGET := fpga
fpga-run-sw: validate-target sw-build ## build TARGET=fpga SW_APP, load/run ELF for GDB_TIMEOUT seconds
	@COREJACK_GDB_RUN_MODE="$(FPGA_GDB_RUN_MODE)" rtl/platform/fpga/scripts/run_elf.sh "$(FW_ELF)" "$(GDB_TIMEOUT)"

fpga-uart-load-sw: TARGET := fpga
fpga-uart-load-sw: validate-target ## build/load/run SW_APP through UART SRAM loader
	@test -n "$(UART_DEV)" || { echo "Error: UART_DEV is required, e.g. UART_DEV=/dev/serial/by-id/<uart>"; exit 1; }
	@$(MAKE) sw-build TARGET="$(TARGET)" CORE="$(CORE)" BOARD="$(BOARD)" SW_APP="$(SW_APP)"
	@extra_args=(); \
	if [ -n "$(UART_LOADER_EXPECT)" ]; then extra_args+=(--expect "$(UART_LOADER_EXPECT)"); fi; \
	$(PY) bin/uart_sram_load.py \
		--uart "$(UART_DEV)" \
		--baud "$(UART_BAUD)" \
		--bin "$(FW_BIN)" \
		--addr "$(UART_LOADER_ADDR)" \
		--chunk-size "$(UART_LOADER_CHUNK_SIZE)" \
		--timeout "$(UART_LOADER_TIMEOUT)" \
		--capture-seconds "$(UART_CAPTURE_TIMEOUT)" \
		"$${extra_args[@]}"

fpga-load-hello: ## load the hello_world ELF over OpenOCD/GDB, stay interactive
	@$(MAKE) fpga-load-sw SW_APP=hello_world

fpga-run-hello: ## load/run the hello_world ELF for GDB_TIMEOUT seconds
	@$(MAKE) fpga-run-sw SW_APP=hello_world

.PHONY: fpga-flist fpga-setup fpga-bit fpga-manifest fpga-report fpga-warning-check fpga-cdc-check fpga-pgm fpga-debug-accept fpga-accept openocd fpga-load-sw fpga-run-sw fpga-uart-load-sw fpga-load-hello fpga-run-hello
