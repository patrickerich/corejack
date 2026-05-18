#!/usr/bin/env bash
# Optional machine-local CoreJack environment overrides.
#
# Copy this file to sourceme.local.sh and edit it for your workstation.
# sourceme.local.sh is intentionally ignored by git.

# Repo-local generic multilib toolchain. This is the default.
# export COREJACK_TOOLCHAIN=riscv-multilib
# export COREJACK_RISCV_TOOLCHAIN="${PWD}/.tools/riscv"

# Repo-local Verilator. This is the default when .tools/verilator exists.
# export COREJACK_VERILATOR="${PWD}/.tools/verilator"

# Repo-local Verible. This is the default when .tools/verible exists.
# export COREJACK_VERIBLE="${PWD}/.tools/verible"

# Optional external riscv32 toolchain slot.
# export COREJACK_TOOLCHAIN=external-riscv32
# export COREJACK_IBEX_TOOLCHAIN=/path/to/riscv32/toolchain

# Optional vendor tool setup. Keep site-specific paths out of sourceme.sh.
# source /opt/Xilinx/2025.2.1/Vivado/settings64.sh
