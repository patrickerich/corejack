#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>

int main(void)
{
	printk("=== CoreJack Zephyr Demo ===\n");
	printk("Target: zephyr\n");
#if defined(CONFIG_BOARD_COREJACK_CV32E40P_AXKU5)
	printk("Core: cv32e40p\n");
#elif defined(CONFIG_BOARD_COREJACK_CV32E40S_AXKU5)
	printk("Core: cv32e40s\n");
#elif defined(CONFIG_BOARD_COREJACK_CV32E40X_AXKU5)
	printk("Core: cv32e40x\n");
#elif defined(CONFIG_BOARD_COREJACK_CVA6_AXKU5)
	printk("Core: cva6\n");
#elif defined(CONFIG_BOARD_COREJACK_SERV_AXKU5)
	printk("Core: serv\n");
#else
	printk("Core: ibex\n");
#endif
	printk("Board: axku5\n");
	printk("UART and Zephyr console path are alive.\n");
	k_sleep(K_MSEC(10));
	printk("Machine timer interrupt path is alive.\n");
#if !defined(CONFIG_BOARD_COREJACK_SERV_AXKU5)
	return 0;
#endif

	while (1) {
		__asm__ volatile("");
	}
}
