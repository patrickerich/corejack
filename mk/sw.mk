# SPDX-License-Identifier: Apache-2.0
#
# Bare-metal software builds: the CMake project in sw/c, turned into the ELF,
# binary, disassembly, and banked RAM preload images under sw/build.
# Included by the root Makefile; see it for the shared settings.

# sw-build calls back into this Makefile for sw-image with TARGET, SW_APP, and
# the descriptor settings on the command line. The file targets below are named
# after TARGET and SW_APP, and make expands target names when it reads the
# Makefile - before a target-specific TARGET (sim-run-sw's, fpga-load-sw's)
# would apply - so only a fresh invocation builds into the right directory.
SW_CMAKE_BUILD_DIR = $(SW_BUILD_DIR)/cmake
SW_DIS             = $(SW_BUILD_DIR)/$(SW_APP).dis
# Marker token written into each CMake build dir after a successful configure.
# Bump this whenever the build-dir layout changes in a way an incremental
# reconfigure cannot recover from (e.g. a moved/renamed linker script), so a
# pre-existing build dir is wiped and reconfigured cleanly instead of failing.
# Layout 1 = static sw/common/link.ld; layout 2 = generated link.ld.in.
SW_BUILD_LAYOUT := 2
# Interleave width of the bank_<n>.hex preload split. Derived from the RTL so
# the images cannot drift from what soc_mem_bank reads back:
# mem_ss_pkg::MemNumBanksDefault is the single source of truth, and soc_top's
# MemNumBanks parameter defaults to it. Set NUM_BANKS on the command line only
# to match a deliberately overridden MemNumBanks. Read only when an image is
# built, so every other target works without it.
ifeq ($(origin NUM_BANKS),undefined)
NUM_BANKS = $(shell python3 $(CURDIR)/bin/validate_target.py --mem-num-banks)
endif
COREJACK_RISCV_TOOLCHAIN ?= $(TOOLS_DIR)/riscv
# riscv-multilib is the only TOOLCHAIN; sw-toolchain-check rejects any other.
SW_TOOLCHAIN_PATH := $(COREJACK_RISCV_TOOLCHAIN)/bin:
SW_CROSS_COMPILE  := riscv64-unknown-elf-

sw-build: ## build SW_APP and emit ELF/bin/disassembly/banked RAM hex
	@$(MAKE) --no-print-directory sw-image SW_APP="$(SW_APP)" TARGET="$(TARGET)" CORE="$(CORE)" BOARD="$(BOARD)" TOOLCHAIN="$(TOOLCHAIN)" MARCH="$(MARCH)" MABI="$(MABI)" SOC_CLK_HZ="$(SOC_CLK_HZ)" UART_BAUD="$(UART_BAUD)" SOC_RAM_BYTES="$(SOC_RAM_BYTES)"
## select software platform with TARGET=fpga|sim

sw-build-hello: ## build the hello_world firmware image
	@$(MAKE) sw-build SW_APP=hello_world

list-apps: ## list C apps available via SW_APP=<name>
	@find sw/c -mindepth 1 -maxdepth 1 -type d ! -name common -printf '%f\n' | sort

sw-clean: ## remove all software build outputs (sw/build)
	rm -rf "$(CURDIR)/sw/build"

# The image itself; run through sw-build (see above).
sw-image: $(FW_BIN) $(SW_DIS) sw-force-hex

sw-toolchain-check:
	@test "$(TOOLCHAIN)" = riscv-multilib || { echo "Error: unsupported TOOLCHAIN='$(TOOLCHAIN)'. Available: riscv-multilib"; exit 1; }
	@PATH="$(SW_TOOLCHAIN_PATH)$$PATH" command -v "$(SW_CROSS_COMPILE)gcc" >/dev/null 2>&1 || { \
		echo "Error: $(SW_CROSS_COMPILE)gcc not found in PATH."; \
		echo "TOOLCHAIN=$(TOOLCHAIN), searched path prefix: $(SW_TOOLCHAIN_PATH)"; \
		echo "Source ./sourceme.sh or set COREJACK_RISCV_TOOLCHAIN to point at the toolchain prefix."; \
		exit 1; \
	}
	@PATH="$(SW_TOOLCHAIN_PATH)$$PATH" command -v "$(SW_CROSS_COMPILE)objcopy" >/dev/null 2>&1 || { \
		echo "Error: $(SW_CROSS_COMPILE)objcopy not found in PATH."; \
		echo "TOOLCHAIN=$(TOOLCHAIN), searched path prefix: $(SW_TOOLCHAIN_PATH)"; \
		echo "Source ./sourceme.sh or set COREJACK_RISCV_TOOLCHAIN to point at the toolchain prefix."; \
		exit 1; \
	}
	@PATH="$(SW_TOOLCHAIN_PATH)$$PATH" command -v "$(SW_CROSS_COMPILE)objdump" >/dev/null 2>&1 || { \
		echo "Error: $(SW_CROSS_COMPILE)objdump not found in PATH."; \
		echo "TOOLCHAIN=$(TOOLCHAIN), searched path prefix: $(SW_TOOLCHAIN_PATH)"; \
		echo "Source ./sourceme.sh or set COREJACK_RISCV_TOOLCHAIN to point at the toolchain prefix."; \
		exit 1; \
	}

