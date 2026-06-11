# Based on the lowRISC bare-metal startup style, adapted for the current FPGA map.

.section .text

default_exc_handler:
  jal x0, simple_exc_handler

reset_handler:
  mv  x1, x0
  mv  x2, x1
  mv  x3, x1
  mv  x4, x1
  mv  x5, x1
  mv  x6, x1
  mv  x7, x1
  mv  x8, x1
  mv  x9, x1
  mv x10, x1
  mv x11, x1
  mv x12, x1
  mv x13, x1
  mv x14, x1
  mv x15, x1
  mv x16, x1
  mv x17, x1
  mv x18, x1
  mv x19, x1
  mv x20, x1
  mv x21, x1
  mv x22, x1
  mv x23, x1
  mv x24, x1
  mv x25, x1
  mv x26, x1
  mv x27, x1
  mv x28, x1
  mv x29, x1
  mv x30, x1
  mv x31, x1

  la  x2, _stack_start

_start:
  .global _start

  la x26, _bss_start
  la x27, _bss_end
  bge x26, x27, zero_loop_end

zero_loop:
  sw x0, 0(x26)
  addi x26, x26, 4
  blt x26, x27, zero_loop

zero_loop_end:
  addi x10, x0, 0
  addi x11, x0, 0
  jal x1, main

sleep_loop:
  wfi
  j sleep_loop

simple_exc_handler:
  j simple_exc_handler

# Default targets for the interrupt slots of the vector table below. Apps
# override them by defining a strong symbol of the same name (a C function
# with __attribute__((interrupt("machine"))), see timer_uart_smoke and
# plic_smoke) and pointing mtvec at _vectors in vectored mode. Vectored mode
# is the portable choice: Ibex and the CV32E40* cores implement mtvec as
# vectored-only WARL, so an mtvec that points directly at a handler would
# enter that handler at offset 4*cause instead of at its first instruction.
.weak corejack_timer_vector
corejack_timer_vector:
.weak corejack_external_vector
corejack_external_vector:
  j default_exc_handler

.section .vectors, "ax"
  .option norvc
  .global _vectors
_vectors:
  .org 0x00
#if COREJACK_RESET_AT_VECTOR_BASE
  jal x0, reset_handler
#else
  jal x0, default_exc_handler
#endif
  .rept 6
  jal x0, default_exc_handler
  .endr
  jal x0, corejack_timer_vector     # cause 7: machine timer interrupt
  .rept 3
  jal x0, default_exc_handler
  .endr
  jal x0, corejack_external_vector  # cause 11: machine external interrupt
  .rept 20
  jal x0, default_exc_handler
  .endr

  .org 0x80
  jal x0, reset_handler
