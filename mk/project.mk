# SPDX-License-Identifier: Apache-2.0
#
# Descriptor checks, scaffolding, versioning, generated docs inputs, and cleanup.
# Included by the root Makefile; see it for the shared settings.

NEW_BOARD      ?= $(BOARD)
NEW_CORE       ?= $(CORE)
FPGA_PART      ?=
BOARD_DISPLAY_NAME ?=
CORE_DISPLAY_NAME ?=
CORE_XLEN      ?= 32
CORE_MARCH     ?= rv32imc
CORE_MABI      ?= ilp32
ALLOW_PLANNED  ?= 0
FLOW           ?= all

DRAWIO         ?= drawio
DRAWIO_SRC     ?= docs/source/media/corejack_soc.drawio
DRAWIO_SVG_DIR ?= docs/source/media

ifeq ($(ALLOW_PLANNED),1)
VALIDATE_PLANNED_ARG := --allow-planned
else
VALIDATE_PLANNED_ARG :=
endif

check-tools: ## report host tools for FLOW=all|sim|fpga|debug
	@$(PY) bin/check_tools.py --core "$(CORE)" --board "$(BOARD)" --flow "$(FLOW)"

new-board: ## create descriptor/wrapper/XDC/FuseSoC scaffold for BOARD
	@test -n "$(FPGA_PART)" || { echo "Error: FPGA_PART is required, e.g. make new-board BOARD=myboard FPGA_PART=xc..."; exit 1; }
	@display_args=(); \
	if [ -n "$(BOARD_DISPLAY_NAME)" ]; then display_args+=(--display-name "$(BOARD_DISPLAY_NAME)"); fi; \
	$(PY) bin/create_board.py \
		--board "$(NEW_BOARD)" \
		--part "$(FPGA_PART)" \
		"$${display_args[@]}"

new-core: ## create planned descriptor/adapter/FuseSoC scaffold for CORE
	@display_args=(); \
	if [ -n "$(CORE_DISPLAY_NAME)" ]; then display_args+=(--display-name "$(CORE_DISPLAY_NAME)"); fi; \
	$(PY) bin/create_core.py \
		--core "$(NEW_CORE)" \
		--board "$(BOARD)" \
		--xlen "$(CORE_XLEN)" \
		--march "$(CORE_MARCH)" \
		--mabi "$(CORE_MABI)" \
		"$${display_args[@]}"

support-matrix: ## generate docs/source/support_matrix.rst from descriptors
	@$(PY) bin/render_support_matrix.py

support-matrix-check:
	@$(PY) bin/render_support_matrix.py --check

version-check: ## verify all .core files agree on a single VLNV version
	@$(PY) bin/bump_version.py --check

bump-version: ## rewrite every CoreJack VLNV version (set VERSION=X.Y.Z)
	@test -n "$(VERSION)" || { echo "Error: VERSION required, e.g. make bump-version VERSION=0.2.0"; exit 1; }
	@$(PY) bin/bump_version.py --to "$(VERSION)"

drawio-svg: ## export each docs/source/media/corejack_soc.drawio tab to its own SVG
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
		$(PY) bin/postprocess_drawio_svg.py "$$out"; \
	done

python-tests: ## run pytest coverage for Python utility scripts
	@test -x "$(VENV_PY)" || { echo "Error: venv not found. Run: source ./sourceme.sh"; exit 1; }
	@"$(VENV_PY)" -m pytest bin/tests

flist: deps-base ## generate Bender flist at build/flist.f
	@mkdir -p build
	@"$(BENDER)" script flist -t all > build/flist.f
	@echo "Generated build/flist.f"

validate-target:
	@$(PY) bin/validate_target.py --core "$(CORE)" --board "$(BOARD)" --quiet $(VALIDATE_PLANNED_ARG)

list-targets: ## list descriptor-backed CORE and BOARD selections
	@$(PY) bin/validate_target.py --list

target-config: ## show descriptor-derived config for CORE/BOARD
	@$(PY) bin/validate_target.py --core "$(CORE)" --board "$(BOARD)" --allow-planned

board-check: ## validate BOARD descriptor, wrapper, constraints, and debug config
	@$(PY) bin/validate_target.py --board "$(BOARD)" --board-check

core-check: ## validate CORE descriptor, adapter, enum, ISA, and board links
	@$(PY) bin/validate_target.py --core "$(CORE)" --core-check

target-check: ## validate BOARD-compatible CORE descriptor matrix
	@$(PY) bin/validate_target.py --board "$(BOARD)" --target-check

plan: ## show the current CoreJack roadmap
	@sed -n '1,240p' docs/source/roadmap.rst

clean: sw-clean ## remove simulation and generated outputs
	@rm -rf build tb/sim_build tb/results.xml deps

distclean: clean ## clean + remove tools and bender dependencies
	@rm -rf "$(TOOLS_DIR)" .bender

.PHONY: check-tools new-board new-core support-matrix support-matrix-check version-check bump-version drawio-svg python-tests flist validate-target list-targets target-config board-check core-check target-check plan clean distclean
