module ReservationStation #(
  parameter RS_OP_WIDTH = 4,
  parameter RS_WIDTH = 4,
  parameter ROB_WIDTH = 4
) (
  input  wire resetIn,   // reset signal
  input  wire clockIn,   // clock signal

  // Instruction Unit part
  input  wire                   addValid,    // add valid signal
  input  wire [RS_OP_WIDTH-1:0] addOp,       // add op
  input  wire [ROB_WIDTH-1:0]   addRobIndex, // add rob index
  input  wire [31:0]            addVal1,     // add value1
  input  wire                   addHasDep1,  // add value1 dependency
  input  wire [ROB_WIDTH-1:0]   addConstrt1, // add value1 constraint
  input  wire [31:0]            addVal2,     // add value2
  input  wire                   addHasDep2,  // add value2 dependency
  input  wire [ROB_WIDTH-1:0]   addConstrt2, // add value2 constraint
  output wire                   full,        // full signal
  output wire                   update,      // update signal
  output wire [ROB_WIDTH-1:0]   updateRobId, // rob index
  output wire [31:0]            updateVal,   // value

  // Load & Store Buffer part
  input  wire                 lsbUpdate,    // load & store buffer update signal
  input  wire [ROB_WIDTH-1:0] lsbRobIndex,  // load & store buffer rob index
  input  wire [31:0]          lsbUpdateVal  // load & store buffer value
);

parameter SUPPORTED_OPS = 12;

parameter ADD = 4'b0000;
parameter SUB = 4'b0001;
parameter XOR = 4'b0010;
parameter OR  = 4'b0011;
parameter AND = 4'b0100;
parameter SLL = 4'b0101;
parameter SRL = 4'b0110;
parameter SRA = 4'b0111;
parameter EQ  = 4'b1000;
parameter NE  = 4'b1001;
parameter LT  = 4'b1010;
parameter LTU = 4'b1011;

// ALU section
reg                    calculating;
reg  [31:0]            v1Cal;
reg  [31:0]            v2Cal;
reg  [ROB_WIDTH-1:0]   robIdCal;
reg  [RS_WIDTH-1:0]    rsIdCal;
reg  [RS_OP_WIDTH-1:0] opCal;
wire [31:0]            aluResult[SUPPORTED_OPS-1:0];
wire [31:0]            resultCal = aluResult[opCal];

assign aluResult[ADD] = v1Cal + v2Cal;
assign aluResult[SUB] = v1Cal - v2Cal;
assign aluResult[XOR] = v1Cal ^ v2Cal;
assign aluResult[OR]  = v1Cal | v2Cal;
assign aluResult[AND] = v1Cal & v2Cal;
assign aluResult[SLL] = v1Cal << v2Cal;
assign aluResult[SRL] = v1Cal >> v2Cal;
assign aluResult[SRA] = v1Cal >>> v2Cal;
assign aluResult[EQ]  = v1Cal  == v2Cal ? 32'b1 : 32'b0;
assign aluResult[NE]  = v1Cal  != v2Cal ? 32'b1 : 32'b0;
assign aluResult[LT]  = $signed(v1Cal) < $signed(v2Cal) ? 32'b1 : 32'b0;
assign aluResult[LTU] = v1Cal < v2Cal ? 32'b1 : 32'b0;

// Reservation Station section
reg                 updateValidReg;
reg [ROB_WIDTH-1:0] updateRobIndexReg;
reg [31:0]          updateValReg;

assign update      = updateValidReg;
assign updateRobId = updateRobIndexReg;
assign updateVal   = updateValReg;

// internal data
reg  [RS_WIDTH-1:0]    occupied;
reg  [2**RS_WIDTH-1:0] valid;
reg  [ROB_WIDTH-1:0]   robIndex [2**RS_WIDTH-1:0];
reg  [31:0]            value1   [2**RS_WIDTH-1:0];
reg  [2**RS_WIDTH-1:0] hasDep1;
reg  [ROB_WIDTH-1:0]   constrt1 [2**RS_WIDTH-1:0];
reg  [31:0]            value2   [2**RS_WIDTH-1:0];
reg  [2**RS_WIDTH-1:0] hasDep2;
reg  [ROB_WIDTH-1:0]   constrt2 [2**RS_WIDTH-1:0];
reg  [RS_OP_WIDTH-1:0] op       [2**RS_WIDTH-1:0];
wire [2**RS_WIDTH-1:0] ready = ~hasDep1 & ~hasDep2;

wire hasDep1Merged = addHasDep1 &&
                     !((lsbUpdate   && (addConstrt1 == lsbRobIndex)) ||
                       (calculating && (addConstrt1 == robIdCal)));
wire hasDep2Merged = addHasDep2 &&
                      !((lsbUpdate   && (addConstrt2 == lsbRobIndex)) &&
                        (calculating && (addConstrt2 == robIdCal)));
wire [31:0] value1Merged = addHasDep1 ?
                             (lsbUpdate   && (addConstrt1 == lsbRobIndex)) ? lsbUpdateVal :
                             (calculating && (addConstrt1 == robIdCal)) ? resultCal : 32'b0 :
                           addVal1;
