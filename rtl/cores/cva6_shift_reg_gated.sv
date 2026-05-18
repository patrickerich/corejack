module shift_reg_gated #(
  parameter type dtype = logic,
  parameter int unsigned Depth = 1
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic valid_i,
  input  dtype data_i,
  output logic valid_o,
  output dtype data_o
);
  dtype [Depth:0] data_q;
  logic [Depth:0] valid_q;

  assign data_q[0]  = data_i;
  assign valid_q[0] = valid_i;
  assign data_o     = data_q[Depth];
  assign valid_o    = valid_q[Depth];

  for (genvar i = 0; i < Depth; i++) begin : gen_shift
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        data_q[i+1]  <= '0;
        valid_q[i+1] <= 1'b0;
      end else begin
        data_q[i+1]  <= data_q[i];
        valid_q[i+1] <= valid_q[i];
      end
    end
  end
endmodule
