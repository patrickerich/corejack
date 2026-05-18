#!/usr/bin/env python3
"""Extract a plain Verilog/SystemVerilog file list from a Vivado project Tcl."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


READ_RE = re.compile(r"^\s*read_(?:verilog|vhdl)\b.*?\{([^}]+)\}")


def resolve_path(path: str, work_root: Path) -> Path:
    candidate = Path(path)
    if candidate.is_absolute():
        return candidate
    return (work_root / candidate).resolve()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tcl", required=True, type=Path)
    parser.add_argument("--work-root", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    files: list[Path] = []
    for line in args.tcl.read_text(encoding="utf-8").splitlines():
        match = READ_RE.match(line)
        if not match:
            continue
        files.append(resolve_path(match.group(1), args.work_root))

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("".join(f"{path}\n" for path in files), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
