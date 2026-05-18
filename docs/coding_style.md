# Coding Style

CoreJack-owned RTL should follow the lowRISC/OpenTitan SystemVerilog coding
style as the default design intent:

- lowRISC guide:
  <https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md>
- OpenTitan rendered guide:
  <https://opentitan.org/book/doc/contributing/style_guides/verilog_coding_style.html>

This applies to RTL, packages, interfaces, wrappers, testbench code, and small
hardware utilities maintained directly in this repository. The intent is to keep
new CoreJack code readable, reviewable, and compatible with the style used by
many of the upstream hardware dependencies.

Third-party RTL keeps its upstream style. Do not reformat vendored,
Bender-managed, or generated dependency code just to match CoreJack style.
Local wrappers and adapters around those dependencies should still follow the
CoreJack style unless there is a concrete tool or integration reason not to.

The repository `.editorconfig` captures only basic whitespace, newline, and
indentation defaults. It is not a complete formatter or lint policy.

Verible is the intended first lint/format tool for this style direction. The
repository can install project-local Verible tools with `make tool-verible`.
Verible checks are intentionally not enforced yet.

Before adding a `make lint-rtl` target to CI or any default smoke flow, define
the CoreJack-owned file scope, initial rule set, and waiver policy. Start with a
manual, non-blocking check over local RTL only. Promote it to CI only after the
rule set is stable, low-noise, and explicitly excludes imported dependency
code.
