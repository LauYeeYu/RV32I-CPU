module ReorderBuffer #(
  parameter ROB_WIDTH = 4,
  parameter ROB_SIZE = 2**ROB_WIDTH,
  parameter ROB_OP_WIDTH = 2
) (
  input  wire        resetIn, // resetIn
  input  wire        clockIn, // clockIn
  output wire        clear,   // clear signal (when branch prediction is wrong)
  output wire [31:0] newPc,   // the correct PC value

  // Reservation Station part
  input  wire                 rsUpdate,    // reservation station update signal
  input  wire [ROB_WIDTH-1:0] rsRobIndex,  // reservation station rob index
  input  wire [31:0]          rsUpdateVal, // reservation station value

  // Load & Store Buffer part
  input  wire                 lsbUpdate,    // load & store buffer update signal
  input  wire [ROB_WIDTH-1:0] lsbRobIndex,  // load & store buffer rob index
  input  wire [31:0]          lsbUpdateVal, // load & store buffer value
  output wire [ROB_WIDTH-1:0] robBeginId,   // begin index of the load & store buffer
  output wire                 writeValid,   // has committed signal

  // Instruction Unit part
  input  wire [ROB_WIDTH-1:0]    request,  // instruction unit request
  input  wire                    addValid, // instruction unit add valid signal
  input  wire [ROB_WIDTH-1:0]    addIndex, // instruction unit add index
  input  wire [ROB_OP_WIDTH-1:0] addType,  // instruction unit add type signal
  input  wire                    addReady, // instruction unit add ready signal
  input  wire [31:0]             addValue, // instruction unit add value signal
  input  wire                    addjump,  // instruction unit add jump signal
  input  wire [4:0]              addDest,  // instruction unit add destination register signal
  input  wire [31:0]             addAddr,  // instruction unit add address
  output wire                    full,     // full signal
  output wire [ROB_WIDTH-1:0]    next,     // next index
  output wire                    reqReady, // ready signal
  output wire [31:0]             reqValue, // instruction unit value

  // Register File part
  output wire                 regUpdateValid, // reorder buffer update valid signal
  output wire [4:0]           regUpdateDest,  // reorder buffer update destination
  output wire [31:0]          regValue,       // reorder buffer update value
  output wire [ROB_WIDTH-1:0] regUpdateRobId, // reorder buffer update rob id
  input  wire [ROB_WIDTH-1:0] rs1Dep,         // rs1 dependency
  output wire                 rs1Ready,       // rs1 ready signal
  output wire [31:0]          rs1Value,       // rs1 value
  input  wire [ROB_WIDTH-1:0] rs2Dep,         // rs2 dependency
  output wire                 rs2Ready,       // rs2 ready signal
  output wire [31:0]          rs2Value        // rs2 value
);

reg                 clearReg;
reg [31:0]          newPcReg;
reg                 regUpdateValidReg;
reg [4:0]           regUpdateDestReg;
reg [31:0]          regValueReg;
reg [ROB_WIDTH-1:0] regUpdateRobIdReg;

assign clear          = clearReg;
assign newPc          = newPcReg;
assign regUpdateValid = regUpdateValidReg;
assign regUpdateDest  = regUpdateDestReg;
assign regValue       = regValueReg;
assign regUpdateRobId = regUpdateRobIdReg;

// FIFO
reg  [ROB_WIDTH-1:0]    beginIndex;
reg  [ROB_WIDTH-1:0]    endIndex;
reg  [ROB_SIZE-1:0]     valid;
reg  [ROB_SIZE-1:0]     ready;
reg  [ROB_SIZE-1:0]     jump;
reg  [ROB_OP_WIDTH-1:0] type[ROB_SIZE-1:0];
reg  [31:0]             value[ROB_SIZE-1:0];
reg  [4:0]              destReg[ROB_SIZE-1:0];
reg  [31:0]             missAddr[ROB_SIZE-1:0];
wire                    topValid    = valid[beginIndex];
wire                    topReady    = ready[beginIndex];
wire                    topJump     = jump[beginIndex];
wire [ROB_OP_WIDTH-1:0] topType     = type[beginIndex];
wire [31:0]             topValue    = value[beginIndex];
wire [4:0]              topDestReg  = destReg[beginIndex];
wire [31:0]             topMissAddr = missAddr[beginIndex];

wire notEmpty = (beginIndex != endIndex);
wire needUpdateReg = notEmpty && (topType == 2'b00) && topReady;

wire [ROB_WIDTH-1:0] endIndexPlusThree = endIndex + 2'd3;
wire [ROB_WIDTH-1:0] nextEndIndex = addIndex + 1'b1;

assign full        = (beginIndex == endIndexPlusThree);
assign next        = endIndex;
assign reqReady    = ready[request];
assign reqValue    = value[request];
assign rs1Ready    = valid[rs1Dep] & ready[rs1Dep];
assign rs1Value    = value[rs1Dep];
assign rs2Ready    = valid[rs1Dep] & ready[rs2Dep];
assign rs2Value    = value[rs2Dep];
assign robBeginId  = beginIndex;
assign writeValid  = notEmpty;

always @* begin
  if (addValid) begin
    valid   [addIndex] <= 1'b1;
    ready   [addIndex] <= addReady;
    jump    [addIndex] <= addjump;
    type    [addIndex] <= addType;
    value   [addIndex] <= addValue;
    destReg [addIndex] <= addDest;
    missAddr[addIndex] <= addAddr;
    endIndex           <= nextEndIndex;
  end
end

// Update data from reservation station
always @* begin
  if (rsUpdate) begin
    value[rsRobIndex] <= rsUpdateVal;
    ready[rsRobIndex] <= 1'b1;
  end
end

// Update data from load & store buffer
always @* begin
  if (lsbUpdate) begin
    value[lsbRobIndex] <= lsbUpdateVal;
    ready[lsbRobIndex] <= 1'b1;
  end
end

always @(posedge clockIn) begin
  if (resetIn) begin
    beginIndex        <= {ROB_WIDTH{1'b0}};
    endIndex          <= {ROB_WIDTH{1'b0}};
    valid             <= {ROB_SIZE{1'b0}};
    clearReg          <= 1'b0;
    regUpdateValidReg <= 1'b0;
  end else if (clearReg) begin
    clearReg          <= 1'b0;
    regUpdateValidReg <= 1'b0;
  end else if (notEmpty) begin
    regUpdateValidReg <= needUpdateReg;
    case (topType)
      2'b00: begin // register write
        if (ready) begin
          valid[beginIndex] <= 1'b0;
          beginIndex        <= beginIndex + 1'b1;
          regUpdateDestReg  <= topDestReg;
          regValueReg       <= topValue;
          regUpdateRobIdReg <= beginIndex;
        end
      end
      2'b01: begin // branch
        if (topReady) begin
          valid[beginIndex] <= 1'b0;
          beginIndex        <= beginIndex + 1'b1;
          if (topJump != value[0]) begin
            beginIndex <= {ROB_WIDTH{1'b0}};
            endIndex   <= {ROB_WIDTH{1'b0}};
            valid      <= {ROB_SIZE{1'b0}};
            newPcReg   <= topMissAddr;
            clearReg   <= 1'b1;
          end
        end
      end
    endcase
  end else begin
    regUpdateValidReg <= 1'b0;
  end
end

endmodule
