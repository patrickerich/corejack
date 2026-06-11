`include "axi/typedef.svh"
`include "apb/typedef.svh"
`include "obi/typedef.svh"
`include "register_interface/typedef.svh"

package soc_bus_pkg;
  localparam int unsigned AxiAddrWidth = 48;
  localparam int unsigned AxiDataWidth = 64;
  localparam int unsigned AxiIdWidth   = 4;
  // Number of AXI initiators entering the system crossbar (core instruction,
  // core data, debug SBA, iDMA). The fabric `axi_xbar` prepends the slave-port
  // index to the AXI ID, so its master ports carry a wider ID; this is the
  // single source for that width. Keep in sync with `soc_top` CoreAxiPorts.
  localparam int unsigned AxiNumInitiators = 4;
  localparam int unsigned AxiMstIdWidth    = AxiIdWidth + $clog2(AxiNumInitiators);
  localparam int unsigned ApbAddrWidth = 32;
  localparam int unsigned ApbDataWidth = 32;
  localparam int unsigned ApbStrbWidth = ApbDataWidth / 8;
  // Wide enough for the largest register window behind a soc_axi_to_reg
  // adapter: the PLIC's standard layout places claim/complete at +0x200004
  // inside a 4 MiB window, so offsets need 24 bits (CLINT and the iDMA
  // window decode only their low bits and are unaffected).
  localparam int unsigned RegAddrWidth = 24;
  localparam int unsigned RegDataWidth = 32;
  localparam int unsigned RegStrbWidth = RegDataWidth / 8;

  typedef logic [AxiAddrWidth-1:0] axi_addr_t;
  typedef logic [AxiDataWidth-1:0] axi_data_t;
  typedef logic [AxiIdWidth-1:0]   axi_id_t;
  typedef logic [AxiMstIdWidth-1:0] axi_mst_id_t;
  typedef logic [AxiDataWidth/8-1:0] axi_strb_t;
  typedef logic [0:0] axi_user_t;

  // Initiator/slave-side fabric types (core instruction, core data, debug SBA).
  `AXI_TYPEDEF_ALL(soc_axi, axi_addr_t, axi_id_t, axi_data_t, axi_strb_t, axi_user_t)

  // Crossbar master-side fabric types: identical except for the wider ID the
  // `axi_xbar` produces (`AxiIdWidth + $clog2(AxiNumInitiators)`). Used on the
  // xbar master ports and the target adapters behind them.
  `AXI_TYPEDEF_ALL(soc_axi_mst, axi_addr_t, axi_mst_id_t, axi_data_t, axi_strb_t, axi_user_t)

  `OBI_TYPEDEF_MINIMAL_A_OPTIONAL(soc_obi_a_optional_t)
  `OBI_TYPEDEF_A_CHAN_T(soc_obi_a_chan_t, AxiAddrWidth, AxiDataWidth, AxiIdWidth, soc_obi_a_optional_t)
  `OBI_TYPEDEF_REQ_T(soc_obi_req_t, soc_obi_a_chan_t)
  `OBI_TYPEDEF_MINIMAL_R_OPTIONAL(soc_obi_r_optional_t)
  `OBI_TYPEDEF_R_CHAN_T(soc_obi_r_chan_t, AxiDataWidth, AxiIdWidth, soc_obi_r_optional_t)
  `OBI_TYPEDEF_RSP_T(soc_obi_rsp_t, soc_obi_r_chan_t)

  typedef logic [ApbAddrWidth-1:0] apb_addr_t;
  typedef logic [ApbDataWidth-1:0] apb_data_t;
  typedef logic [ApbStrbWidth-1:0] apb_strb_t;
  `APB_TYPEDEF_ALL(soc_apb, apb_addr_t, apb_data_t, apb_strb_t)

  typedef logic [RegAddrWidth-1:0] reg_addr_t;
  typedef logic [RegDataWidth-1:0] reg_data_t;
  typedef logic [RegStrbWidth-1:0] reg_strb_t;
  `REG_BUS_TYPEDEF_ALL(soc_reg, reg_addr_t, reg_data_t, reg_strb_t)
endpackage
