#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>
#if defined(CONFIG_UART_INTERRUPT_DRIVEN)
#include <zephyr/drivers/uart.h>
#endif

/* CoreJack core/board names are injected at build time (see sw/zephyr/CMakeLists.txt
 * and the Makefile zephyr-build target), so the banner is correct for any
 * core/board without per-target preprocessor chains. */
#ifndef COREJACK_CORE
#define COREJACK_CORE "unknown"
#endif
#ifndef COREJACK_BOARD
#define COREJACK_BOARD "unknown"
#endif

#if defined(CONFIG_UART_INTERRUPT_DRIVEN)
static K_SEM_DEFINE(uart_tx_irq, 0, 1);

static void uart_isr(const struct device *dev, void *user_data)
{
	ARG_UNUSED(user_data);

	if (uart_irq_update(dev) && uart_irq_tx_ready(dev)) {
		uart_irq_tx_disable(dev);
		k_sem_give(&uart_tx_irq);
	}
}

/* The console UART's transmitter-empty interrupt reaches the core only through
 * the PLIC (source 1), so taking it proves the external interrupt path - the
 * same event sw/c/plic_smoke uses. */
static bool plic_path_alive(void)
{
	const struct device *uart = DEVICE_DT_GET(DT_CHOSEN(zephyr_console));

	uart_irq_callback_set(uart, uart_isr);
	uart_irq_tx_enable(uart);
	return k_sem_take(&uart_tx_irq, K_MSEC(100)) == 0;
}
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
#if defined(CONFIG_UART_INTERRUPT_DRIVEN)
	if (plic_path_alive()) {
		printk("PLIC external interrupt path is alive.\n");
	} else {
		printk("PLIC external interrupt FAILED: no UART interrupt within 100 ms.\n");
	}
#endif
	/* SERV loops rather than returning from main; other cores return cleanly. */
#if !defined(CONFIG_BOARD_COREJACK_SERV_AXKU5)
	return 0;
#endif

	while (1) {
		__asm__ volatile("");
	}
}
