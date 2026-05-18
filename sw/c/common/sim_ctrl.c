#include "sim_ctrl.h"

#ifndef SIM_CTRL_ENABLE
#define SIM_CTRL_ENABLE 0
#endif

void sim_ctrl_write(uint32_t code) {
#if SIM_CTRL_ENABLE
  extern volatile uint32_t sim_ctrl;
  sim_ctrl = code;
#else
  (void)code;
#endif
}

void sim_ctrl_pass(void) { sim_ctrl_write(COREJACK_SIM_PASS); }

void sim_ctrl_fail(uint32_t code) { sim_ctrl_write(code & ~COREJACK_SIM_PASS); }
