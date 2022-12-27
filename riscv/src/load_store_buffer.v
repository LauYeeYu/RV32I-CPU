module LoadStoreBuffer #(
  parameter ROB_WIDTH = 4,
  parameter LSB_WIDTH = 4,
  parameter LSB_SIZE = 2**LSB_WIDTH,
  parameter ROB_OP_WIDTH = 2,
  parameter LSB_OP_WIDTH = 3
) (
  input  wire                 resetIn,      // resetIn
  input  wire                 clockIn,      // clockIn
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
  input wire [ROB_WIDTH-1:0] robBeginId, // begin index of the load & store buffer
  input wire                 beginValid, // has committed signal

  // Register File part
  input  wire [31:0] regValue, // register value of the destination register
  output wire [4:0]  regIndex, // register index of the destination register

  // Reservation Station part
  input  wire                    rsUpdate,    // reservation station update signal
  input  wire [ROB_WIDTH-1:0]    rsRobIndex,  // reservation station rob index
  input  wire [31:0]             rsUpdateVal, // reservation station value

  // Instruction Unit part
    input  wire                    addValid,     // Instruction Unit add valid signal
    input  wire                    addReadWrite, // Instruction Unit read/write select
    input  wire [ROB_WIDTH-1:0]    addRobId,     // Instruction Unit rob index
    input  wire                    addHasDep,    // Instruction Unit has dependency
    input  wire [31:0]             addBase,      // Instruction Unit add base addr
    input  wire [ROB_WIDTH-1:0]    addConstrtId, // Instruction Unit add constraint index (RoB)
    input  wire [31:0]             addOffset,    // Instruction Unit add offset
    input  wire [4:0]              addTarget,    // Instruction Unit add target register
    input  wire [LSB_OP_WIDTH-1:0] addOp,        // Instruction Unit add op
    output wire                    full          // full signal
);

reg [1:0]           accessTypeReg; // access type (none: 2'b00, byte: 2'b01, half word: 2'b10, word: 2'b11)
reg                 readWriteReg;  // read/write select (read: 1, write: 0)
reg [31:0]          dataAddrReg;   // data address
reg [31:0]          dataOutReg;    // data to write
reg                 updateReg;
reg [ROB_WIDTH-1:0] updateRobIdReg;
reg [31:0]          updateValReg;

assign accessType   = accessTypeReg;
assign readWriteOut = readWriteReg;
assign dataAddr     = dataAddrReg;
assign dataOut      = dataOutReg;
assign lsbUpdate    = updateReg;
assign lsbRobIndex  = updateRobIdReg;
assign lsbUpdateVal = updateValReg;

// FIFO
reg [LSB_WIDTH-1:0]    beginIndex;
reg [LSB_WIDTH-1:0]    endIndex;
reg [LSB_SIZE-1:0]     sentToDcache;
reg [LSB_SIZE-1:0]     readWrite; // 0: write, 1: read
reg [ROB_WIDTH-1:0]    robId[LSB_SIZE-1:0];
reg [LSB_SIZE-1:0]     hasDep;
reg [31:0]             baseAddr[LSB_SIZE-1:0];
reg [ROB_WIDTH-1:0]    constrtId[LSB_SIZE-1:0];
reg [31:0]             offset[LSB_SIZE-1:0];
reg [4:0]              target[LSB_SIZE-1:0];
reg [LSB_OP_WIDTH-1:0] op[LSB_SIZE-1:0];

assign regIndex = target[beginIndex];

wire [ROB_WIDTH-1:0] endIndexPlusThree = endIndex + 2'd3;

assign full = (beginIndex == endIndexPlusThree);

// Utensils
wire                    topValid     = (beginIndex != endIndex);
wire                    topSentToDc  = sentToDcache[beginIndex];
wire                    topReadWrite = readWrite[beginIndex];
wire [ROB_WIDTH-1:0]    topRobId     = robId[beginIndex];
wire                    topHasDep    = hasDep[beginIndex];
wire [31:0]             topBaseAddr  = baseAddr[beginIndex];
wire [31:0]             topOffset    = offset[beginIndex];
wire [31:0]             topAddr      = topBaseAddr + topOffset;
wire [LSB_OP_WIDTH-1:0] topOp        = op[beginIndex];

wire [31:0] signedByte    = {{24{1'b0}}, regValue[31], regValue[6:0]};
wire [31:0] signedHW      = {{16{1'b0}}, regValue[31], regValue[14:0]};
wire [1:0]  topAccessType = topOp == 3'b000 ? 2'b01 : // Byte
                                topOp == 3'b001 ? 2'b10 : // Half Word
                                topOp == 3'b010 ? 2'b11 :
                                topOp == 3'b011 ? 2'b01 : // Byte
                                                  2'b10;  // Half Word;

wire isIoAddr = (topAddr[17:16] == 2'b11);
wire ready = (topValid && !topHasDep) &&
             ((isIoAddr && beginValid && (robBeginId == topRobId)) || !isIoAddr);

integer i;
always @(posedge clockIn) begin
  if (resetIn) begin
    beginIndex <= {LSB_WIDTH{1'b0}};
    endIndex   <= {LSB_WIDTH{1'b0}};
  end else begin
    // Handle the update data from the reservation station
    if (rsUpdate) begin
      for (i = 0; i < LSB_SIZE; i = i + 1) begin
        if (hasDep[i] && rsRobIndex == constrtId[i]) begin
          baseAddr[i] <= rsUpdateVal;
          hasDep[i]   <= 1'b0;
        end
      end
    end

    // Add new data to the buffer
    if (addValid) begin
      sentToDcache[endIndex] <= 1'b0;
      readWrite   [endIndex] <= addReadWrite;
      robId       [endIndex] <= addRobId;
      hasDep      [endIndex] <= addHasDep;
      baseAddr    [endIndex] <= addBase;
      constrtId   [endIndex] <= addConstrtId;
      offset      [endIndex] <= addOffset;
      target      [endIndex] <= addTarget;
      op          [endIndex] <= addOp;
      endIndex <= endIndex + 1;
    end

    // Memeory access
    updateReg <= dataValid;
    updateValReg <= dataIn;
    if (ready) begin
      if (topSentToDc) begin
        accessTypeReg <= 2'b00;
        if (topReadWrite) begin // read
          if (dataValid) beginIndex <= beginIndex + 1;
        end else begin // write
          if (dataWriteSuc) beginIndex <= beginIndex + 1;
        end
      end else begin
        accessTypeReg            <= topAccessType;
        readWriteReg             <= topReadWrite;
        dataAddrReg              <= topAddr;
        dataOutReg               <= regValue;
        updateRobIdReg           <= topRobId;
        sentToDcache[beginIndex] <= 1'b1;
      end
    end else begin
      accessTypeReg <= 2'b00;
    end
  end
end

endmodule
