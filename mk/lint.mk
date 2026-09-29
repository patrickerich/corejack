# SPDX-License-Identifier: Apache-2.0
#
# RTL lint.
# Included by the root Makefile; see it for the shared settings.

# Verilator lint, one soc_top configuration per core (the core adapters differ).
# Any warning not waived in cfg/verilator_lint_waivers.vlt fails the target. The
# loader is enabled so its RTL is linted too.
LINT_CORES       ?= $(AXI_SMOKE_CORES)
LINT_UART_LOADER ?= 1
LINT_WORK_ROOT   ?= $(CURDIR)/build/lint/$(CORE)

lint-rtl: ## Verilator -Wall lint of soc_top for each AXI_SMOKE_CORES core
	@for core in $(LINT_CORES); do \
		$(MAKE) --no-print-directory lint-rtl-core CORE="$$core" || exit 1; \
	done

lint-rtl-core: deps-core
	@mkdir -p "$(LINT_WORK_ROOT)"
	@echo "lint-rtl: CORE=$(CORE) -> $(LINT_WORK_ROOT)/lint.log"
	@PATH="$(CURDIR)/.venv/bin:$$PATH" VIRTUAL_ENV="$(CURDIR)/.venv" \
		fusesoc --cores-root . run --clean --target lint --work-root "$(LINT_WORK_ROOT)/fusesoc" $(FUSESOC_FLAG_ARGS) corejack:corejack:platform --CoreType="$(CORE_TYPE)" --EnableUartLoader="$(LINT_UART_LOADER)" > "$(LINT_WORK_ROOT)/lint.log" 2>&1 \
		|| { tail -20 "$(LINT_WORK_ROOT)/lint.log"; exit 1; }
	@count=$$(grep -c '^%Warning' "$(LINT_WORK_ROOT)/lint.log"); \
	echo "lint-rtl: CORE=$(CORE): $$count warning(s)"; \
	if [ "$$count" -ne 0 ]; then \
		grep -A4 '^%Warning' "$(LINT_WORK_ROOT)/lint.log"; \
		echo "Fix these, or waive them with a reason in cfg/verilator_lint_waivers.vlt."; \
		exit 1; \
	fi

.PHONY: lint-rtl lint-rtl-core
