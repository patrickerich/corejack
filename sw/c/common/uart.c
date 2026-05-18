#include "uart.h"

#define UART_RBR 0x00u
#define UART_THR 0x00u
#define UART_DLL 0x00u
#define UART_DLM 0x04u
#define UART_FCR 0x08u
#define UART_LCR 0x0cu
#define UART_LSR 0x14u

#define UART_LCR_DLAB      0x80u
#define UART_LCR_8N1       0x03u
#define UART_FCR_ENABLE    0x07u
#define UART_LSR_THR_EMPTY 0x20u

static inline void mmio_write8(uintptr_t addr, uint8_t value) {
  *(volatile uint8_t *)addr = value;
}

static inline uint8_t mmio_read8(uintptr_t addr) {
  return *(volatile uint8_t *)addr;
}

void uart_init(uintptr_t uart_base, uint32_t core_clk_hz, uint32_t baud) {
  uint32_t divisor;

  divisor = (core_clk_hz + (8u * baud)) / (16u * baud);

  mmio_write8(uart_base + UART_LCR, UART_LCR_DLAB);
  mmio_write8(uart_base + UART_DLL, (uint8_t)(divisor & 0xffu));
  mmio_write8(uart_base + UART_DLM, (uint8_t)((divisor >> 8) & 0xffu));
  mmio_write8(uart_base + UART_LCR, UART_LCR_8N1);
  mmio_write8(uart_base + UART_FCR, UART_FCR_ENABLE);
}

void uart_putc(uintptr_t uart_base, char c) {
  while ((mmio_read8(uart_base + UART_LSR) & UART_LSR_THR_EMPTY) == 0u) {
  }

  mmio_write8(uart_base + UART_THR, (uint8_t)c);
}

void uart_puts(uintptr_t uart_base, const char *str) {
  while (*str != '\0') {
    if (*str == '\n') {
      uart_putc(uart_base, '\r');
    }
    uart_putc(uart_base, *str++);
  }
}
