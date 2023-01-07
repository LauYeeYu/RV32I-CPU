module DCache #(
  parameter BLOCK_WIDTH = 4,
  parameter BLOCK_SIZE = 2**BLOCK_WIDTH,
  parameter CACHE_WIDTH = 9,
  parameter CACHE_SIZE = 2**CACHE_WIDTH
) (
  input  wire                    clkIn,             // system clock (from CPU)
  input  wire                    resetIn,           // resetIn
  input  wire                    clearIn,           // wrong branch prediction signal
  input  wire [1:0]              accessType,        // access type (none: 2'b00, byte: 2'b01, half word: 2'b10, word: 2'b11)
  input  wire                    readWriteIn,       // read/write select (read: 1, write: 0)
  input  wire [31:0]             dataAddrIn,        // data address (Load & Store Buffer)
  input  wire [31:0]             dataIn,            // data to write
  input  wire                    memDataValid,      // data valid signal
  input  wire [31:BLOCK_WIDTH]   memAddr,           // memory address
  input  wire [BLOCK_SIZE*8-1:0] memDataIn,         // data to loaded from RAM
  input  wire                    acceptWrite,       // write accept signal (Cache)
  input  wire                    mutableMemInValid, // mutable memory valid signal
  input  wire [31:0]             mutableMemDataIn,  // data to load from IO
  input  wire                    mutableWriteSuc,   // mutable write success signal
  output wire                    miss,              // miss signal (for input and output)
  output wire [31:BLOCK_WIDTH]   missAddr,          // miss address (for input and output)
  output wire                    readWriteOut,      // read/write select for mem (read: 1, write: 0)
  output wire [BLOCK_SIZE*8-1:0] writeBackOut,      // data to write
  output wire                    dataOutValid,      // data output valid signal (Load & Store Buffer)
  output wire [31:0]             dataOut,           // data (Load & Store Buffer)
  output wire                    dataWriteSuc       // data write success signal (Load Store Buffer)
);

// cache block
reg [CACHE_SIZE-1:0]             cacheValid;
reg [CACHE_SIZE-1:0]             cacheDirty;
reg [31:CACHE_WIDTH+BLOCK_WIDTH] cacheTag  [CACHE_SIZE-1:0];
reg [BLOCK_SIZE*8-1:0]           cacheData [CACHE_SIZE-1:0];

// output registers
reg [31:0]           outReg;
reg                  outValidReg;
reg                  outRegWriteSuc;

