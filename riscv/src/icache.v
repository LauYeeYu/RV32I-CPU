module ICache #(
  parameter BLOCK_WIDTH = 4,
  parameter BLOCK_SIZE = 2**BLOCK_WIDTH,
  parameter CACHE_WIDTH = 8,
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

assign miss          = ~hit;
assign instrOutValid = hit;
assign instrOut      = hit ?
                         (blockPos == 2'b00) ? cacheData[instrPos][31:0] :
                         (blockPos == 2'b01) ? cacheData[instrPos][63:32] :
                         (blockPos == 2'b10) ? cacheData[instrPos][95:64] :
                                               cacheData[instrPos][127:96] : 32'b0;

always @* begin
  if (resetIn) begin
  cacheValid <= {CACHE_SIZE{1'b0}};
  end else if (memDataValid) begin
    cacheValid[memPos] <= 1'b1;
    cacheTag  [memPos] <= memAddr[31:CACHE_WIDTH+BLOCK_WIDTH];
    cacheData [memPos] <= memDataIn[127:0];
  end
end

endmodule
