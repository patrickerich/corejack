#!/usr/bin/env python3
"""Summarize Vivado warnings and fail on unreviewed warning IDs."""

from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path


WARNING_RE = re.compile(r"^(WARNING|CRITICAL WARNING): \[([^\]]+)\] (.*)$")


def load_allowlist(path: Path) -> set[str]:
    allowed: set[str] = set()
    with path.open(encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.split("#", 1)[0].strip()
            if line:
                allowed.add(line)
    return allowed


def parse_logs(paths: list[Path]) -> dict[str, dict[str, object]]:
    warnings: dict[str, dict[str, object]] = defaultdict(
        lambda: {"count": 0, "severity": "WARNING", "examples": []}
    )
    for path in paths:
        if not path.exists():
            continue
        with path.open(encoding="utf-8", errors="replace") as handle:
            for lineno, line in enumerate(handle, start=1):
                match = WARNING_RE.match(line.rstrip())
                if not match:
                    continue
                severity, msg_id, message = match.groups()
                entry = warnings[msg_id]
                entry["count"] = int(entry["count"]) + 1
                if severity == "CRITICAL WARNING":
                    entry["severity"] = severity
                examples = entry["examples"]
                assert isinstance(examples, list)
                if len(examples) < 2:
                    examples.append((path, lineno, message))
    return warnings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--allowlist", required=True, type=Path)
    parser.add_argument("logs", nargs="+", type=Path)
    args = parser.parse_args()

    allowed = load_allowlist(args.allowlist)
    warnings = parse_logs(args.logs)
    unreviewed = sorted(msg_id for msg_id in warnings if msg_id not in allowed)

    print("Vivado warning summary:")
    if not warnings:
        print("  no warnings found")
        return 0

    for msg_id in sorted(warnings):
        entry = warnings[msg_id]
        status = "reviewed" if msg_id in allowed else "UNREVIEWED"
        print(f"  {entry['severity']} [{msg_id}]: {entry['count']} ({status})")
        examples = entry["examples"]
        assert isinstance(examples, list)
        for path, lineno, message in examples:
            print(f"    {path}:{lineno}: {message}")

    if unreviewed:
        print("\nUnreviewed Vivado warning IDs:")
        for msg_id in unreviewed:
            print(f"  {msg_id}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
