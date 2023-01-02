module Predictor #(
  parameter LOCAL_WIDTH = 12,
  parameter LOCAL_SIZE = 2**LOCAL_WIDTH
) (
  input  wire        resetIn,       // resetIn
  input  wire        clockIn,       // clockIn
  input  wire [31:0] instrAddr,     // instruction address (icache)
  input  wire        updateValid,   // update valid signal (Reorder Buffer)
  input  wire [31:0] updateInstr,   // instruction (Reorder Buffer)
  input  wire        taken,         // taken signal (Reorder Buffer)
  output wire        jump           // jump signal
);

reg [1:0]             localHistory [LOCAL_SIZE-1:0];
reg [LOCAL_WIDTH-1:0] instrPos;

wire [LOCAL_WIDTH-1:0] updatePos = updateInstr[LOCAL_WIDTH+1:2];

assign jump = localHistory[instrPos][1];

integer i;

always @(posedge clockIn) begin
  if (resetIn) begin
    for (i = 0; i < LOCAL_SIZE; i = i + 1) begin
      localHistory[i] <= 2'b01;
    end
  end else begin
    instrPos <= instrAddr[LOCAL_WIDTH+1:2];
    if (updateValid) begin
      case (localHistory[updatePos])
        2'b00: localHistory[updatePos] <= taken ? 2'b01 : 2'b00;
        2'b01: localHistory[updatePos] <= taken ? 2'b11 : 2'b00;
        2'b10: localHistory[updatePos] <= taken ? 2'b11 : 2'b10;
        2'b11: localHistory[updatePos] <= taken ? 2'b11 : 2'b10;
      endcase
    end
  end
end
endmodule
