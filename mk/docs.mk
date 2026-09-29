# SPDX-License-Identifier: Apache-2.0
#
# Sphinx documentation: docs/source built into docs/build.
# Included by the root Makefile; see it for the shared settings.
#
# `source ./sourceme.sh` first. That puts .venv/bin on PATH, so SPHINXBUILD
# resolves to the Sphinx version pinned in docs/requirements.txt rather than
# whatever the host happens to have. Any Sphinx builder is reachable through
# docs-<builder> without adding a target for it, e.g. make docs-linkcheck.

SPHINXBUILD     ?= sphinx-build
SPHINXOPTS      ?= -W --keep-going
DOCS_SOURCE_DIR := $(CURDIR)/docs/source
DOCS_BUILD_DIR  := $(CURDIR)/docs/build
DOCS_PORT       ?= 8000

# Fail loudly rather than silently building with an unpinned system Sphinx,
# then make sure the documentation dependencies are present.
define DOCS_PREP
@test -x "$(VENV_PY)" || { echo "Error: venv not found. Run: source ./sourceme.sh"; exit 1; }
@$(VENV_PY) -m pip install -q -r "$(CURDIR)/docs/requirements.txt"
endef

docs: ## build the Sphinx documentation into docs/build/html
	$(DOCS_PREP)
	@$(SPHINXBUILD) -M html "$(DOCS_SOURCE_DIR)" "$(DOCS_BUILD_DIR)" $(SPHINXOPTS)

# Serves exactly what a deploy would publish -- no live-reload injection.
docs-serve: docs ## build the docs and serve them on http://localhost:DOCS_PORT (default 8000)
	@echo "Serving docs at http://localhost:$(DOCS_PORT)/  (Ctrl-C to stop)"
	@$(VENV_PY) -m http.server $(DOCS_PORT) --directory "$(DOCS_BUILD_DIR)/html"

# Authoring loop. No -W here: a half-finished edit should not kill the server.
docs-preview: ## rebuild-on-save docs server with live browser reload
	$(DOCS_PREP)
	@$(VENV_PY) -m sphinx_autobuild --port $(DOCS_PORT) --open-browser \
	   --ignore '$(DOCS_BUILD_DIR)/*' "$(DOCS_SOURCE_DIR)" "$(DOCS_BUILD_DIR)/html"

docs-clean: ## remove the documentation build (docs/build)
	$(DOCS_PREP)
	@$(SPHINXBUILD) -M clean "$(DOCS_SOURCE_DIR)" "$(DOCS_BUILD_DIR)" $(SPHINXOPTS)

docs-help: ## list the Sphinx builders reachable as docs-<builder>
	@$(SPHINXBUILD) -M help "$(DOCS_SOURCE_DIR)" "$(DOCS_BUILD_DIR)" $(SPHINXOPTS)

# Any other Sphinx builder, e.g. docs-linkcheck, docs-latexpdf, docs-dirhtml.
# A pattern rule, so it cannot be .PHONY (make skips pattern search for those).
docs-%: ## run Sphinx builder <builder> as docs-<builder>, e.g. docs-linkcheck
	$(DOCS_PREP)
	@$(SPHINXBUILD) -M $* "$(DOCS_SOURCE_DIR)" "$(DOCS_BUILD_DIR)" $(SPHINXOPTS)

.PHONY: docs docs-serve docs-preview docs-clean docs-help
