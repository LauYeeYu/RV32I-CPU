module ICache #(
  parameter ADDR_WIDTH = 17,
  parameter BLOCK_WIDTH = 4,
  parameter BLOCK_SIZE = 2**BLOCK_WIDTH,
  parameter CACHE_WIDTH = 8,
  parameter CACHE_SIZE = 2**CACHE_WIDTH
) (
  input  wire                            clkIn,         // system clock (from CPU)
  input  wire                            resetIn,       // resetIn
  input  wire                            instrInValid,  // instruction valid signal (Instruction Unit)
  input  wire [ADDR_WIDTH-1:0]           instrAddrIn,   // instruction address (Instruction Unit)
  input  wire                            memDataValid,  // data valid signal (Instruction Unit)
  input  wire [ADDR_WIDTH-1:BLOCK_WIDTH] memAddr,       // memory address
  input  wire [BLOCK_SIZE*8-1:0]         memDataIn,     // data to loaded from RAM
  output wire                            miss,          // miss signal
  output wire                            instrOutValid, // instruction output valid signal (Instruction Unit)
  output wire [31:0]                     instrOut       // instruction (Instruction Unit)
);

reg [CACHE_SIZE-1:0] cacheValid;
reg [CACHE_SIZE-1:0] cacheTag  [ADDR_WIDTH-1:BLOCK_WIDTH+CACHE_WIDTH];
reg [CACHE_SIZE-1:0] cacheData [BLOCK_SIZE-1:0];

reg [31:0] outReg;
reg        missReg;

assign instrOut = outReg;
assign miss     = missReg;

always @(posedge clkIn) begin
  if (resetIn) begin
    cacheValid <= {CACHE_SIZE{1'b0}};
  end else begin
    if (memDataValid) begin
      cacheValid[memAddr[CACHE_WIDTH-1:BLOCK_WIDTH]] <= 1'b1;
      cacheTag[memAddr[CACHE_WIDTH-1:BLOCK_WIDTH]]   <= memAddr[ADDR_WIDTH-1:CACHE_WIDTH];
      cacheData[memAddr[CACHE_WIDTH-1:BLOCK_WIDTH]]  <= memDataIn;
    end
    if (instrInValid) begin
      if (cacheValid[instrAddrIn[CACHE_WIDTH-1:BLOCK_WIDTH]] &
       (cacheTag[instrAddrIn[CACHE_WIDTH-1:BLOCK_WIDTH]] == instrAddrIn[ADDR_WIDTH-1:CACHE_WIDTH])) begin
       // Cache hit
        case (instrAddrIn[BLOCK_WIDTH-1:2])
          2'b00: outReg <= cacheData[instrAddrIn[CACHE_WIDTH-1:BLOCK_WIDTH]][31:0];
          2'b01: outReg <= cacheData[instrAddrIn[CACHE_WIDTH-1:BLOCK_WIDTH]][63:32];
          2'b10: outReg <= cacheData[instrAddrIn[CACHE_WIDTH-1:BLOCK_WIDTH]][95:64];
          2'b11: outReg <= cacheData[instrAddrIn[CACHE_WIDTH-1:BLOCK_WIDTH]][127:96];
        endcase
      end else begin
        missReg <= 1'b1;
      end
    end
  end
end
endmodule
