# SPDX-License-Identifier: Apache-2.0
#
# External HDL dependencies: Bender, the shared deps, and per-core checkouts.
# Included by the root Makefile; see it for the shared settings.

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
	curl -fsSL --retry 5 --retry-max-time 60 "$$url" -o "$$tmp/bender.tgz"; \
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
bender: $(BENDER_BIN) ## fetch pinned bender binary into TOOLS_DIR

deps: deps-base deps-core ## fetch base deps plus selected CORE dependency

deps-update: $(BENDER_BIN) ## deliberately refresh Bender.lock, then checkout
	@"$(BENDER)" update
	@"$(BENDER)" checkout

deps-base: $(BENDER_BIN) ## fetch shared base dependencies only
	@"$(BENDER)" checkout
	@mkdir -p deps
	@for dep in axi apb apb_uart clint obi obi_peripherals register_interface riscv-dbg common_cells tech_cells_generic common_verification idma axi_stream; do \
		path="$$("$(BENDER)" path "$$dep" 2>/dev/null || true)"; \
		if [ -n "$$path" ]; then ln -sfn "$$path" "deps/$$dep"; fi; \
	done

deps-core: deps-base ## fetch only the selected CORE dependency
	@if [ "$(CORE)" = "cva6" ]; then \
		$(MAKE) deps-cva6; \
	else \
		$(PY) bin/deps_core.py --core "$(CORE)"; \
	fi

deps-all: deps-base ## fetch all optional core dependencies
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

deps-serv: deps-base ## fetch SERV core dependency
	@$(PY) bin/deps_core.py --core serv

deps-picorv32: deps-base ## fetch PicoRV32 core dependency
	@$(PY) bin/deps_core.py --core picorv32

deps-cvw: deps-base ## fetch CVW/Wally core dependency
	@$(PY) bin/deps_core.py --core cvw

deps-cv32e40p: deps-base ## fetch CV32E40P core dependency
	@$(PY) bin/deps_core.py --core cv32e40p

deps-cv32e40x: deps-base ## fetch CV32E40X core dependency
	@$(PY) bin/deps_core.py --core cv32e40x

deps-cv32e40s: deps-base ## fetch CV32E40S core dependency
	@$(PY) bin/deps_core.py --core cv32e40s

deps-cva6: deps-base ## fetch CVA6 core dependency
	@$(PY) bin/deps_core.py --core cva6 --upstream "$(CVA6_REPO)" --rev "$(CVA6_REV)"
	@for patch in $(CVA6_PATCHES); do \
		echo "Applying CVA6 patch $$patch"; \
		git -C "$(CURDIR)/.bender/vendor/cva6" apply "$(CURDIR)/$$patch"; \
	done

.PHONY: bender deps deps-update deps-base deps-core deps-vendor deps-all deps-serv deps-picorv32 deps-cvw deps-cv32e40p deps-cv32e40x deps-cv32e40s deps-cva6