wire [31:0] value2Merged = addHasDep2 ?
                             (lsbUpdate   && (addConstrt2 == lsbRobIndex)) ? lsbUpdateVal :
                             (calculating && (addConstrt2 == robIdCal)) ? resultCal : 32'b0 :
                            addVal2;
// The time latency on the nextFree can be reduced by using binary search
wire [RS_WIDTH-1:0] nextFree = ~valid[0]  ? 4'b0000 :
                               ~valid[1]  ? 4'b0001 :
                               ~valid[2]  ? 4'b0010 :
                               ~valid[3]  ? 4'b0011 :
                               ~valid[4]  ? 4'b0100 :
                               ~valid[5]  ? 4'b0101 :
                               ~valid[6]  ? 4'b0110 :
                               ~valid[7]  ? 4'b0111 :
                               ~valid[8]  ? 4'b1000 :
                               ~valid[9]  ? 4'b1001 :
                               ~valid[10] ? 4'b1010 :
                               ~valid[11] ? 4'b1011 :
                               ~valid[12] ? 4'b1100 :
                               ~valid[13] ? 4'b1101 :
                               ~valid[14] ? 4'b1110 :
                                            4'b1111;
wire hasNextCalc = (ready != 0);
wire [RS_WIDTH-1:0] nextCalc = ready[0]  ? 4'b0000 :
                               ready[1]  ? 4'b0001 :
                               ready[2]  ? 4'b0010 :
                               ready[3]  ? 4'b0011 :
                               ready[4]  ? 4'b0100 :
                               ready[5]  ? 4'b0101 :
                               ready[6]  ? 4'b0110 :
                               ready[7]  ? 4'b0111 :
                               ready[8]  ? 4'b1000 :
                               ready[9]  ? 4'b1001 :
                               ready[10] ? 4'b1010 :
                               ready[11] ? 4'b1011 :
                               ready[12] ? 4'b1100 :
                               ready[13] ? 4'b1101 :
                               ready[14] ? 4'b1110 :
                                           4'b1111;
wire v1ToCalc                    = value1[nextCalc];
wire v2ToCalc                    = value2[nextCalc];
wire opToCalc                    = op[nextCalc];
wire robIdToCalc                 = robIndex[nextCalc];
wire [RS_WIDTH-1:0] occupiedNext = occupied + (addValid ? 1'b1 : 1'b0)
                                            - (hasNextCalc ? 1'b1 : 1'b0);

assign full = (occupied > 13);

integer i;
always @(posedge clockIn) begin
  if (resetIn) begin
    valid          <= {2**RS_WIDTH{1'b0}};
    occupied       <= {RS_WIDTH{1'b0}};
    hasDep1        <= {2**RS_WIDTH{1'b0}};
    hasDep2        <= {2**RS_WIDTH{1'b0}};
    calculating    <= 0;
    updateValidReg <= 0;
  end else begin
    if (addValid) begin
      valid    [nextFree] <= 1'b1;
      robIndex [nextFree] <= addRobIndex;
      value1   [nextFree] <= value1Merged;
      hasDep1  [nextFree] <= hasDep1Merged;
      constrt1 [nextFree] <= addConstrt1;
      value2   [nextFree] <= value2Merged;
      hasDep2  [nextFree] <= hasDep2Merged;
      constrt2 [nextFree] <= addConstrt2;
      op       [nextFree] <= addOp;
    end
    occupied <= occupiedNext;

    // send the update data out
    updateValidReg    <= calculating;
    updateRobIndexReg <= robIdCal;
    updateValReg      <= resultCal;

    // Updating the dependencies
    for (i = 0; i < 2**RS_WIDTH; i = i + 1) begin
      if (calculating && valid[i] && hasDep1[i] && (constrt1[i] == robIdCal)) begin
        value1[i]  <= resultCal;
        hasDep1[i] <= 0;
      end
      if (calculating && valid[i] && hasDep2[i] && (constrt2[i] == robIdCal)) begin
        value2[i]  <= resultCal;
        hasDep2[i] <= 0;
      end
      if (lsbUpdate && valid[i] && hasDep1[i] && (constrt1[i] == lsbRobIndex)) begin
        value1[i]  <= lsbUpdateVal;
        hasDep1[i] <= 0;
      end
      if (lsbUpdate && valid[i] && hasDep2[i] && (constrt2[i] == lsbRobIndex)) begin
        value2[i]  <= lsbUpdateVal;
        hasDep2[i] <= 0;
      end
    end

    // Dispatch the nextCalc
    calculating       <= hasNextCalc;
    v1Cal             <= v1ToCalc;
    v2Cal             <= v2ToCalc;
    opCal             <= opToCalc;
    robIdCal          <= robIdToCalc;
    rsIdCal           <= nextCalc;
    valid[nextCalc]   <= 0;
    hasDep1[nextCalc] <= 1;
    hasDep2[nextCalc] <= 1;
  end
end

endmodule