$(FW_BIN) $(SW_DIS): $(FW_ELF)
	@mkdir -p "$(SW_BUILD_DIR)"
	@PATH="$(SW_TOOLCHAIN_PATH)$$PATH" "$(SW_CROSS_COMPILE)objcopy" -O binary "$(FW_ELF)" "$(FW_BIN)"
	@PATH="$(SW_TOOLCHAIN_PATH)$$PATH" "$(SW_CROSS_COMPILE)objdump" -d "$(FW_ELF)" > "$(SW_DIS)"

sw-force-hex: $(SW_BUILD_DIR)/.hex-stamp

$(SW_BUILD_DIR)/.hex-stamp: FORCE $(FW_BIN) mk/sw.mk
	@set -e; banks="$(NUM_BANKS)"; \
	test -n "$$banks" || { echo "Error: NUM_BANKS is empty: cannot read mem_ss_pkg::MemNumBanksDefault via validate_target.py"; exit 1; }; \
	mkdir -p "$(SW_BUILD_DIR)"; \
	rm -f "$(SW_BUILD_DIR)"/bank_*.hex; \
	hexdump -v -e '1/8 "%016x\n"' "$(FW_BIN)" | \
	awk -v banks="$$banks" -v outdir="$(SW_BUILD_DIR)" '\
		{ \
			bank = (NR - 1) % banks; \
			print $$1 >> (outdir "/bank_" bank ".hex"); \
		} \
		END { \
			for (bank = 0; bank < banks; bank++) { \
				close(outdir "/bank_" bank ".hex"); \
			} \
		}'; \
	for bank in $$(seq 0 $$(($$banks - 1))); do \
		test -f "$(SW_BUILD_DIR)/bank_$$bank.hex" || : > "$(SW_BUILD_DIR)/bank_$$bank.hex"; \
	done
	@touch "$@"

$(SW_BUILD_DIR)/bank_%.hex: $(SW_BUILD_DIR)/.hex-stamp
	@test -f "$@" || : > "$@"

$(FW_ELF): sw-toolchain-check
	@if [ -e "$(SW_CMAKE_BUILD_DIR)/CMakeCache.txt" ] && [ "$$(cat "$(SW_CMAKE_BUILD_DIR)/.layout-version" 2>/dev/null)" != "$(SW_BUILD_LAYOUT)" ]; then \
		echo "sw: build dir layout changed or pre-dates layout $(SW_BUILD_LAYOUT); wiping $(SW_CMAKE_BUILD_DIR) for a clean reconfigure"; \
		rm -rf "$(SW_CMAKE_BUILD_DIR)"; \
	fi
	@mkdir -p "$(SW_CMAKE_BUILD_DIR)"
	@cd sw/c && PATH="$(SW_TOOLCHAIN_PATH)$$PATH" cmake -B "$(SW_CMAKE_BUILD_DIR)" -DCMAKE_BUILD_TYPE=Release -DCOREJACK_CROSS_COMPILE="$(SW_CROSS_COMPILE)" -DCOREJACK_TARGET="$(TARGET)" -DCOREJACK_CORE="$(CORE)" -DCOREJACK_BOARD="$(BOARD)" -DCOREJACK_MARCH="$(MARCH)" -DCOREJACK_MABI="$(MABI)" -DCOREJACK_CORE_CLK_HZ="$(SOC_CLK_HZ)" -DCOREJACK_UART_BAUD="$(UART_BAUD)" -DCOREJACK_RAM_BYTES="$(SOC_RAM_BYTES)" .
	@PATH="$(SW_TOOLCHAIN_PATH)$$PATH" cmake --build "$(SW_CMAKE_BUILD_DIR)" --target "$(SW_APP)"
	@printf '%s\n' "$(SW_BUILD_LAYOUT)" > "$(SW_CMAKE_BUILD_DIR)/.layout-version"

.PHONY: sw-build sw-build-hello list-apps sw-clean sw-image sw-toolchain-check sw-force-hex FORCE
