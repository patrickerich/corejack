#!/usr/bin/env python3
"""Fetch the optional dependency for one CoreJack core descriptor."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
CORE_DIR = REPO_ROOT / "cfg" / "cores"


def fail(message: str) -> None:
    print(f"Error: {message}", file=sys.stderr)
    sys.exit(1)


def yaml_path_scalar(text: str, path: tuple[str, ...]) -> str | None:
    current_path: list[tuple[int, str]] = []

    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("- "):
            continue

        match = re.match(r"^(\s*)([A-Za-z0-9_]+):\s*(.*?)\s*$", line)
        if not match:
            continue

        indent = len(match.group(1))
        key = match.group(2)
        value = match.group(3)

        while current_path and current_path[-1][0] >= indent:
            current_path.pop()
        current_path.append((indent, key))

        if tuple(item[1] for item in current_path) == path:
            if not value:
                return None
            return value.strip().strip("'\"")

    return None


def run(cmd: list[str], cwd: Path | None = None) -> None:
    subprocess.run(cmd, cwd=cwd, check=True)


def commit_exists(checkout: Path, rev: str) -> bool:
    return subprocess.run(
        ["git", "cat-file", "-e", f"{rev}^{{commit}}"],
        cwd=checkout,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode == 0


def sanitize_checkout(package: str, checkout: Path) -> None:
    if package == "picorv32":
        # The upstream FuseSoC core file is not used by CoreJack and currently
        # trips FuseSoC metadata parsing during --cores-root scans.
        (checkout / "picorv32.core").unlink(missing_ok=True)


def checkout_dependency(core: str) -> None:
    descriptor = CORE_DIR / f"{core}.yaml"
    if not descriptor.is_file():
        fail(f"unknown CORE '{core}'")

    text = descriptor.read_text(encoding="utf-8")
    manager = yaml_path_scalar(text, ("dependency", "manager"))
    if manager is None:
        print(f"CORE={core}: no external core dependency")
        return

    package = yaml_path_scalar(text, ("dependency", "package"))
    path_text = yaml_path_scalar(text, ("dependency", "path"))
    upstream = yaml_path_scalar(text, ("dependency", "upstream"))
    rev = yaml_path_scalar(text, ("dependency", "rev"))
    if not package or not path_text or not upstream or not rev:
        fail(f"CORE '{core}' dependency requires package, path, upstream, and rev")

    if manager not in {"bender_vendor_package", "project_local_git_checkout"}:
        fail(f"unsupported dependency manager for CORE '{core}': {manager}")

    if Path(path_text).parts[:1] != ("deps",):
        fail(f"CORE '{core}' dependency path must be under deps/: {path_text}")

    checkout = REPO_ROOT / ".bender" / "vendor" / package
    link = REPO_ROOT / path_text
    checkout.parent.mkdir(parents=True, exist_ok=True)
    link.parent.mkdir(parents=True, exist_ok=True)

    if checkout.exists() and not (checkout / ".git").is_dir():
        # Existing Bender vendor-copy checkout. It is already an exact source
        # copy, but not a Git checkout that can be fetched in place.
        pass
    elif not (checkout / ".git").is_dir():
        run(["git", "clone", upstream, str(checkout)])
        if not commit_exists(checkout, rev):
            run(["git", "fetch", "--tags", "--prune", "origin"], cwd=checkout)
        run(["git", "checkout", "--force", rev], cwd=checkout)
    else:
        if not commit_exists(checkout, rev):
            run(["git", "fetch", "--tags", "--prune", "origin"], cwd=checkout)
        run(["git", "checkout", "--force", rev], cwd=checkout)
    sanitize_checkout(package, checkout)
    link.unlink(missing_ok=True)
    link.symlink_to(checkout)
    print(f"CORE={core}: {package} -> {checkout}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core", required=True)
    args = parser.parse_args()
    checkout_dependency(args.core)


if __name__ == "__main__":
    main()
