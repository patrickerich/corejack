# SPDX-License-Identifier: Apache-2.0
#
# Simulation: the cocotb/Verilator smoke, software sims, benches, and axi-smoke.
# Included by the root Makefile; see it for the shared settings.

SIM_TIMEOUT_CYCLES ?= 1000000
MEM_BW_TIMEOUT_CYCLES ?= 4000000
SIM_FUSESOC_WORK_ROOT ?= $(CURDIR)/build/sim/fusesoc/$(CORE)/$(SIM_FUSESOC_TARGET)
SIM_WAVES      ?= 0
SIM_WAVE_FORMAT ?= fst
SIM_WAVE_DIR   ?= $(CURDIR)/build/waves
SIM_WAVE_FILE  ?=
# The common_cells ASSERT macros run in simulation by default; SIM_ASSERTS=0
# turns them off (FuseSoC flag asserts_off). Plain SystemVerilog asserts
# always run.
SIM_ASSERTS    ?= 1
# sv-tb: which self-checking SystemVerilog bench to run, and whether it uses
# the Xilinx SRAM slice (1) or the simulation model (0).
TB             ?=
SV_TB_XILINX_SRAM ?= 0

# Edalize builds the verilated model with a plain `make -f Vtop.mk`, i.e. serial.
# Measured: a full axi-smoke took the same 148s per core on 4 CPUs as on 16,
# because nothing was ever parallel. Pass -j through so the model build uses the
# machine it is on -- 4 on a CI runner, all cores locally.
SIM_BUILD_JOBS   ?= $(shell nproc 2>/dev/null || echo 4)
SIM_MAKE_OPTIONS ?= --make_options=-j$(SIM_BUILD_JOBS)

SIM_ASSERT_FUSESOC_FLAGS := $(if $(filter 0,$(SIM_ASSERTS)),--flag asserts_off,)

SV_TB_BENCHES := tb_mem_ss tb_axi_to_mem
SV_TB_SLICE   := $(if $(filter 1,$(SV_TB_XILINX_SRAM)),xilinx,model)

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

sim-run-sw: TARGET := sim
sim-run-sw: deps-core sw-build ## build TARGET=sim SW_APP and run cocotb software simulation
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
		fusesoc --cores-root . run --clean --target "$(SIM_FUSESOC_TARGET)" --tool verilator --work-root "$(SIM_FUSESOC_WORK_ROOT)" $(FUSESOC_FLAG_ARGS) $(SIM_TRACE_FUSESOC_FLAGS) $(SIM_ASSERT_FUSESOC_FLAGS) corejack:corejack:platform $(SIM_MAKE_OPTIONS) --run_options="$$run_options"
## tests must use sim_ctrl_pass()/sim_ctrl_fail() and print via UART
## set SIM_WAVES=1 SIM_WAVE_FORMAT=fst|vcd to dump optional waveforms
## set SIM_ASSERTS=0 to disable the common_cells IP assertions

cva6-reset-sim: deps-base deps-cva6 ## run CVA6 AXI reset-isolation regression
	@wave_file="$(SIM_WAVE_FILE)"; \
	if [ -z "$$wave_file" ]; then wave_file="$(SIM_WAVE_DIR)/cva6-reset-sim.$(SIM_WAVE_FORMAT)"; fi; \
	extra_args=(); \
	if [ "$(SIM_WAVES)" = "1" ]; then \
		mkdir -p "$$(dirname "$$wave_file")"; \
		echo "Waveform: $$wave_file"; \
		extra_args+=(--run_options="--trace --trace-file $$wave_file"); \
	fi; \
	PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" CCACHE_DISABLE=1 \
		fusesoc --cores-root . run --clean --target cva6-reset-sim --tool verilator $(SIM_TRACE_FUSESOC_FLAGS) $(SIM_ASSERT_FUSESOC_FLAGS) corejack:corejack:platform $(SIM_MAKE_OPTIONS) "$${extra_args[@]}"

