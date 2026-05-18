from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


def run_cmd(args: list[str], cwd: Path = REPO_ROOT, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=cwd,
        check=check,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def copy_file(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def copy_minimal_board_repo(tmp_path: Path) -> Path:
    repo = tmp_path / "repo"
    copy_file(REPO_ROOT / "bin" / "create_board.py", repo / "bin" / "create_board.py")
    copy_file(REPO_ROOT / "corejack.core", repo / "corejack.core")
    return repo


def copy_minimal_core_repo(tmp_path: Path) -> Path:
    repo = tmp_path / "repo"
    for script in ("create_core.py", "validate_target.py"):
        copy_file(REPO_ROOT / "bin" / script, repo / "bin" / script)
    copy_file(REPO_ROOT / "corejack.core", repo / "corejack.core")
    copy_file(REPO_ROOT / "rtl" / "pkg" / "platform_pkg.sv", repo / "rtl" / "pkg" / "platform_pkg.sv")
    copy_file(REPO_ROOT / "cfg" / "boards" / "axku5.yaml", repo / "cfg" / "boards" / "axku5.yaml")
    return repo


def next_core_type_from_platform_pkg(path: Path) -> int:
    values: list[int] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip().startswith("CORE_") and "=" in line:
            values.append(int(line.rsplit("=", 1)[1].rstrip(",").strip()))
    return max(values, default=-1) + 1


def test_validate_target_emits_combined_fusesoc_flags() -> None:
    result = run_cmd(
        [
            sys.executable,
            "bin/validate_target.py",
            "--core",
            "ibex",
            "--board",
            "axku5",
            "--make",
            "--allow-planned",
        ]
    )

    assert "$(eval FUSESOC_CORE_FLAGS := core_ibex core_region)" in result.stdout
    assert "$(eval FUSESOC_BOARD_FLAG := board_axku5)" in result.stdout
    assert "$(eval FUSESOC_FLAGS := core_ibex core_region board_axku5)" in result.stdout


def test_validate_target_rejects_unknown_core() -> None:
    result = run_cmd(
        [
            sys.executable,
            "bin/validate_target.py",
            "--core",
            "does_not_exist",
            "--board",
            "axku5",
        ],
        check=False,
    )

    assert result.returncode != 0
    assert "unknown CORE" in result.stderr


def test_support_matrix_generation_covers_all_core_descriptors(tmp_path: Path) -> None:
    out = tmp_path / "support_matrix.md"
    run_cmd([sys.executable, "bin/render_support_matrix.py", "--out", str(out)])
    text = out.read_text(encoding="utf-8")

    for descriptor in sorted((REPO_ROOT / "cfg" / "cores").glob("*.yaml")):
        assert f"`{descriptor.stem}`" in text


def test_support_matrix_check_detects_stale_output(tmp_path: Path) -> None:
    out = tmp_path / "support_matrix.md"
    out.write_text("# stale\n", encoding="utf-8")

    result = run_cmd(
        [sys.executable, "bin/render_support_matrix.py", "--out", str(out), "--check"],
        check=False,
    )

    assert result.returncode != 0
    assert "is stale" in result.stderr


def test_create_board_scaffold_and_overwrite_guard(tmp_path: Path) -> None:
    repo = copy_minimal_board_repo(tmp_path)
    create_board = repo / "bin" / "create_board.py"

    run_cmd(
        [
            sys.executable,
            str(create_board),
            "--repo-root",
            str(repo),
            "--board",
            "testboard",
            "--part",
            "xc7a35ticsg324-1L",
            "--display-name",
            "Test Board",
        ],
        cwd=repo,
    )

    assert (repo / "cfg" / "boards" / "testboard.yaml").is_file()
    assert (repo / "rtl" / "platform" / "fpga" / "boards" / "testboard" / "testboard.xdc").is_file()
    assert (repo / "rtl" / "platform" / "fpga" / "boards" / "testboard" / "corejack_testboard_wrap.sv").is_file()
    assert (repo / "corejack_board_testboard.core").is_file()
    corejack_core = (repo / "corejack.core").read_text(encoding="utf-8")
    assert "board_testboard_rtl" in corejack_core
    assert "board_testboard ? (corejack_testboard_wrap)" in corejack_core

    duplicate = run_cmd(
        [
            sys.executable,
            str(create_board),
            "--repo-root",
            str(repo),
            "--board",
            "testboard",
            "--part",
            "xc7a35ticsg324-1L",
        ],
        cwd=repo,
        check=False,
    )
    assert duplicate.returncode != 0
    assert "refusing to overwrite" in duplicate.stderr or "already exists" in duplicate.stderr


def test_create_core_scaffold_core_check_and_overwrite_guard(tmp_path: Path) -> None:
    repo = copy_minimal_core_repo(tmp_path)
    create_core = repo / "bin" / "create_core.py"
    validate_target = repo / "bin" / "validate_target.py"

    run_cmd(
        [
            sys.executable,
            str(create_core),
            "--repo-root",
            str(repo),
            "--core",
            "testcore",
            "--display-name",
            "Test Core",
        ],
        cwd=repo,
    )

    assert (repo / "cfg" / "cores" / "testcore.yaml").is_file()
    assert (repo / "rtl" / "cores" / "corejack_testcore_socket_adapter.sv").is_file()
    assert (repo / "corejack_core_testcore.core").is_file()
    expected_core_type = next_core_type_from_platform_pkg(REPO_ROOT / "rtl" / "pkg" / "platform_pkg.sv")
    assert f"CORE_TESTCORE = {expected_core_type}" in (
        repo / "rtl" / "pkg" / "platform_pkg.sv"
    ).read_text(encoding="utf-8")
    assert "  - testcore" in (repo / "cfg" / "boards" / "axku5.yaml").read_text(encoding="utf-8")

    check = run_cmd([sys.executable, str(validate_target), "--core", "testcore", "--core-check"], cwd=repo)
    assert "CORE_CHECK=passed" in check.stdout

    duplicate = run_cmd(
        [
            sys.executable,
            str(create_core),
            "--repo-root",
            str(repo),
            "--core",
            "testcore",
        ],
        cwd=repo,
        check=False,
    )
    assert duplicate.returncode != 0
    assert "refusing to overwrite" in duplicate.stderr or "already exists" in duplicate.stderr
