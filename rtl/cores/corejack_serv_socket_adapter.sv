// SPDX-License-Identifier: Apache-2.0
//
module corejack_serv_socket_adapter #(
  parameter logic [31:0] BootAddr = 32'h8000_0080
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        irq_timer_i,

  output logic        instr_req_o,
  input  logic        instr_gnt_i,
  input  logic        instr_rvalid_i,
  output logic [31:0] instr_addr_o,
  input  logic [31:0] instr_rdata_i,
  input  logic        instr_err_i,

  output logic        data_req_o,
  input  logic        data_gnt_i,
  input  logic        data_rvalid_i,
  output logic        data_we_o,
  output logic [3:0]  data_be_o,
  output logic [31:0] data_addr_o,
  output logic [31:0] data_wdata_o,
  input  logic [31:0] data_rdata_i,
  input  logic        data_err_i,

  output logic        core_sleep_o
);
  logic        ibus_cyc;
  logic [31:0] ibus_addr;
  logic [31:0] ibus_rdata;
  logic        ibus_ack;
  logic        ibus_outstanding_q;

  logic        dbus_cyc;
  logic [31:0] dbus_addr;
  logic [31:0] dbus_wdata;
  logic [3:0]  dbus_sel;
  logic        dbus_we;
  logic [31:0] dbus_rdata;
  logic        dbus_ack;
  logic        dbus_outstanding_q;

  logic [31:0] ext_rs1_unused;
  logic [31:0] ext_rs2_unused;
  logic [2:0]  ext_funct3_unused;
  logic        mdu_valid_unused;

  logic        ibus_accept;
  logic        dbus_accept;

  assign ibus_accept = instr_req_o && instr_gnt_i;
  assign dbus_accept = data_req_o && data_gnt_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ibus_outstanding_q <= 1'b0;
      dbus_outstanding_q <= 1'b0;
    end else begin
      unique case ({ibus_accept, instr_rvalid_i})
        2'b10: ibus_outstanding_q <= 1'b1;
        2'b01,
        2'b11: ibus_outstanding_q <= 1'b0;
        default: ;
      endcase

      unique case ({dbus_accept, data_rvalid_i})
        2'b10: dbus_outstanding_q <= 1'b1;
        2'b01,
        2'b11: dbus_outstanding_q <= 1'b0;
        default: ;
      endcase
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      if (instr_err_i && instr_rvalid_i) begin
        $fatal(1, "SERV instruction bus error is not supported");
      end

      if (data_err_i && data_rvalid_i) begin
        $fatal(1, "SERV data bus error is not supported");
      end
    end
  end
`endif

  assign instr_req_o  = ibus_cyc && !ibus_outstanding_q;
  assign instr_addr_o = ibus_addr;
  assign ibus_ack     = instr_rvalid_i && ibus_cyc;
  assign ibus_rdata   = instr_rdata_i;

  assign data_req_o   = dbus_cyc && !dbus_outstanding_q;
  assign data_we_o    = dbus_we;
  assign data_be_o    = dbus_sel;
  assign data_addr_o  = dbus_addr;
  assign data_wdata_o = dbus_wdata;
  assign dbus_ack     = data_rvalid_i && dbus_cyc;
  assign dbus_rdata   = data_rdata_i;

  assign core_sleep_o = 1'b0;

  serv_rf_top #(
    .RESET_PC       (BootAddr),
    .COMPRESSED     (1'b0),
    .ALIGN          (1'b0),
    .MDU            (1'b0),
    .PRE_REGISTER   (1),
    .RESET_STRATEGY ("MINI"),
    .DEBUG          (1'b0),
    .WITH_CSR       (1),
    .W              (1)
  ) i_serv (
    .clk          (clk_i),
    .i_rst        (!rst_ni),
    .i_timer_irq  (irq_timer_i),
    .o_ibus_adr   (ibus_addr),
    .o_ibus_cyc   (ibus_cyc),
    .i_ibus_rdt   (ibus_rdata),
    .i_ibus_ack   (ibus_ack),
    .o_dbus_adr   (dbus_addr),
    .o_dbus_dat   (dbus_wdata),
    .o_dbus_sel   (dbus_sel),
    .o_dbus_we    (dbus_we),
    .o_dbus_cyc   (dbus_cyc),
    .i_dbus_rdt   (dbus_rdata),
    .i_dbus_ack   (dbus_ack),
    .o_ext_rs1    (ext_rs1_unused),
    .o_ext_rs2    (ext_rs2_unused),
    .o_ext_funct3 (ext_funct3_unused),
    .i_ext_rd     (32'h0),
    .i_ext_ready  (1'b0),
    .o_mdu_valid  (mdu_valid_unused)
  );
endmodule
