# SPDX-License-Identifier: Apache-2.0
"""Sphinx configuration for the CoreJack documentation.

The documentation is reStructuredText. It used to be Markdown parsed by MyST so
that the pages also rendered on GitHub, but the published site at
https://patrickerich.github.io/corejack/ is now the canonical reader and the
root README/CONTRIBUTING/AGENTS files point at it, so the GitHub source view no
longer has to carry these pages. Those three root files stay Markdown.

Build with `make docs`; `make docs-serve` to view, `make docs-preview` to
edit with live reload.
"""

from docutils import nodes

project = "CoreJack"
author = "CoreJack contributors"
copyright = "CoreJack contributors"

extensions = [
    "sphinx_copybutton",
]

html_theme = "furo"
html_title = "CoreJack"
html_static_path = []

# `gdb` is not a Pygments lexer, but several pages use `.. code:: gdb` to show
# GDB sessions. Map it to plain text rather than relabelling those blocks.
from pygments.lexers.special import TextLexer  # noqa: E402
from sphinx.highlighting import lexers  # noqa: E402

lexers["gdb"] = TextLexer()

# References that point out of docs/source/ at repository files Sphinx does not
# know about - README.md, CONTRIBUTING.md, cfg/ descriptors, bin/ scripts - are
# written as :repofile:`cfg/cores/ibex.yaml` and resolved to GitHub URLs here.
# A plain extlinks entry would render the path as body text; this keeps it
# monospaced, the way the surrounding file references are written.
REPO_BLOB = "https://github.com/patrickerich/corejack/blob/main/"


def repofile_role(name, rawtext, text, lineno, inliner, options=None, content=None):
    node = nodes.reference(rawtext, "", nodes.literal(text, text), refuri=REPO_BLOB + text)
    return [node], []


def setup(app):
    app.add_role("repofile", repofile_role)
    return {"parallel_read_safe": True}