assign dataOut      = mutableAddr ? mutableMemDataIn : outReg;
assign dataOutValid = outValidReg | mutableMemInValid;
assign dataWriteSuc = outRegWriteSuc | mutableWriteSuc;
assign miss         = (needWriteBack | needLoad) & ~mutableAddr & (accessTypeReg != 2'b00);
assign missAddr     = needWriteBack ? writeBackTag : loadTag;
assign readWriteOut = ~needWriteBack;

// Utensils
reg [1:0]  accessTypeReg;
reg [31:0] dataAddrReg;
reg [31:0] dataReg;
reg        readWriteReg;

wire                   onLastLine  = (dataAddrReg[CACHE_WIDTH+BLOCK_WIDTH-1:BLOCK_WIDTH] == (CACHE_SIZE - 1));
wire [CACHE_WIDTH-1:0] dataPos     = dataAddrReg[CACHE_WIDTH+BLOCK_SIZE-1:BLOCK_WIDTH];
wire [CACHE_WIDTH-1:0] nextDataPos = dataAddrReg[CACHE_WIDTH+BLOCK_SIZE-1:BLOCK_WIDTH] + 1;
wire [CACHE_WIDTH-1:0] memPos      = memAddr[CACHE_WIDTH+BLOCK_SIZE-1:BLOCK_WIDTH];
wire [BLOCK_WIDTH-1:0] blockPos    = dataAddrReg[BLOCK_WIDTH-1:0];
wire [31:CACHE_WIDTH+BLOCK_WIDTH] dataTag     = dataAddrReg[31:CACHE_WIDTH+BLOCK_WIDTH];
wire [31:CACHE_WIDTH+BLOCK_WIDTH] nextDataTag = dataAddrReg[31:CACHE_WIDTH+BLOCK_WIDTH] + onLastLine;

wire hit           = cacheValid[dataPos] && (cacheTag[dataPos] == dataTag);
wire nextHit       = cacheValid[nextDataPos] && (cacheTag[nextDataPos] == nextDataTag);
wire mutableAddr   = (accessTypeReg == 2'b00) ? 1'b0 : (dataAddrReg[17:16] == 2'b11);
wire nextLineUsed  = (accessTypeReg == 2'b11) ? (dataAddrReg[BLOCK_WIDTH-1:0] > BLOCK_SIZE - 4) :
                     (accessTypeReg == 2'b10) ? (dataAddrReg[BLOCK_WIDTH-1:0] > BLOCK_SIZE - 2) : 1'b0;
wire lineDirty     = cacheDirty[dataPos];
wire nextLineDirty = cacheDirty[nextDataPos];
wire needWriteBack = (!mutableAddr && (accessTypeReg != 2'b00)) &&
                     (lineDirty || (nextLineUsed && nextLineDirty)) &&
                     (!hit || (nextLineUsed && !nextHit));
wire needLoad      = !hit || (nextLineUsed && !nextHit);
wire [31:BLOCK_WIDTH] writeBackTag = lineDirty ? {cacheTag[dataPos], dataPos} : {cacheTag[nextDataPos], nextDataPos};
wire [31:BLOCK_WIDTH] loadTag      = hit ? {nextDataTag, nextDataPos} : {dataTag, dataPos};
wire ready       = hit && (accessTypeReg != 2'b00) && (!nextLineUsed || nextHit); // mutable address cannot hit
wire outValid    = ready && readWriteReg;
wire outRegWrite = ready && !readWriteReg;

assign writeBackOut = lineDirty ? cacheData[dataPos] : cacheData[nextDataPos];

always @* begin
  if (accessType != 2'b00) begin
    dataAddrReg   <= dataAddrIn;
    accessTypeReg <= accessType;
    dataReg       <= dataIn;
    readWriteReg  <= readWriteIn;
  end
end

always @* begin
  if (memDataValid) begin
    cacheValid[memPos] <= 1;
    cacheTag  [memPos] <= memAddr[31:CACHE_WIDTH+BLOCK_WIDTH];
    cacheData [memPos] <= memDataIn;
    if (readWriteReg) cacheDirty[memPos] <= 0;
  end
  if (acceptWrite) begin
    cacheDirty[memPos] <= 0;
  end
end

integer i;
always @(posedge clkIn) begin
  if (resetIn) begin
    cacheValid     <= {CACHE_SIZE{1'b0}};
    cacheDirty     <= {CACHE_SIZE{1'b0}};
    outValidReg    <= 0;
    outRegWriteSuc <= 0;
    accessTypeReg  <= 2'b00;
    dataAddrReg    <= 32'b0;
    dataReg        <= 32'b0;
    readWriteReg   <= 1'b1;
    for (i = 0; i < CACHE_SIZE; i = i + 1) begin
      cacheTag[i]  <= 0;
      cacheData[i] <= 0;
    end
  end else if (clearIn && readWriteReg == 1) begin
    // abort memory read operation when there is a wrong branch prediction
    outValidReg    <= 0;
    outRegWriteSuc <= 0;
    accessTypeReg  <= 2'b00;
  end else begin
    outValidReg    <= outValid;
    outRegWriteSuc <= outRegWrite;
    if (ready) begin
      accessTypeReg  <= 2'b00;
      case (accessTypeReg)
        2'b01: begin // byte
          if (readWriteReg) begin
            // read
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
        end

        2'b10: begin // half word
          if (readWriteReg) begin
            // read
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
              4'b1111: outReg <= {16'b0, cacheData[nextDataPos][15:0], cacheData[dataPos][128:120]};
            endcase
          end else begin
            // write
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
                cacheData[dataPos][127:120] <= dataReg[7:0];
                cacheData[nextDataPos][7:0] <= dataReg[15:8];
                cacheDirty[nextDataPos]     <= 1;
              end
            endcase
          end
        end

        2'b11: begin // word
          if (readWriteReg) begin
            // read
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
              4'b1101: outReg <= {cacheData[nextDataPos][7:0], cacheData[dataPos][127:104]};
              4'b1110: outReg <= {cacheData[nextDataPos][15:0], cacheData[dataPos][127:112]};
              4'b1111: outReg <= {cacheData[nextDataPos][23:0], cacheData[dataPos][127:120]};
            endcase
          end else begin
            // write
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
                cacheData[dataPos][127:104] <= dataReg[23:0];
                cacheData[nextDataPos][7:0] <= dataReg[31:24];
                cacheDirty[nextDataPos]     <= 1;
              end
              4'b1110: begin
                cacheData[dataPos][127:112]  <= dataReg[15:0];
                cacheData[nextDataPos][15:0] <= dataReg[31:16];
                cacheDirty[nextDataPos]      <= 1;
              end
              4'b1111: begin
                cacheData[dataPos][127:120]  <= dataReg[7:0];
                cacheData[nextDataPos][23:0] <= dataReg[31:8];
                cacheDirty[nextDataPos]      <= 1;
              end
            endcase
          end
        end
      endcase
    end
  end
end

endmodule
