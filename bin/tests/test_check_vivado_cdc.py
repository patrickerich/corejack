from __future__ import annotations

import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "bin" / "check_vivado_cdc.py"
ALLOWLIST = REPO_ROOT / "cfg" / "vivado_cdc_allowlist.txt"
HEADER = "check\tseverity\tstartpoint_clock\tendpoint_clock\tstartpoint\tendpoint\n"


def run_check(tmp_path: Path, rows: list[str]) -> subprocess.CompletedProcess[str]:
    tsv = tmp_path / "cdc_crossings.tsv"
    tsv.write_text(HEADER + "".join(row + "\n" for row in rows), encoding="utf-8")
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--allowlist", str(ALLOWLIST), str(tsv)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )


def test_reviewed_crossings_pass(tmp_path: Path) -> None:
    result = run_check(
        tmp_path,
        [
            "CDC-1\tCritical\tjtag_tck_pin\tcore_clk_raw\t"
            "i_soc_top/gen_platform.i_dmi_jtag/i_dmi_cdc/i_cdc_req/i_src/data_src_q_reg[3]/C\t"
            "i_soc_top/gen_platform.i_dm_top/i_dm_csrs/data_q_reg[0][3]/D",
            "CDC-7\tCritical\tinput port clock\tcore_clk_raw\tsys_rst_n\tpll_locked_r_reg/CLR",
        ],
    )
    assert result.returncode == 0, result.stdout
    assert "Unreviewed" not in result.stdout


def test_new_crossing_fails(tmp_path: Path) -> None:
    # A crossing out of CoreJack RTL, and a new rule ID on a reviewed source.
    result = run_check(
        tmp_path,
        [
            "CDC-1\tCritical\tcore_clk_raw\tjtag_tck_pin\t"
            "i_soc_top/gen_platform.i_plic/irq_q_reg/C\ti_soc_top/gen_platform.i_dmi_jtag/x_reg/D",
            "CDC-10\tCritical\tjtag_tck_pin\tcore_clk_raw\t"
            "i_soc_top/gen_platform.i_dmi_jtag/i_dmi_cdc/y_reg/C\tz_reg/D",
        ],
    )
    assert result.returncode == 1
    assert "Unreviewed crossings (2)" in result.stdout
    assert "i_plic/irq_q_reg" in result.stdout


def test_reviewed_source_into_corejack_logic_fails(tmp_path: Path) -> None:
    # Starts in the reviewed DMI handshake, but lands in CoreJack's PLIC.
    result = run_check(
        tmp_path,
        [
            "CDC-1\tCritical\tjtag_tck_pin\tcore_clk_raw\t"
            "i_soc_top/gen_platform.i_dmi_jtag/i_dmi_cdc/i_cdc_req/i_src/data_src_q_reg[0]/C\t"
            "i_soc_top/gen_platform.i_plic/prio_q_reg[0]/D",
        ],
    )
    assert result.returncode == 1
    assert "i_plic/prio_q_reg" in result.stdout


def test_every_pin_of_a_multibit_crossing_must_match(tmp_path: Path) -> None:
    src = "i_soc_top/gen_platform.i_dmi_jtag/i_dmi_cdc/i_cdc_req/i_src/data_src_q_reg[{}]/C"
    reviewed = "i_soc_top/gen_platform.i_dm_top/i_dm_csrs/data_q_reg[{}]/D"
    stray = "i_soc_top/gen_platform.i_plic/prio_q_reg[1]/D"
    starts = f"{src.format(0)} {src.format(1)}"
    ends = f"{reviewed.format(0)} {reviewed.format(1)}"
    ok = run_check(tmp_path, [f"CDC-1\tCritical\ta\tb\t{starts}\t{ends}"])
    assert ok.returncode == 0, ok.stdout
    bad = run_check(tmp_path, [f"CDC-1\tCritical\ta\tb\t{starts}\t{reviewed.format(0)} {stray}"])
    assert bad.returncode == 1


def test_missing_report_is_an_error(tmp_path: Path) -> None:
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--allowlist", str(ALLOWLIST), str(tmp_path / "none.tsv")],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    assert result.returncode == 2
