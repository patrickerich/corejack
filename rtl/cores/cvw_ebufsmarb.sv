// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Adapted from the upstream CORE-V-Wally ebufsmarb; internal naming keeps the
// upstream Wally style deliberately, to minimize the diff against the source
// it tracks (style exception). The cvw_ file prefix avoids collisions with
// other cores' files (filename != module name is intentional).
module ebufsmarb (
  input  logic       HCLK,
  input  logic       HRESETn,
  input  logic [2:0] HBURST,
  input  logic       HREADY,
  input  logic       LSUReq,
  input  logic       IFUReq,
  output logic       IFUSave,
  output logic       IFURestore,
  output logic       IFUDisable,
  output logic       IFUSelect,
  output logic       LSUDisable,
  output logic       LSUSelect
);
  typedef enum logic [1:0] {
    IDLE,
    ARBITRATE
  } statetype;

  statetype   CurrState;
  statetype   NextState;
  logic       both;
  logic       IFUReqDelay;
  logic       FinalBeat;
  logic       FinalBeatD;
  logic       BeatCntEn;
  logic [3:0] BeatCount;
  logic       BeatCntReset;
  logic [3:0] Threshold;

  assign both = LSUReq & IFUReq;

  flopenl #(.TYPE(statetype)) busreg (
    .clk   (HCLK),
    .load  (~HRESETn),
    .en    (1'b1),
    .d     (NextState),
    .val   (IDLE),
    .q     (CurrState)
  );

  always_comb begin
    unique case (CurrState)
      IDLE:      NextState = both ? ARBITRATE : IDLE;
      ARBITRATE: NextState = (HREADY & FinalBeatD & ~both) ? IDLE : ARBITRATE;
      default:   NextState = IDLE;
    endcase
  end

  assign IFUSave    = CurrState == IDLE & both;
  assign IFURestore = CurrState == ARBITRATE;
  assign IFUDisable = IFURestore;
  assign IFUSelect  = (NextState == ARBITRATE) ? 1'b0 : IFUReq;

  flopr #(1) ifureqreg (
    .clk   (HCLK),
    .reset (~HRESETn),
    .d     (IFUReq),
    .q     (IFUReqDelay)
  );

  assign LSUDisable = (CurrState != ARBITRATE) & IFUReqDelay;
  assign LSUSelect  = (NextState == ARBITRATE) ? 1'b1 : LSUReq;

  assign BeatCntReset = NextState == IDLE;
  assign FinalBeat    = (BeatCount == Threshold);
  assign BeatCntEn    = (NextState == ARBITRATE) & HREADY;

  cvw_counter #(4) BeatCounter (
    .clk   (HCLK),
    .reset (~HRESETn | BeatCntReset | FinalBeat),
    .en    (BeatCntEn),
    .q     (BeatCount)
  );

  flopenr #(1) FinalBeatReg (
    .clk   (HCLK),
    .reset (~HRESETn | BeatCntReset),
    .en    (BeatCntEn),
    .d     (FinalBeat),
    .q     (FinalBeatD)
  );

  always_comb begin
    if (HBURST[2:1] == 2'b00) begin
      Threshold = 4'b0000;
    end else begin
      Threshold = (4'd2 << HBURST[2:1]) - 4'd1;
    end
  end
endmodule
