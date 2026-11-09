# SPDX-License-Identifier: Apache-2.0
#
# Simulation: the cocotb/Verilator smoke, software sims, benches, and axi-smoke.
# Included by the root Makefile; see it for the shared settings.

SIM_TIMEOUT_CYCLES ?= 1000000
MEM_BW_TIMEOUT_CYCLES ?= 4000000
# Software built with TARGET=sim programs the UART at SOC_CLK_HZ/32, which
# uart_init rounds to divisor 2: the fastest the vendored UART runs, because its
# baud generator treats divisor 1 as unset and never sends. uart_putc waits for
# each character to go out, so this cuts every printed character from ~2240
# cycles at 115200 baud to ~320. The testbench reads UART output from the APB
# write, so capture does not depend on the baud. The different constant does
# move code, so cycle-timed figures such as mem-bw-bench's can shift. Set
# SIM_UART_BAUD=115200 to simulate at the board's baud.
SIM_UART_BAUD ?= $(if $(SOC_CLK_HZ),$(shell expr $(SOC_CLK_HZ) / 32))
SIM_FUSESOC_WORK_ROOT ?= $(CURDIR)/build/sim/fusesoc/$(CORE)/$(SIM_FUSESOC_TARGET)
# cocotb ends the simulator with exit code 0 whether its tests pass or fail, and
# writes the outcome to the JUnit file named by COCOTB_RESULTS_FILE. cocotb's own
# makefiles then check that file; FuseSoC does not. So each cocotb target below
# deletes its results file, runs, and checks the file with sim_check_results: a
# failing test, or a run that stops before writing the file, fails make.
SIM_RESULTS_DIR ?= $(CURDIR)/build/sim/results
sim_check_results = "$(VENV_PY)" -m cocotb_tools.check_results "$(1)" || \
	{ echo "Error: cocotb tests failed, or the simulation wrote no results: $(1)"; exit 1; }
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
# sim-sweep: which cores and apps it runs, the per-run budget (the slowest run,
# bench_smoke on SERV, needs ~7.0M cycles), where the per-run logs go, the
# core/app pairs it skips, and how many cores it runs at once. mem_bw_smoke
# reads the mcycle CSR, which SERV and PicoRV32 lack.
SIM_SWEEP_CORES          ?= $(AXI_SMOKE_CORES)
SIM_SWEEP_APPS           ?= $(SW_APPS)
SIM_SWEEP_TIMEOUT_CYCLES ?= 8000000
SIM_SWEEP_LOG_DIR        ?= $(CURDIR)/build/sim/sweep
SIM_SWEEP_SKIP           ?= serv/mem_bw_smoke picorv32/mem_bw_smoke
SIM_SWEEP_JOBS           ?= 1

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

# The software only reaches the model at run time (+MEM_PATH), so sim-run-sw
# keeps each core's work root between runs instead of passing --clean: FuseSoC
# re-copies only changed sources, and Verilator rebuilds only when a source,
# flag, or parameter changed. A rerun skips the ~20 s model build. FuseSoC
# keeps each source's timestamp, so a file changed without a newer timestamp
# (cp -p, an unpacked archive) is not seen; make clean forces a full rebuild.
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
	results="$(SIM_RESULTS_DIR)/$(SIM_FUSESOC_TARGET)-$(CORE)-$(SW_APP).xml"; \
	mkdir -p "$(SIM_RESULTS_DIR)"; rm -f "$$results"; \
	PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" \
		COREJACK_TIMEOUT_CYCLES='$(SIM_TIMEOUT_CYCLES)' \
		CCACHE_DISABLE=1 \
		COCOTB_RESULTS_FILE="$$results" \
		fusesoc --cores-root . run --target "$(SIM_FUSESOC_TARGET)" --tool verilator --work-root "$(SIM_FUSESOC_WORK_ROOT)" $(FUSESOC_FLAG_ARGS) $(SIM_TRACE_FUSESOC_FLAGS) $(SIM_ASSERT_FUSESOC_FLAGS) corejack:corejack:platform $(SIM_MAKE_OPTIONS) --run_options="$$run_options" && \
	$(call sim_check_results,$$results)
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
	results="$(SIM_RESULTS_DIR)/cva6-reset-sim.xml"; \
	mkdir -p "$(SIM_RESULTS_DIR)"; rm -f "$$results"; \
	PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" CCACHE_DISABLE=1 \
		COCOTB_RESULTS_FILE="$$results" \
		fusesoc --cores-root . run --clean --target cva6-reset-sim --tool verilator $(SIM_TRACE_FUSESOC_FLAGS) $(SIM_ASSERT_FUSESOC_FLAGS) corejack:corejack:platform $(SIM_MAKE_OPTIONS) "$${extra_args[@]}" && \
	$(call sim_check_results,$$results)

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
	results="$(SIM_RESULTS_DIR)/debug-sim.xml"; \
	mkdir -p "$(SIM_RESULTS_DIR)"; rm -f "$$results"; \
	PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" CCACHE_DISABLE=1 \
		COCOTB_RESULTS_FILE="$$results" \
		fusesoc --cores-root . run --clean --target debug-sim --tool verilator $(SIM_TRACE_FUSESOC_FLAGS) $(SIM_ASSERT_FUSESOC_FLAGS) corejack:corejack:platform $(SIM_MAKE_OPTIONS) "$${extra_args[@]}" && \
	$(call sim_check_results,$$results)

