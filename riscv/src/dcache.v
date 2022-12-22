module DCache #(
  parameter BLOCK_WIDTH = 4,
  parameter BLOCK_SIZE = 2**BLOCK_WIDTH,
  parameter CACHE_WIDTH = 9,
  parameter CACHE_SIZE = 2**CACHE_WIDTH
) (
  input  wire                    clkIn,             // system clock (from CPU)
  input  wire                    resetIn,           // resetIn
  input  wire [1:0]              accessType,        // access type (none: 2'b00, byte: 2'b01, half word: 2'b10, word: 2'b11)
  input  wire                    readWriteIn,       // read/write select (read: 1, write: 0)
  input  wire [31:0]             dataAddrIn,        // data address (Load/Store Buffer)
  input  wire [31:0]             dataIn,            // data to write
  input  wire                    memDataValid,      // data valid signal (Instruction Unit)
  input  wire [31:BLOCK_WIDTH]   memAddr,           // memory address
  input  wire [BLOCK_SIZE*8-1:0] memDataIn,         // data to loaded from RAM
  input  wire                    acceptWrite,       // write accept signal (Cache)
  input  wire                    mutableMemInValid, // mutable memory valid signal
  input  wire [31:0]             mutableMemDataIn,  // data to load from IO
  input  wire                    mutableWriteSuc,   // mutable write success signal
  output wire                    miss,              // miss signal (for input and output)
  output wire [31:BLOCK_WIDTH]   missAddr,          // miss address (for input and output)
  output wire                    readWriteOut,      // read/write select for mem (read: 1, write: 0)
  output wire [31:BLOCK_WIDTH]   memAddrOut,        // data address
  output wire [BLOCK_SIZE*8-1:0] memOut,            // data to write
  output wire                    dataOutValid,      // instruction output valid signal (Load/Store Buffer)
  output wire [31:0]             dataOut,           // instruction (Load/Store Buffer)
  output wire                    dataWriteSuc       // data write success signal (Load Store Buffer)
);

// cache block
reg [CACHE_SIZE-1:0] cacheValid;
reg [CACHE_SIZE-1:0] cacheDirty;
reg [CACHE_SIZE-1:0] cacheTag  [31:BLOCK_WIDTH];
reg [CACHE_SIZE-1:0] cacheData [BLOCK_SIZE*8-1:0];

// output registers
reg [31:0]           outReg;
reg                  outValidReg;
reg                  missReg;
reg [31:BLOCK_WIDTH] missAddrReg;
reg                  outRegWriteSuc;
reg                  readWriteOutReg;

assign dataOut      = outReg;
assign dataOutValid = outValidReg;
assign dataWriteSuc = outRegWriteSuc;
assign miss         = missReg;
assign missAddr     = missAddrReg;
assign readWriteOut = readWriteOutReg;

// Utensils
reg [1:0]  accessTypeReg;
reg [31:0] dataAddrReg;
reg [31:0] dataReg;

wire [CACHE_WIDTH-1:BLOCK_WIDTH] dataPos     = dataAddrReg[CACHE_WIDTH-1:BLOCK_WIDTH];
wire [CACHE_WIDTH-1:BLOCK_WIDTH] nextDataPos = dataAddrReg[CACHE_WIDTH-1:BLOCK_WIDTH] + 1;
wire [31:BLOCK_WIDTH]            memPos      = memAddr[CACHE_WIDTH-1:BLOCK_WIDTH];
wire hit = cacheValid[dataPos] && (cacheTag[dataPos] == dataAddrReg[31:CACHE_WIDTH]);
wire nextHit = cacheValid[nextDataPos] &&
  (cacheTag[nextDataPos] == ((dataAddrReg + BLOCK_SIZE) >> CACHE_WIDTH));
wire blockPos = dataAddrReg[BLOCK_WIDTH-1:0];
wire mutableAddr = dataAddrReg[17:16] == 2'b11;

