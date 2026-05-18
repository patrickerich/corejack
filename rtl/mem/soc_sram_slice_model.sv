module soc_sram_slice_model #(
  parameter int unsigned NumWords = 32768,
  parameter int unsigned DataWidth = 32,
  parameter int unsigned AddressShift = 3
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
  localparam int unsigned IdxWidth = (NumWords > 1) ? $clog2(NumWords) : 1;

  logic [DataWidth-1:0] mem_q [0:NumWords-1];
  logic [DataWidth-1:0] rdata_q;
  logic [DataWidth-1:0] mem_wdata_d;
  logic        mem_we_d;
  logic [IdxWidth-1:0] word_idx;

  function automatic logic [DataWidth-1:0] apply_be(
    input logic [DataWidth-1:0] old_word,
    input logic [DataWidth-1:0] new_word,
    input logic [DataWidth/8-1:0]  be
  );
    logic [DataWidth-1:0] res;
    begin
      res = old_word;
      for (int i = 0; i < DataWidth/8; i++) begin
        if (be[i]) begin
          res[i*8 +: 8] = new_word[i*8 +: 8];
        end
      end
      return res;
    end
  endfunction

  assign word_idx = addr_i[AddressShift + IdxWidth - 1 : AddressShift];

  always_comb begin
    mem_wdata_d = mem_q[word_idx];
    mem_we_d = 1'b0;
    if (req_i && we_i) begin
      mem_wdata_d = apply_be(mem_q[word_idx], wdata_i, be_i);
      mem_we_d = 1'b1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rdata_q <= '0;
    end else begin
      if (req_i) begin
        rdata_q <= mem_q[word_idx];
      end
      if (mem_we_d) begin
        mem_q[word_idx] <= mem_wdata_d;
      end
    end
  end

  assign rdata_o = rdata_q;

  task automatic load_mem(string file_path);
    $readmemh(file_path, mem_q);
  endtask : load_mem
endmodule
