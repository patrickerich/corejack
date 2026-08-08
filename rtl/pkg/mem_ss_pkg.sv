// SPDX-License-Identifier: Apache-2.0
//
package mem_ss_pkg;
  typedef enum logic [0:0] {
    MemImplModel,
    MemImplXilinx
  } mem_impl_e;

  // Single source of truth for the SRAM bank count. soc_top's MemNumBanks
  // parameter defaults to this, and the software build reads the same literal
  // back through bin/validate_target.py (--mem-num-banks) to split the preload
  // image into bank_<n>.hex, so the RTL and the hex images cannot drift apart.
  // Must be a power of two >= 2 - soc_mem_ss decodes the bank index by bit
  // slicing and fails elaboration otherwise.
  localparam int unsigned MemNumBanksDefault = 8;
endpackage
