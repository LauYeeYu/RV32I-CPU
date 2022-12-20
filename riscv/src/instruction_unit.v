module InstructionUnit#(
  parameter ROB_WIDTH = 4
) (
  input  wire                 resetIn,       // resetIn
  input  wire                 clockIn,       // clockIn
  input  wire                 instrInValid,  // instruction valid signal (icache)
  input  wire [31:0]          instrIn,       // data valid signal (icache)
  input  wire [31:0]          instrAddr,     // instruction address (icache)

  // Reservation Station part
  input  wire                 rsFull,        // reservation station full signal
  input  wire                 rsUpdate,      // reservation station update signal
  input  wire [ROB_WIDTH-1:0] rsRobIndex,    // reservation station rob index
  input  wire [31:0]          rsUpdateVal,   // reservation station value
  output wire                 rsAddValid,    // reservation station add valid signal
  output wire [3:0]           rsAddOp,       // reservation station add op
  output wire [ROB_WIDTH-1:0] rsAddRobIndex, // reservation station add rob index
  output wire [31:0]          rsAddVal1,     // reservation station add value1
  output wire                 rsAddHasDep1,  // reservation station add value1 dependency
  output wire [ROB_WIDTH-1:0] rsAddConstrt1, // reservation station add value1 constraint
  output wire [31:0]          rsAddVal2,     // reservation station add value2
  output wire                 rsAddHasDep2,  // reservation station add value2 dependency
  output wire [ROB_WIDTH-1:0] rsAddConstrt2, // reservation station add value2 constraint

  // Reorder Buffer part
  input  wire                 robFull,       // reorder buffer full signal
  input  wire [ROB_WIDTH-1:0] robNext,       // reorder buffer next index
  input  wire                 robReady,      // reorder buffer ready signal
  input  wire [31:0]          robValue,      // reorder buffer value
  output wire [ROB_WIDTH-1:0] robRequest,    // reorder buffer request
  output wire                 robAddValid,   // reorder buffer add valid signal
  output wire [1:0]           robAddType,    // reorder buffer add type signal
  output wire                 robAddReady,   // reorder buffer add ready signal
  output wire [31:0]          robAddValue,   // reorder buffer add value signal
  output wire                 robAddDest,    // reorder buffer add destination register signal
  output wire [31:0]          robAddAddr,    // reorder buffer add address

  // Load/Store Buffer part
  input  wire                 lsbFull,       // load/store buffer full signal
  input  wire                 lsbUpdate,     // load/store buffer update signal
  input  wire [ROB_WIDTH-1:0] lsbRobIndex,   // load/store buffer rob index
  input  wire [31:0]          lsbUpdateVal,  // load/store buffer value

  // Register File part
  input  wire                 rs1Dirty,      // rs1 dirty signal
  input  wire [ROB_WIDTH-1:0] rs1Dependency, // rs1 dependency
  input  wire [31:0]          rs1Value,      // rs1 value
  input  wire                 rs2Dirty,      // rs2 dirty signal
  input  wire [ROB_WIDTH-1:0] rs2Dependency, // rs2 dependency
  input  wire [31:0]          rs2Value,      // rs2 value
  output wire                 rfUpdateValid, // register file update valid signal
  output wire [4:0]           rfUpdateDest,  // register file update destination
  output wire [ROB_WIDTH-1:0] rfUpdateIndex, // register file update value

  // Predictor part
  input  wire                 jump,          // jump signal
  output wire                 instrOutValid, // instruction output valid signal (PC)
  output wire [31:0]          instrAddrOut   // instruction address (PC)
);

reg [31:0]          PC;
reg [31:0]          instrReg; // for instrction decode and issue
reg [31:0]          instrAddrReg;
reg                 instrRegValid;
reg                 stall;
reg [ROB_WIDTH-1:0] stallDependency;
reg                 pending; // pending for the next PC information
reg                 robAddValidReg;
reg [1:0]           robAddTypeReg;
reg                 robAddReadyReg;
reg [31:0]          robValueReg;
reg [4:0]           destReg;
reg [31:0]          robAddrReg;
reg                 rfUpdateValidReg;
reg                 rsAddValidReg;
reg [3:0]           rsAddOpReg;
reg [ROB_WIDTH-1:0] rsAddRobIndexReg;
reg [31:0]          rsAddVal1Reg;
reg                 rsAddHasDep1Reg;
reg [ROB_WIDTH-1:0] rsAddConstrt1Reg;
reg [31:0]          rsAddVal2Reg;
reg                 rsAddHasDep2Reg;
reg [ROB_WIDTH-1:0] rsAddConstrt2Reg;

