module ICache #(
  parameter BLOCK_WIDTH = 4,
  parameter BLOCK_SIZE = 2**BLOCK_WIDTH,
  parameter CACHE_WIDTH = 8,
  parameter CACHE_SIZE = 2**CACHE_WIDTH
) (
  input  wire                    clkIn,         // system clock (from CPU)
  input  wire                    resetIn,       // resetIn
  input  wire                    instrInValid,  // instruction valid signal (Instruction Unit)
  input  wire [31:0]             instrAddrIn,   // instruction address (Instruction Unit)
  input  wire                    memDataValid,  // data valid signal (Instruction Unit)
  input  wire [31:BLOCK_WIDTH]   memAddr,       // memory address
  input  wire [BLOCK_SIZE*8-1:0] memDataIn,     // data to loaded from RAM
  output wire                    miss,          // miss signal
  output wire                    instrOutValid, // instruction output valid signal (Instruction Unit)
  output wire [31:0]             instrOut,      // instruction (Instruction Unit)
  output wire [31:0]             instrAddrOut   // instruction address (Instruction Unit)
);

reg [CACHE_SIZE-1:0]             cacheValid;
reg [31:BLOCK_WIDTH+CACHE_WIDTH] cacheTag [CACHE_SIZE-1:0];
reg [31:0]                       cacheData[CACHE_SIZE-1:0][3:0];

// Utensils
wire [CACHE_WIDTH-1:BLOCK_WIDTH] instrPos = instrAddrIn[CACHE_WIDTH-1:BLOCK_WIDTH];
wire [CACHE_WIDTH-1:BLOCK_WIDTH] memPos   = memAddr[CACHE_WIDTH-1:BLOCK_WIDTH];
wire [BLOCK_WIDTH-3:0]           blockPos = instrAddrIn[BLOCK_WIDTH-1:2];
wire hit = instrInValid && cacheValid[instrPos] && (cacheTag[instrPos] == instrAddrIn[31:CACHE_WIDTH]);

assign miss          = ~hit;
assign instrOutValid = hit;
assign instrOut      = cacheData[instrPos][blockPos];
assign instrAddrOut  = instrAddrIn;

always @(posedge clkIn) begin
  if (resetIn) begin
    cacheValid       <= {CACHE_SIZE{1'b0}};
  end else begin
    if (memDataValid) begin
      cacheValid[memPos]    <= 1'b1;
      cacheTag  [memPos]    <= memAddr[31:CACHE_WIDTH];
      cacheData [memPos][0] <= memDataIn[31:0];
      cacheData [memPos][1] <= memDataIn[63:32];
      cacheData [memPos][2] <= memDataIn[95:64];
      cacheData [memPos][3] <= memDataIn[127:96];
    end
  end
end
endmodule
