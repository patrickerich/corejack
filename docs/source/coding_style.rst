Coding Style
============

CoreJack-owned RTL should follow the lowRISC/OpenTitan SystemVerilog coding
style as the default design intent:

-  lowRISC guide:
   https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md
-  OpenTitan rendered guide:
   https://opentitan.org/book/doc/contributing/style_guides/verilog_coding_style.html

This applies to RTL, packages, interfaces, wrappers, testbench code, and small
hardware utilities maintained directly in this repository. The intent is to keep
new CoreJack code readable, reviewable, and compatible with the style used by
many of the upstream hardware dependencies.

Third-party RTL keeps its upstream style. Do not reformat vendored,
Bender-managed, or generated dependency code just to match CoreJack style.
Local wrappers and adapters around those dependencies should still follow the
CoreJack style unless there is a concrete tool or integration reason not to.

The repository ``.editorconfig`` captures only basic whitespace, newline, and
indentation defaults. It is not a complete formatter or lint policy.

``make lint-rtl`` runs Verilator's lint (``--lint-only -Wall``) over the
elaborated ``soc_top``, once per core in ``AXI_SMOKE_CORES``, configured as the
board wrappers build it. This is the semantic check - widths, latches,
undriven and multiply-driven signals, implicit nets, incomplete ``case``
statements - that a per-file style linter cannot do, because it needs the whole
design. Any warning that is not waived fails it, and ``smoke.yml`` runs it on
every pull request. Each core's output is in ``build/lint/<core>/lint.log``.

Waivers live in ``cfg/verilator_lint_waivers.vlt``, each with its reason:

-  Imported IP is waived by file: everything under a ``deps/`` directory, the
   vendored Ibex, and the ``rtl/cores`` copies of upstream files. It keeps its
   upstream style and is linted upstream.
-  ``PINCONNECTEMPTY`` (deliberately open output ports) and ``DECLFILENAME``
   (stand-in files named after the upstream module they replace) are off.
-  Anything else in CoreJack-owned RTL is fixed, or waived for one named signal
   with ``-match`` - not by line number, which would drift as the file changes.
   Verilator also skips signals whose name contains ``unused``, the usual way
   to mark a deliberate sink.

Verible remains the intended style and format tool. The repository can install
project-local Verible tools with ``make tool-verible``. Verible checks are
intentionally not enforced yet.

Before adding Verible to CI, define its rule set and waiver policy the same
way: stable, low-noise, and excluding imported dependency code.
