#!/usr/bin/env python3
"""Check the CoreJack AXI fabric address map for obvious decode mistakes."""

from __future__ import annotations

import argparse
import ast
import operator
import re
import sys
from pathlib import Path


ASSIGN_RE = re.compile(
    r"(?:parameter|localparam)\s+(?:int\s+unsigned|logic\s+\[31:0\])\s+"
    r"(?P<name>\w+)\s*=\s*(?P<expr>[^,;\n]+)"
)
RULE_RE = re.compile(
    r"\{idx:\s*(?P<idx>\d+),\s*start_addr:\s*(?P<base>\w+),\s*"
    r"end_addr:\s*(?P=base)\s*\+\s*(?P<size>\w+)\}"
)


OPS = {
    ast.Add: operator.add,
    ast.Sub: operator.sub,
    ast.Mult: operator.mul,
    ast.FloorDiv: operator.floordiv,
}


def normalize_expr(expr: str) -> str:
    return re.sub(r"32'h([0-9a-fA-F_]+)", lambda m: str(int(m.group(1).replace("_", ""), 16)), expr)


def eval_expr(expr: str, values: dict[str, int]) -> int:
    def walk(node: ast.AST) -> int:
        if isinstance(node, ast.Expression):
            return walk(node.body)
        if isinstance(node, ast.Constant) and isinstance(node.value, int):
            return node.value
        if isinstance(node, ast.Name) and node.id in values:
            return values[node.id]
        if isinstance(node, ast.BinOp) and type(node.op) in OPS:
            return OPS[type(node.op)](walk(node.left), walk(node.right))
        raise ValueError(expr)

    return walk(ast.parse(normalize_expr(expr), mode="eval"))


def parse_soc_top(path: Path) -> tuple[dict[str, int], list[tuple[int, str, str]]]:
    text = path.read_text(encoding="utf-8")
    # The RTL widens the 32-bit window parameters to the 64-bit xbar rule
    # fields with a zero-extension concatenation; flatten it so the rule
    # regex sees the bare parameter names.
    text = re.sub(r"\{\s*32'h0\s*,\s*(\w+)\s*\}", r"\1", text)
    values: dict[str, int] = {}
    pending = [(match["name"], match["expr"].strip()) for match in ASSIGN_RE.finditer(text)]
    while pending:
        next_pending: list[tuple[str, str]] = []
        progress = False
        for name, expr in pending:
            try:
                values[name] = eval_expr(expr, values)
                progress = True
            except (SyntaxError, ValueError):
                next_pending.append((name, expr))
        if not progress:
            break
        pending = next_pending
    rules = [
        (int(match["idx"]), match["base"], match["size"])
        for match in RULE_RE.finditer(text)
    ]
    return values, rules


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--soc-top",
        default="rtl/top/soc_top.sv",
        type=Path,
        help="soc_top RTL file to inspect",
    )
    args = parser.parse_args()

    values, rules = parse_soc_top(args.soc_top)
    if not rules:
        print(f"ERROR: no AXI fabric address-map rules found in {args.soc_top}", file=sys.stderr)
        return 1

    windows: list[tuple[int, int, int, str]] = []
    for idx, base_name, size_name in rules:
        missing = [name for name in (base_name, size_name) if name not in values]
        if missing:
            print(f"ERROR: unresolved address-map symbol(s): {', '.join(missing)}", file=sys.stderr)
            return 1
        start = values[base_name]
        size = values[size_name]
        end = start + size
        if size <= 0:
            print(f"ERROR: zero-sized AXI window for {base_name}", file=sys.stderr)
            return 1
        if end > 2**32:
            print(f"ERROR: AXI window {base_name} exceeds 32-bit address space", file=sys.stderr)
            return 1
        windows.append((idx, start, end, base_name.removesuffix("BaseAddr").lower()))

    indices = [idx for idx, *_ in windows]
    if len(indices) != len(set(indices)):
        print("ERROR: duplicate AXI fabric target index", file=sys.stderr)
        return 1

    sorted_windows = sorted(windows, key=lambda item: item[1])
    for prev, curr in zip(sorted_windows, sorted_windows[1:]):
        if prev[2] > curr[1]:
            print(
                "ERROR: overlapping AXI windows: "
                f"{prev[3]} 0x{prev[1]:08x}..0x{prev[2] - 1:08x} and "
                f"{curr[3]} 0x{curr[1]:08x}..0x{curr[2] - 1:08x}",
                file=sys.stderr,
            )
            return 1

    for idx, start, end, name in sorted(windows):
        print(f"AXI[{idx}] {name}: 0x{start:08x}..0x{end - 1:08x}")
    print("AXI address map check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
