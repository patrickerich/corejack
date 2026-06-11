add_library(common OBJECT uart.c dma.c printf.c printf_io.c sim_ctrl.c crt0.S)
target_include_directories(common INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_options(common PRIVATE ${COREJACK_RISCV_FLAGS})
target_compile_definitions(common PRIVATE
  PRINTF_DISABLE_SUPPORT_LONG_LONG
  SIM_CTRL_ENABLE=${SIM_CTRL_ENABLE}
  COREJACK_RESET_AT_VECTOR_BASE=${COREJACK_RESET_AT_VECTOR_BASE}
  COREJACK_CORE_CLK_HZ=${COREJACK_CORE_CLK_HZ}u
  COREJACK_UART_BAUD=${COREJACK_UART_BAUD}u
)
