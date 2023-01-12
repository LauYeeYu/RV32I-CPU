module Cache #(
  parameter BLOCK_WIDTH = 4,
  parameter BLOCK_SIZE = 2**BLOCK_WIDTH,
  parameter ICACHE_WIDTH = 4,
  parameter DCACHE_WIDTH = 3
) (
  input  wire        clkIn,         // system clock (from CPU)
  input  wire        resetIn,       // resetIn (from CPU)
  input  wire        clearIn,       // wrong branch prediction signal
  input  wire        readyIn,       // ready signal (from CPU)
  input  wire        ioBufferFull,  // IO buffer full signal
  input  wire [7:0]  memIn,         // data from RAM
  input  wire [31:0] instrAddrIn,   // instruction address (Instruction Unit)
  input  wire [1:0]  accessType,    // access type (none: 2'b00, byte: 2'b01, half word: 2'b10, word: 2'b11)
  input  wire        readWriteIn,   // read/write select (read: 1, write: 0)
  input  wire [31:0] dataAddrIn,    // data address (from Load Store Buffer)
  input  wire [31:0] dataIn,        // data to write (from Load Store Buffer)
  output wire        readWriteOut,  // read/write select (read: 0, write: 1)
  output wire [31:0] memAddr,       // memory address
  output wire [7:0]  memOut,        // write data to RAM
  output wire        instrOutValid, // instruction output valid signal (Instruction Unit)
  output wire [31:0] instrOut,      // instruction (Instruction Unit)
  output wire        dataOutValid,  // data output valid signal (Load Store Buffer)
  output wire [31:0] dataOut,       // data (Load Store Buffer)
  output wire        dataWriteSuc   // data write success signal (Load Store Buffer)
);

  // Buffer
  reg                    loading;
  reg                    resultReady;
  reg                    readWrite; // 1: read, 0: write
  reg                    idle;
  reg                    idleAgain;
  reg [31:BLOCK_WIDTH]   tag;
  reg [BLOCK_SIZE*8-1:0] buffer;
  reg [BLOCK_WIDTH-1:0]  progress;
  reg                    fromICache; // DCache: 0, ICache: 1
  reg                    acceptWriteReg;

  // Mem regs
  reg        memReadWrite;
  reg [7:0]  memOutReg;
  reg [31:0] memAddrReg;

  // ICache input wires
  reg                     icacheMemInValid;
  wire [31:BLOCK_WIDTH]   icacheMemAddr = tag;
  wire [BLOCK_SIZE*8-1:0] icacheMemData = buffer;

  // ICache output wires
  wire icacheMiss;

  // DCache input wires
  reg                     dcacheMemInValid;
  wire [31:BLOCK_WIDTH]   dcacheMemAddrIn = tag;
  wire [BLOCK_SIZE*8-1:0] dcacheMemDataIn = buffer;

  // DCache output wires
  wire                    dcacheMiss;
  wire [31:BLOCK_WIDTH]   dcacheMissAddr;
  wire                    dcacheReadWriteOut;
  wire [31:BLOCK_WIDTH]   dcacheMemAddrOut;
  wire [BLOCK_SIZE*8-1:0] dcacheMemDataOut;
  reg                     dcacheMutableInValid;
  reg                     dcacheMutableWriteSuc;

  // Mutable memory
  reg [1:0]  accessTypeReg;
  reg [31:0] dataAddrReg;
  reg [31:0] dataReg;
  reg        readWriteReg;

  wire [1:0]  accessTypeMerged = (accessType != 2'b00) ? accessType : accessTypeReg;
  wire [31:0] dataAddrMerged   = (accessType != 2'b00) ? dataAddrIn : dataAddrReg;
  wire [31:0] dataMerged       = (accessType != 2'b00) ? dataIn     : dataReg;
  wire        readWriteMerged  = (accessType != 2'b00) ? readWriteIn : readWriteReg;

  reg        mutableReady;
  reg        mutableLoading;
  reg [1:0]  mutableProgress;
  wire mutableAddr = (accessTypeMerged != 2'b00) && (dataAddrMerged[17:16] == 2'b11);

  ICache #(
    .BLOCK_WIDTH (BLOCK_WIDTH),
    .BLOCK_SIZE  (BLOCK_SIZE),
    .CACHE_WIDTH (ICACHE_WIDTH),
    .CACHE_SIZE  (2**ICACHE_WIDTH)
  ) icache(
    .clkIn         (clkIn),
    .resetIn       (resetIn),
    .instrAddrIn   (instrAddrIn),
    .memDataValid  (icacheMemInValid),
    .memAddr       (icacheMemAddr),
    .memDataIn     (icacheMemData),
    .miss          (icacheMiss),
    .instrOutValid (instrOutValid),
    .instrOut      (instrOut)
  );

  DCache #(
    .BLOCK_WIDTH (BLOCK_WIDTH),
    .BLOCK_SIZE  (BLOCK_SIZE),
    .CACHE_WIDTH (DCACHE_WIDTH),
    .CACHE_SIZE  (2**DCACHE_WIDTH)
  ) dcache(
    .clkIn             (clkIn),
    .resetIn           (resetIn),
    .clearIn           (clearIn),
    .readyIn           (readyIn),
    .accessType        (accessType),
    .readWriteIn       (readWriteIn),
    .dataAddrIn        (dataAddrIn),
    .dataIn            (dataIn),
    .memDataValid      (dcacheMemInValid),
    .memAddr           (dcacheMemAddrIn),
    .memDataIn         (dcacheMemDataIn),
    .acceptWrite       (acceptWriteReg),
    .mutableMemInValid (dcacheMutableInValid),
    .mutableMemDataIn  (dataReg),
    .mutableWriteSuc   (dcacheMutableWriteSuc),
    .missAddr          (dcacheMissAddr),
    .miss              (dcacheMiss),
    .readWriteOut      (dcacheReadWriteOut),
    .writeBackOut      (dcacheMemDataOut),
    .dataOutValid      (dataOutValid),
    .dataOut           (dataOut),
    .dataWriteSuc      (dataWriteSuc)
  );

  assign readWriteOut = ~memReadWrite;
  assign memOut       = memOutReg;
  assign memAddr      = memAddrReg;

  // ICache and DCache control logic
  always @(posedge clkIn) begin
    if (resetIn) begin
      loading               <= 0;
      resultReady           <= 0;
      readWrite             <= 1;
      idle                  <= 0;
      idleAgain             <= 0;
      progress              <= 0;
      mutableReady          <= 0;
      mutableLoading        <= 0;
      mutableProgress       <= 2'b00;
      memReadWrite          <= 1;
      dcacheMutableInValid  <= 0;
      dcacheMutableWriteSuc <= 0;
      dataAddrReg           <= 32'b0;
      accessTypeReg         <= 2'b00;
      dataReg               <= 32'b0;
      readWriteReg          <= 1'b0;
      tag                   <= {(32-BLOCK_WIDTH){1'b0}};
      buffer                <= {(BLOCK_SIZE*8){1'b0}};
      icacheMemInValid      <= 0;
      dcacheMemInValid      <= 0;
      memOutReg             <= 8'b0;
      memAddrReg            <= 32'b0;
      fromICache            <= 0;
    end else if (readyIn) begin
      if (accessType != 2'b00) begin
        dataAddrReg   <= dataAddrIn;
        accessTypeReg <= accessType;
        dataReg       <= dataIn;
        readWriteReg  <= readWriteIn;
      end

      // If the memory has already been loaded
      if (resultReady) begin
        buffer[BLOCK_SIZE*8-1:BLOCK_SIZE*8-8] <= memIn;
        if (readWrite) begin // read
          if (fromICache) begin
            icacheMemInValid <= 1;
          end else begin
            dcacheMemInValid <= 1;
          end
        end else begin // write
          memReadWrite   <= 1; // set back to read state
          acceptWriteReg <= 1;
        end
        // reset (missed memory cannot be read within 1 clock)
        resultReady <= 1'b0;
      end else begin
        icacheMemInValid <= 0;
        dcacheMemInValid <= 0;
        acceptWriteReg   <= 0;
      end

      if (mutableReady) begin
        if (readWriteMerged) begin // read
          dcacheMutableInValid <= 1;
          case (accessTypeMerged)
            2'b01: dataReg[7:0]   <= memIn; // Byte
            2'b10: dataReg[15:8]  <= memIn; // Halfword
            2'b11: dataReg[31:24] <= memIn; // Word
          endcase
        end else begin // write
          dcacheMutableWriteSuc <= 1;
        end
        mutableReady  <= 0;
        memReadWrite  <= 1;
        accessTypeReg <= 2'b00;
      end else begin
        dcacheMutableInValid  <= 0;
        dcacheMutableWriteSuc <= 0;
      end

      // load the memory
      if (loading) begin
        acceptWriteReg <= 0;
        case (progress)
          // For reading the memory, the progress indicates that the data read
          // from the memory is at the progress; while for writing the memory,
          // the progress indicates that the data to be written is at the progress.
          4'b1111: begin
            loading     <= 0;
            idle        <= 1;
            progress    <= 0;
            resultReady <= 1;
            if (readWrite) begin // read
              buffer[4'b1111*8-1:4'b1111*8-8] <= memIn;
            end else begin // write
              memOutReg <= buffer[BLOCK_SIZE*8-1:BLOCK_SIZE*8-8];
              memAddrReg <= {tag, progress};
            end
          end
          4'b1110: begin
            progress <= 4'b1111;
            if (readWrite) begin
              buffer[4'b1110*8-1:4'b1110*8-8] <= memIn;
              memAddrReg <= {tag, 4'b1111};
            end else begin
              memOutReg <= buffer[4'b1110*8+7:4'b1110*8];
              memAddrReg <= {tag, 4'b1110};
            end
          end
          4'b1101: begin
            progress <= 4'b1110;
            if (readWrite) begin
              buffer[4'b1101*8-1:4'b1101*8-8] <= memIn;
              memAddrReg <= {tag, 4'b1110};
            end else begin
              memOutReg <= buffer[4'b1101*8+7:4'b1101*8];
              memAddrReg <= {tag, 4'b1101};
            end
          end
          4'b1100: begin
            progress <= 4'b1101;
            if (readWrite) begin
              buffer[4'b1100*8-1:4'b1100*8-8] <= memIn;
              memAddrReg <= {tag, 4'b1101};
            end else begin
              memOutReg <= buffer[4'b1100*8+7:4'b1100*8];
              memAddrReg <= {tag, 4'b1100};
            end
          end
          4'b1011: begin
            progress <= 4'b1100;
            if (readWrite) begin
              buffer[4'b1011*8-1:4'b1011*8-8] <= memIn;
              memAddrReg <= {tag, 4'b1100};
            end else begin
              memOutReg <= buffer[4'b1011*8+7:4'b1011*8];
              memAddrReg <= {tag, 4'b1011};
            end
          end
          4'b1010: begin
            progress <= 4'b1011;
            if (readWrite) begin
              buffer[4'b1010*8-1:4'b1010*8-8] <= memIn;
              memAddrReg <= {tag, 4'b1011};
            end else begin
              memOutReg <= buffer[4'b1010*8+7:4'b1010*8];
              memAddrReg <= {tag, 4'b1010};
            end
          end
          4'b1001: begin
            progress <= 4'b1010;
            if (readWrite) begin
              buffer[4'b1001*8-1:4'b1001*8-8] <= memIn;
              memAddrReg <= {tag, 4'b1010};
            end else begin
              memOutReg <= buffer[4'b1001*8+7:4'b1001*8];
              memAddrReg <= {tag, 4'b1001};
            end
          end
          4'b1000: begin
            progress <= 4'b1001;
            if (readWrite) begin
              buffer[4'b1000*8-1:4'b1000*8-8] <= memIn;
              memAddrReg <= {tag, 4'b1001};
            end else begin
              memOutReg <= buffer[4'b1000*8+7:4'b1000*8];
              memAddrReg <= {tag, 4'b1000};
            end
          end
          4'b0111: begin
            progress <= 4'b1000;
            if (readWrite) begin
              buffer[4'b0111*8-1:4'b0111*8-8] <= memIn;
              memAddrReg <= {tag, 4'b1000};
            end else begin
              memOutReg <= buffer[4'b0111*8+7:4'b0111*8];
              memAddrReg <= {tag, 4'b0111};
            end
          end
          4'b0110: begin
            progress <= 4'b0111;
            if (readWrite) begin
              buffer[4'b0110*8-1:4'b0110*8-8] <= memIn;
              memAddrReg <= {tag, 4'b0111};
            end else begin
              memOutReg <= buffer[4'b0110*8+7:4'b0110*8];
              memAddrReg <= {tag, 4'b0110};
            end
          end
          4'b0101: begin
            progress <= 4'b0110;
            if (readWrite) begin
              buffer[4'b0101*8-1:4'b0101*8-8] <= memIn;
              memAddrReg <= {tag, 4'b0110};
            end else begin
              memOutReg <= buffer[4'b0101*8+7:4'b0101*8];
              memAddrReg <= {tag, 4'b0101};
            end
          end
          4'b0100: begin
            progress <= 4'b0101;
            if (readWrite) begin
              buffer[4'b0100*8-1:4'b0100*8-8] <= memIn;
              memAddrReg <= {tag, 4'b0101};
            end else begin
              memOutReg <= buffer[4'b0100*8+7:4'b0100*8];
              memAddrReg <= {tag, 4'b0100};
            end
          end
          4'b0011: begin
            progress <= 4'b0100;
            if (readWrite) begin
              buffer[4'b0011*8-1:4'b0011*8-8] <= memIn;
              memAddrReg <= {tag, 4'b0100};
            end else begin
              memOutReg <= buffer[4'b0011*8+7:4'b0011*8];
              memAddrReg <= {tag, 4'b0011};
            end
          end
          4'b0010: begin
            progress <= 4'b0011;
            if (readWrite) begin
              buffer[4'b0010*8-1:4'b0010*8-8] <= memIn;
              memAddrReg <= {tag, 4'b0011};
            end else begin
              memOutReg <= buffer[4'b0010*8+7:4'b0010*8];
              memAddrReg <= {tag, 4'b0010};
            end
          end
          4'b0001: begin
            progress <= 4'b0010;
            if (readWrite) begin
              buffer[4'b0001*8-1:4'b0001*8-8] <= memIn;
              memAddrReg <= {tag, 4'b0010};
            end else begin
              memOutReg <= buffer[4'b0001*8+7:4'b0001*8];
              memAddrReg <= {tag, 4'b0001};
            end
          end
          4'b0000: begin
            progress <= 4'b0001;
            if (readWrite) begin
              memAddrReg <= {tag, 4'b0001};
            end else begin
              memReadWrite <= 1'b0;
              memOutReg <= buffer[4'b0000*8+7:4'b0000*8];
              memAddrReg <= {tag, 4'b0000};
            end
          end
        endcase
      end else if (idle) begin
        if (idleAgain) begin
          idle <= 0;
          idleAgain <= 0;
        end else begin
          idleAgain <= 1;
        end
      end else if (mutableLoading) begin
        if (readWriteMerged || !ioBufferFull) begin
          case (mutableProgress)
            2'b00: begin
              memAddrReg <= dataAddrMerged + 1;
              mutableProgress <= 2'b01;
              if (accessTypeMerged == 2'b01) begin
                mutableReady   <= 1;
                mutableLoading <= 0;
              end
            end
            2'b01: begin
              memAddrReg      <= dataAddrMerged + 2;
              mutableProgress <= 2'b10;
              if (readWriteMerged) dataReg[7:0] <= memIn;
              else              memOutReg    <= dataMerged[15:8];
              if (accessTypeMerged == 2'b10) begin
                mutableReady   <= 1;
                mutableLoading <= 0;
              end
            end
            2'b10: begin
              memAddrReg      <= dataAddrMerged + 3;
              mutableProgress <= 2'b11;
              if (readWriteMerged) dataReg[15:8] <= memIn;
              else              memOutReg     <= dataMerged[23:16];
            end
            2'b11: begin
              mutableReady   <= 1;
              mutableLoading <= 0;
              if (readWriteMerged) begin
                dataReg[23:16] <= memIn;
                memAddrReg     <= 32'b0;
              end else begin
                memOutReg  <= dataMerged[31:24];
                memAddrReg <= dataAddrMerged + 4;
              end
            end
          endcase
        end
      end else if (mutableAddr && !mutableReady) begin
        if (readWriteMerged || !ioBufferFull) begin
          mutableProgress <= readWriteMerged ? 2'b00 : 2'b01;
          mutableLoading  <= readWriteMerged == 1 || accessTypeMerged != 2'b01;
          mutableReady    <= readWriteMerged == 0 && accessTypeMerged == 2'b01;
          memReadWrite    <= readWriteMerged;
          memAddrReg      <= dataAddrMerged;
          if (!readWriteMerged) memOutReg  <= dataMerged[7:0];
        end
      end else if (dcacheMiss) begin // dcache have the priority to use memory
        readWrite         <= dcacheReadWriteOut;
        fromICache        <= 0;
        loading           <= 1;
        progress          <= 0;
        if (dcacheReadWriteOut) begin // read
          tag        <= dcacheMissAddr;
          memAddrReg <= {dcacheMissAddr, 4'b0000};
        end else begin // write
          tag        <= dcacheMissAddr;
          buffer     <= dcacheMemDataOut;
          memAddrReg <= 32'b0;
        end
      end else if (icacheMiss) begin
        readWrite         <= 1; // read
        fromICache        <= 1;
        loading           <= 1;
        progress          <= 0;
        tag               <= instrAddrIn[31:BLOCK_WIDTH];
        memAddrReg        <= {instrAddrIn[31:BLOCK_WIDTH], 4'b0000};
      end else begin
        memAddrReg     <= 32'b0;
      end
    end
  end
endmodule
