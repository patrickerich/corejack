# SPDX-License-Identifier: Apache-2.0
"""Sphinx configuration for the CoreJack documentation.

The documentation stays in Markdown and is parsed by MyST rather than being
converted to reStructuredText: the pages must keep rendering on GitHub, where
contributors read them directly, and README.md / CONTRIBUTING.md / AGENTS.md
have to be Markdown regardless.

Build with `make docs`; `make docs-serve` to view, `make docs-preview` to
edit with live reload.
"""

import re

project = "CoreJack"
author = "CoreJack contributors"
copyright = "CoreJack contributors"

extensions = [
    "myst_parser",
    "sphinx_copybutton",
]

myst_enable_extensions = [
    "colon_fence",
    "deflist",
]
# Resolve .md links between pages to the built .html pages.
myst_heading_anchors = 3

html_theme = "furo"
html_title = "CoreJack"
html_static_path = []

# `gdb` is not a Pygments lexer, but several pages show GDB sessions in fenced
# blocks. Map it to plain text rather than rewriting the fences.
from pygments.lexers.special import TextLexer  # noqa: E402
from sphinx.highlighting import lexers  # noqa: E402

lexers["gdb"] = TextLexer()

# Links that climb out of docs/source/ point at repository files Sphinx does not
# know about - README.md, CONTRIBUTING.md, cfg/ descriptors, bin/ scripts. They
# have to stay repo-relative so they work when the page is read on GitHub, so
# rewrite them to GitHub URLs at build time instead of moving files or dropping
# the references.
REPO_BLOB = "https://github.com/patrickerich/corejack/blob/main/"
_ESCAPES_SOURCE = re.compile(r"\]\(\.\./\.\./([^)]+)\)")


def _rewrite_root_links(app, docname, source):
    source[0] = _ESCAPES_SOURCE.sub(lambda m: f"]({REPO_BLOB}{m.group(1)})", source[0])


def setup(app):
    app.connect("source-read", _rewrite_root_links)
    return {"parallel_read_safe": True}
