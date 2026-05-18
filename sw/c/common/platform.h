#ifndef COREJACK_PLATFORM_H_
#define COREJACK_PLATFORM_H_

#ifndef COREJACK_CORE_CLK_HZ
#define COREJACK_CORE_CLK_HZ 25000000u
#endif

#ifndef COREJACK_UART_BAUD
#define COREJACK_UART_BAUD 115200u
#endif

#ifndef COREJACK_TARGET
#define COREJACK_TARGET "fpga"
#endif

#ifndef COREJACK_CORE
#define COREJACK_CORE "ibex"
#endif

#ifndef COREJACK_BOARD
#define COREJACK_BOARD "axku5"
#endif

#ifndef COREJACK_HAS_JTAG_DEBUG
#define COREJACK_HAS_JTAG_DEBUG 1
#endif

#endif
