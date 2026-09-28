#!/usr/bin/env python3
"""Summarize Vivado clock-domain crossings and fail on unreviewed ones.

Reads the cdc_crossings.tsv that rtl/platform/fpga/scripts/report_vivado_impl.tcl
writes from report_cdc, and checks every crossing against an allowlist of
<CDC rule ID> <startpoint glob> <endpoint glob> entries.
"""

from __future__ import annotations

import argparse
import csv
import sys
from collections import Counter
from fnmatch import fnmatchcase
from pathlib import Path

MAX_EXAMPLES = 20


Entry = tuple[str, str, str]


def load_allowlist(path: Path) -> list[Entry]:
    """Return the (rule ID, startpoint glob, endpoint glob) entries of an allowlist."""
    entries: list[Entry] = []
    with path.open(encoding="utf-8") as handle:
        for lineno, raw_line in enumerate(handle, start=1):
            line = raw_line.split("#", 1)[0].strip()
            if not line:
                continue
            fields = line.split()
            if len(fields) != 3:
                raise SystemExit(
                    f"{path}:{lineno}: expected '<CDC rule ID> <startpoint glob> <endpoint glob>'"
                )
            entries.append((fields[0], fields[1], fields[2]))
    return entries


def all_match(pins: str, glob: str) -> bool:
    """True if every pin in a field matches; multi-bit crossings list several."""
    names = pins.split()
    return bool(names) and all(fnmatchcase(name, glob) for name in names)


def reviewed_by(row: dict[str, str], entries: list[Entry]) -> Entry | None:
    """Return the allowlist entry that covers a crossing, or None."""
    for entry in entries:
        check, start_glob, end_glob = entry
        if (
            row["check"] == check
            and all_match(row["startpoint"], start_glob)
            and all_match(row["endpoint"], end_glob)
        ):
            return entry
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--allowlist", required=True, type=Path)
    parser.add_argument("crossings", type=Path, help="cdc_crossings.tsv from the report step")
    args = parser.parse_args()

    if not args.crossings.is_file():
        print(f"Error: {args.crossings} not found; run make fpga-report first", file=sys.stderr)
        return 2

    entries = load_allowlist(args.allowlist)
    with args.crossings.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))

    covered: Counter[Entry] = Counter()
    unreviewed: list[dict[str, str]] = []
    for row in rows:
        entry = reviewed_by(row, entries)
        if entry is None:
            unreviewed.append(row)
        else:
            covered[entry] += 1

    print(f"Vivado CDC summary: {len(rows)} crossing endpoint(s)")
    for (check, start_glob, end_glob), count in sorted(covered.items()):
        print(f"  {check} {start_glob} -> {end_glob}: {count} (reviewed)")

    if unreviewed:
        print(f"\nUnreviewed crossings ({len(unreviewed)}):")
        for row in unreviewed[:MAX_EXAMPLES]:
            print(
                f"  {row['check']} {row['severity']} "
                f"{row['startpoint_clock']} -> {row['endpoint_clock']}: "
                f"{row['startpoint']} -> {row['endpoint']}"
            )
        if len(unreviewed) > MAX_EXAMPLES:
            print(f"  ... and {len(unreviewed) - MAX_EXAMPLES} more")
        print(f"Review them in cdc_details.rpt, then fix the RTL or add them to {args.allowlist}.")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
