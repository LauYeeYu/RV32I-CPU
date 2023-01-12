module ICache #(
  parameter BLOCK_WIDTH = 4,
  parameter BLOCK_SIZE = 2**BLOCK_WIDTH,
  parameter CACHE_WIDTH = 4,
  parameter CACHE_SIZE = 2**CACHE_WIDTH
) (
  input  wire                    clkIn,         // system clock (from CPU)
  input  wire                    resetIn,       // resetIn
  input  wire [31:0]             instrAddrIn,   // instruction address (Instruction Unit)
  input  wire                    memDataValid,  // data valid signal (Instruction Unit)
  input  wire [31:BLOCK_WIDTH]   memAddr,       // memory address
  input  wire [BLOCK_SIZE*8-1:0] memDataIn,     // data to loaded from RAM
  output wire                    miss,          // miss signal
  output wire                    instrOutValid, // instruction output valid signal (Instruction Unit)
  output wire [31:0]             instrOut       // instruction (Instruction Unit)
);

reg [CACHE_SIZE-1:0]             cacheValid;
reg [31:BLOCK_WIDTH+CACHE_WIDTH] cacheTag [CACHE_SIZE-1:0];
reg [127:0]                      cacheData[CACHE_SIZE-1:0];

// Utensils
wire [CACHE_WIDTH-1:0] instrPos = instrAddrIn[CACHE_WIDTH+BLOCK_SIZE-1:BLOCK_WIDTH];
wire [CACHE_WIDTH-1:0] memPos   = memAddr[CACHE_WIDTH+BLOCK_SIZE-1:BLOCK_WIDTH];
wire [BLOCK_WIDTH-3:0] blockPos = instrAddrIn[BLOCK_WIDTH-1:2];
wire hit = cacheValid[instrPos] && (cacheTag[instrPos] == instrAddrIn[31:CACHE_WIDTH+BLOCK_WIDTH]);
wire [BLOCK_SIZE*8-1:0] cacheDataLine  = cacheData[instrPos];

assign miss          = ~hit;
assign instrOutValid = hit;
assign instrOut      = hit ?
                         (blockPos == 2'b00) ? cacheDataLine[31:0] :
                         (blockPos == 2'b01) ? cacheDataLine[63:32] :
                         (blockPos == 2'b10) ? cacheDataLine[95:64] :
                                               cacheDataLine[127:96] : 32'b0;

integer i;
always @* begin
  if (resetIn) begin
    cacheValid <= {CACHE_SIZE{1'b0}};
    for (i=0; i<CACHE_SIZE; i=i+1) begin
      cacheTag[i]  <= {(32-CACHE_WIDTH-BLOCK_WIDTH){1'b0}};
      cacheData[i] <= {(BLOCK_SIZE*8){1'b0}};
    end
  end else if (memDataValid) begin
    cacheValid[memPos] <= 1'b1;
    cacheTag  [memPos] <= memAddr[31:CACHE_WIDTH+BLOCK_WIDTH];
    cacheData [memPos] <= memDataIn[127:0];
  end
end

endmodule