axi-adapter-sim: deps-base ## run OBI-to-AXI and AXI-to-memory adapter regressions
	@wave_file="$(SIM_WAVE_FILE)"; \
	if [ -z "$$wave_file" ]; then wave_file="$(SIM_WAVE_DIR)/axi-adapter-sim.$(SIM_WAVE_FORMAT)"; fi; \
	extra_args=(); \
	if [ "$(SIM_WAVES)" = "1" ]; then \
		mkdir -p "$$(dirname "$$wave_file")"; \
		echo "Waveform: $$wave_file"; \
		extra_args+=(--run_options="--trace --trace-file $$wave_file"); \
	fi; \
	results="$(SIM_RESULTS_DIR)/axi-adapter-sim.xml"; \
	mkdir -p "$(SIM_RESULTS_DIR)"; rm -f "$$results"; \
	PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" CCACHE_DISABLE=1 \
		COCOTB_RESULTS_FILE="$$results" \
		fusesoc --cores-root . run --clean --target axi-adapter-sim --tool verilator $(SIM_TRACE_FUSESOC_FLAGS) $(SIM_ASSERT_FUSESOC_FLAGS) corejack:corejack:platform $(SIM_MAKE_OPTIONS) "$${extra_args[@]}" && \
	$(call sim_check_results,$$results)

uart-loader-sim: deps-base ## run side-path UART SRAM loader protocol regression
	@wave_file="$(SIM_WAVE_FILE)"; \
	if [ -z "$$wave_file" ]; then wave_file="$(SIM_WAVE_DIR)/uart-loader-sim.$(SIM_WAVE_FORMAT)"; fi; \
	extra_args=(); \
	if [ "$(SIM_WAVES)" = "1" ]; then \
		mkdir -p "$$(dirname "$$wave_file")"; \
		echo "Waveform: $$wave_file"; \
		extra_args+=(--run_options="--trace --trace-file $$wave_file"); \
	fi; \
	results="$(SIM_RESULTS_DIR)/uart-loader-sim.xml"; \
	mkdir -p "$(SIM_RESULTS_DIR)"; rm -f "$$results"; \
	PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" CCACHE_DISABLE=1 \
		COCOTB_RESULTS_FILE="$$results" \
		fusesoc --cores-root . run --clean --target uart-loader-sim --tool verilator $(SIM_TRACE_FUSESOC_FLAGS) $(SIM_ASSERT_FUSESOC_FLAGS) corejack:corejack:platform $(SIM_MAKE_OPTIONS) "$${extra_args[@]}" && \
	$(call sim_check_results,$$results)

plic-sim: deps-base ## run soc_plic claim/complete and gateway regression
	@wave_file="$(SIM_WAVE_FILE)"; \
	if [ -z "$$wave_file" ]; then wave_file="$(SIM_WAVE_DIR)/plic-sim.$(SIM_WAVE_FORMAT)"; fi; \
	extra_args=(); \
	if [ "$(SIM_WAVES)" = "1" ]; then \
		mkdir -p "$$(dirname "$$wave_file")"; \
		echo "Waveform: $$wave_file"; \
		extra_args+=(--run_options="--trace --trace-file $$wave_file"); \
	fi; \
	results="$(SIM_RESULTS_DIR)/plic-sim.xml"; \
	mkdir -p "$(SIM_RESULTS_DIR)"; rm -f "$$results"; \
	PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" CCACHE_DISABLE=1 \
		COCOTB_RESULTS_FILE="$$results" \
		fusesoc --cores-root . run --clean --target plic-sim --tool verilator $(SIM_TRACE_FUSESOC_FLAGS) $(SIM_ASSERT_FUSESOC_FLAGS) corejack:corejack:platform $(SIM_MAKE_OPTIONS) "$${extra_args[@]}" && \
	$(call sim_check_results,$$results)

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
	results="$(SIM_RESULTS_DIR)/mem-ss-bench.xml"; \
	mkdir -p "$(SIM_RESULTS_DIR)"; rm -f "$$results"; \
	PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" CCACHE_DISABLE=1 \
		COCOTB_RESULTS_FILE="$$results" \
		fusesoc --cores-root . run --clean --target mem-ss-bench --tool verilator $(SIM_TRACE_FUSESOC_FLAGS) $(SIM_ASSERT_FUSESOC_FLAGS) corejack:corejack:platform $(SIM_MAKE_OPTIONS) "$${extra_args[@]}" && \
	$(call sim_check_results,$$results)

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
		$(MAKE) sim-run-sw CORE="$$core" SW_APP=hello_world SIM_TIMEOUT_CYCLES="$(SIM_TIMEOUT_CYCLES)" || exit 1; \
	done

