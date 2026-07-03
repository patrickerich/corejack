// SPDX-License-Identifier: Apache-2.0
//
package platform_pkg;

  typedef enum int unsigned {
    CORE_IBEX = 0,
    CORE_CV32E40P = 1,
    CORE_CV32E40X = 2,
    CORE_CV32E40S = 3,
    CORE_CVA6 = 4,
    CORE_SERV = 5,
    CORE_PICORV32 = 6,
    CORE_CVW = 7
  } core_type_e;

  typedef enum logic [1:0] {
    MAP_LINEAR,
    MAP_INTERLEAVED,
    MAP_BLOCK_INTERLEAVED,
    MAP_CUSTOM
  } mem_map_mode_e;

  typedef enum logic [1:0] {
    MEM_TECH_BEHAVIORAL,
    MEM_TECH_XILINX_BRAM,
    MEM_TECH_FOUNDRY
  } mem_tech_e;

  typedef enum logic [1:0] {
    IC_AXI_FLAT,
    IC_AXI_HIERARCHICAL,
    IC_OBI_SIMPLE
  } interconnect_e;

endpackage
