#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>

/* CoreJack core/board names are injected at build time (see sw/zephyr/CMakeLists.txt
 * and the Makefile zephyr-build target), so the banner is correct for any
 * core/board without per-target preprocessor chains. */
#ifndef COREJACK_CORE
#define COREJACK_CORE "unknown"
#endif
#ifndef COREJACK_BOARD
#define COREJACK_BOARD "unknown"
#endif

int main(void)
{
	printk("=== CoreJack Zephyr Demo ===\n");
	printk("Target: zephyr\n");
	printk("Core: " COREJACK_CORE "\n");
	printk("Board: " COREJACK_BOARD "\n");
	printk("UART and Zephyr console path are alive.\n");
	k_sleep(K_MSEC(10));
	printk("Machine timer interrupt path is alive.\n");
	/* SERV loops rather than returning from main; other cores return cleanly. */
#if !defined(CONFIG_BOARD_COREJACK_SERV_AXKU5)
	return 0;
#endif

	while (1) {
		__asm__ volatile("");
	}
}
