// SPDX-License-Identifier: Apache-2.0
//
package platform_pkg;

  typedef enum int unsigned {
    CoreIbex = 0,
    CoreCv32e40p = 1,
    CoreCv32e40x = 2,
    CoreCv32e40s = 3,
    CoreCva6 = 4,
    CoreServ = 5,
    CorePicorv32 = 6,
    CoreCvw = 7
  } core_type_e;

  typedef enum logic [1:0] {
    MapLinear,
    MapInterleaved,
    MapBlockInterleaved,
    MapCustom
  } mem_map_mode_e;

  typedef enum logic [1:0] {
    MemTechBehavioral,
    MemTechXilinxBram,
    MemTechFoundry
  } mem_tech_e;

  typedef enum logic [1:0] {
    IcAxiFlat,
    IcAxiHierarchical,
    IcObiSimple
  } interconnect_e;

endpackage
