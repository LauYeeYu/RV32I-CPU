module RegisterFile #(
  parameter ROB_WIDTH = 4
) (
  input wire       resetIn, // resetIn
  input wire       clockIn, // clockIn
  input wire [4:0] reg1,    // register 1
  input wire [4:0] reg2,    // register 2

  // Load & Store Buffer part
  input  wire [4:0]  lsbRegIndex, // register index of the destination register
  output wire [31:0] lsbRegValue, // register value of the destination register

  // Instruction Unit part
  input  wire                 rfUpdateValid, // instruction unit update valid signal
  input  wire [4:0]           rfUpdateDest,  // instruction unit update destination
  input  wire [ROB_WIDTH-1:0] rfUpdateRobId, // instruction unit update value
  output wire                 rs1Dirty,      // rs1 dirty signal
  output wire [ROB_WIDTH-1:0] rs1Dependency, // rs1 dependency
  output wire [31:0]          rs1Value,      // rs1 value
  output wire                 rs2Dirty,      // rs2 dirty signal
  output wire [ROB_WIDTH-1:0] rs2Dependency, // rs2 dependency
  output wire [31:0]          rs2Value,      // rs2 value

  // Reorder Buffer part
  input  wire                 regUpdateValid, // reorder buffer update valid signal
  input  wire [4:0]           regUpdateDest,  // reorder buffer update destination
  input  wire [31:0]          regUpdateValue, // reorder buffer update value
  input  wire [ROB_WIDTH-1:0] regUpdateRobId, // reorder buffer update rob id
  input  wire                 robRs1Ready,    // rs1 ready signal
  input  wire [31:0]          robRs1Value,    // rs1 value
  output wire [ROB_WIDTH-1:0] robRs1Dep,      // rs1 dependency
  input  wire                 robRs2Ready,    // rs2 ready signal
  input  wire [31:0]          robRs2Value,    // rs2 value
  output wire [ROB_WIDTH-1:0] robRs2Dep       // rs2 dependency
);

// Registers and their constraints
reg [31:0]          register[31:0];
reg [31:0]          hasconstraint;
reg [ROB_WIDTH-1:0] constraintId[31:0];

reg [4:0]           reg1Reg;
reg [4:0]           reg2Reg;

// Update register file
always @* begin
  if (rfUpdateValid && rfUpdateDest != 5'b00000) begin
    constraintId [rfUpdateDest] <= rfUpdateRobId;
    hasconstraint[rfUpdateDest] <= 1'b1;
  end
end

// Update the value of register
always @* begin
  if (regUpdateValid && rfUpdateDest != 5'b00000) begin
    register[regUpdateDest] <= regUpdateValue;
    if (regUpdateRobId == constraintId[regUpdateDest] &&
        !(rfUpdateValid && rfUpdateDest == regUpdateDest)) begin
      hasconstraint[regUpdateDest] <= 1'b0;
    end
  end
end

// Handle the request from load & store buffer
assign lsbRegValue = register[lsbRegIndex];

// Handle the request from instruction unit
assign robRs1Dep = constraintId[reg1Reg];
assign robRs2Dep = constraintId[reg2Reg];
assign rs1Dirty  = hasconstraint[reg1Reg] & ~robRs1Ready;
assign rs2Dirty  = hasconstraint[reg2Reg] & ~robRs2Ready;
assign rs1Dependency = constraintId[reg1Reg];
assign rs2Dependency = constraintId[reg2Reg];
assign rs1Value = hasconstraint ? robRs1Value : register[reg1Reg];
assign rs2Value = hasconstraint ? robRs2Value : register[reg2Reg];

// The daemon for register file
integer i;
always @(posedge clockIn) begin
  if (resetIn) begin
    for (i = 0; i < 32; i = i + 1) begin
      register[i] <= 32'b0;
    end
    hasconstraint <= {32{1'b0}};
  end else begin
    reg1Reg <= reg1;
    reg2Reg <= reg2;
  end
end
endmodule
