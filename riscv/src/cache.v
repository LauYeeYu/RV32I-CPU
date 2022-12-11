module Cache #(
  parameter ADDR_WIDTH = 17,
  parameter BLOCK_WIDTH = 4,
  parameter BLOCK_SIZE = 2**BLOCK_WIDTH,
  parameter ICACHE_WIDTH = 8,
  parameter DCACHE_WIDTH = 9
) (
  input  wire                  clkIn,         // system clock (from CPU)
  input  wire                  resetIn,       // resetIn (from CPU)
  input  wire                  readyIn,       // ready signal (from CPU)
  input  wire [7:0]            memIn,         // data from RAM
  input  wire                  instrInValid,  // instruction valid signal (Instruction Unit)
  input  wire [ADDR_WIDTH-1:0] instrAddrIn,   // instruction address (Instruction Unit)
  input  wire [1:0]            accessType,    // access type (none: 2'b00, byte: 2'b01, half word: 2'b10, word: 2'b11)
  input  wire                  readWriteIn,   // read/write select (read: 1, write: 0)
  input  wire [ADDR_WIDTH-1:0] dataAddrIn,    // data address (from Load Store Buffer)
  input  wire [31:0]           dataIn,        // data to write (from Load Store Buffer)
  output wire                  readWriteOut,  // read/write select (read: 1, write: 0)
  output wire [ADDR_WIDTH-1:0] memAddr,       // memory address
  output wire [7:0]            memOut,        // write data to RAM
  output wire                  instrOutValid, // instruction output valid signal (Instruction Unit)
  output wire [31:0]           instrOut,      // instruction (Instruction Unit)
  output wire                  dataOutValid,  // data output valid signal (Load Store Buffer)
  output wire [31:0]           dataOut,       // data (Load Store Buffer)
  output wire                  dataWriteSuc   // data write success signal (Load Store Buffer)
);

  // Mem regs
  reg                  memReadWrite = 1'b1;
  reg [7:0]            memOutReg;
  reg [ADDR_WIDTH-1:0] memAddrReg;

  // ICache input wires
  reg                             icacheMemInValid;
  wire [ADDR_WIDTH-1:BLOCK_WIDTH] icacheMemAddr = tag;
  wire [BLOCK_SIZE*8-1:0]         icacheMemData = buffer;

  // ICache output wires
  wire icacheMiss;

  // DCache input wires
  reg                             dcacheMemInValid;
  wire [ADDR_WIDTH-1:BLOCK_WIDTH] dcacheMemAddrIn = tag;
  wire [BLOCK_SIZE*8-1:0]         dcacheMemDataIn = buffer;

  // DCache output wires
  wire                            dcacheMiss;
  wire                            dcacheReadWriteOut;
  wire [ADDR_WIDTH-1:BLOCK_WIDTH] dcacheMemAddrOut;
  wire [BLOCK_SIZE*8-1:0]         dcacheMemDataOut;

  // Buffer
  reg                            loading = 1'b0;
  reg                            resultReady = 1'b0;
  reg                            readWrite; // 1: read, 0: write
  reg                            idle = 1'b0;
  reg [ADDR_WIDTH-1:BLOCK_WIDTH] tag = 0;
  reg [BLOCK_SIZE*8-1:0]         buffer = 0;
  reg [BLOCK_WIDTH-1:0]          progress = 0;
  reg                            fromICache = 0; // DCache: 0, ICache: 1

  ICache #(
    .ADDR_WIDTH  (ADDR_WIDTH),
    .BLOCK_WIDTH (BLOCK_WIDTH),
    .BLOCK_SIZE  (BLOCK_SIZE),
    .CACHE_WIDTH (ICACHE_WIDTH),
    .CACHE_SIZE  (2**ICACHE_WIDTH)
  ) icache(
    .clkIn         (clkIn),
    .resetIn       (resetIn),
    .instrInValid  (instrInValid),
    .instrAddrIn   (instrAddrIn),
    .memDataValid  (icacheMemInValid),
    .memAddr       (icacheMemAddr),
    .memDataIn     (icacheMemData),
    .miss          (icacheMiss),
    .instrOutValid (instrOutValid),
    .instrOut      (instrOut)
  );

  DCache #(
    .ADDR_WIDTH  (ADDR_WIDTH),
    .BLOCK_WIDTH (BLOCK_WIDTH),
    .BLOCK_SIZE  (BLOCK_SIZE),
    .CACHE_WIDTH (DCACHE_WIDTH),
    .CACHE_SIZE  (2**DCACHE_WIDTH)
  ) dcache(
    .clkIn         (clkIn),
    .resetIn      (resetIn),
    .accessType   (accessType),
    .readWriteIn  (readWriteIn),
    .dataAddrIn   (dataAddrIn),
    .dataIn       (dataIn),
    .memDataValid (dcacheMemInValid),
    .memAddr      (dcacheMemAddrIn),
    .memDataIn    (dcacheMemDataIn),
    .miss         (dcacheMiss),
    .readWriteOut (dcacheReadWriteOut),
    .memAddrOut   (dcacheMemAddrOut),
    .memOut       (dcacheMemDataOut),
    .dataOutValid (dataOutValid),
    .dataOut      (dataOut),
    .dataWriteSuc (dataWriteSuc)
  );

  assign readWriteOut = memReadWrite;
  assign memOut       = memOutReg;
  assign memAddr      = memAddrReg;

  // ICache and DCache control logic
  always @(posedge clkIn) begin
    // If the memory has already been loaded
    if (resultReady) begin
      if (readWrite) begin // read
        if (fromICache) begin
          icacheMemInValid <= 1;
        end else begin
          dcacheMemInValid <= 1;
        end
      end else begin // write
        memReadWrite <= 1; // set back to read state
      end
      // reset (missed memory cannot be read within 1 clock)
      resultReady <= 1'b0;
    end else begin
      icacheMemInValid <= 0;
      dcacheMemInValid <= 0;
      memReadWrite     <= 1;
    end

    // load the memory
    if (loading) begin
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
            buffer[BLOCK_SIZE*8-1:BLOCK_SIZE*8-8] <= memIn;
          end else begin // write
            memOutReg <= buffer[BLOCK_SIZE*8-1:BLOCK_SIZE*8-8];
            memAddrReg <= {tag, progress};
          end
        end
        4'b1110: begin
          progress <= 4'b1111;
          if (readWrite) begin
            buffer[4'b1110*8+7:4'b1110*8] <= memIn;
            memAddrReg <= {tag, 4'b1111};
          end else begin
            memOutReg <= buffer[4'b1110*8+7:4'b1110*8];
            memAddrReg <= {tag, 4'b1110};
          end
        end
        4'b1101: begin
          progress <= 4'b1110;
          if (readWrite) begin
            buffer[4'b1101*8+7:4'b1101*8] <= memIn;
            memAddrReg <= {tag, 4'b1110};
          end else begin
            memOutReg <= buffer[4'b1101*8+7:4'b1101*8];
            memAddrReg <= {tag, 4'b1101};
          end
        end
        4'b1100: begin
          progress <= 4'b1101;
          if (readWrite) begin
            buffer[4'b1100*8+7:4'b1100*8] <= memIn;
            memAddrReg <= {tag, 4'b1101};
          end else begin
            memOutReg <= buffer[4'b1100*8+7:4'b1100*8];
            memAddrReg <= {tag, 4'b1100};
          end
        end
        4'b1011: begin
          progress <= 4'b1100;
          if (readWrite) begin
            buffer[4'b1011*8+7:4'b1011*8] <= memIn;
            memAddrReg <= {tag, 4'b1100};
          end else begin
            memOutReg <= buffer[4'b1011*8+7:4'b1011*8];
            memAddrReg <= {tag, 4'b1011};
          end
        end
        4'b1010: begin
          progress <= 4'b1011;
          if (readWrite) begin
            buffer[4'b1010*8+7:4'b1010*8] <= memIn;
            memAddrReg <= {tag, 4'b1011};
          end else begin
            memOutReg <= buffer[4'b1010*8+7:4'b1010*8];
            memAddrReg <= {tag, 4'b1010};
          end
        end
        4'b1001: begin
          progress <= 4'b1010;
          if (readWrite) begin
            buffer[4'b1001*8+7:4'b1001*8] <= memIn;
            memAddrReg <= {tag, 4'b1010};
          end else begin
            memOutReg <= buffer[4'b1001*8+7:4'b1001*8];
            memAddrReg <= {tag, 4'b1001};
          end
        end
        4'b1000: begin
          progress <= 4'b1001;
          if (readWrite) begin
            buffer[4'b1000*8+7:4'b1000*8] <= memIn;
            memAddrReg <= {tag, 4'b1001};
          end else begin
            memOutReg <= buffer[4'b1000*8+7:4'b1000*8];
            memAddrReg <= {tag, 4'b1000};
          end
        end
        4'b0111: begin
          progress <= 4'b1000;
          if (readWrite) begin
            buffer[4'b0111*8+7:4'b0111*8] <= memIn;
            memAddrReg <= {tag, 4'b1000};
          end else begin
            memOutReg <= buffer[4'b0111*8+7:4'b0111*8];
            memAddrReg <= {tag, 4'b0111};
          end
        end
        4'b0110: begin
          progress <= 4'b0111;
          if (readWrite) begin
            buffer[4'b0110*8+7:4'b0110*8] <= memIn;
            memAddrReg <= {tag, 4'b0111};
          end else begin
            memOutReg <= buffer[4'b0110*8+7:4'b0110*8];
            memAddrReg <= {tag, 4'b0110};
          end
        end
        4'b0101: begin
          progress <= 4'b0110;
          if (readWrite) begin
            buffer[4'b0101*8+7:4'b0101*8] <= memIn;
            memAddrReg <= {tag, 4'b0110};
          end else begin
            memOutReg <= buffer[4'b0101*8+7:4'b0101*8];
            memAddrReg <= {tag, 4'b0101};
          end
        end
        4'b0100: begin
          progress <= 4'b0101;
          if (readWrite) begin
            buffer[4'b0100*8+7:4'b0100*8] <= memIn;
            memAddrReg <= {tag, 4'b0101};
          end else begin
            memOutReg <= buffer[4'b0100*8+7:4'b0100*8];
            memAddrReg <= {tag, 4'b0100};
          end
        end
        4'b0011: begin
          progress <= 4'b0100;
          if (readWrite) begin
            buffer[4'b0011*8+7:4'b0011*8] <= memIn;
            memAddrReg <= {tag, 4'b0100};
          end else begin
            memOutReg <= buffer[4'b0011*8+7:4'b0011*8];
            memAddrReg <= {tag, 4'b0011};
          end
        end
        4'b0010: begin
          progress <= 4'b0011;
          if (readWrite) begin
            buffer[4'b0010*8+7:4'b0010*8] <= memIn;
            memAddrReg <= {tag, 4'b0011};
          end else begin
            memOutReg <= buffer[4'b0010*8+7:4'b0010*8];
            memAddrReg <= {tag, 4'b0010};
          end
        end
        4'b0001: begin
          progress <= 4'b0010;
          if (readWrite) begin
            buffer[4'b0001*8+7:4'b0001*8] <= memIn;
            memAddrReg <= {tag, 4'b0010};
          end else begin
            memOutReg <= buffer[4'b0001*8+7:4'b0001*8];
            memAddrReg <= {tag, 4'b0001};
          end
        end
        4'b0000: begin
          progress <= 4'b0001;
          if (readWrite) begin
            buffer[4'b0000*8+7:4'b0000*8] <= memIn;
            memAddrReg <= {tag, 4'b0001};
          end else begin
            memReadWrite <= 1'b0;
            memOutReg <= buffer[4'b0000*8+7:4'b0000*8];
            memAddrReg <= {tag, 4'b0000};
          end
        end
      endcase
    end else if (idle) begin
      idle <= 0;
    end else if (dcacheMiss) begin // dcache have the priority to use memory
      readWrite  <= dcacheReadWriteOut;
      fromICache <= 0;
      loading    <= 1;
      progress   <= 0;
      if (dcacheReadWriteOut) begin // read
        tag        <= dcacheMemAddrOut[ADDR_WIDTH-1:BLOCK_WIDTH];
        memAddrReg <= {tag, 4'b0000};
      end else begin // write
        buffer <= dcacheMemDataOut;
      end
    end else if (icacheMiss) begin
      readWrite  <= 1; // read
      fromICache <= 1;
      loading    <= 1;
      progress   <= 0;
      tag        <= instrAddrIn[ADDR_WIDTH-1:BLOCK_WIDTH];
      memAddrReg <= {instrAddrIn[ADDR_WIDTH-1:BLOCK_WIDTH], 4'b0000};
    end
  end
endmodule
