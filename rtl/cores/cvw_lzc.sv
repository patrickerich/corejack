// CoreJack override: verbatim copy of the upstream CORE-V-Wally source with
// the leading-zero-counter module renamed `lzc` -> `cvw_lzc` to avoid a name
// collision with the PULP common_cells `lzc` pulled in by the system AXI
// crossbar (axi_xbar -> rr_arb_tree). Only the lzc module name and its
// instantiations differ from upstream. Listed in corejack_core_cvw.core in
// place of the upstream files.
///////////////////////////////////////////
//
// Written: me@KatherineParry.com
// Modified: 7/5/2022
// Modified: 2/11/2026 james.stine@okstate.edu/marcus@infinitymdm.dev
//
// Purpose: Leading Zero Counter
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// https://github.com/openhwgroup/cvw
//
// Copyright (C) 2021-23 Harvey Mudd College & Oklahoma State University
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the “License”); you may not use this file
// except in compliance with the License, or, at your option, the Apache License version 2.0. You
// may obtain a copy of the License at
//
// https://solderpad.org/licenses/SHL-2.1/
//
// Unless required by applicable law or agreed to in writing, any work distributed under the
// License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions
// and limitations under the License.
////////////////////////////////////////////////////////////////////////////////////////////////

module cvw_lzc #(parameter WIDTH = 1) (
  input  logic [WIDTH-1:0]            num,    // number to count the leading zeroes of
  output logic [$clog2(WIDTH+1)-1:0]  ZeroCnt // the number of leading zeroes
);

  integer i;

  always_comb begin
    i = 0;
    // search for leading one
    while ((i < WIDTH) && (!num[WIDTH-1-i])) begin
      i = i + 1;
    end
    ZeroCnt = i[$clog2(WIDTH+1)-1:0];
  end
endmodule
