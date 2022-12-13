module predictor #(
  parameter LOCAL_WIDTH = 12,
  parameter LOCAL_SIZE = 2**LOCAL_WIDTH,
) (
  input  wire        resetIn,       // resetIn
  input  wire        clockIn,       // clockIn
  input  wire        instrInValid,  // instruction valid signal (icache)
  input  wire [31:0] instrIn,       // data valid signal (icache)
  input  wire [31:0] instrAddr,     // instruction address (icache)
  input  wire        updateValid,   // update valid signal (Reorder Buffer)
  input  wire [31:0] updateInstr,   // instruction (Reorder Buffer)
  input  wire        taken,         // taken signal (Reorder Buffer)
  output wire        jump,          // jump signal
);

reg [LOCAL_WIDTH-1:0] localHistory[1:0];

wire instrPos = instrAddr[LOCAL_WIDTH+1:2];
wire updatePos = updateInstr[LOCAL_WIDTH+1:2];

assign jump = localHistory[instrPos] > 2'b01 ? 1'b1 : 1'b0;

always @(posedge clockIn) begin
  if (resetIn) begin
    localHistory <= {LOCAL_SIZE{2'b01}};
  end else begin
    if (updateValid) begin
      localHistory[updatePos] <= taken ? localHistory[updatePos] + 2'b01 : localHistory[updatePos] - 2'b01;
    end
  end
end
endmodule