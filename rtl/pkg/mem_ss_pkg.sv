// SPDX-License-Identifier: Apache-2.0
//
package mem_ss_pkg;
  typedef enum logic [0:0] {
    MemImplModel,
    MemImplXilinx
  } mem_impl_e;

  // Registered-read latency of each SRAM slice implementation, in cycles: the
  // model reads in one, the Xilinx byte cell pipelines through two registers.
  // soc_mem_bank aligns response metadata to it, soc_sram_slice_wrapper masks
  // write responses with it, and soc_top sizes the RAM bridges' in-flight
  // bound from it, so a new implementation only has to be added here.
  function automatic int unsigned mem_read_latency(mem_impl_e impl);
    return (impl == MemImplXilinx) ? 32'd2 : 32'd1;
  endfunction

  // Single source of truth for the SRAM bank count. soc_top's MemNumBanks
  // parameter defaults to this, and the software build reads the same literal
  // back through bin/validate_target.py (--mem-num-banks) to split the preload
  // image into bank_<n>.hex, so the RTL and the hex images cannot drift apart.
  // Must be a power of two >= 2 - soc_mem_ss decodes the bank index by bit
  // slicing and fails elaboration otherwise.
  localparam int unsigned MemNumBanksDefault = 8;
endpackage
