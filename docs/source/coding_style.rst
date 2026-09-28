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
design. It is manual and report-only for now: warnings never fail it, each
core's output is in ``build/lint/<core>/lint.log``, and the output still
includes the imported dependencies' warnings.

Verible remains the intended style and format tool. The repository can install
project-local Verible tools with ``make tool-verible``. Verible checks are
intentionally not enforced yet.

Before adding either check to CI or any default smoke flow, define the
CoreJack-owned file scope, initial rule set, and waiver policy. Promote a check
to CI only after the rule set is stable, low-noise, and explicitly excludes
imported dependency code.