# Appends the ibex, cv32e40p and cv32e40s filesets (see corejack.core), so it
# needs those cores fetched -- deps-base alone leaves fusesoc unable to find
# them on a clean checkout.
debug-sim: deps-base deps-cv32e40p deps-cv32e40s ## run debug-window and SBA integration regressions
	@wave_file="$(SIM_WAVE_FILE)"; \
	if [ -z "$$wave_file" ]; then wave_file="$(SIM_WAVE_DIR)/debug-sim.$(SIM_WAVE_FORMAT)"; fi; \
	extra_args=(); \
	if [ "$(SIM_WAVES)" = "1" ]; then \
		mkdir -p "$$(dirname "$$wave_file")"; \
		echo "Waveform: $$wave_file"; \
		extra_args+=(--run_options="--trace --trace-file $$wave_file"); \
	fi; \
	PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" CCACHE_DISABLE=1 \
		fusesoc --cores-root . run --clean --target debug-sim --tool verilator $(SIM_TRACE_FUSESOC_FLAGS) $(SIM_ASSERT_FUSESOC_FLAGS) corejack:corejack:platform $(SIM_MAKE_OPTIONS) "$${extra_args[@]}"

axi-adapter-sim: deps-base ## run OBI-to-AXI and AXI-to-memory adapter regressions
	@wave_file="$(SIM_WAVE_FILE)"; \
	if [ -z "$$wave_file" ]; then wave_file="$(SIM_WAVE_DIR)/axi-adapter-sim.$(SIM_WAVE_FORMAT)"; fi; \
	extra_args=(); \
	if [ "$(SIM_WAVES)" = "1" ]; then \
		mkdir -p "$$(dirname "$$wave_file")"; \
		echo "Waveform: $$wave_file"; \
		extra_args+=(--run_options="--trace --trace-file $$wave_file"); \
	fi; \
	PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" CCACHE_DISABLE=1 \
		fusesoc --cores-root . run --clean --target axi-adapter-sim --tool verilator $(SIM_TRACE_FUSESOC_FLAGS) $(SIM_ASSERT_FUSESOC_FLAGS) corejack:corejack:platform $(SIM_MAKE_OPTIONS) "$${extra_args[@]}"

uart-loader-sim: deps-base ## run side-path UART SRAM loader protocol regression
	@wave_file="$(SIM_WAVE_FILE)"; \
	if [ -z "$$wave_file" ]; then wave_file="$(SIM_WAVE_DIR)/uart-loader-sim.$(SIM_WAVE_FORMAT)"; fi; \
	extra_args=(); \
	if [ "$(SIM_WAVES)" = "1" ]; then \
		mkdir -p "$$(dirname "$$wave_file")"; \
		echo "Waveform: $$wave_file"; \
		extra_args+=(--run_options="--trace --trace-file $$wave_file"); \
	fi; \
	PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" CCACHE_DISABLE=1 \
		fusesoc --cores-root . run --clean --target uart-loader-sim --tool verilator $(SIM_TRACE_FUSESOC_FLAGS) $(SIM_ASSERT_FUSESOC_FLAGS) corejack:corejack:platform $(SIM_MAKE_OPTIONS) "$${extra_args[@]}"

plic-sim: deps-base ## run soc_plic claim/complete and gateway regression
	@wave_file="$(SIM_WAVE_FILE)"; \
	if [ -z "$$wave_file" ]; then wave_file="$(SIM_WAVE_DIR)/plic-sim.$(SIM_WAVE_FORMAT)"; fi; \
	extra_args=(); \
	if [ "$(SIM_WAVES)" = "1" ]; then \
		mkdir -p "$$(dirname "$$wave_file")"; \
		echo "Waveform: $$wave_file"; \
		extra_args+=(--run_options="--trace --trace-file $$wave_file"); \
	fi; \
	PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" CCACHE_DISABLE=1 \
		fusesoc --cores-root . run --clean --target plic-sim --tool verilator $(SIM_TRACE_FUSESOC_FLAGS) $(SIM_ASSERT_FUSESOC_FLAGS) corejack:corejack:platform $(SIM_MAKE_OPTIONS) "$${extra_args[@]}"

# System-level memory-bandwidth benchmark: a CPU streaming loop against a
# concurrent iDMA copy, timed with the mcycle CSR so the figures are unaffected
# by the baud-throttled UART. This is the instrument that sizes the fabric's
# outstanding depths - see docs/source/axi4_fabric.rst for the reference numbers.
# Needs a core with the standard counters (ibex, cv32e40*, cva6).
mem-bw-bench: ## measure CPU+iDMA memory bandwidth (mcycle-timed)
	@$(MAKE) sim-run-sw SW_APP=mem_bw_smoke SIM_TIMEOUT_CYCLES="$(MEM_BW_TIMEOUT_CYCLES)"

