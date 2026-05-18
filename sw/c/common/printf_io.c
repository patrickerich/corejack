#include <stdint.h>

#include "printf.h"
#include "uart.h"

void _putchar(char character) {
  if (character == '\n') {
    uart_putc(UART0_BASE, '\r');
  }
  uart_putc(UART0_BASE, character);
}
