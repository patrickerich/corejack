cmake_minimum_required(VERSION 3.20.0)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(corejack_zephyr_hello)

# CoreJack core/board names for the console banner, passed by the Makefile
# zephyr-build target (mirrors the bare-metal sw/c flow). Defaults keep a direct
# `west build` working without them.
set(COREJACK_CORE "unknown" CACHE STRING "CoreJack core name for the banner")
set(COREJACK_BOARD "unknown" CACHE STRING "CoreJack board name for the banner")

target_sources(app PRIVATE src/main.c)
target_compile_definitions(app PRIVATE
	COREJACK_CORE="${COREJACK_CORE}"
	COREJACK_BOARD="${COREJACK_BOARD}"
)
