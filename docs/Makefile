# Sphinx documentation build.
#
# Usually invoked from the repository root (`make docs`, `make docs-serve`,
# `make docs-preview`), which just delegates here. Anything Sphinx supports is
# reachable directly without adding a wrapper for it:
#
#   make -C docs linkcheck
#   make -C docs latexpdf
#   make -C docs dirhtml
#
# `source ./sourceme.sh` first. That puts .venv/bin on PATH, so SPHINXBUILD
# below resolves to the Sphinx version pinned in requirements.txt rather than
# whatever the host happens to have.

SPHINXBUILD ?= sphinx-build
SPHINXOPTS  ?= -W --keep-going
SOURCEDIR   := source
BUILDDIR    := build
PORT        ?= 8000
VENV_PY     := $(CURDIR)/../.venv/bin/python

# Fail loudly rather than silently building with an unpinned system Sphinx,
# then make sure the documentation dependencies are present.
define PREP
@test -x "$(VENV_PY)" || { echo "Error: venv not found. Run: source ./sourceme.sh"; exit 1; }
@$(VENV_PY) -m pip install -q -r requirements.txt
endef

.PHONY: help serve preview

help:
	@$(SPHINXBUILD) -M help "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS)
	@echo
	@echo "CoreJack additions:"
	@printf '  %-12s %s\n' 'serve' 'build html and serve it on http://localhost:$(PORT)'
	@printf '  %-12s %s\n' 'preview' 'rebuild on save with live browser reload'

# Serves exactly what a deploy would publish -- no live-reload injection.
serve: html
	@echo "Serving docs at http://localhost:$(PORT)/  (Ctrl-C to stop)"
	@$(VENV_PY) -m http.server $(PORT) --directory $(BUILDDIR)/html

# Authoring loop. No -W here: a half-finished edit should not kill the server.
preview:
	$(PREP)
	@$(VENV_PY) -m sphinx_autobuild --port $(PORT) --open-browser \
	   --ignore '$(CURDIR)/$(BUILDDIR)/*' $(SOURCEDIR) $(BUILDDIR)/html

# Catch-all: forward every other target to Sphinx, so new builders work with no
# change here. Must stay last.
%: Makefile
	$(PREP)
	@$(SPHINXBUILD) -M $@ "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS)
