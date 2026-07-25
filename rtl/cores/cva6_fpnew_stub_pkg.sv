// SPDX-License-Identifier: Apache-2.0
//
// Minimal stub of the fpnew_pkg enums CVA6 references when the FPU is
// disabled. The package name is mandated by CVA6; the cva6_ file prefix
// avoids a collision (style exception: filename != package name).
package fpnew_pkg;
  typedef enum logic [2:0] {
    RNE = 3'b000,
    RTZ = 3'b001,
    RDN = 3'b010,
    RUP = 3'b011,
    RMM = 3'b100,
    DYN = 3'b111
  } roundmode_e;
endpackage
