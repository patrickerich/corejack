#!/usr/bin/env python3
"""Fetch the optional dependency for one CoreJack core descriptor."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
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


def run_with_retry(cmd: list[str], cwd: Path, attempts: int = 4) -> None:
    """Run a network command, retrying failures after 2, 4 and 8 s.

    A single TLS or HTTP hiccup from GitHub is enough to fail a CI run that has
    nothing wrong with it. A genuinely bad revision still fails, just 14 s later.
    """
    for attempt in range(1, attempts + 1):
        returncode = subprocess.run(cmd, cwd=cwd, check=False).returncode
        if returncode == 0:
            return
        if attempt == attempts:
            fail(f"'{' '.join(cmd)}' failed {attempts} times (last exit {returncode})")
        delay = 2**attempt
        print(
            f"'{' '.join(cmd)}' failed (exit {returncode}); retrying in {delay} s",
            file=sys.stderr,
        )
        time.sleep(delay)


def is_shallow_or_empty(checkout: Path) -> bool:
    shallow = subprocess.run(
        ["git", "rev-parse", "--is-shallow-repository"],
        cwd=checkout,
        stdout=subprocess.PIPE,
        text=True,
        check=True,
    ).stdout.strip()
    return shallow == "true" or not commit_exists(checkout, "HEAD")


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


def checkout_dependency(
    core: str, upstream_override: str | None = None, rev_override: str | None = None
) -> None:
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
    upstream = upstream_override or upstream
    rev = rev_override or rev
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
    else:
        if not (checkout / ".git").is_dir():
            run(["git", "init", "--quiet", str(checkout)])
            run(["git", "remote", "add", "origin", upstream], cwd=checkout)
        if not commit_exists(checkout, rev):
            if is_shallow_or_empty(checkout):
                # Fetch only the pinned commit, not the upstream history: for
                # CVA6 that is 33 MB instead of 163 MB.
                run_with_retry(["git", "fetch", "--depth", "1", "origin", rev], cwd=checkout)
            else:
                # A full clone from before pinned-commit fetches: keep it full.
                run_with_retry(["git", "fetch", "--tags", "--prune", "origin"], cwd=checkout)
        run(["git", "checkout", "--force", rev], cwd=checkout)
    sanitize_checkout(package, checkout)
    link.unlink(missing_ok=True)
    link.symlink_to(checkout)
    print(f"CORE={core}: {package} -> {checkout}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core", required=True)
    # For make deps-cva6, whose pin lives in the Makefile (CVA6_REPO, CVA6_REV).
    parser.add_argument("--upstream", help="override the descriptor's upstream URL")
    parser.add_argument("--rev", help="override the descriptor's pinned revision")
    args = parser.parse_args()
    checkout_dependency(args.core, args.upstream, args.rev)


if __name__ == "__main__":
    main()
