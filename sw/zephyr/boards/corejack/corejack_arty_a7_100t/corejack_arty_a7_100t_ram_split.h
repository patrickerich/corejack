/*
 * The Artix-7 100T block-RAM budget caps the shared SRAM at 256 KiB; the total
 * comes from the single source of truth (cfg/boards/arty_a7_100t.yaml:
 * memory.ram_bytes), passed in by the build as COREJACK_RAM_BYTES. Only the
 * executable/writable split is board-local: give 192 KiB to the executable
 * (flash) region; sram0 takes the remaining 64 KiB. A core's devicetree file
 * includes this before its CPU description, so the common dtsi computes both
 * regions from it.
 */
#define COREJACK_FLASH_BYTES 0x00030000