always @* begin
  if (accessType != 2'b00) begin
    dataAddrReg   <= dataAddrIn;
    accessTypeReg <= accessType;
    dataReg       <= dataIn;
  end
end

always @(posedge clkIn) begin
  if (resetIn) begin
    cacheValid      <= {CACHE_SIZE{1'b0}};
    cacheDirty      <= {CACHE_SIZE{1'b0}};
    outValidReg     <= 0;
    missReg         <= 0;
    outRegWriteSuc  <= 0;
    readWriteOutReg <= 1;
  end else begin
    if (memDataValid) begin
      cacheValid[memPos] <= 1;
      cacheTag  [memPos] <= memAddr[31:CACHE_WIDTH];
      cacheData [memPos] <= memDataIn;
      cacheDirty[memPos] <= 0;
    end
    case (accessTypeReg)
      2'b01: begin // byte
        if (mutableAddr) begin

        end else begin
          if (hit) begin
            if (readWriteIn) begin
              // read
              outValidReg     <= 1;
              missReg         <= 0;
              outRegWriteSuc  <= 0;
              readWriteOutReg <= 1;
              case (blockPos)
                4'b0000: outReg <= {24'b0, cacheData[dataPos][7:0]};
                4'b0001: outReg <= {24'b0, cacheData[dataPos][15:8]};
                4'b0010: outReg <= {24'b0, cacheData[dataPos][23:16]};
                4'b0011: outReg <= {24'b0, cacheData[dataPos][31:24]};
                4'b0100: outReg <= {24'b0, cacheData[dataPos][39:32]};
                4'b0101: outReg <= {24'b0, cacheData[dataPos][47:40]};
                4'b0110: outReg <= {24'b0, cacheData[dataPos][55:48]};
                4'b0111: outReg <= {24'b0, cacheData[dataPos][63:56]};
                4'b1000: outReg <= {24'b0, cacheData[dataPos][71:64]};
                4'b1001: outReg <= {24'b0, cacheData[dataPos][79:72]};
                4'b1010: outReg <= {24'b0, cacheData[dataPos][87:80]};
                4'b1011: outReg <= {24'b0, cacheData[dataPos][95:88]};
                4'b1100: outReg <= {24'b0, cacheData[dataPos][103:96]};
                4'b1101: outReg <= {24'b0, cacheData[dataPos][111:104]};
                4'b1110: outReg <= {24'b0, cacheData[dataPos][119:112]};
                4'b1111: outReg <= {24'b0, cacheData[dataPos][127:120]};
              endcase
            end else begin
              // write
              outRegWriteSuc      <= 1;
              cacheDirty[dataPos] <= 1;
              case (blockPos)
                4'b0000: cacheData[dataPos][7:0]     <= dataReg[7:0];
                4'b0001: cacheData[dataPos][15:8]    <= dataReg[7:0];
                4'b0010: cacheData[dataPos][23:16]   <= dataReg[7:0];
                4'b0011: cacheData[dataPos][31:24]   <= dataReg[7:0];
                4'b0100: cacheData[dataPos][39:32]   <= dataReg[7:0];
                4'b0101: cacheData[dataPos][47:40]   <= dataReg[7:0];
                4'b0110: cacheData[dataPos][55:48]   <= dataReg[7:0];
                4'b0111: cacheData[dataPos][63:56]   <= dataReg[7:0];
                4'b1000: cacheData[dataPos][71:64]   <= dataReg[7:0];
                4'b1001: cacheData[dataPos][79:72]   <= dataReg[7:0];
                4'b1010: cacheData[dataPos][87:80]   <= dataReg[7:0];
                4'b1011: cacheData[dataPos][95:88]   <= dataReg[7:0];
                4'b1100: cacheData[dataPos][103:96]  <= dataReg[7:0];
                4'b1101: cacheData[dataPos][111:104] <= dataReg[7:0];
                4'b1110: cacheData[dataPos][119:112] <= dataReg[7:0];
                4'b1111: cacheData[dataPos][127:120] <= dataReg[7:0];
              endcase
            end
          end else begin
            // Cache miss
            outValidReg         <= 0;
            outRegWriteSuc      <= 0;
            missAddrReg         <= dataAddrReg[31:BLOCK_WIDTH];
            missReg             <= 1;
            readWriteOutReg     <= cacheDirty[dataPos] && ~acceptWrite;
            if (acceptWrite) cacheDirty[dataPos] <= 0;
          end
        end
      end

      2'b10: begin // half word
        if (mutableAddr) begin
        end else begin
          if (hit) begin
            if (readWriteIn) begin
              // read
              outValidReg     <= (blockPos != 4'b1111) || nextHit;
              missReg         <= 0;
              outRegWriteSuc  <= 0;
              readWriteOutReg <= 1;
              case (blockPos)
                4'b0000: outReg <= {16'b0, cacheData[dataPos][15:0]};
                4'b0001: outReg <= {16'b0, cacheData[dataPos][23:8]};
                4'b0010: outReg <= {16'b0, cacheData[dataPos][31:16]};
                4'b0011: outReg <= {16'b0, cacheData[dataPos][39:24]};
                4'b0100: outReg <= {16'b0, cacheData[dataPos][47:32]};
                4'b0101: outReg <= {16'b0, cacheData[dataPos][55:40]};
                4'b0110: outReg <= {16'b0, cacheData[dataPos][63:48]};
                4'b0111: outReg <= {16'b0, cacheData[dataPos][71:56]};
                4'b1000: outReg <= {16'b0, cacheData[dataPos][79:64]};
                4'b1001: outReg <= {16'b0, cacheData[dataPos][87:72]};
                4'b1010: outReg <= {16'b0, cacheData[dataPos][95:80]};
                4'b1011: outReg <= {16'b0, cacheData[dataPos][103:88]};
                4'b1100: outReg <= {16'b0, cacheData[dataPos][111:96]};
                4'b1101: outReg <= {16'b0, cacheData[dataPos][119:104]};
                4'b1110: outReg <= {16'b0, cacheData[dataPos][127:112]};
                4'b1111: begin
                  if (nextHit) begin
                    outReg <= {16'b0, cacheData[nextDataPos][15:0], cacheData[dataPos][128:120]};
                  end else begin
                    // Cache miss
                    outValidReg         <= 0;
                    outRegWriteSuc      <= 0;
                    missAddrReg         <= dataAddrReg[31:BLOCK_WIDTH];
                    missReg             <= 1;
                    readWriteOutReg     <= cacheDirty[dataPos+1] & ~acceptWrite;
                    if (acceptWrite) cacheDirty[dataPos+1] <= 0;
                  end
                end
              endcase
            end else begin
              // write
              outRegWriteSuc <= (blockPos != 4'b1111) || nextHit;
              cacheDirty[dataPos] <= 1;
              case (blockPos)
                4'b0000: cacheData[dataPos][15:0]    <= dataReg[15:0];
                4'b0001: cacheData[dataPos][23:8]    <= dataReg[15:0];
                4'b0010: cacheData[dataPos][31:16]   <= dataReg[15:0];
                4'b0011: cacheData[dataPos][39:24]   <= dataReg[15:0];
                4'b0100: cacheData[dataPos][47:32]   <= dataReg[15:0];
                4'b0101: cacheData[dataPos][55:40]   <= dataReg[15:0];
                4'b0110: cacheData[dataPos][63:48]   <= dataReg[15:0];
                4'b0111: cacheData[dataPos][71:56]   <= dataReg[15:0];
                4'b1000: cacheData[dataPos][79:64]   <= dataReg[15:0];
                4'b1001: cacheData[dataPos][87:72]   <= dataReg[15:0];
                4'b1010: cacheData[dataPos][95:80]   <= dataReg[15:0];
                4'b1011: cacheData[dataPos][103:88]  <= dataReg[15:0];
                4'b1100: cacheData[dataPos][111:96]  <= dataReg[15:0];
                4'b1101: cacheData[dataPos][119:104] <= dataReg[15:0];
                4'b1110: cacheData[dataPos][127:112] <= dataReg[15:0];
                4'b1111: begin
                  if (nextHit) begin
                    cacheData[dataPos][128:120]  <= dataReg[15:0];
                    cacheData[nextDataPos][15:0] <= dataReg[31:16];
                    cacheDirty[nextDataPos]      <= 1;
                  end else begin
                    // Cache miss
                    outValidReg         <= 0;
                    outRegWriteSuc      <= 0;
                    missAddrReg         <= dataAddrReg[31:BLOCK_WIDTH];
                    missReg             <= 1;
                    readWriteOutReg     <= cacheDirty[dataPos+1] & ~acceptWrite;
                    if (acceptWrite) cacheDirty[dataPos+1] <= 0;
                  end
                end
              endcase
            end
          end else begin
            // Cache miss
            outValidReg         <= 0;
            outRegWriteSuc      <= 0;
            missAddrReg         <= dataAddrReg[31:BLOCK_WIDTH];
            missReg             <= 1;
            readWriteOutReg     <= cacheDirty[dataPos]& ~acceptWrite;
            if (acceptWrite) cacheDirty[dataPos] <= 0;
          end
        end
      end

      2'b11: begin // word
        if (hit) begin
          if (readWriteIn) begin
            // read
            outValidReg     <= (blockPos < 4'b1101) || nextHit;
            missReg         <= 0;
            outRegWriteSuc  <= 0;
            readWriteOutReg <= 1;
            case (blockPos)
              4'b0000: outReg <= cacheData[dataPos][31:0];
              4'b0001: outReg <= cacheData[dataPos][39:8];
              4'b0010: outReg <= cacheData[dataPos][47:16];
              4'b0011: outReg <= cacheData[dataPos][55:24];
              4'b0100: outReg <= cacheData[dataPos][63:32];
              4'b0101: outReg <= cacheData[dataPos][71:40];
              4'b0110: outReg <= cacheData[dataPos][79:48];
              4'b0111: outReg <= cacheData[dataPos][87:56];
              4'b1000: outReg <= cacheData[dataPos][95:64];
              4'b1001: outReg <= cacheData[dataPos][103:72];
              4'b1010: outReg <= cacheData[dataPos][111:80];
              4'b1011: outReg <= cacheData[dataPos][119:88];
              4'b1100: outReg <= cacheData[dataPos][127:96];
              4'b1101: begin
                if (nextHit) begin
                  outReg <= {cacheData[nextDataPos][7:0], cacheData[dataPos][127:104]};
                end else begin
                  // Cache miss
                  outValidReg         <= 0;
                  outRegWriteSuc      <= 0;
                  missAddrReg         <= dataAddrReg[31:BLOCK_WIDTH];
                  missReg             <= 1;
                  readWriteOutReg     <= cacheDirty[dataPos+1] & ~acceptWrite;
                  if (acceptWrite) cacheDirty[dataPos+1] <= 0;
                end
              end
              4'b1110: begin
                if (nextHit) begin
                  outReg <= {cacheData[nextDataPos][15:0], cacheData[dataPos][127:112]};
                end else begin
                  // Cache miss
                  outValidReg         <= 0;
                  outRegWriteSuc      <= 0;
                  missAddrReg         <= dataAddrReg[31:BLOCK_WIDTH];
                  missReg             <= 1;
                  readWriteOutReg     <= cacheDirty[dataPos+1] & ~acceptWrite;
                  if (acceptWrite) cacheDirty[dataPos+1] <= 0;
                end
              end
              4'b1111: begin
                if (nextHit) begin
                  outReg <= {cacheData[nextDataPos][23:0], cacheData[dataPos][127:120]};
                end else begin
                  // Cache miss
                  outValidReg         <= 0;
                  outRegWriteSuc      <= 0;
                  missAddrReg         <= dataAddrReg[31:BLOCK_WIDTH];
                  missReg             <= 1;
                  readWriteOutReg     <= cacheDirty[dataPos+1] & ~acceptWrite;
                  if (acceptWrite) cacheDirty[dataPos+1] <= 0;
                end
              end
            endcase
          end else begin
            // write
            outValidReg         <= (blockPos < 4'b1101) || nextHit;
            cacheDirty[dataPos] <= 1;
            case (blockPos)
              4'b0000: cacheData[dataPos][31:0]    <= dataReg[31:0];
              4'b0001: cacheData[dataPos][39:8]    <= dataReg[31:0];
              4'b0010: cacheData[dataPos][47:16]   <= dataReg[31:0];
              4'b0011: cacheData[dataPos][55:24]   <= dataReg[31:0];
              4'b0100: cacheData[dataPos][63:32]   <= dataReg[31:0];
              4'b0101: cacheData[dataPos][71:40]   <= dataReg[31:0];
              4'b0110: cacheData[dataPos][79:48]   <= dataReg[31:0];
              4'b0111: cacheData[dataPos][87:56]   <= dataReg[31:0];
              4'b1000: cacheData[dataPos][95:64]   <= dataReg[31:0];
              4'b1001: cacheData[dataPos][103:72]  <= dataReg[31:0];
              4'b1010: cacheData[dataPos][111:80]  <= dataReg[31:0];
              4'b1011: cacheData[dataPos][119:88]  <= dataReg[31:0];
              4'b1100: cacheData[dataPos][127:96]  <= dataReg[31:0];
              4'b1101: begin
                if (nextHit) begin
                  cacheData[dataPos][127:104] <= dataReg[31:0];
                  cacheData[nextDataPos][7:0] <= dataReg[39:32];
                  cacheDirty[nextDataPos]     <= 1;
                end else begin
                  // Cache miss
                  outValidReg         <= 0;
                  outRegWriteSuc      <= 0;
                  missAddrReg         <= dataAddrReg[31:BLOCK_WIDTH];
                  missReg             <= 1;
                  readWriteOutReg     <= cacheDirty[dataPos+1] & ~acceptWrite;
                  if (acceptWrite) cacheDirty[dataPos+1] <= 0;
                end
              end
              4'b1110: begin
                if (nextHit) begin
                  cacheData[dataPos][127:112] <= dataReg[31:0];
                  cacheData[nextDataPos][15:0] <= dataReg[39:32];
                  cacheDirty[nextDataPos]      <= 1;
                end else begin
                  // Cache miss
                  outValidReg         <= 0;
                  outRegWriteSuc      <= 0;
                  missAddrReg         <= dataAddrReg[31:BLOCK_WIDTH];
                  missReg             <= 1;
                  readWriteOutReg     <= cacheDirty[dataPos+1] & ~acceptWrite;
                  if (acceptWrite) cacheDirty[dataPos+1] <= 0;
                end
              end
              4'b1111: begin
                if (nextHit) begin
                  cacheData[dataPos][127:120] <= dataReg[31:0];
                  cacheData[nextDataPos][23:0] <= dataReg[39:32];
                  cacheDirty[nextDataPos]      <= 1;
                end else begin
                  // Cache miss
                  outValidReg         <= 0;
                  outRegWriteSuc      <= 0;
                  missAddrReg         <= dataAddrReg[31:BLOCK_WIDTH];
                  missReg             <= 1;
                  readWriteOutReg     <= cacheDirty[dataPos+1] & ~acceptWrite;
                  if (acceptWrite) cacheDirty[dataPos+1] <= 0;
                end
              end
            endcase
          end
        end else begin
          // Cache miss
          outValidReg         <= 0;
          outRegWriteSuc      <= 0;
          missAddrReg         <= dataAddrReg[31:BLOCK_WIDTH];
          missReg             <= 1;
          readWriteOutReg     <= cacheDirty[dataPos] & ~acceptWrite;
          if (acceptWrite) cacheDirty[dataPos] <= 0;
        end
      end
    endcase
  end
end

endmodule
