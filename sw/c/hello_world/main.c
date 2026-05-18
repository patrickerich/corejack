#include "printf.h"
#include "platform.h"
#include "sim_ctrl.h"
#include "uart.h"

static int str_eq(const char *lhs, const char *rhs) {
  while (*lhs != '\0' && *rhs != '\0') {
    if (*lhs != *rhs) {
      return 0;
    }
    lhs++;
    rhs++;
  }

  return *lhs == *rhs;
}

int main(void) {
  uart_init(UART0_BASE, COREJACK_CORE_CLK_HZ, COREJACK_UART_BAUD);
  printf("=== CoreJack SoC Demo ===\n");
  printf("Target: %s\n", COREJACK_TARGET);
  printf("Core: %s\n", COREJACK_CORE);
  if (str_eq(COREJACK_TARGET, "fpga")) {
    printf("Board: %s\n", COREJACK_BOARD);
  }
  printf("UART base: 0x%08x\n", UART0_BASE);
  printf("Clock: %u Hz, baud: %u\n", COREJACK_CORE_CLK_HZ, COREJACK_UART_BAUD);
  if (str_eq(COREJACK_TARGET, "sim")) {
    printf("UART and sim_ctrl path are alive.\n");
  } else if (COREJACK_HAS_JTAG_DEBUG) {
    printf("UART and JTAG debug path are alive.\n");
  } else {
    printf("UART path is alive.\n");
  }
  sim_ctrl_pass();

  while (1) {
#if COREJACK_HAS_JTAG_DEBUG
    __asm__ volatile("wfi");
#else
    __asm__ volatile("");
#endif
  }

  return 0;
}
