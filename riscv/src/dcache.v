module DCache #(
  parameter BLOCK_WIDTH = 4,
  parameter BLOCK_SIZE = 2**BLOCK_WIDTH,
  parameter CACHE_WIDTH = 9,
  parameter CACHE_SIZE = 2**CACHE_WIDTH
) (
  input  wire                    clkIn,             // system clock (from CPU)
  input  wire                    resetIn,           // resetIn
  input  wire                    clearIn,           // wrong branch prediction signal
  input  wire                    readyIn,           // ready signal
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

// Utensils
reg [1:0]  accessTypeReg;
reg [31:0] dataAddrReg;
reg [31:0] dataReg;
reg        readWriteReg;
wire [1:0]  accessTypeMerged = (accessType != 2'b00) ? accessType : accessTypeReg;
wire [31:0] dataAddrMerged   = (accessType != 2'b00) ? dataAddrIn : dataAddrReg;
wire [31:0] dataMerged       = (accessType != 2'b00) ? dataIn     : dataReg;
wire        readWriteMerged  = (accessType != 2'b00) ? readWriteIn : readWriteReg;

wire                   onLastLine  = (dataAddrMerged[CACHE_WIDTH+BLOCK_WIDTH-1:BLOCK_WIDTH] == (CACHE_SIZE - 1));
wire [CACHE_WIDTH-1:0] dataPos     = dataAddrMerged[CACHE_WIDTH+BLOCK_SIZE-1:BLOCK_WIDTH];
wire [CACHE_WIDTH-1:0] nextDataPos = dataAddrMerged[CACHE_WIDTH+BLOCK_SIZE-1:BLOCK_WIDTH] + 1;
wire [CACHE_WIDTH-1:0] memPos      = memAddr[CACHE_WIDTH+BLOCK_SIZE-1:BLOCK_WIDTH];
wire [BLOCK_WIDTH-1:0] blockPos    = dataAddrMerged[BLOCK_WIDTH-1:0];
wire [31:CACHE_WIDTH+BLOCK_WIDTH] dataTag     = dataAddrMerged[31:CACHE_WIDTH+BLOCK_WIDTH];
wire [31:CACHE_WIDTH+BLOCK_WIDTH] nextDataTag = dataAddrMerged[31:CACHE_WIDTH+BLOCK_WIDTH] + onLastLine;
wire [BLOCK_SIZE*8-1:0] cacheDataLine     = cacheData[dataPos];
wire [BLOCK_SIZE*8-1:0] nextCacheDataLine = cacheData[nextDataPos];

wire hit           = cacheValid[dataPos] && (cacheTag[dataPos] == dataTag);
wire nextHit       = cacheValid[nextDataPos] && (cacheTag[nextDataPos] == nextDataTag);
wire mutableAddr   = (accessTypeMerged == 2'b00) ? 1'b0 : (dataAddrMerged[17:16] == 2'b11);
wire nextLineUsed  = (accessTypeMerged == 2'b11) ? (dataAddrMerged[BLOCK_WIDTH-1:0] > BLOCK_SIZE - 4) :
                     (accessTypeMerged == 2'b10) ? (dataAddrMerged[BLOCK_WIDTH-1:0] > BLOCK_SIZE - 2) : 1'b0;
wire lineDirty     = cacheDirty[dataPos] && (!acceptWrite || memPos != dataPos);
wire nextLineDirty = cacheDirty[nextDataPos] && (!acceptWrite || memPos != nextDataPos);
wire needWriteBack = (!mutableAddr && (accessTypeMerged != 2'b00)) &&
                     (lineDirty || (nextLineUsed && nextLineDirty)) &&
                     (!hit || (nextLineUsed && !nextHit));
wire needLoad      = !hit || (nextLineUsed && !nextHit);
wire [31:BLOCK_WIDTH] writeBackTag = lineDirty ? {cacheTag[dataPos], dataPos} : {cacheTag[nextDataPos], nextDataPos};
wire [31:BLOCK_WIDTH] loadTag      = hit ? {nextDataTag, nextDataPos} : {dataTag, dataPos};
wire ready       = hit && (accessTypeMerged != 2'b00) && (!nextLineUsed || nextHit); // mutable address cannot hit
wire outValid    = ready && readWriteMerged;
wire outRegWrite = ready && !readWriteMerged;

assign writeBackOut = lineDirty ? cacheDataLine : nextCacheDataLine;
assign dataOut      = mutableAddr ? mutableMemDataIn : outReg;
assign dataOutValid = outValidReg | mutableMemInValid;
assign dataWriteSuc = outRegWriteSuc | mutableWriteSuc;
assign miss         = (needWriteBack | needLoad) & ~mutableAddr & (accessTypeMerged != 2'b00);
assign missAddr     = needWriteBack ? writeBackTag : loadTag;
assign readWriteOut = ~needWriteBack;

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
    outReg         <= 32'b0;
    for (i = 0; i < CACHE_SIZE; i = i + 1) begin
      cacheTag[i]  <= 0;
      cacheData[i] <= 0;
    end
  end else if (readyIn) begin
    if (memDataValid) begin
      cacheValid[memPos] <= 1;
      cacheTag  [memPos] <= memAddr[31:CACHE_WIDTH+BLOCK_WIDTH];
      cacheData [memPos] <= memDataIn;
    end
    if (acceptWrite) begin
      cacheDirty[memPos] <= 0;
    end
    if (clearIn && readWriteMerged == 1) begin
      // abort memory read operation when there is a wrong branch prediction
      outValidReg    <= 0;
      outRegWriteSuc <= 0;
      accessTypeReg  <= 2'b00;
    end else begin
      if (accessType != 2'b00) begin
        dataAddrReg   <= dataAddrIn;
        accessTypeReg <= accessType;
        dataReg       <= dataIn;
        readWriteReg  <= readWriteIn;
      end
      outValidReg    <= outValid;
      outRegWriteSuc <= outRegWrite;
      if (ready) begin
        accessTypeReg  <= 2'b00;
        case (accessTypeMerged)
          2'b01: begin // byte
            if (readWriteMerged) begin
              // read
              case (blockPos)
                4'b0000: outReg <= {24'b0, cacheDataLine[7:0]};
                4'b0001: outReg <= {24'b0, cacheDataLine[15:8]};
                4'b0010: outReg <= {24'b0, cacheDataLine[23:16]};
                4'b0011: outReg <= {24'b0, cacheDataLine[31:24]};
                4'b0100: outReg <= {24'b0, cacheDataLine[39:32]};
                4'b0101: outReg <= {24'b0, cacheDataLine[47:40]};
                4'b0110: outReg <= {24'b0, cacheDataLine[55:48]};
                4'b0111: outReg <= {24'b0, cacheDataLine[63:56]};
                4'b1000: outReg <= {24'b0, cacheDataLine[71:64]};
                4'b1001: outReg <= {24'b0, cacheDataLine[79:72]};
                4'b1010: outReg <= {24'b0, cacheDataLine[87:80]};
                4'b1011: outReg <= {24'b0, cacheDataLine[95:88]};
                4'b1100: outReg <= {24'b0, cacheDataLine[103:96]};
                4'b1101: outReg <= {24'b0, cacheDataLine[111:104]};
                4'b1110: outReg <= {24'b0, cacheDataLine[119:112]};
                4'b1111: outReg <= {24'b0, cacheDataLine[127:120]};
              endcase
            end else begin
              // write
              cacheDirty[dataPos] <= 1;
              case (blockPos)
                4'b0000: cacheData[dataPos][7:0]     <= dataMerged[7:0];
                4'b0001: cacheData[dataPos][15:8]    <= dataMerged[7:0];
                4'b0010: cacheData[dataPos][23:16]   <= dataMerged[7:0];
                4'b0011: cacheData[dataPos][31:24]   <= dataMerged[7:0];
                4'b0100: cacheData[dataPos][39:32]   <= dataMerged[7:0];
                4'b0101: cacheData[dataPos][47:40]   <= dataMerged[7:0];
                4'b0110: cacheData[dataPos][55:48]   <= dataMerged[7:0];
                4'b0111: cacheData[dataPos][63:56]   <= dataMerged[7:0];
                4'b1000: cacheData[dataPos][71:64]   <= dataMerged[7:0];
                4'b1001: cacheData[dataPos][79:72]   <= dataMerged[7:0];
                4'b1010: cacheData[dataPos][87:80]   <= dataMerged[7:0];
                4'b1011: cacheData[dataPos][95:88]   <= dataMerged[7:0];
                4'b1100: cacheData[dataPos][103:96]  <= dataMerged[7:0];
                4'b1101: cacheData[dataPos][111:104] <= dataMerged[7:0];
                4'b1110: cacheData[dataPos][119:112] <= dataMerged[7:0];
                4'b1111: cacheData[dataPos][127:120] <= dataMerged[7:0];
              endcase
            end
          end

          2'b10: begin // half word
            if (readWriteMerged) begin
              // read
              case (blockPos)
                4'b0000: outReg <= {16'b0, cacheDataLine[15:0]};
                4'b0001: outReg <= {16'b0, cacheDataLine[23:8]};
                4'b0010: outReg <= {16'b0, cacheDataLine[31:16]};
                4'b0011: outReg <= {16'b0, cacheDataLine[39:24]};
                4'b0100: outReg <= {16'b0, cacheDataLine[47:32]};
                4'b0101: outReg <= {16'b0, cacheDataLine[55:40]};
                4'b0110: outReg <= {16'b0, cacheDataLine[63:48]};
                4'b0111: outReg <= {16'b0, cacheDataLine[71:56]};
                4'b1000: outReg <= {16'b0, cacheDataLine[79:64]};
                4'b1001: outReg <= {16'b0, cacheDataLine[87:72]};
                4'b1010: outReg <= {16'b0, cacheDataLine[95:80]};
                4'b1011: outReg <= {16'b0, cacheDataLine[103:88]};
                4'b1100: outReg <= {16'b0, cacheDataLine[111:96]};
                4'b1101: outReg <= {16'b0, cacheDataLine[119:104]};
                4'b1110: outReg <= {16'b0, cacheDataLine[127:112]};
                4'b1111: outReg <= {16'b0, nextCacheDataLine[7:0], cacheDataLine[127:120]};
              endcase
            end else begin
              // write
              cacheDirty[dataPos] <= 1;
              case (blockPos)
                4'b0000: cacheData[dataPos][15:0]    <= dataMerged[15:0];
                4'b0001: cacheData[dataPos][23:8]    <= dataMerged[15:0];
                4'b0010: cacheData[dataPos][31:16]   <= dataMerged[15:0];
                4'b0011: cacheData[dataPos][39:24]   <= dataMerged[15:0];
                4'b0100: cacheData[dataPos][47:32]   <= dataMerged[15:0];
                4'b0101: cacheData[dataPos][55:40]   <= dataMerged[15:0];
                4'b0110: cacheData[dataPos][63:48]   <= dataMerged[15:0];
                4'b0111: cacheData[dataPos][71:56]   <= dataMerged[15:0];
                4'b1000: cacheData[dataPos][79:64]   <= dataMerged[15:0];
                4'b1001: cacheData[dataPos][87:72]   <= dataMerged[15:0];
                4'b1010: cacheData[dataPos][95:80]   <= dataMerged[15:0];
                4'b1011: cacheData[dataPos][103:88]  <= dataMerged[15:0];
                4'b1100: cacheData[dataPos][111:96]  <= dataMerged[15:0];
                4'b1101: cacheData[dataPos][119:104] <= dataMerged[15:0];
                4'b1110: cacheData[dataPos][127:112] <= dataMerged[15:0];
                4'b1111: begin
                  cacheData[dataPos][127:120] <= dataMerged[7:0];
                  cacheData[nextDataPos][7:0] <= dataMerged[15:8];
                  cacheDirty[nextDataPos]     <= 1;
                end
              endcase
            end
          end

          2'b11: begin // word
            if (readWriteMerged) begin
              // read
              case (blockPos)
                4'b0000: outReg <= cacheDataLine[31:0];
                4'b0001: outReg <= cacheDataLine[39:8];
                4'b0010: outReg <= cacheDataLine[47:16];
                4'b0011: outReg <= cacheDataLine[55:24];
                4'b0100: outReg <= cacheDataLine[63:32];
                4'b0101: outReg <= cacheDataLine[71:40];
                4'b0110: outReg <= cacheDataLine[79:48];
                4'b0111: outReg <= cacheDataLine[87:56];
                4'b1000: outReg <= cacheDataLine[95:64];
                4'b1001: outReg <= cacheDataLine[103:72];
                4'b1010: outReg <= cacheDataLine[111:80];
                4'b1011: outReg <= cacheDataLine[119:88];
                4'b1100: outReg <= cacheDataLine[127:96];
                4'b1101: outReg <= {nextCacheDataLine[7:0], cacheDataLine[127:104]};
                4'b1110: outReg <= {nextCacheDataLine[15:0], cacheDataLine[127:112]};
                4'b1111: outReg <= {nextCacheDataLine[23:0], cacheDataLine[127:120]};
              endcase
            end else begin
              // write
              cacheDirty[dataPos] <= 1;
              case (blockPos)
                4'b0000: cacheData[dataPos][31:0]    <= dataMerged[31:0];
                4'b0001: cacheData[dataPos][39:8]    <= dataMerged[31:0];
                4'b0010: cacheData[dataPos][47:16]   <= dataMerged[31:0];
                4'b0011: cacheData[dataPos][55:24]   <= dataMerged[31:0];
                4'b0100: cacheData[dataPos][63:32]   <= dataMerged[31:0];
                4'b0101: cacheData[dataPos][71:40]   <= dataMerged[31:0];
                4'b0110: cacheData[dataPos][79:48]   <= dataMerged[31:0];
                4'b0111: cacheData[dataPos][87:56]   <= dataMerged[31:0];
                4'b1000: cacheData[dataPos][95:64]   <= dataMerged[31:0];
                4'b1001: cacheData[dataPos][103:72]  <= dataMerged[31:0];
                4'b1010: cacheData[dataPos][111:80]  <= dataMerged[31:0];
                4'b1011: cacheData[dataPos][119:88]  <= dataMerged[31:0];
                4'b1100: cacheData[dataPos][127:96]  <= dataMerged[31:0];
                4'b1101: begin
                  cacheData[dataPos][127:104] <= dataMerged[23:0];
                  cacheData[nextDataPos][7:0] <= dataMerged[31:24];
                  cacheDirty[nextDataPos]     <= 1;
                end
                4'b1110: begin
                  cacheData[dataPos][127:112]  <= dataMerged[15:0];
                  cacheData[nextDataPos][15:0] <= dataMerged[31:16];
                  cacheDirty[nextDataPos]      <= 1;
                end
                4'b1111: begin
                  cacheData[dataPos][127:120]  <= dataMerged[7:0];
                  cacheData[nextDataPos][23:0] <= dataMerged[31:8];
                  cacheDirty[nextDataPos]      <= 1;
                end
              endcase
            end
          end
        endcase
      end
    end
  end
end

endmodule
