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

  // In-flight bound for a soc_axi_to_mem bridge driving soc_mem_ss ports
  // directly (soc_top's iDMA and CVA6 legs, and tb/tb_axi_to_mem.sv). A
  // transaction counts from AXI accept to AXI response, which is the read
  // latency plus six cycles of bridge and soc_mem_ss pipeline at soc_mem_ss's
  // default depths. Admission sees the registered count, so the bound must be
  // one more than that round trip; one short, each engine stalls one cycle per
  // round trip (8 transfers in 9 cycles at a bound of 8 on the Xilinx slice).
  // One further entry leaves room for one-cycle latency jitter (at the exact
  // bound the iDMA hit it about once per 256-beat burst); it saved 22 cycles of
  // mem-bw-bench's 24 KiB copy on CVA6 (model slice) and 1 on Ibex (Xilinx
  // slice).
  function automatic int unsigned mem_bridge_outstanding(mem_impl_e impl);
    return mem_read_latency(impl) + 32'd8;
  endfunction

  // Request and response FIFO depth for those bridges. Only their 4-bit id
  // FIFOs grow with the in-flight bound; these queues stay shallow and
  // backpressure into soc_mem_ss, which keeps the wide payload storage small.
  // At least 2: a depth-1 fifo_v3 blocks its push while full.
  localparam int unsigned MemBridgeQueueDepth = 2;

  // Single source of truth for the SRAM bank count. soc_top's MemNumBanks
  // parameter defaults to this, and the software build reads the same literal
  // back through bin/validate_target.py (--mem-num-banks) to split the preload
  // image into bank_<n>.hex, so the RTL and the hex images cannot drift apart.
  // Must be a power of two >= 2 - soc_mem_ss decodes the bank index by bit
  // slicing and fails elaboration otherwise.
  localparam int unsigned MemNumBanksDefault = 8;
endpackage
