`ifdef DEBUG
`define PRINT_RESULT
`endif
module LoadStoreBuffer #(
  parameter ROB_WIDTH = 4,
  parameter LSB_WIDTH = 4,
  parameter LSB_SIZE = 2**LSB_WIDTH,
  parameter LSB_OP_WIDTH = 3
) (
  input  wire                 resetIn,      // resetIn
  input  wire                 clockIn,      // clockIn
  input  wire                 clearIn,      // clearIn
  output wire                 lsbUpdate,    // load & store buffer update signal
  output wire [ROB_WIDTH-1:0] lsbRobIndex,  // load & store buffer rob index
  output wire [31:0]          lsbUpdateVal, // load & store buffer value

  // DCache part
  input  wire        dataValid,    // data input valid signal
  input  wire [31:0] dataIn,       // data
  input  wire        dataWriteSuc, // data write success sign
  output wire [1:0]  accessType,   // access type (none: 2'b00, byte: 2'b01, half word: 2'b10, word: 2'b11)
  output wire        readWriteOut, // read/write select (read: 1, write: 0)
  output wire [31:0] dataAddr,     // data address
  output wire [31:0] dataOut,      // data to write

  // Reorder Buffer part
  input wire [ROB_WIDTH-1:0] robBeginId,    // begin index of the load & store buffer
  input wire                 robBeginValid, // has committed signal

  // Reservation Station part
  input  wire                    rsUpdate,    // reservation station update signal
  input  wire [ROB_WIDTH-1:0]    rsRobIndex,  // reservation station rob index
  input  wire [31:0]             rsUpdateVal, // reservation station value

  // Instruction Unit part
  input  wire                    addValid,         // Instruction Unit add valid signal
  input  wire                    addReadWrite,     // Instruction Unit read/write select
  input  wire [ROB_WIDTH-1:0]    addRobId,         // Instruction Unit rob index
  input  wire                    addBaseHasDep,    // Instruction Unit has dependency
  input  wire [31:0]             addBase,          // Instruction Unit add base addr
  input  wire [ROB_WIDTH-1:0]    addBaseConstrtId, // Instruction Unit add constraint index (RoB)
  input  wire [31:0]             addOffset,        // Instruction Unit add offset
  input  wire                    addDataHasDep,    // Instruction Unit has dependency
  input  wire [31:0]             addData,          // Instruction Unit add data
  input  wire [ROB_WIDTH-1:0]    addDataConstrtId, // Instruction Unit add constraint index (RoB)
  input  wire [LSB_OP_WIDTH-1:0] addOp,            // Instruction Unit add op
  output wire                    full              // full signal
);

reg [1:0]              accessTypeReg; // access type (none: 2'b00, byte: 2'b01, half word: 2'b10, word: 2'b11)
reg                    readWriteReg;  // read/write select (read: 1, write: 0)
reg [31:0]             dataAddrReg;   // data address
reg [31:0]             dataOutReg;    // data to write
reg                    processing;    // there is a value to be processed by dcache
reg [ROB_WIDTH-1:0]    updateRobIdReg;
reg [ROB_WIDTH-1:0]    nextRobIdReg;
reg [LSB_OP_WIDTH-1:0] processOpReg;

assign accessType   = accessTypeReg;
assign readWriteOut = readWriteReg;
assign dataAddr     = dataAddrReg;
assign dataOut      = dataOutReg;
assign lsbUpdate    = dataValid;
assign lsbRobIndex  = updateRobIdReg;
assign lsbUpdateVal = (processOpReg == 3'b000) ? {{24{dataIn[7]}},  dataIn[7:0]} : // signed byte
                      (processOpReg == 3'b001) ? {{16{dataIn[15]}}, dataIn[15:0]} : // signed halfword
                      dataIn; // unsigned byte, unsigned halfword, word

// FIFO
reg [LSB_WIDTH-1:0]    beginIndex;
reg [LSB_WIDTH-1:0]    endIndex;
reg [LSB_SIZE-1:0]     valid;
reg [LSB_SIZE-1:0]     ready;
reg [LSB_SIZE-1:0]     readWrite; // 0: write, 1: read
reg [ROB_WIDTH-1:0]    robId[LSB_SIZE-1:0];
reg [LSB_SIZE-1:0]     baseHasDep;
reg [31:0]             baseAddr[LSB_SIZE-1:0];
reg [ROB_WIDTH-1:0]    baseConstrtId[LSB_SIZE-1:0];
reg [31:0]             offset[LSB_SIZE-1:0];
reg [LSB_SIZE-1:0]     dataHasDep;
reg [31:0]             data[LSB_SIZE-1:0];
reg [ROB_WIDTH-1:0]    dataConstrtId[LSB_SIZE-1:0];
reg [LSB_OP_WIDTH-1:0] op[LSB_SIZE-1:0];

wire [ROB_WIDTH-1:0] endIndexPlusThree = endIndex + 2'd3;
wire [ROB_WIDTH-1:0] endIndexPlusTwo   = endIndex + 2'd2;
wire [ROB_WIDTH-1:0] endIndexPlusOne   = endIndex + 1'd1;

assign full = (beginIndex == endIndexPlusThree) ||
              (beginIndex == endIndexPlusTwo) ||
              (beginIndex == endIndexPlusOne);

// Utensils
wire                    topValid      = (beginIndex != endIndex);
wire                    topReadWrite  = readWrite[beginIndex];
wire [ROB_WIDTH-1:0]    topRobId      = robId[beginIndex];
wire                    topReadyState = ready[beginIndex];
wire                    topBaseHasDep = baseHasDep[beginIndex];
wire [31:0]             topBaseAddr   = baseAddr[beginIndex];
wire [31:0]             topOffset     = offset[beginIndex];
wire [31:0]             topAddr       = topBaseAddr + topOffset;
wire                    topDataHasDep = dataHasDep[beginIndex];
wire [31:0]             topData       = data[beginIndex];
wire [LSB_OP_WIDTH-1:0] topOp         = op[beginIndex];
wire                    lastFinished  = dataValid | dataWriteSuc;
wire                    readyForNext  = topValid & topReady & (lastFinished | ~processing);

wire [31:0] signedByte    = {{24{1'b0}}, topData[31], topData[6:0]};
wire [31:0] signedHW      = {{16{1'b0}}, topData[31], topData[14:0]};
wire [1:0]  topAccessType = topOp == 3'b000 ? 2'b01 : // Byte
                            topOp == 3'b001 ? 2'b10 : // Half Word
                            topOp == 3'b010 ? 2'b11 :
                            topOp == 3'b011 ? 2'b01 : // Byte
                                              2'b10;  // Half Word;

wire isIoAddr = (topAddr[17:16] == 2'b11);
wire topReady = (!valid[beginIndex] || topBaseHasDep) ? 1'b0 :
                topReadWrite  ? isIoAddr ? topReadyState : 1'b1 // read
                              : topReadyState & ~topDataHasDep; // write

wire baseHasDepMerged = addBaseHasDep &&
                        !((dataValid && (addBaseConstrtId == updateRobIdReg)) ||
                          (rsUpdate && (addBaseConstrtId == rsRobIndex)));
wire dataHasDepMerged = addDataHasDep &&
                        !((dataValid && (addDataConstrtId == updateRobIdReg)) ||
                          (rsUpdate && (addDataConstrtId == rsRobIndex)));
wire [31:0] baseMerged = addBaseHasDep ?
                         (dataValid && (addBaseConstrtId == updateRobIdReg)) ? dataIn :
                         (rsUpdate && (addBaseConstrtId == rsRobIndex)) ? rsUpdateVal : 32'b0 :
                         addBase;
wire [31:0] dataMerged = addDataHasDep ?
                         (dataValid && (addDataConstrtId == updateRobIdReg)) ? dataIn :
                         (rsUpdate && (addDataConstrtId == rsRobIndex)) ? rsUpdateVal : 32'b0 :
                         addData;

integer i;
always @* begin
  if (robBeginValid) begin
    for (i = 0; i < LSB_SIZE; i = i + 1) begin
      if (robId[i] == robBeginId) begin
        ready[i] = 1'b1;
      end
    end
  end
end

always @(posedge clockIn) begin
  if (resetIn) begin
    beginIndex     <= {LSB_WIDTH{1'b0}};
    endIndex       <= {LSB_WIDTH{1'b0}};
    valid          <= {LSB_SIZE{1'b0}};
    ready          <= {LSB_SIZE{1'b0}};
    readWrite      <= {LSB_SIZE{1'b1}};
    baseHasDep     <= {LSB_SIZE{1'b1}};
    dataHasDep     <= {LSB_SIZE{1'b1}};
    updateRobIdReg <= {ROB_WIDTH{1'b0}};
    accessTypeReg  <= 2'b00;
    processing     <= 1'b0;
    processOpReg   <= {LSB_OP_WIDTH{1'b0}};
    readWriteReg   <= 1'b1;
    for (i = 0; i < LSB_SIZE; i = i + 1) begin
      robId[i]          <= {ROB_WIDTH{1'b0}};
      baseAddr[i]       <= 32'b0;
      baseConstrtId[i]  <= {ROB_WIDTH{1'b0}};
      offset[i]         <= 32'b0;
      data[i]           <= 32'b0;
      dataConstrtId[i]  <= {ROB_WIDTH{1'b0}};
      op[i]             <= {LSB_OP_WIDTH{1'b0}};
    end
  end else if (clearIn) begin
    for (i = 0; i < LSB_SIZE; i = i + 1) begin
      valid <= ready;
    end
    if (processing && ((readWriteReg == 1) || dataWriteSuc)) begin
      processing <= 1'b0;
    end
  end else begin
    // Handle the update data from the reservation station
    if (rsUpdate) begin
      for (i = 0; i < LSB_SIZE; i = i + 1) begin
        if (baseHasDep[i] && rsRobIndex == baseConstrtId[i]) begin
          baseAddr[i]   <= rsUpdateVal;
          baseHasDep[i] <= 1'b0;
        end
        if (dataHasDep[i] && rsRobIndex == dataConstrtId[i]) begin
          data[i]       <= rsUpdateVal;
          dataHasDep[i] <= 1'b0;
        end
      end
    end

    // Handle the update data from the DCache
    if (dataValid) begin
      for (i = 0; i < LSB_SIZE; i = i + 1) begin
        if (baseHasDep[i] && updateRobIdReg == baseConstrtId[i]) begin
          baseAddr[i]   <= dataIn;
          baseHasDep[i] <= 1'b0;
        end
        if (dataHasDep[i] && updateRobIdReg == dataConstrtId[i]) begin
          data[i]       <= dataIn;
          dataHasDep[i] <= 1'b0;
        end
      end
    end

    // Add new data to the buffer
    if (addValid) begin
      valid        [endIndex] <= 1'b1;
      ready        [endIndex] <= 1'b0; // No need to check whether the ready state is 1 or 0
      readWrite    [endIndex] <= addReadWrite;
      robId        [endIndex] <= addRobId;
      baseHasDep   [endIndex] <= baseHasDepMerged;
      baseAddr     [endIndex] <= baseMerged;
      baseConstrtId[endIndex] <= addBaseConstrtId;
      offset       [endIndex] <= addOffset;
      dataHasDep   [endIndex] <= dataHasDepMerged;
      data         [endIndex] <= dataMerged;
      dataConstrtId[endIndex] <= addDataConstrtId;
      op           [endIndex] <= addOp;
      endIndex <= endIndex + 1;
    end

    // Memeory access
    updateRobIdReg <= nextRobIdReg;
    if (readyForNext) begin
      dataOutReg        <= topData;
      accessTypeReg     <= topAccessType;
      readWriteReg      <= topReadWrite;
      dataAddrReg       <= topAddr;
      nextRobIdReg      <= topRobId;
      beginIndex        <= beginIndex + 1;
      processing        <= 1'b1;
      processOpReg      <= topOp;
      ready[beginIndex] <= 1'b0;
    end else begin
      accessTypeReg <= 2'b00;
      if (dataValid || dataWriteSuc) begin
        processing <= 1'b0;
      end
      if (topValid && !valid[beginIndex]) begin
        ready[beginIndex] <= 1'b1;
        beginIndex <= beginIndex + 1;
      end
    end
  end
end

endmodule
