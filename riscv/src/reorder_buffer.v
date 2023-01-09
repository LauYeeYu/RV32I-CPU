`ifdef DEBUG
`define PRINT_REG_CHANGE
`define PRINT_WRONG_BRANCH
`endif
module ReorderBuffer #(
  parameter ROB_WIDTH = 4,
  parameter ROB_SIZE = 2**ROB_WIDTH,
  parameter ROB_OP_WIDTH = 2
) (
  input  wire        resetIn, // resetIn
  input  wire        clockIn, // clockIn
  input  wire        readyIn, // readyIn
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
  output wire                 beginValid,   // has committed signal

  // Instruction Unit part
  input  wire [ROB_WIDTH-1:0]    request,      // instruction unit request
  input  wire                    addValid,     // instruction unit add valid signal
  input  wire [ROB_WIDTH-1:0]    addIndex,     // instruction unit add index
  input  wire [ROB_OP_WIDTH-1:0] addType,      // instruction unit add type signal
  input  wire                    addReady,     // instruction unit add ready signal
  input  wire [31:0]             addValue,     // instruction unit add value signal
  input  wire                    addJump,      // instruction unit add jump signal
  input  wire [4:0]              addDest,      // instruction unit add destination register signal
  input  wire [31:0]             addAddr,      // instruction unit add address
  input  wire [31:0]             addInstrAddr, // instruction unit add instruction address
  output wire                    full,         // full signal
  output wire [ROB_WIDTH-1:0]    next,         // next index
  output wire                    reqReady,     // ready signal
  output wire [31:0]             reqValue,     // instruction unit value

  // Predictor part
  output wire        predictUpdValid, // predictor update valid signal
  output wire [31:0] updInstrAddr,    // instruction address
  output wire        jumpResult,      // jump result

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
reg                 predictUpdValidReg;
reg [31:0]          updInstrAddrReg;
reg                 jumpResultReg;
reg                 regUpdateValidReg;
reg [4:0]           regUpdateDestReg;
reg [31:0]          regValueReg;
reg [ROB_WIDTH-1:0] regUpdateRobIdReg;
reg [ROB_WIDTH-1:0] robBeginIdReg;
reg                 beginValidReg;

assign clear           = clearReg;
assign newPc           = newPcReg;
assign predictUpdValid = predictUpdValidReg;
assign updInstrAddr    = updInstrAddrReg;
assign jumpResult      = jumpResultReg;
assign regUpdateValid  = regUpdateValidReg;
assign regUpdateDest   = regUpdateDestReg;
assign regValue        = regValueReg;
assign regUpdateRobId  = regUpdateRobIdReg;

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
reg  [31:0]             instrAddr[ROB_SIZE-1:0];
wire                    topValid     = valid[beginIndex];
wire                    topReady     = ready[beginIndex];
wire                    topJump      = jump[beginIndex];
wire [ROB_OP_WIDTH-1:0] topType      = type[beginIndex];
wire [31:0]             topValue     = value[beginIndex];
wire [4:0]              topDestReg   = destReg[beginIndex];
wire [31:0]             topMissAddr  = missAddr[beginIndex];
wire [31:0]             topInstrAddr = instrAddr[beginIndex];
wire                    wrongBranch  = (topJump != topValue[0]);

wire notEmpty = (beginIndex != endIndex);
wire needUpdateReg = notEmpty && (topType == 2'b00) && topReady;
wire nextPredictUpdValid = notEmpty && (topType == 2'b01) && topReady;

wire [ROB_WIDTH-1:0] endIndexPlusThree = endIndex + 2'd3;
wire [ROB_WIDTH-1:0] endIndexPlusTwo   = endIndex + 2'd2;
wire [ROB_WIDTH-1:0] endIndexPlusOne   = endIndex + 1'd1;
wire [ROB_WIDTH-1:0] nextEndIndex      = addIndex + 1'b1;

assign full        = (beginIndex == endIndexPlusThree) ||
                     (beginIndex == endIndexPlusTwo) ||
                     (beginIndex == endIndexPlusOne);
assign next        = addValid ? endIndexPlusOne : endIndex;
assign reqReady    = ready[request] || (rsUpdate && rsRobIndex == request) || (lsbUpdate && lsbRobIndex == request);
assign reqValue    = (rsUpdate && rsRobIndex == request) ? rsUpdateVal :
                     (lsbUpdate && lsbRobIndex == request) ? lsbUpdateVal : value[request];
assign rs1Ready    = (valid[rs1Dep] && ready[rs1Dep]) ||
                     (rsUpdate && rsRobIndex == rs1Dep) ||
                     (lsbUpdate && lsbRobIndex == rs1Dep) ||
                     (addValid && addReady && addIndex == rs1Dep);
assign rs1Value    = (rsUpdate && rsRobIndex == rs1Dep) ? rsUpdateVal :
                     (lsbUpdate && lsbRobIndex == rs1Dep) ? lsbUpdateVal :
                     (addValid && addReady && addIndex == rs1Dep) ? addValue : value[rs1Dep];
assign rs2Ready    = (valid[rs2Dep] && ready[rs2Dep]) ||
                     (rsUpdate && rsRobIndex == rs2Dep) ||
                     (lsbUpdate && lsbRobIndex == rs2Dep) ||
                     (addValid && addReady && addIndex == rs2Dep);
assign rs2Value    = (rsUpdate && rsRobIndex == rs2Dep) ? rsUpdateVal :
                     (lsbUpdate && lsbRobIndex == rs2Dep) ? lsbUpdateVal :
                     (addValid && addReady && addIndex == rs2Dep) ? addValue : value[rs2Dep];
assign robBeginId  = robBeginIdReg;
assign beginValid  = beginValidReg;

always @(posedge clockIn) begin
  if (resetIn) begin
    beginIndex         <= {ROB_WIDTH{1'b0}};
    endIndex           <= {ROB_WIDTH{1'b0}};
    valid              <= {ROB_SIZE{1'b0}};
    ready              <= {ROB_SIZE{1'b0}};
    clearReg           <= 1'b0;
    regUpdateValidReg  <= 1'b0;
    predictUpdValidReg <= 1'b0;
    robBeginIdReg      <= {ROB_WIDTH{1'b0}};
    beginValidReg      <= 1'b0;
  end else if (readyIn) begin
    if (clearReg) begin
      clearReg           <= 1'b0;
      regUpdateValidReg  <= 1'b0;
      predictUpdValidReg <= 1'b0;
      robBeginIdReg      <= {ROB_WIDTH{1'b0}};
      beginValidReg      <= 1'b0;
      beginIndex         <= {ROB_WIDTH{1'b0}};
      endIndex           <= {ROB_WIDTH{1'b0}};
      valid              <= {ROB_SIZE{1'b0}};
    end else begin
      if (addValid) begin
        valid    [addIndex] <= 1'b1;
        ready    [addIndex] <= addReady;
        jump     [addIndex] <= addJump;
        type     [addIndex] <= addType;
        value    [addIndex] <= addValue;
        destReg  [addIndex] <= addDest;
        missAddr [addIndex] <= addAddr;
        instrAddr[addIndex] <= addInstrAddr;
        endIndex            <= nextEndIndex;
      end
      // Update data from reservation station
      if (rsUpdate) begin
        value[rsRobIndex] <= rsUpdateVal;
        ready[rsRobIndex] <= 1'b1;
      end
      // Update data from load & store buffer
      if (lsbUpdate) begin
        value[lsbRobIndex] <= lsbUpdateVal;
        ready[lsbRobIndex] <= 1'b1;
      end
      if (notEmpty) begin
        robBeginIdReg      <= beginIndex;
        beginValidReg      <= 1'b1;
        regUpdateValidReg  <= needUpdateReg;
        predictUpdValidReg <= nextPredictUpdValid;
        case (topType)
          2'b00: begin // register write
            if (topReady) begin
`ifdef PRINT_REG_CHANGE
              $display("ROB: write reg %d with value %h", topDestReg, topValue);
`endif
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
              updInstrAddrReg   <= topInstrAddr;
              jumpResultReg     <= topValue[0];
              if (wrongBranch) begin
`ifdef PRINT_WRONG_BRANCH
                $display("ROB: wrong branch, correct to %h", topMissAddr);
`endif
                beginIndex <= {ROB_WIDTH{1'b0}};
                endIndex   <= {ROB_WIDTH{1'b0}};
                valid      <= {ROB_SIZE{1'b0}};
                newPcReg   <= topMissAddr;
                clearReg   <= 1'b1;
              end
            end
          end
          2'b10: begin
            beginIndex <= beginIndex + 1'b1;
          end
        endcase
      end else begin
        robBeginIdReg      <= {ROB_WIDTH{1'b0}};
        beginValidReg      <= 1'b0;
        regUpdateValidReg  <= 1'b0;
        predictUpdValidReg <= 1'b0;
      end
    end
  end
end

endmodule