# Runs sim-run-sw for every app on every core and keeps going past a failure, so
# one sweep shows every broken pair. Each run's output goes to its own log; the
# terminal gets one PASS/FAIL/SKIP line per run. xargs runs SIM_SWEEP_JOBS cores
# at once, each through sim-sweep-core, and they split SIM_BUILD_JOBS between
# them for any model builds. A core's own apps run one at a time, because they
# share its model. The dependencies are fetched once, up front, and the runs
# skip that step (make -o deps-core): runs on several cores would otherwise all
# run bender checkout at the same time. xargs fails only if a sim-sweep-core
# stops early; failed runs are listed in failed.txt.
sim-sweep: ## run every SW app on every core in SIM_SWEEP_CORES, logs in build/sim/sweep
	@if ! [ "$(SIM_SWEEP_JOBS)" -ge 1 ] 2>/dev/null; then \
		echo "Error: SIM_SWEEP_JOBS='$(SIM_SWEEP_JOBS)' must be a whole number, 1 or more"; \
		exit 1; \
	fi; \
	mkdir -p "$(SIM_SWEEP_LOG_DIR)"; \
	rm -f "$(SIM_SWEEP_LOG_DIR)/failed.txt" "$(SIM_SWEEP_LOG_DIR)/deps.log"; \
	for core in $(SIM_SWEEP_CORES); do \
		$(MAKE) --no-print-directory deps-core CORE="$$core" >> "$(SIM_SWEEP_LOG_DIR)/deps.log" 2>&1 || { \
			echo "sim-sweep: fetching the dependencies for $$core failed (log in $(SIM_SWEEP_LOG_DIR)/deps.log)"; \
			exit 1; \
		}; \
	done; \
	build_jobs=$$(( $(SIM_BUILD_JOBS) / $(SIM_SWEEP_JOBS) )); \
	[ "$$build_jobs" -ge 1 ] || build_jobs=1; \
	printf '%s\n' $(SIM_SWEEP_CORES) | xargs -P "$(SIM_SWEEP_JOBS)" -I{} \
		$(MAKE) --no-print-directory sim-sweep-core CORE={} SIM_BUILD_JOBS="$$build_jobs"; \
	xargs_rc=$$?; \
	if [ -s "$(SIM_SWEEP_LOG_DIR)/failed.txt" ]; then \
		echo "sim-sweep: FAILED: $$(tr '\n' ' ' < "$(SIM_SWEEP_LOG_DIR)/failed.txt")(logs in $(SIM_SWEEP_LOG_DIR))"; \
		exit 1; \
	fi; \
	if [ "$$xargs_rc" -ne 0 ]; then \
		echo "sim-sweep: FAILED: a core stopped before finishing its runs, see the errors above"; \
		exit 1; \
	fi; \
	echo "sim-sweep: all runs passed (logs in $(SIM_SWEEP_LOG_DIR))"
## set SIM_SWEEP_JOBS=<n> to run n cores at once

# One core's part of sim-sweep: runs CORE's apps in order, prints a line per
# run, and adds each failed pair to failed.txt.
sim-sweep-core:
	@for app in $(SIM_SWEEP_APPS); do \
		case " $(SIM_SWEEP_SKIP) " in \
			*" $(CORE)/$$app "*) printf 'SKIP %-9s %s\n' "$(CORE)" "$$app"; continue;; \
		esac; \
		log="$(SIM_SWEEP_LOG_DIR)/$(CORE)-$$app.log"; \
		start=$$(date +%s); \
		if $(MAKE) --no-print-directory -o deps-core sim-run-sw CORE="$(CORE)" SW_APP="$$app" \
			SIM_TIMEOUT_CYCLES="$(SIM_SWEEP_TIMEOUT_CYCLES)" > "$$log" 2>&1; then \
			result=PASS; \
		else \
			result=FAIL; echo "$(CORE)/$$app" >> "$(SIM_SWEEP_LOG_DIR)/failed.txt"; \
		fi; \
		printf '%s %-9s %-17s %4ss\n' "$$result" "$(CORE)" "$$app" "$$(( $$(date +%s) - start ))"; \
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
	results="$(SIM_RESULTS_DIR)/smoke.xml"; \
	mkdir -p "$(SIM_RESULTS_DIR)"; rm -f "$$results"; \
	PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" CCACHE_DISABLE=1 \
		COCOTB_RESULTS_FILE="$$results" \
		fusesoc --cores-root . run --clean --target smoke --tool verilator $(SIM_TRACE_FUSESOC_FLAGS) $(SIM_ASSERT_FUSESOC_FLAGS) corejack:corejack:platform $(SIM_MAKE_OPTIONS) "$${extra_args[@]}" && \
	$(call sim_check_results,$$results)

.PHONY: sim-run-sw debug-sim cva6-reset-sim axi-adapter-sim uart-loader-sim plic-sim mem-ss-bench mem-bw-bench sv-tb sv-tb-smoke axi-addr-map-check axi-smoke sim-sweep sim-sweep-core smoke