mem-ss-bench: deps-base ## measure soc_mem_ss words/cycle vs active ports/banks
	@wave_file="$(SIM_WAVE_FILE)"; \
	if [ -z "$$wave_file" ]; then wave_file="$(SIM_WAVE_DIR)/mem-ss-bench.$(SIM_WAVE_FORMAT)"; fi; \
	extra_args=(); \
	if [ "$(SIM_WAVES)" = "1" ]; then \
		mkdir -p "$$(dirname "$$wave_file")"; \
		echo "Waveform: $$wave_file"; \
		extra_args+=(--run_options="--trace --trace-file $$wave_file"); \
	fi; \
	PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" CCACHE_DISABLE=1 \
		fusesoc --cores-root . run --clean --target mem-ss-bench --tool verilator $(SIM_TRACE_FUSESOC_FLAGS) $(SIM_ASSERT_FUSESOC_FLAGS) corejack:corejack:platform $(SIM_MAKE_OPTIONS) "$${extra_args[@]}"

# Self-checking SystemVerilog benches with no cocotb side (tb/tb_mem_ss.sv,
# tb/tb_axi_to_mem.sv). The bench prints PASS/FAIL and exits nonzero on
# failure, so the make exit status is the result.
sv-tb: deps-base ## run a self-checking SV bench: TB=tb_mem_ss|tb_axi_to_mem
	@case " $(SV_TB_BENCHES) " in *" $(TB) "*) ;; \
		*) echo "Error: set TB to one of: $(SV_TB_BENCHES)"; exit 1;; esac
	@PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" CCACHE_DISABLE=1 \
		fusesoc --cores-root . run --clean --target sv-tb --tool verilator \
		--work-root "$(CURDIR)/build/sim/sv-tb/$(TB)-$(SV_TB_SLICE)" --flag $(TB) \
		$(if $(filter xilinx,$(SV_TB_SLICE)),--flag memimpl_xilinx,) \
		$(SIM_ASSERT_FUSESOC_FLAGS) corejack:corejack:platform $(SIM_MAKE_OPTIONS)
## set SV_TB_XILINX_SRAM=1 to use the Xilinx SRAM slice

# The SV benches in axi-smoke. tb_axi_to_mem runs on both slices because
# the bridge's in-flight bound is derived from the slice read latency.
sv-tb-smoke: ## run the SV benches in the axi-smoke set
	@$(MAKE) sv-tb TB=tb_mem_ss
	@$(MAKE) sv-tb TB=tb_axi_to_mem
	@$(MAKE) sv-tb TB=tb_axi_to_mem SV_TB_XILINX_SRAM=1

axi-addr-map-check: ## check AXI fabric address windows for overlap
	@$(PY) bin/check_axi_addr_map.py

axi-smoke: axi-addr-map-check axi-adapter-sim uart-loader-sim plic-sim mem-ss-bench sv-tb-smoke mem-bw-bench debug-sim cva6-reset-sim ## run AXI fabric regressions and supported-core SW sims
	@for core in $(AXI_SMOKE_CORES); do \
		echo "AXI smoke: sim-run-sw CORE=$$core"; \
		$(MAKE) sim-run-sw CORE="$$core" SW_APP=hello_world SIM_TIMEOUT_CYCLES="$(SIM_TIMEOUT_CYCLES)"; \
	done

smoke: deps-base ## run FuseSoC cocotb+Verilator smoke target
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
		fusesoc --cores-root . run --clean --target smoke --tool verilator $(SIM_TRACE_FUSESOC_FLAGS) $(SIM_ASSERT_FUSESOC_FLAGS) corejack:corejack:platform $(SIM_MAKE_OPTIONS) "$${extra_args[@]}"

.PHONY: sim-run-sw debug-sim cva6-reset-sim axi-adapter-sim uart-loader-sim plic-sim mem-ss-bench mem-bw-bench sv-tb sv-tb-smoke axi-addr-map-check axi-smoke smoke
