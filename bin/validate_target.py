#!/usr/bin/env python3
"""Validate CoreJack CORE/BOARD selections against descriptor files."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from string import Formatter


REPO_ROOT = Path(__file__).resolve().parents[1]
CORE_DIR = REPO_ROOT / "cfg" / "cores"
BOARD_DIR = REPO_ROOT / "cfg" / "boards"
MAKEFILE = REPO_ROOT / "Makefile"
FUSESOC_CORE = REPO_ROOT / "corejack.core"
SUPPORTED_STATUS = "supported"
ZEPHYR_STATUSES = {"initial_supported", "supported", "planned", "unsupported"}
PLATFORM_INTEGRATIONS = {"socket_region", "native_axi"}


def descriptor_names(directory: Path) -> list[str]:
    return sorted(path.stem for path in directory.glob("*.yaml"))


def descriptor_path(directory: Path, name: str) -> Path:
    return directory / f"{name}.yaml"


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

        keys = tuple(item[1] for item in current_path)
        if keys == path:
            if not value:
                return None
            if value.startswith(("'", '"')) and value.endswith(("'", '"')):
                value = value[1:-1]
            return value

    return None


def require_scalar(text: str, path: tuple[str, ...], descriptor: str) -> str:
    value = yaml_path_scalar(text, path)
    if value is None:
        fail(f"missing required field '{'.'.join(path)}' in {descriptor}")
    return value


def yaml_top_list(text: str, key: str) -> list[str]:
    lines = text.splitlines()
    values: list[str] = []
    in_list = False
    base_indent = 0

    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        key_match = re.match(rf"^(\s*){re.escape(key)}:\s*(.*)$", line)
        if key_match:
            in_list = True
            base_indent = len(key_match.group(1))
            inline = key_match.group(2).strip()
            if inline.startswith("[") and inline.endswith("]"):
                body = inline[1:-1].strip()
                if body:
                    values.extend(item.strip().strip("'\"") for item in body.split(","))
                return values
            if inline:
                values.append(inline.strip("'\""))
                return values
            continue

        if in_list:
            indent = len(line) - len(line.lstrip())
            if indent <= base_indent:
                break
            item_match = re.match(r"^\s*-\s*(.+?)\s*$", line)
            if item_match:
                values.append(item_match.group(1).strip().strip("'\""))

    return values


def parse_positive_int(value: str, field: str) -> int:
    try:
        parsed = int(value, 0)
    except ValueError:
        fail(f"{field} must be an integer, got '{value}'")
    if parsed <= 0:
        fail(f"{field} must be positive, got '{value}'")
    return parsed


def parse_nonnegative_int(value: str, field: str) -> int:
    try:
        parsed = int(value, 0)
    except ValueError:
        fail(f"{field} must be an integer, got '{value}'")
    if parsed < 0:
        fail(f"{field} must be non-negative, got '{value}'")
    return parsed


def integration_status(core_text: str, flow: str) -> str:
    return yaml_path_scalar(core_text, ("integration", flow)) or SUPPORTED_STATUS


def zephyr_status(core_text: str) -> str:
    return yaml_path_scalar(core_text, ("software", "zephyr", "status")) or "planned"


def platform_integration(core_text: str) -> str:
    integration = require_scalar(core_text, ("platform", "integration"), "CORE descriptor")
    if integration not in PLATFORM_INTEGRATIONS:
        fail(
            "platform.integration must be one of "
            f"{', '.join(sorted(PLATFORM_INTEGRATIONS))}; got '{integration}'"
        )
    return integration


def fusesoc_core_flags(core_text: str) -> list[str]:
    core_flag = require_scalar(core_text, ("fusesoc", "core_flag"), "CORE descriptor")
    integration = platform_integration(core_text)
    flags = [core_flag]
    if integration == "socket_region":
        flags.append("core_region")
    return flags


def fusesoc_board_flag(board_text: str) -> str:
    flag = require_scalar(board_text, ("fusesoc", "board_flag"), "BOARD descriptor")
    if not re.fullmatch(r"[A-Za-z0-9_]+", flag):
        fail(f"fusesoc.board_flag contains unsupported characters: {flag}")
    return flag


def fail(message: str) -> None:
    print(f"Error: {message}", file=sys.stderr)
    sys.exit(1)


def target_config(core: str, board: str, core_text: str, board_text: str) -> dict[str, str]:
    top_template = require_scalar(board_text, ("fpga", "top_template"), f"BOARD '{board}'")
    template_fields = {field for _, field, _, _ in Formatter().parse(top_template) if field}
    unsupported_fields = template_fields - {"core", "board"}
    if unsupported_fields:
        fail(
            f"unsupported field(s) in board top_template: "
            f"{', '.join(sorted(unsupported_fields))}"
        )

    fpga_target_template = require_scalar(board_text, ("fpga", "target"), f"BOARD '{board}'")
    fpga_target_fields = {field for _, field, _, _ in Formatter().parse(fpga_target_template) if field}
    unsupported_fpga_target_fields = fpga_target_fields - {"core", "board"}
    if unsupported_fpga_target_fields:
        fail(
            f"unsupported field(s) in board fpga.target: "
            f"{', '.join(sorted(unsupported_fpga_target_fields))}"
        )
    fpga_target = fpga_target_template.format(core=core, board=board)
    board_flag = fusesoc_board_flag(board_text)
    work_root = require_scalar(board_text, ("fpga", "work_root"), f"BOARD '{board}'")
    jtag_adapter = require_scalar(board_text, ("debug", "jtag_adapter"), f"BOARD '{board}'")
    openocd_cfg = f"rtl/platform/fpga/scripts/openocd-{jtag_adapter}.cfg"
    soc_clk_hz = require_scalar(board_text, ("clock", "soc_hz"), f"BOARD '{board}'")
    uart_baud = require_scalar(board_text, ("uart", "baud"), f"BOARD '{board}'")
    # Optional per-board SRAM size. Unset preserves the soc_top default of
    # 1 MiB (262144 32-bit words), so existing boards are unaffected. This is
    # the single source of truth: the bare-metal linker (SOC_RAM_BYTES), the
    # FPGA wrapper (RAM_WORDS -> soc_top RamWords vlogparam), and the Zephyr
    # devicetree (COREJACK_RAM_BYTES cpp define) all derive from it.
    ram_bytes = yaml_path_scalar(board_text, ("memory", "ram_bytes")) or "1048576"
    ram_words = str(int(ram_bytes, 0) // 4)
    march = require_scalar(core_text, ("isa", "march"), f"CORE '{core}'")
    mabi = require_scalar(core_text, ("isa", "mabi"), f"CORE '{core}'")
    toolchain = require_scalar(core_text, ("software", "toolchain"), f"CORE '{core}'")
    zephyr = zephyr_status(core_text)
    core_type = require_scalar(core_text, ("platform", "core_type"), f"CORE '{core}'")
    integration = platform_integration(core_text)
    sim_target = require_scalar(core_text, ("fusesoc", "sim_target"), f"CORE '{core}'")
    core_flag = require_scalar(core_text, ("fusesoc", "core_flag"), f"CORE '{core}'")
    core_flags = fusesoc_core_flags(core_text)
    fusesoc_flags = [*core_flags, board_flag]

    return {
        "CORE_TYPE": core_type,
        "CORE_INTEGRATION": integration,
        "SIM_FUSESOC_TARGET": sim_target,
        "FUSESOC_CORE_FLAG": core_flag,
        "FUSESOC_CORE_FLAGS": " ".join(core_flags),
        "FUSESOC_BOARD_FLAG": board_flag,
        "FUSESOC_FLAGS": " ".join(fusesoc_flags),
        "FPGA_TOP": top_template.format(core=core, board=board),
        "FPGA_TARGET": fpga_target,
        "FPGA_WORK_ROOT": str(
            (REPO_ROOT / work_root.format(core=core, board=board)).resolve()
        ),
        "JTAG_ADAPTER": jtag_adapter,
        "MARCH": march,
        "MABI": mabi,
        "TOOLCHAIN": toolchain,
        "ZEPHYR_STATUS": zephyr,
        "SOC_CLK_HZ": soc_clk_hz,
        "UART_BAUD": uart_baud,
        "SOC_RAM_BYTES": ram_bytes,
        "RAM_WORDS": ram_words,
    }


def load_descriptors(core: str, board: str) -> tuple[str, str]:
    core_path = descriptor_path(CORE_DIR, core)
    board_path = descriptor_path(BOARD_DIR, board)

    if not core_path.is_file():
        cores = descriptor_names(CORE_DIR)
        fail(f"unknown CORE '{core}'. Available cores: {', '.join(cores) or '(none)'}")
    if not board_path.is_file():
        boards = descriptor_names(BOARD_DIR)
        fail(f"unknown BOARD '{board}'. Available boards: {', '.join(boards) or '(none)'}")

    return (
        core_path.read_text(encoding="utf-8"),
        board_path.read_text(encoding="utf-8"),
    )


def is_compatible(
    core: str,
    board: str,
    core_text: str,
    board_text: str,
    flow: str,
    allow_planned: bool = False,
) -> tuple[bool, str]:
    status = integration_status(core_text, flow)
    if status == "unsupported":
        return False, f"{flow} integration status: {status}"
    if status != SUPPORTED_STATUS and not allow_planned:
        return False, f"{flow} integration status: {status}"

    compatible_boards = yaml_top_list(core_text, "compatible_boards")
    compatible_cores = yaml_top_list(board_text, "compatible_cores")

    if compatible_boards and board not in compatible_boards:
        return False, f"core supports: {', '.join(compatible_boards)}"
    if compatible_cores and core not in compatible_cores:
        return False, f"board supports: {', '.join(compatible_cores)}"
    return True, ""


def validate(
    core: str,
    board: str,
    quiet: bool,
    make: bool,
    allow_planned: bool,
    flow: str,
) -> None:
    core_text, board_text = load_descriptors(core, board)

    compatible, reason = is_compatible(
        core,
        board,
        core_text,
        board_text,
        flow,
        allow_planned,
    )

    if not compatible:
        fail(f"CORE '{core}' and BOARD '{board}' are not compatible ({reason})")

    config = target_config(core, board, core_text, board_text)

    if quiet:
        return

    if make:
        for key, value in config.items():
            print(f"$(eval {key} := {value})")
        return

    print(f"CORE={core}")
    print(f"BOARD={board}")
    print(f"FLOW={flow}")
    print(f"INTEGRATION_STATUS={integration_status(core_text, flow)}")
    for key in (
        "FPGA_TOP",
        "FPGA_TARGET",
        "FPGA_WORK_ROOT",
        "CORE_TYPE",
        "CORE_INTEGRATION",
        "SIM_FUSESOC_TARGET",
        "FUSESOC_CORE_FLAG",
        "FUSESOC_CORE_FLAGS",
        "FUSESOC_BOARD_FLAG",
        "FUSESOC_FLAGS",
        "JTAG_ADAPTER",
        "MARCH",
        "MABI",
        "TOOLCHAIN",
        "ZEPHYR_STATUS",
        "SOC_CLK_HZ",
        "UART_BAUD",
    ):
        print(f"{key}={config[key]}")


def list_targets() -> None:
    cores = descriptor_names(CORE_DIR)
    boards = descriptor_names(BOARD_DIR)

    print("Available cores:")
    for core in cores:
        print(f"  {core}")
    if not cores:
        print("  (none)")

    print("Available boards:")
    for board in boards:
        print(f"  {board}")
    if not boards:
        print("  (none)")

    print("Descriptor combinations:")
    found = False
    unavailable: list[tuple[str, str, str]] = []
    for core in cores:
        for board in boards:
            core_text, board_text = load_descriptors(core, board)
            compatible, reason = is_compatible(
                core,
                board,
                core_text,
                board_text,
                "fpga",
                allow_planned=True,
            )
            if not compatible:
                unavailable.append((core, board, reason))
                continue

            config = target_config(core, board, core_text, board_text)
            found = True
            print(
                "  "
                f"{core}/{board}: "
                f"sim_target={config['SIM_FUSESOC_TARGET']} "
                f"core_flag={config['FUSESOC_CORE_FLAG']} "
                f"core_flags={config['FUSESOC_CORE_FLAGS']} "
                f"board_flag={config['FUSESOC_BOARD_FLAG']} "
                f"target={config['FPGA_TARGET']} "
                f"top={config['FPGA_TOP']} "
                f"core_type={config['CORE_TYPE']} "
                f"integration={config['CORE_INTEGRATION']} "
                f"toolchain={config['TOOLCHAIN']} "
                f"zephyr={config['ZEPHYR_STATUS']} "
                f"march={config['MARCH']} "
                f"mabi={config['MABI']} "
                f"clk={config['SOC_CLK_HZ']}Hz "
                f"baud={config['UART_BAUD']} "
                f"sim={integration_status(core_text, 'sim')} "
                f"fpga={integration_status(core_text, 'fpga')} "
                f"debug={integration_status(core_text, 'debug')}"
            )
    if not found:
        print("  (none)")

    if unavailable:
        print("Unavailable combinations:")
        for core, board, reason in unavailable:
            print(f"  {core}/{board}: {reason}")


def print_compatible_cores(board: str) -> None:
    board_path = descriptor_path(BOARD_DIR, board)
    if not board_path.is_file():
        boards = descriptor_names(BOARD_DIR)
        fail(f"unknown BOARD '{board}'. Available boards: {', '.join(boards) or '(none)'}")

    board_text = board_path.read_text(encoding="utf-8")
    compatible_cores = yaml_top_list(board_text, "compatible_cores")
    if compatible_cores:
        print(" ".join(compatible_cores))
    else:
        print(" ".join(descriptor_names(CORE_DIR)))


def make_target_exists(target: str) -> bool:
    if not MAKEFILE.is_file():
        return False
    makefile_text = MAKEFILE.read_text(encoding="utf-8")
    return re.search(rf"(?m)^{re.escape(target)}\s*:", makefile_text) is not None


def fusesoc_target_exists(target: str) -> bool:
    if not FUSESOC_CORE.is_file():
        return False
    core_text = FUSESOC_CORE.read_text(encoding="utf-8")
    return re.search(rf"(?m)^\s{{2}}{re.escape(target)}:\s*$", core_text) is not None


def check_repo_file(path_text: str, field: str) -> Path:
    path = REPO_ROOT / path_text
    if not path.is_file():
        fail(f"{field} points to a missing file: {path_text}")
    return path


def platform_core_type_values() -> dict[str, int]:
    pkg_path = REPO_ROOT / "rtl" / "pkg" / "platform_pkg.sv"
    if not pkg_path.is_file():
        fail(f"missing platform package: {pkg_path.relative_to(REPO_ROOT)}")

    text = pkg_path.read_text(encoding="utf-8")
    match = re.search(
        r"typedef\s+enum\s+int\s+unsigned\s*\{(?P<body>.*?)\}\s*core_type_e\s*;",
        text,
        flags=re.S,
    )
    if not match:
        fail("could not find platform_pkg::core_type_e")

    values: dict[str, int] = {}
    for name, value in re.findall(r"\b(CORE_[A-Z0-9_]+)\s*=\s*([0-9]+)", match.group("body")):
        values[name] = int(value, 10)
    return values


def expected_core_enum_name(core: str) -> str:
    return "CORE_" + re.sub(r"[^A-Za-z0-9]+", "_", core).upper()


def core_type_usage() -> dict[int, list[str]]:
    usage: dict[int, list[str]] = {}
    for core in descriptor_names(CORE_DIR):
        core_text = descriptor_path(CORE_DIR, core).read_text(encoding="utf-8")
        value = yaml_path_scalar(core_text, ("platform", "core_type"))
        if value is None:
            continue
        core_type = parse_nonnegative_int(value, f"{core}.platform.core_type")
        usage.setdefault(core_type, []).append(core)
    return usage


def require_status(value: str, field: str) -> None:
    if value not in {"supported", "planned", "unsupported"}:
        fail(f"{field} must be supported, planned, or unsupported; got '{value}'")


def core_check(core: str, verbose: bool = True) -> None:
    core_path = descriptor_path(CORE_DIR, core)
    if not core_path.is_file():
        cores = descriptor_names(CORE_DIR)
        fail(f"unknown CORE '{core}'. Available cores: {', '.join(cores) or '(none)'}")

    core_text = core_path.read_text(encoding="utf-8")
    name = require_scalar(core_text, ("name",), f"CORE '{core}'")
    display_name = require_scalar(core_text, ("display_name",), f"CORE '{core}'")
    if name != core:
        fail(f"CORE descriptor name '{name}' does not match filename '{core}'")

    statuses = {
        flow: require_scalar(core_text, ("integration", flow), f"CORE '{core}'")
        for flow in ("sim", "fpga", "debug")
    }
    for flow, status in statuses.items():
        require_status(status, f"integration.{flow}")

    adapter_module = require_scalar(core_text, ("adapter", "module"), f"CORE '{core}'")
    adapter_file = require_scalar(core_text, ("adapter", "file"), f"CORE '{core}'")
    adapter_path = check_repo_file(adapter_file, "adapter.file")
    adapter_text = adapter_path.read_text(encoding="utf-8")
    if re.search(rf"(?m)^\s*module\s+{re.escape(adapter_module)}\b", adapter_text) is None:
        fail(f"adapter.file does not define module {adapter_module}: {adapter_file}")

    core_type = parse_nonnegative_int(
        require_scalar(core_text, ("platform", "core_type"), f"CORE '{core}'"),
        "platform.core_type",
    )
    integration = require_scalar(core_text, ("platform", "integration"), f"CORE '{core}'")
    enum_values = platform_core_type_values()
    enum_name = expected_core_enum_name(core)
    if enum_name not in enum_values:
        fail(f"platform_pkg::core_type_e is missing {enum_name}")
    if enum_values[enum_name] != core_type:
        fail(
            f"platform.core_type={core_type} does not match "
            f"platform_pkg::{enum_name}={enum_values[enum_name]}"
        )

    users = core_type_usage().get(core_type, [])
    duplicates = [name for name in users if name != core]
    if duplicates:
        fail(f"platform.core_type={core_type} is also used by: {', '.join(duplicates)}")

    wrapper_module = require_scalar(core_text, ("wrapper", "module"), f"CORE '{core}'")
    sim_target = require_scalar(core_text, ("fusesoc", "sim_target"), f"CORE '{core}'")
    core_flag = require_scalar(core_text, ("fusesoc", "core_flag"), f"CORE '{core}'")
    xlen = parse_positive_int(require_scalar(core_text, ("isa", "xlen"), f"CORE '{core}'"), "isa.xlen")
    march = require_scalar(core_text, ("isa", "march"), f"CORE '{core}'")
    mabi = require_scalar(core_text, ("isa", "mabi"), f"CORE '{core}'")
    boot_addr = parse_nonnegative_int(
        require_scalar(core_text, ("reset", "boot_addr"), f"CORE '{core}'"),
        "reset.boot_addr",
    )
    mtvec_addr = parse_nonnegative_int(
        require_scalar(core_text, ("reset", "mtvec_addr"), f"CORE '{core}'"),
        "reset.mtvec_addr",
    )
    instruction_bus = require_scalar(core_text, ("buses", "instruction"), f"CORE '{core}'")
    data_bus = require_scalar(core_text, ("buses", "data"), f"CORE '{core}'")
    validated_min_hz = parse_nonnegative_int(
        require_scalar(core_text, ("clocking", "validated_min_hz"), f"CORE '{core}'"),
        "clocking.validated_min_hz",
    )
    validated_max_hz = parse_nonnegative_int(
        require_scalar(core_text, ("clocking", "validated_max_hz"), f"CORE '{core}'"),
        "clocking.validated_max_hz",
    )
    default_target = require_scalar(core_text, ("software", "default_target"), f"CORE '{core}'")
    toolchain = require_scalar(core_text, ("software", "toolchain"), f"CORE '{core}'")
    zephyr = require_scalar(core_text, ("software", "zephyr", "status"), f"CORE '{core}'")
    compatible_boards = yaml_top_list(core_text, "compatible_boards")

    if xlen not in {32, 64}:
        fail(f"isa.xlen must be 32 or 64, got {xlen}")
    expected_march_prefix = f"rv{xlen}"
    if not march.startswith(expected_march_prefix):
        fail(f"isa.march must start with {expected_march_prefix}, got '{march}'")
    if xlen == 32 and not mabi.startswith("ilp32"):
        fail(f"RV32 core must use an ilp32 ABI, got '{mabi}'")
    if xlen == 64 and not mabi.startswith("lp64"):
        fail(f"RV64 core must use an lp64 ABI, got '{mabi}'")
    if boot_addr % 4 != 0:
        fail(f"reset.boot_addr must be word-aligned, got 0x{boot_addr:x}")
    if mtvec_addr % 4 != 0:
        fail(f"reset.mtvec_addr must be word-aligned, got 0x{mtvec_addr:x}")
    if instruction_bus not in {"obi", "axi", "ahb_lite", "serv_wishbone_minimal", "picorv32_native"}:
        fail(f"unsupported instruction bus contract: {instruction_bus}")
    if data_bus not in {"obi", "axi", "ahb_lite", "serv_wishbone_minimal", "picorv32_native"}:
        fail(f"unsupported data bus contract: {data_bus}")
    if validated_max_hz and validated_min_hz > validated_max_hz:
        fail("clocking.validated_min_hz must be <= validated_max_hz")
    if default_target not in {"sim", "fpga"}:
        fail(f"software.default_target must be sim or fpga, got '{default_target}'")
    if not re.fullmatch(r"[A-Za-z0-9_.:-]+", sim_target):
        fail(f"fusesoc.sim_target contains unsupported characters: {sim_target}")
    if not re.fullmatch(r"[A-Za-z0-9_]+", core_flag):
        fail(f"fusesoc.core_flag contains unsupported characters: {core_flag}")
    if integration not in PLATFORM_INTEGRATIONS:
        fail(
            "platform.integration must be one of "
            f"{', '.join(sorted(PLATFORM_INTEGRATIONS))}; got '{integration}'"
        )
    if integration == "native_axi" and (instruction_bus != "axi" or data_bus != "axi"):
        fail("platform.integration native_axi requires axi instruction and data buses")
    if toolchain != "riscv-multilib":
        fail(f"unsupported software.toolchain: {toolchain}")
    if zephyr not in ZEPHYR_STATUSES:
        fail(f"unsupported software.zephyr.status: {zephyr}")
    if not compatible_boards:
        fail("compatible_boards must list at least one board")

    debug_supported = require_scalar(core_text, ("debug", "supported"), f"CORE '{core}'")
    if debug_supported not in {"true", "false"}:
        fail(f"debug.supported must be true or false, got '{debug_supported}'")
    if statuses["debug"] == "supported" and debug_supported != "true":
        fail("integration.debug is supported but debug.supported is not true")
    if statuses["debug"] == "unsupported" and debug_supported != "false":
        fail("integration.debug is unsupported but debug.supported is not false")
    if statuses["debug"] == "supported":
        parse_positive_int(
            require_scalar(core_text, ("debug", "hart_count"), f"CORE '{core}'"),
            "debug.hart_count",
        )
        parse_nonnegative_int(
            require_scalar(core_text, ("debug", "hartsel"), f"CORE '{core}'"),
            "debug.hartsel",
        )
        parse_nonnegative_int(
            require_scalar(core_text, ("debug", "halt_addr"), f"CORE '{core}'"),
            "debug.halt_addr",
        )
        parse_nonnegative_int(
            require_scalar(core_text, ("debug", "exception_addr"), f"CORE '{core}'"),
            "debug.exception_addr",
        )

    known_boards = set(descriptor_names(BOARD_DIR))
    missing_boards = [board for board in compatible_boards if board not in known_boards]
    if missing_boards:
        fail(f"compatible_boards references unknown board(s): {', '.join(missing_boards)}")

    for board in compatible_boards:
        board_text = descriptor_path(BOARD_DIR, board).read_text(encoding="utf-8")
        compatible_cores = yaml_top_list(board_text, "compatible_cores")
        if compatible_cores and core not in compatible_cores:
            fail(f"BOARD '{board}' does not list CORE '{core}' in compatible_cores")

    if verbose:
        print(f"CORE={core}")
        print(f"DISPLAY_NAME={display_name}")
        print(f"ADAPTER={adapter_module}")
        print(f"ADAPTER_FILE={adapter_file}")
        print(f"WRAPPER={wrapper_module}")
        print(f"SIM_FUSESOC_TARGET={sim_target}")
        print(f"FUSESOC_CORE_FLAG={core_flag}")
        print(f"FUSESOC_CORE_FLAGS={' '.join(fusesoc_core_flags(core_text))}")
        print(f"CORE_TYPE={core_type}")
        print(f"CORE_INTEGRATION={integration}")
        print(f"CORE_TYPE_ENUM={enum_name}")
        print(f"XLEN={xlen}")
        print(f"MARCH={march}")
        print(f"MABI={mabi}")
        print(f"BUSES={instruction_bus},{data_bus}")
        print(f"TOOLCHAIN={toolchain}")
        print(f"ZEPHYR_STATUS={zephyr}")
        print(f"COMPATIBLE_BOARDS={' '.join(compatible_boards)}")
        print(
            "INTEGRATION="
            f"sim:{statuses['sim']} fpga:{statuses['fpga']} debug:{statuses['debug']}"
        )
        print("CORE_CHECK=passed")


def board_check(board: str, verbose: bool = True) -> None:
    board_path = descriptor_path(BOARD_DIR, board)
    if not board_path.is_file():
        boards = descriptor_names(BOARD_DIR)
        fail(f"unknown BOARD '{board}'. Available boards: {', '.join(boards) or '(none)'}")

    board_text = board_path.read_text(encoding="utf-8")
    display_name = require_scalar(board_text, ("display_name",), f"BOARD '{board}'")
    part = require_scalar(board_text, ("fpga", "part"), f"BOARD '{board}'")
    top_template = require_scalar(board_text, ("fpga", "top_template"), f"BOARD '{board}'")
    fpga_target_template = require_scalar(board_text, ("fpga", "target"), f"BOARD '{board}'")
    board_flag = fusesoc_board_flag(board_text)
    work_root = require_scalar(board_text, ("fpga", "work_root"), f"BOARD '{board}'")
    input_hz = parse_positive_int(
        require_scalar(board_text, ("clock", "input_hz"), f"BOARD '{board}'"),
        "clock.input_hz",
    )
    soc_hz = parse_positive_int(
        require_scalar(board_text, ("clock", "soc_hz"), f"BOARD '{board}'"),
        "clock.soc_hz",
    )
    clk_p = require_scalar(board_text, ("clock", "constraints_ports", "p"), f"BOARD '{board}'")
    # `n` is optional: differential clock boards define it, single-ended boards
    # (e.g. a single CMOS oscillator) omit it.
    clk_n = yaml_path_scalar(board_text, ("clock", "constraints_ports", "n")) or ""
    reset_polarity = require_scalar(board_text, ("reset", "polarity"), f"BOARD '{board}'")
    reset_port = require_scalar(board_text, ("reset", "constraints_port"), f"BOARD '{board}'")
    # Optional per-board SRAM size; must satisfy the 64-bit SRAM word geometry.
    ram_bytes_raw = yaml_path_scalar(board_text, ("memory", "ram_bytes"))
    if ram_bytes_raw is not None:
        ram_bytes_val = parse_positive_int(ram_bytes_raw, "memory.ram_bytes")
        if ram_bytes_val % 8 != 0:
            fail("memory.ram_bytes must be a multiple of 8 (64-bit SRAM word)")
    uart_baud = parse_positive_int(
        require_scalar(board_text, ("uart", "baud"), f"BOARD '{board}'"),
        "uart.baud",
    )
    uart_tx = require_scalar(board_text, ("uart", "tx_port"), f"BOARD '{board}'")
    uart_rx = require_scalar(board_text, ("uart", "rx_port"), f"BOARD '{board}'")
    debug_transport = require_scalar(board_text, ("debug", "transport"), f"BOARD '{board}'")
    jtag_adapter = require_scalar(board_text, ("debug", "jtag_adapter"), f"BOARD '{board}'")
    openocd_cfg = f"rtl/platform/fpga/scripts/openocd-{jtag_adapter}.cfg"
    xdc = require_scalar(board_text, ("constraints", "xdc"), f"BOARD '{board}'")
    programming_flow = require_scalar(board_text, ("programming", "flow"), f"BOARD '{board}'")
    bitstream_target = require_scalar(
        board_text,
        ("programming", "bitstream_target"),
        f"BOARD '{board}'",
    )
    program_target = require_scalar(
        board_text,
        ("programming", "program_target"),
        f"BOARD '{board}'",
    )
    smoke_app = require_scalar(board_text, ("validation", "smoke_app"), f"BOARD '{board}'")
    expected_uart = yaml_top_list(board_text, "expected_uart")
    compatible_cores = yaml_top_list(board_text, "compatible_cores")

    template_fields = {field for _, field, _, _ in Formatter().parse(top_template) if field}
    unsupported_fields = template_fields - {"core", "board"}
    if unsupported_fields:
        fail(
            f"unsupported field(s) in fpga.top_template: "
            f"{', '.join(sorted(unsupported_fields))}"
        )

    top_module = top_template.format(
        core=compatible_cores[0] if compatible_cores else "core",
        board=board,
    )
    wrapper_path = (
        REPO_ROOT
        / "rtl"
        / "platform"
        / "fpga"
        / "boards"
        / board
        / f"{top_module}.sv"
    )
    if not wrapper_path.is_file():
        fail(f"expected FPGA wrapper file is missing: {wrapper_path.relative_to(REPO_ROOT)}")
    wrapper_text = wrapper_path.read_text(encoding="utf-8")
    if re.search(rf"(?m)^\s*module\s+{re.escape(top_module)}\b", wrapper_text) is None:
        fail(
            f"FPGA wrapper file does not define module {top_module}: "
            f"{wrapper_path.relative_to(REPO_ROOT)}"
        )

    check_repo_file(xdc, "constraints.xdc")
    check_repo_file(openocd_cfg, "debug.jtag_adapter (derived OpenOCD config)")

    target_fields = {field for _, field, _, _ in Formatter().parse(fpga_target_template) if field}
    unsupported_target_fields = target_fields - {"core", "board"}
    if unsupported_target_fields:
        fail(
            f"unsupported field(s) in fpga.target: "
            f"{', '.join(sorted(unsupported_target_fields))}"
        )
    for core in compatible_cores:
        fpga_target = fpga_target_template.format(core=core, board=board)
        if not fusesoc_target_exists(fpga_target):
            fail(f"fpga.target is not defined in corejack.core: {fpga_target}")
    if not make_target_exists(bitstream_target):
        fail(f"programming.bitstream_target is not a Make target: {bitstream_target}")
    if not make_target_exists(program_target):
        fail(f"programming.program_target is not a Make target: {program_target}")
    if reset_polarity not in {"active_low", "active_high"}:
        fail(f"reset.polarity must be active_low or active_high, got '{reset_polarity}'")
    if debug_transport != "jtag":
        fail(f"debug.transport currently must be jtag, got '{debug_transport}'")
    if programming_flow != "vivado":
        fail(f"programming.flow currently must be vivado, got '{programming_flow}'")
    if "{board}" not in work_root:
        fail("fpga.work_root should include {board} to keep board builds isolated")
    if "{core}" not in work_root:
        fail("fpga.work_root should include {core} to keep core builds isolated")
    if not compatible_cores:
        fail("compatible_cores must list at least one core")
    if not expected_uart:
        fail("validation.expected_uart must list expected smoke-test UART text")
    for line in expected_uart:
        fields = {field for _, field, _, _ in Formatter().parse(line) if field}
        unsupported_fields = fields - {"core", "board"}
        if unsupported_fields:
            fail(
                "validation.expected_uart contains unsupported placeholder(s): "
                f"{', '.join(sorted(unsupported_fields))}"
            )

    known_cores = set(descriptor_names(CORE_DIR))
    missing_cores = [core for core in compatible_cores if core not in known_cores]
    if missing_cores:
        fail(f"compatible_cores references unknown core(s): {', '.join(missing_cores)}")

    for core in compatible_cores:
        core_text = descriptor_path(CORE_DIR, core).read_text(encoding="utf-8")
        compatible_boards = yaml_top_list(core_text, "compatible_boards")
        if compatible_boards and board not in compatible_boards:
            fail(f"CORE '{core}' does not list BOARD '{board}' in compatible_boards")

    if verbose:
        print(f"BOARD={board}")
        print(f"DISPLAY_NAME={display_name}")
        print(f"FPGA_PART={part}")
        print(f"FPGA_TARGET_TEMPLATE={fpga_target_template}")
        print(f"FUSESOC_BOARD_FLAG={board_flag}")
        print(f"FPGA_TOP={top_module}")
        print(f"FPGA_WRAPPER={wrapper_path.relative_to(REPO_ROOT)}")
        print(f"XDC={xdc}")
        print(f"JTAG_ADAPTER={jtag_adapter}")
        print(f"OPENOCD_CFG={openocd_cfg}")
        print(f"CLOCK_INPUT_HZ={input_hz}")
        print(f"SOC_CLK_HZ={soc_hz}")
        print(f"CLOCK_PORTS={clk_p},{clk_n}" if clk_n else f"CLOCK_PORTS={clk_p}")
        print(f"RESET={reset_port},{reset_polarity}")
        print(f"UART={uart_tx},{uart_rx},{uart_baud}")
        print(f"SMOKE_APP={smoke_app}")
        print(f"COMPATIBLE_CORES={' '.join(compatible_cores)}")
        print("BOARD_CHECK=passed")


def target_check(board: str) -> None:
    board_path = descriptor_path(BOARD_DIR, board)
    if not board_path.is_file():
        boards = descriptor_names(BOARD_DIR)
        fail(f"unknown BOARD '{board}'. Available boards: {', '.join(boards) or '(none)'}")

    board_text = board_path.read_text(encoding="utf-8")
    compatible_cores = yaml_top_list(board_text, "compatible_cores")
    if not compatible_cores:
        fail(f"BOARD '{board}' has no compatible_cores entries")

    board_check(board, verbose=False)
    print(f"BOARD={board}")
    print(f"COMPATIBLE_CORES={' '.join(compatible_cores)}")

    checked = 0
    for core in compatible_cores:
        core_check(core, verbose=False)
        core_text, current_board_text = load_descriptors(core, board)
        config = target_config(core, board, core_text, current_board_text)
        flow_results: list[str] = []
        for flow in ("sim", "fpga", "debug"):
            status = integration_status(core_text, flow)
            if status == SUPPORTED_STATUS:
                compatible, reason = is_compatible(
                    core,
                    board,
                    core_text,
                    current_board_text,
                    flow,
                    allow_planned=False,
                )
                if not compatible:
                    fail(f"{core}/{board} failed {flow} compatibility: {reason}")
                flow_results.append(f"{flow}:supported")
            else:
                flow_results.append(f"{flow}:{status}")

        print(
            "TARGET="
            f"{core}/{board} "
            f"top={config['FPGA_TOP']} "
            f"core_type={config['CORE_TYPE']} "
            f"integration={config['CORE_INTEGRATION']} "
            f"toolchain={config['TOOLCHAIN']} "
            f"zephyr={config['ZEPHYR_STATUS']} "
            f"march={config['MARCH']} "
            f"mabi={config['MABI']} "
            f"{' '.join(flow_results)}"
        )
        checked += 1

    print(f"TARGET_CHECK=passed board={board} targets={checked}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core", help="Selected core name")
    parser.add_argument("--board", help="Selected board name")
    parser.add_argument("--quiet", action="store_true", help="Only print errors")
    parser.add_argument("--make", action="store_true", help="Emit Makefile assignments")
    parser.add_argument(
        "--flow",
        choices=("sim", "fpga", "debug"),
        default="fpga",
        help="Capability to validate. Defaults to fpga.",
    )
    parser.add_argument(
        "--allow-planned",
        action="store_true",
        help="Resolve descriptor metadata even when the selected flow is not supported",
    )
    parser.add_argument("--list", action="store_true", help="List available cores and boards")
    parser.add_argument(
        "--compatible-cores",
        action="store_true",
        help="Print the descriptor-compatible cores for --board as a space-separated list",
    )
    parser.add_argument(
        "--board-check",
        action="store_true",
        help="Validate a board descriptor and its referenced local files",
    )
    parser.add_argument(
        "--core-check",
        action="store_true",
        help="Validate a core descriptor and its referenced local files",
    )
    parser.add_argument(
        "--target-check",
        action="store_true",
        help="Validate the descriptor matrix for a board and its compatible cores",
    )
    args = parser.parse_args()

    if args.list:
        list_targets()
        return 0

    if args.compatible_cores:
        if not args.board:
            fail("--board is required with --compatible-cores")
        print_compatible_cores(args.board)
        return 0

    if args.board_check:
        if not args.board:
            fail("--board is required with --board-check")
        board_check(args.board)
        return 0

    if args.core_check:
        if not args.core:
            fail("--core is required with --core-check")
        core_check(args.core)
        return 0

    if args.target_check:
        if not args.board:
            fail("--board is required with --target-check")
        target_check(args.board)
        return 0

    if not args.core:
        fail(
            "--core is required unless --list, --compatible-cores, "
            "--board-check, --core-check, or --target-check is used"
        )
    if not args.board:
        fail("--board is required unless --list is used")

    validate(args.core, args.board, args.quiet, args.make, args.allow_planned, args.flow)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
