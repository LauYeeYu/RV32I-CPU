module RegisterFile #(
  parameter ROB_WIDTH = 4
) (
  input wire       resetIn, // resetIn
  input wire       clockIn, // clockIn
  input wire       clearIn, // clearIn
  input wire       readyIn, // readyIn
  input wire [4:0] reg1,    // register 1
  input wire [4:0] reg2,    // register 2

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

integer i;
always @(posedge clockIn) begin
  if (resetIn) begin
    for (i = 0; i < 32; i = i + 1) begin
      register[i]     <= 32'b0;
      constraintId[i] <= {ROB_WIDTH{1'b0}};
    end
    hasconstraint <= {32{1'b0}};
    reg1Reg <= 5'b00000;
    reg2Reg <= 5'b00000;
  end else if (clearIn) begin
    hasconstraint <= {32{1'b0}};
  end else if (readyIn) begin
    reg1Reg <= reg1;
    reg2Reg <= reg2;
    // Update register file
    if (rfUpdateValid && rfUpdateDest != 5'b00000) begin
      constraintId [rfUpdateDest] <= rfUpdateRobId;
      hasconstraint[rfUpdateDest] <= 1'b1;
    end
    // Update the value of register
    if (regUpdateValid && regUpdateDest != 5'b00000) begin
      register[regUpdateDest] <= regUpdateValue;
      if (regUpdateRobId == constraintId[regUpdateDest] &&
          !(rfUpdateValid && rfUpdateDest == regUpdateDest)) begin
        hasconstraint[regUpdateDest] <= 1'b0;
      end
    end
  end
end

// Handle the request from instruction unit
wire hasConstraintReg1 = hasconstraint[reg1Reg];
wire hasConstraintReg2 = hasconstraint[reg2Reg];
wire rfMatch1 = (rfUpdateValid && rfUpdateDest != 5'b00000 && reg1Reg == rfUpdateDest);
wire rfMatch2 = (rfUpdateValid && rfUpdateDest != 5'b00000 && reg2Reg == rfUpdateDest);
wire regUpdMatch1 = (regUpdateValid && regUpdateDest != 5'b00000 && reg1Reg == regUpdateDest &&
                     regUpdateRobId == constraintId[regUpdateDest]);
wire regUpdMatch2 = (regUpdateValid && regUpdateDest != 5'b00000 && reg2Reg == regUpdateDest &&
                      regUpdateRobId == constraintId[regUpdateDest]);
assign robRs1Dep = rfMatch1 ? rfUpdateRobId : constraintId[reg1Reg];
assign robRs2Dep = rfMatch2 ? rfUpdateRobId : constraintId[reg2Reg];
wire hasconstraint1 = rfMatch1 ? 1'b1 : regUpdMatch1 ? 1'b0 : hasConstraintReg1;
wire hasconstraint2 = rfMatch2 ? 1'b1 : regUpdMatch2 ? 1'b0 : hasConstraintReg2;
assign rs1Dirty  = hasconstraint1 & ~robRs1Ready;
assign rs2Dirty  = hasconstraint2 & ~robRs2Ready;
assign rs1Dependency = robRs1Dep;
assign rs2Dependency = robRs2Dep;
assign rs1Value = rfMatch1 ? robRs1Value : regUpdMatch1 ? regUpdateValue : hasConstraintReg1 ? robRs1Value : register[reg1Reg];
assign rs2Value = rfMatch2 ? robRs2Value : regUpdMatch2 ? regUpdateValue : hasConstraintReg2 ? robRs2Value : register[reg2Reg];

// Register values
`ifdef DEBUG
wire [31:0] reg0Value = register[0];
wire [31:0] reg1Value = register[1];
wire [31:0] reg2Value = register[2];
wire [31:0] reg3Value = register[3];
wire [31:0] reg4Value = register[4];
wire [31:0] reg5Value = register[5];
wire [31:0] reg6Value = register[6];
wire [31:0] reg7Value = register[7];
wire [31:0] reg8Value = register[8];
wire [31:0] reg9Value = register[9];
wire [31:0] reg10Value = register[10];
wire [31:0] reg11Value = register[11];
wire [31:0] reg12Value = register[12];
wire [31:0] reg13Value = register[13];
wire [31:0] reg14Value = register[14];
wire [31:0] reg15Value = register[15];
wire [31:0] reg16Value = register[16];
wire [31:0] reg17Value = register[17];
wire [31:0] reg18Value = register[18];
wire [31:0] reg19Value = register[19];
wire [31:0] reg20Value = register[20];
wire [31:0] reg21Value = register[21];
wire [31:0] reg22Value = register[22];
wire [31:0] reg23Value = register[23];
wire [31:0] reg24Value = register[24];
wire [31:0] reg25Value = register[25];
wire [31:0] reg26Value = register[26];
wire [31:0] reg27Value = register[27];
wire [31:0] reg28Value = register[28];
wire [31:0] reg29Value = register[29];
wire [31:0] reg30Value = register[30];
wire [31:0] reg31Value = register[31];
`endif

// The daemon for register file
always @(posedge clockIn) begin
  if (resetIn) begin
  end else if (readyIn) begin
  end
end
endmodule
