APP ?= hello_world
TARGET ?= fpga
CORE ?= ibex
BOARD ?= axku5
BUILD_DIR ?= build
CMAKE_BUILD_DIR := $(BUILD_DIR)/$(TARGET)/$(CORE)/$(TOOLCHAIN)/$(APP)/cmake
ELF := $(CMAKE_BUILD_DIR)/$(APP)/$(APP)
BIN := $(BUILD_DIR)/$(TARGET)/$(CORE)/$(TOOLCHAIN)/$(APP)/$(APP).bin
DIS := $(BUILD_DIR)/$(TARGET)/$(CORE)/$(TOOLCHAIN)/$(APP)/$(APP).dis
NUM_BANKS ?= 4
TOOLCHAIN ?= riscv-multilib
MARCH ?= rv32imc
MABI ?= ilp32
SOC_CLK_HZ ?= 25000000
UART_BAUD ?= 115200
SOC_RAM_BYTES ?= 1048576
COREJACK_RISCV_TOOLCHAIN ?= $(abspath $(CURDIR)/../.tools/riscv)

ifeq ($(TOOLCHAIN),riscv-multilib)
TOOLCHAIN_PATH := $(COREJACK_RISCV_TOOLCHAIN)/bin:
CROSS_COMPILE := riscv64-unknown-elf-
else
$(error unsupported TOOLCHAIN='$(TOOLCHAIN)'. Available: riscv-multilib)
endif

.PHONY: all clean $(APP) list-apps force-hex FORCE

all: $(APP)

$(APP): $(BIN) $(DIS) force-hex

toolchain-check:
	@PATH="$(TOOLCHAIN_PATH)$$PATH" command -v "$(CROSS_COMPILE)gcc" >/dev/null 2>&1 || { \
		echo "Error: $(CROSS_COMPILE)gcc not found in PATH."; \
		echo "TOOLCHAIN=$(TOOLCHAIN), searched path prefix: $(TOOLCHAIN_PATH)"; \
		echo "Source ./sourceme.sh or set COREJACK_RISCV_TOOLCHAIN to point at the toolchain prefix."; \
		exit 1; \
	}
	@PATH="$(TOOLCHAIN_PATH)$$PATH" command -v "$(CROSS_COMPILE)objcopy" >/dev/null 2>&1 || { \
		echo "Error: $(CROSS_COMPILE)objcopy not found in PATH."; \
		echo "TOOLCHAIN=$(TOOLCHAIN), searched path prefix: $(TOOLCHAIN_PATH)"; \
		echo "Source ./sourceme.sh or set COREJACK_RISCV_TOOLCHAIN to point at the toolchain prefix."; \
		exit 1; \
	}
	@PATH="$(TOOLCHAIN_PATH)$$PATH" command -v "$(CROSS_COMPILE)objdump" >/dev/null 2>&1 || { \
		echo "Error: $(CROSS_COMPILE)objdump not found in PATH."; \
		echo "TOOLCHAIN=$(TOOLCHAIN), searched path prefix: $(TOOLCHAIN_PATH)"; \
		echo "Source ./sourceme.sh or set COREJACK_RISCV_TOOLCHAIN to point at the toolchain prefix."; \
		exit 1; \
	}

$(BIN) $(DIS): $(ELF)
	@mkdir -p "$(BUILD_DIR)/$(TARGET)/$(CORE)/$(TOOLCHAIN)/$(APP)"
	@PATH="$(TOOLCHAIN_PATH)$$PATH" "$(CROSS_COMPILE)objcopy" -O binary "$(ELF)" "$(BIN)"
	@PATH="$(TOOLCHAIN_PATH)$$PATH" "$(CROSS_COMPILE)objdump" -d "$(ELF)" > "$(DIS)"

force-hex: $(BUILD_DIR)/$(TARGET)/$(CORE)/$(TOOLCHAIN)/$(APP)/.hex-stamp

$(BUILD_DIR)/$(TARGET)/$(CORE)/$(TOOLCHAIN)/$(APP)/.hex-stamp: FORCE $(BIN) Makefile
	@mkdir -p "$(BUILD_DIR)/$(TARGET)/$(CORE)/$(TOOLCHAIN)/$(APP)"
	@rm -f "$(BUILD_DIR)/$(TARGET)/$(CORE)/$(TOOLCHAIN)/$(APP)"/bank_*.hex
	@hexdump -v -e '1/8 "%016x\n"' "$(BIN)" | \
	awk -v banks="$(NUM_BANKS)" -v outdir="$(BUILD_DIR)/$(TARGET)/$(CORE)/$(TOOLCHAIN)/$(APP)" '\
		{ \
			bank = (NR - 1) % banks; \
			print $$1 >> (outdir "/bank_" bank ".hex"); \
		} \
		END { \
			for (bank = 0; bank < banks; bank++) { \
				close(outdir "/bank_" bank ".hex"); \
			} \
		}'
	@for bank in $$(seq 0 $$(($(NUM_BANKS) - 1))); do \
		test -f "$(BUILD_DIR)/$(TARGET)/$(CORE)/$(TOOLCHAIN)/$(APP)/bank_$$bank.hex" || : > "$(BUILD_DIR)/$(TARGET)/$(CORE)/$(TOOLCHAIN)/$(APP)/bank_$$bank.hex"; \
	done
	@touch "$@"

$(BUILD_DIR)/$(TARGET)/$(CORE)/$(TOOLCHAIN)/$(APP)/bank_%.hex: $(BUILD_DIR)/$(TARGET)/$(CORE)/$(TOOLCHAIN)/$(APP)/.hex-stamp
	@test -f "$@" || : > "$@"

$(ELF): toolchain-check
	@mkdir -p "$(CMAKE_BUILD_DIR)"
	@cd c && PATH="$(TOOLCHAIN_PATH)$$PATH" cmake -B "../$(CMAKE_BUILD_DIR)" -DCMAKE_BUILD_TYPE=Release -DCOREJACK_CROSS_COMPILE="$(CROSS_COMPILE)" -DCOREJACK_TARGET="$(TARGET)" -DCOREJACK_CORE="$(CORE)" -DCOREJACK_BOARD="$(BOARD)" -DCOREJACK_MARCH="$(MARCH)" -DCOREJACK_MABI="$(MABI)" -DCOREJACK_CORE_CLK_HZ="$(SOC_CLK_HZ)" -DCOREJACK_UART_BAUD="$(UART_BAUD)" -DCOREJACK_RAM_BYTES="$(SOC_RAM_BYTES)" .
	@PATH="$(TOOLCHAIN_PATH)$$PATH" cmake --build "$(CMAKE_BUILD_DIR)" --target "$(APP)"

list-apps:
	@find c -mindepth 1 -maxdepth 1 -type d ! -name common -printf '%f\n' | sort

clean:
	rm -rf "$(BUILD_DIR)"