assign instrOutValid = ~stall & ~pending;
assign instrAddrOut  = PC;
assign robRequest    = stallDependency;
assign robAddValid   = robAddValidReg;
assign robAddType    = robAddTypeReg;
assign robAddReady   = robAddReadyReg;
assign robAddValue   = robValueReg;
assign robAddDest    = destReg;
assign robAddAddr    = robAddrReg;
assign rfUpdateIndex = robNext;
assign rfUpdateDest  = destReg;
assign rfUpdateValid = rfUpdateValidReg;
assign rsAddValid    = rsAddValidReg;
assign rsAddOp       = rsAddOpReg;
assign rsAddRobIndex = rsAddRobIndexReg;
assign rsAddVal1     = rsAddVal1Reg;
assign rsAddHasDep1  = rsAddHasDep1Reg;
assign rsAddConstrt1 = rsAddConstrt1Reg;
assign rsAddVal2     = rsAddVal2Reg;
assign rsAddHasDep2  = rsAddHasDep2Reg;
assign rsAddConstrt2 = rsAddConstrt2Reg;

// Utensils for fetching instruction
wire lsbUsed = (instrIn[6:0] == 7'b0000011) || (instrIn[6:0] == 7'b0100011);
wire rsUsed  = (instrIn[6:0] == 7'b0110011) || (instrIn[6:0] == 7'b0010011);
wire full    = robFull || (lsbUsed && lsbFull) || (rsUsed && rsFull);

