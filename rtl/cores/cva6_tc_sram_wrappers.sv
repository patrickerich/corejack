module tc_sram_wrapper #(
  parameter int unsigned NumWords     = 32'd1024,
  parameter int unsigned DataWidth    = 32'd128,
  parameter int unsigned ByteWidth    = 32'd8,
  parameter int unsigned NumPorts     = 32'd2,
  parameter int unsigned Latency      = 32'd1,
  parameter              SimInit      = "none",
  parameter bit          PrintSimCfg  = 1'b0,
  parameter int unsigned AddrWidth    = (NumWords > 32'd1) ? $clog2(NumWords) : 32'd1,
  parameter int unsigned BeWidth      = (DataWidth + ByteWidth - 32'd1) / ByteWidth,
  parameter type         addr_t       = logic [AddrWidth-1:0],
  parameter type         data_t       = logic [DataWidth-1:0],
  parameter type         be_t         = logic [BeWidth-1:0]
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,
  input  logic  [NumPorts-1:0] req_i,
  input  logic  [NumPorts-1:0] we_i,
  input  addr_t [NumPorts-1:0] addr_i,
  input  data_t [NumPorts-1:0] wdata_i,
  input  be_t   [NumPorts-1:0] be_i,
  output data_t [NumPorts-1:0] rdata_o
);
  localparam int unsigned ReadLatency = (Latency > 0) ? Latency : 1;

  (* ram_style = "block" *) data_t mem_q [0:NumWords-1];
  data_t [NumPorts-1:0][ReadLatency-1:0] rdata_q;
  logic unused_rst_ni;
  logic unused_print_sim_cfg;
  logic unused_sim_init;

  assign unused_rst_ni = rst_ni;
  assign unused_print_sim_cfg = PrintSimCfg;
  assign unused_sim_init = (SimInit == "none");

  if (Latency == 0) begin : gen_comb_read
    for (genvar port = 0; port < NumPorts; port++) begin : gen_port
      assign rdata_o[port] = (req_i[port] && !we_i[port]) ? mem_q[addr_i[port]] : '0;
    end
  end else begin : gen_sync_read
    for (genvar port = 0; port < NumPorts; port++) begin : gen_port
      assign rdata_o[port] = rdata_q[port][0];
    end

    always_ff @(posedge clk_i) begin
      for (int unsigned port = 0; port < NumPorts; port++) begin
        for (int unsigned stage = 0; stage < ReadLatency - 1; stage++) begin
          rdata_q[port][stage] <= rdata_q[port][stage + 1];
        end

        if (req_i[port] && !we_i[port]) begin
          rdata_q[port][ReadLatency - 1] <= mem_q[addr_i[port]];
        end
      end

      for (int unsigned port = 0; port < NumPorts; port++) begin
        if (req_i[port] && we_i[port]) begin
          for (int unsigned byte_idx = 0; byte_idx < BeWidth; byte_idx++) begin
            if (be_i[port][byte_idx]) begin
              mem_q[addr_i[port]][byte_idx*ByteWidth +: ByteWidth] <=
                  wdata_i[port][byte_idx*ByteWidth +: ByteWidth];
            end
          end
        end
      end
    end
  end
endmodule

module tc_sram_wrapper_cache_techno #(
  parameter int unsigned NumWords     = 32'd1024,
  parameter int unsigned DataWidth    = 32'd128,
  parameter int unsigned ByteWidth    = 32'd8,
  parameter int unsigned NumPorts     = 32'd2,
  parameter int unsigned Latency      = 32'd1,
  parameter              SimInit      = "none",
  parameter              BYTE_ACCESS  = 1,
  parameter bit          PrintSimCfg  = 1'b0,
  parameter int unsigned AddrWidth    = (NumWords > 32'd1) ? $clog2(NumWords) : 32'd1,
  parameter int unsigned BeWidth      = (DataWidth + ByteWidth - 32'd1) / ByteWidth,
  parameter type         addr_t       = logic [AddrWidth-1:0],
  parameter type         data_t       = logic [DataWidth-1:0],
  parameter type         be_t         = logic [BeWidth-1:0]
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,
  input  logic  [NumPorts-1:0] req_i,
  input  logic  [NumPorts-1:0] we_i,
  input  addr_t [NumPorts-1:0] addr_i,
  input  data_t [NumPorts-1:0] wdata_i,
  input  be_t   [NumPorts-1:0] be_i,
  output data_t [NumPorts-1:0] rdata_o
);
  logic unused_byte_access;

  assign unused_byte_access = BYTE_ACCESS;

  tc_sram_wrapper #(
    .NumWords    (NumWords),
    .DataWidth   (DataWidth),
    .ByteWidth   (ByteWidth),
    .NumPorts    (NumPorts),
    .Latency     (Latency),
    .SimInit     (SimInit),
    .PrintSimCfg (PrintSimCfg)
  ) i_tc_sram_wrapper (
    .clk_i,
    .rst_ni,
    .req_i,
    .we_i,
    .addr_i,
    .wdata_i,
    .be_i,
    .rdata_o
  );
endmodule
