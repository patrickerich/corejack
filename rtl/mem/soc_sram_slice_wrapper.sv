module soc_sram_slice_wrapper
  import mem_ss_pkg::*;
#(
  parameter int unsigned NumWords = 32768,
  parameter int unsigned DataWidth = 32,
  parameter int unsigned AddressShift = 3,
  parameter mem_impl_e MemImpl = MemImplModel
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        req_i,
  input  logic        we_i,
  input  logic [31:0] addr_i,
  input  logic [DataWidth-1:0] wdata_i,
  input  logic [DataWidth/8-1:0]  be_i,
  output logic [DataWidth-1:0] rdata_o
);
  logic [DataWidth-1:0] raw_rdata;
  logic        we_q;

  if (MemImpl == MemImplXilinx) begin : gen_impl
    soc_sram_slice_xilinx #(
      .NumWords(NumWords),
      .DataWidth(DataWidth),
      .AddressShift(AddressShift)
    ) u_sram (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .req_i(req_i),
      .we_i(we_i),
      .addr_i(addr_i),
      .wdata_i(wdata_i),
      .be_i(be_i),
      .rdata_o(raw_rdata)
    );
  end else begin : gen_impl
    soc_sram_slice_model #(
      .NumWords(NumWords),
      .DataWidth(DataWidth),
      .AddressShift(AddressShift)
    ) u_sram (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .req_i(req_i),
      .we_i(we_i),
      .addr_i(addr_i),
      .wdata_i(wdata_i),
      .be_i(be_i),
      .rdata_o(raw_rdata)
    );
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      we_q <= 1'b0;
    end else begin
      we_q <= req_i & we_i;
    end
  end

  assign rdata_o = we_q ? '0 : raw_rdata;

`ifndef SYNTHESIS
  task automatic load_mem(string file_path);
    gen_impl.u_sram.load_mem(file_path);
  endtask : load_mem
`endif
endmodule