// Utensils for decoding instruction
wire [4:0]  rd            = instrReg[11:7];
wire [4:0]  rs1           = instrReg[19:15];
wire [4:0]  rs2           = instrReg[24:20];
wire [6:0]  op1           = instrReg[6:0];
wire [2:0]  op2           = instrReg[14:12];
wire [6:0]  op3           = instrReg[31:25];
wire [11:0] imm           = instrReg[31:20];
wire [31:0] upperImm      = {instrReg[31:12], 12'b0};
wire [31:0] jalImm        = {{12{instrReg[31]}}, instrReg[19:12], instrReg[20], instrReg[30:21], 1'b0};
wire [31:0] signedExtImm  = {{20{instrReg[31]}}, instrReg[31:20]};
wire [31:0] branchDiff    = {{20{instrReg[31]}}, instrReg[7], instrReg[30:25], instrReg[11:8], 1'b0};
wire [31:0] storeDiff     = {{20{instrReg[31]}}, instrReg[31:25], instrReg[11:7]};
wire [31:0] shiftAmount   = {27'b0, instrReg[24:20]};
wire        regUpdate     = rd != 5'b00000;
wire        rs1Constraint = rs1Dirty &&
                            (rsUpdate && (rs1Dependency == rsRobIndex) ||
                             lsbUpdate && (rs1Dependency == lsbRobIndex));
wire [31:0] rs1RealValue  = rs1Dirty ?
                              (rsUpdate && (rs1Dependency == rsRobIndex)) ? rsUpdateVal :
                              (lsbUpdate && (rs1Dependency == lsbRobIndex)) ? lsbUpdateVal : 0 :
                            rs1Value;
wire       rs2Constraint = rs2Dirty &&
                            (rsUpdate && (rs2Dependency == rsRobIndex) ||
                             lsbUpdate && (rs2Dependency == lsbRobIndex));
wire [31:0] rs2RealValue = rs2Dirty ?
                              (rsUpdate && (rs2Dependency == rsRobIndex)) ? rsUpdateVal :
                              (lsbUpdate && (rs2Dependency == lsbRobIndex)) ? lsbUpdateVal : 0 :
                            rs2Value;

always @(posedge clockIn) begin
  if (resetIn) begin
    PC              <= 32'b0;
    stall           <= 1'b0;
    stallDependency <= 4'b0000;
    instrRegValid   <= 1'b0;
    robAddReadyReg <= 1'b0;
    rsAddValidReg  <= 1'b0;
  end else begin
    if (stall) begin
      if (robReady) begin
        stall         <= 1'b0;
        instrRegValid <= 1'b1;
        PC            <= robValue + upperImm;
      end else begin
        stall         <= 1'b1;
        instrRegValid <= 1'b0;
      end
    end else begin
      // Fetch
      if (~full && instrInValid && ~pending) begin
       instrReg      <= instrIn;
       instrAddrReg  <= PC;
       instrRegValid <= 1'b1;
       case (instrIn[6:0])
         7'b1100011: begin // branch
           pending <= 1'b1;
         end
         7'b1101111: begin // JAL
           pending <= 1'b1;
         end
         7'b1100111: begin // JALR
           pending <= 1'b1;
         end
         default: begin // Other instructions
         PC <= PC + 4;
         end
       endcase
      end else begin
       instrRegValid <= 1'b0;
      end
    end

    // Decode and issue
    if (instrRegValid) begin
      rsAddRobIndexReg <= robNext;
      case (op1)
        7'b0110111: begin // LUI
          robAddValidReg   <= regUpdate;
          robAddTypeReg    <= 2'b00; // Register write
          robValueReg      <= upperImm;
          destReg          <= rd;
          robAddReadyReg   <= 1'b1;
          rfUpdateValidReg <= regUpdate;
          rsAddValidReg    <= 1'b0;
        end
        7'b0010111: begin // AUIPC
          robAddValidReg   <= regUpdate;
          robAddTypeReg    <= 2'b00; // Register write
          robValueReg      <= instrAddrReg + upperImm;
          destReg          <= rd;
          robAddReadyReg   <= 1'b1;
          rfUpdateValidReg <= regUpdate;
          rsAddValidReg    <= 1'b0;
        end
        7'b1101111: begin // JAL
          robAddValidReg   <= regUpdate;
          robAddTypeReg    <= 2'b00; // Register write
          robValueReg      <= instrAddrReg + 4;
          destReg          <= rd;
          robAddReadyReg   <= 1'b1;
          rfUpdateValidReg <= regUpdate;
          pending          <= 1'b0;
          PC               <= PC + jalImm;
          rsAddValidReg    <= 1'b0;
        end
        7'b1100111: begin // JALR
          robAddValidReg   <= regUpdate;
          robAddTypeReg    <= 2'b00; // Register write
          robValueReg      <= instrAddrReg + 4;
          destReg          <= rd;
          robAddReadyReg   <= 1'b1;
          rfUpdateValidReg <= regUpdate;
          pending          <= 1'b0;
          rsAddValidReg    <= 1'b0;
          if (rs1Constraint) begin
            PC <= rs1RealValue + signedExtImm;
          end else begin
            stall           <= 1'b1;
            stallDependency <= rs1Dependency;
          end
        end
        7'b1100011: begin // branch
          robAddValidReg   <= 1'b1;
          pending          <= 1'b0;
          PC               <= jump ? PC + branchDiff : PC + 4;
          robAddTypeReg    <= 2'b01; // Branch
          robAddReadyReg   <= ~rs1Constraint & ~rs2Constraint;
          robAddrReg       <= jump ? PC + 4 : PC + branchDiff;
          rfUpdateValidReg <= 1'b0;
          rsAddValidReg    <= 1'b0;
          case (op2)
            3'b000: begin // BEQ
              rsAddOpReg       <= 4'b1000; // EQ
              rsAddHasDep1Reg  <= rs1Constraint;
              rsAddHasDep2Reg  <= rs2Constraint;
              rsAddVal1Reg     <= rs1RealValue;
              rsAddVal2Reg     <= rs2RealValue;
              rsAddConstrt1Reg <= rs1Dependency;
              rsAddConstrt2Reg <= rs2Dependency;
            end
            3'b001: begin // BNE
              rsAddOpReg       <= 4'b1001; // NE
              rsAddHasDep1Reg  <= rs1Constraint;
              rsAddHasDep2Reg  <= rs2Constraint;
              rsAddVal1Reg     <= rs1RealValue;
              rsAddVal2Reg     <= rs2RealValue;
              rsAddConstrt1Reg <= rs1Dependency;
              rsAddConstrt2Reg <= rs2Dependency;
            end
            3'b100: begin // BLT
              rsAddOpReg       <= 4'b1010; // LT
              rsAddHasDep1Reg  <= rs1Constraint;
              rsAddHasDep2Reg  <= rs2Constraint;
              rsAddVal1Reg     <= rs1RealValue;
              rsAddVal2Reg     <= rs2RealValue;
              rsAddConstrt1Reg <= rs1Dependency;
              rsAddConstrt2Reg <= rs2Dependency;
            end
            3'b101: begin // BGE
              rsAddOpReg <= 4'b1010; // LT (swap the operands)
              rsAddHasDep1Reg  <= rs2Constraint;
              rsAddHasDep2Reg  <= rs1Constraint;
              rsAddVal1Reg     <= rs2RealValue;
              rsAddVal2Reg     <= rs1RealValue;
              rsAddConstrt1Reg <= rs2Dependency;
              rsAddConstrt2Reg <= rs1Dependency;
            end
            3'b110: begin // BLTU
              rsAddOpReg       <= 4'b1011; // LTU
              rsAddHasDep1Reg  <= rs1Constraint;
              rsAddHasDep2Reg  <= rs2Constraint;
              rsAddVal1Reg     <= rs1RealValue;
              rsAddVal2Reg     <= rs2RealValue;
              rsAddConstrt1Reg <= rs1Dependency;
              rsAddConstrt2Reg <= rs2Dependency;
            end
            3'b111: begin // BGEU
              rsAddOpReg <= 4'b1011; // LTU (swap the operands)
              rsAddHasDep1Reg  <= rs2Constraint;
              rsAddHasDep2Reg  <= rs1Constraint;
              rsAddVal1Reg     <= rs2RealValue;
              rsAddVal2Reg     <= rs1RealValue;
              rsAddConstrt1Reg <= rs2Dependency;
              rsAddConstrt2Reg <= rs1Dependency;
            end
          endcase
        end
      endcase
    end else begin
      robAddReadyReg <= 1'b0;
      rsAddValidReg  <= 1'b0;
    end
  end
end
endmodule
