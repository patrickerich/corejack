#!/usr/bin/env python3
"""Rewrite all CoreJack FuseSoC VLNV versions in .core files and scaffolds.

Most users should invoke this through the Make wrappers:

    make version-check                  # drift check (passes --check below)
    make bump-version VERSION=X.Y.Z     # rewrite (passes --to below)

Invoking this script directly is equivalent:

    python bin/bump_version.py --check
    python bin/bump_version.py --to X.Y.Z

FuseSoC parses the `name:` and dependency VLNV strings verbatim, so we cannot
inherit the project version from an environment variable at parse time. This
helper rewrites every `corejack:<lib>:<name>:<old>` occurrence to a new SemVer
in one atomic sweep, keeping every cross-reference in sync.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

CORE_FILES = sorted(REPO_ROOT.glob("*.core"))
SCAFFOLD_TEMPLATES = [
    REPO_ROOT / "bin" / "create_core.py",
    REPO_ROOT / "bin" / "create_board.py",
]

# Match a CoreJack VLNV (Vendor:Library:Name:Version) where Version is SemVer.
# Captures the prefix up to (but excluding) the final ":Version" segment.
VLNV_RE = re.compile(r"(corejack(?::[A-Za-z0-9_]+)+):(\d+\.\d+\.\d+)")
SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+$")


def collect_files() -> list[Path]:
    files = [p for p in CORE_FILES if p.is_file()]
    files += [p for p in SCAFFOLD_TEMPLATES if p.is_file()]
    return files


def find_versions(files: list[Path]) -> dict[str, list[Path]]:
    """Return a map of version → list of files where it appears."""
    by_version: dict[str, list[Path]] = {}
    for path in files:
        text = path.read_text(encoding="utf-8")
        for match in VLNV_RE.finditer(text):
            by_version.setdefault(match.group(2), []).append(path)
    return by_version


def detect_current_version(files: list[Path]) -> str:
    by_version = find_versions(files)
    if not by_version:
        sys.exit("error: no CoreJack VLNV versions found")
    if len(by_version) > 1:
        print("error: multiple CoreJack VLNV versions present:", file=sys.stderr)
        for version, paths in sorted(by_version.items()):
            rels = ", ".join(str(p.relative_to(REPO_ROOT)) for p in sorted(set(paths)))
            print(f"  {version}: {rels}", file=sys.stderr)
        sys.exit(1)
    return next(iter(by_version))


def rewrite(path: Path, new_version: str) -> int:
    text = path.read_text(encoding="utf-8")
    new_text, n = VLNV_RE.subn(lambda m: f"{m.group(1)}:{new_version}", text)
    if n > 0 and new_text != text:
        path.write_text(new_text, encoding="utf-8")
    return n


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--to",
        help="New SemVer version to rewrite to, e.g. 0.2.0",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Verify all .core files agree on a single version; no rewrite",
    )
    args = parser.parse_args()

    files = collect_files()
    if not files:
        sys.exit("error: no .core files or scaffold templates found")

    current = detect_current_version(files)
    print(f"Current CoreJack VLNV version: {current}")

    if args.check:
        print("OK (all .core files and scaffold templates agree)")
        return

    if not args.to:
        sys.exit("error: --to <VERSION> is required (or pass --check)")
    if not SEMVER_RE.match(args.to):
        sys.exit(f"error: --to must be SemVer X.Y.Z; got '{args.to}'")
    if args.to == current:
        print(f"Already at {args.to}; nothing to do.")
        return

    print(f"Bumping to: {args.to}")
    total = 0
    for path in files:
        n = rewrite(path, args.to)
        if n > 0:
            rel = path.relative_to(REPO_ROOT)
            print(f"  {rel}: {n} VLNV reference(s) updated")
            total += n
    print(f"Done: {total} VLNV references rewritten across {len(files)} file(s).")
    print(
        "Review with `git diff`, commit, then tag (e.g. "
        f"`git tag -a v{args.to} -m 'CoreJack v{args.to}'`)."
    )


if __name__ == "__main__":
    main()
