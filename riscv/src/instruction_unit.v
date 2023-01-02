`define PRINT_INSTRUCTION_TYPE // Show the information of the instruction on instruction fetch
module InstructionUnit #(
  parameter ROB_WIDTH = 4,
  parameter LSB_WIDTH = 4,
  parameter RS_OP_WIDTH = 4,
  parameter ROB_OP_WIDTH = 2,
  parameter LSB_OP_WIDTH = 3
) (
  input  wire        resetIn,      // resetIn
  input  wire        clockIn,      // clockIn
  input  wire        readyIn,      // readyIn
  input  wire        clearIn,      // clear signal (when branch prediction is wrong)
  input  wire [31:0] newPc,        // the correct PC value

  // Cache part
  input  wire        instrInValid, // instruction valid signal (icache)
  input  wire [31:0] instrIn,      // data valid signal (icache)
  output wire [31:0] instrAddrOut, // instruction address (icache)

  // Reservation Station part
  input  wire                   rsFull,        // reservation station full signal
  input  wire                   rsUpdate,      // reservation station update signal
  input  wire [ROB_WIDTH-1:0]   rsUpdateRobId, // reservation station rob index
  input  wire [31:0]            rsUpdateVal,   // reservation station value
  output wire                   rsAddValid,    // reservation station add valid signal
  output wire [RS_OP_WIDTH-1:0] rsAddOp,       // reservation station add op
  output wire [ROB_WIDTH-1:0]   rsAddRobIndex, // reservation station add rob index
  output wire [31:0]            rsAddVal1,     // reservation station add value1
  output wire                   rsAddHasDep1,  // reservation station add value1 dependency
  output wire [ROB_WIDTH-1:0]   rsAddConstrt1, // reservation station add value1 constraint
  output wire [31:0]            rsAddVal2,     // reservation station add value2
  output wire                   rsAddHasDep2,  // reservation station add value2 dependency
  output wire [ROB_WIDTH-1:0]   rsAddConstrt2, // reservation station add value2 constraint

  // Reorder Buffer part
  input  wire                    robFull,         // reorder buffer full signal
  input  wire [ROB_WIDTH-1:0]    robNext,         // reorder buffer next index
  input  wire                    robReady,        // reorder buffer ready signal
  input  wire [31:0]             robValue,        // reorder buffer value
  output wire [ROB_WIDTH-1:0]    robRequest,      // reorder buffer request
  output wire                    robAddValid,     // reorder buffer add valid signal
  output wire [ROB_WIDTH-1:0]    robAddIndex,     // reorder buffer add index
  output wire [ROB_OP_WIDTH-1:0] robAddType,      // reorder buffer add type signal
  output wire                    robAddReady,     // reorder buffer add ready signal
  output wire [31:0]             robAddValue,     // reorder buffer add value signal
  output wire                    robAddJump,      // reorder buffer add jump signal
  output wire [4:0]              robAddDest,      // reorder buffer add destination register signal
  output wire [31:0]             robAddAddr,      // reorder buffer add address
  output wire [31:0]             robAddInstrAddr, // reorder buffer add instruction address

  // load & Store Buffer part
  input  wire                    lsbFull,             // load & store buffer full signal
  input  wire                    lsbUpdate,           // load & store buffer update signal
  input  wire [ROB_WIDTH-1:0]    lsbUpdateRobId,         // load & store buffer rob index
  input  wire [31:0]             lsbUpdateVal,        // load & store buffer value
  output wire                    lsbAddValid,         // load & store buffer add valid signal
  output wire                    lsbAddReadWrite,     // load & store buffer read/write select
  output wire [ROB_WIDTH-1:0]    lsbAddRobId,         // load & store buffer rob index
  output wire                    lsbAddBaseHasDep,    // load & store buffer has dependency
  output wire [31:0]             lsbAddBase,          // load & store buffer add base addr
  output wire [ROB_WIDTH-1:0]    lsbAddBaseConstrtId, // load & store buffer add constraint index (RoB)
  output wire [31:0]             lsbAddOffset,        // load & store buffer add offset
  output wire                    lsbAddDataHasDep,    // load & store buffer has dependency
  output wire [31:0]             lsbAddData,          // load & store buffer add base addr
  output wire [ROB_WIDTH-1:0]    lsbAddDataConstrtId, // load & store buffer add constraint index (RoB)
  output wire [LSB_OP_WIDTH-1:0] lsbAddOp,            // load & store buffer add op

  // Register File part
  input  wire                 rs1Dirty,      // rs1 dirty signal
  input  wire [ROB_WIDTH-1:0] rs1Dependency, // rs1 dependency
  input  wire [31:0]          rs1Value,      // rs1 value
  input  wire                 rs2Dirty,      // rs2 dirty signal
  input  wire [ROB_WIDTH-1:0] rs2Dependency, // rs2 dependency
  input  wire [31:0]          rs2Value,      // rs2 value
  output wire                 rfUpdateValid, // register file update valid signal
  output wire [4:0]           rfUpdateDest,  // register file update destination
  output wire [ROB_WIDTH-1:0] rfUpdateRobId, // register file update value

  // Predictor part
  input wire jump // jump signal
);

reg [31:0]             PC;
reg [31:0]             instrReg; // for instrction decode and issue
reg [31:0]             instrAddrReg;
reg                    instrRegValid;
reg                    stall;
reg [ROB_WIDTH-1:0]    stallDependency;
reg                    pending; // pending for the next PC information

reg                    robAddValidReg;
reg [ROB_WIDTH-1:0]    robAddIndexReg;
reg [ROB_OP_WIDTH-1:0] robAddTypeReg;
reg                    robAddReadyReg;
reg [31:0]             robValueReg;
reg [31:0]             robAddrReg;
reg [31:0]             robInstrAddrReg;
reg                    jumpReg;
reg [4:0]              destReg;
reg                    rfUpdateValidReg;

reg                   rsAddValidReg;
reg [RS_OP_WIDTH-1:0] rsAddOpReg;
reg [ROB_WIDTH-1:0]   rsAddRobIndexReg;
reg [31:0]            rsAddVal1Reg;
reg                   rsAddHasDep1Reg;
reg [ROB_WIDTH-1:0]   rsAddConstrt1Reg;
reg [31:0]            rsAddVal2Reg;
reg                   rsAddHasDep2Reg;
reg [ROB_WIDTH-1:0]   rsAddConstrt2Reg;

reg                     lsbAddValidReg;
reg                     lsbAddReadWriteReg;
reg [ROB_WIDTH-1:0]     lsbAddRobIdReg;
reg                     lsbAddBaseHasDepReg;
reg [31:0]              lsbAddBaseReg;
reg [ROB_WIDTH-1:0]     lsbAddBaseConstrtIdReg;
reg [31:0]              lsbAddOffsetReg;
reg                     lsbAddDataHasDepReg;
reg [31:0]              lsbAddDataReg;
reg [ROB_WIDTH-1:0]     lsbAddDataConstrtIdReg;
reg [LSB_OP_WIDTH-1:0]  lsbAddOpReg;

assign instrAddrOut = PC;

assign robRequest      = stallDependency;
assign robAddValid     = robAddValidReg;
assign robAddIndex     = robAddIndexReg;
assign robAddType      = robAddTypeReg;
assign robAddReady     = robAddReadyReg;
assign robAddValue     = robValueReg;
assign robAddDest      = destReg;
assign robAddAddr      = robAddrReg;
assign robAddInstrAddr = robInstrAddrReg;
assign robAddJump      = jumpReg;

assign rfUpdateRobId = robAddIndexReg;
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

assign lsbAddValid         = lsbAddValidReg;
assign lsbAddReadWrite     = lsbAddReadWriteReg;
assign lsbAddRobId         = lsbAddRobIdReg;
assign lsbAddBaseHasDep    = lsbAddBaseHasDepReg;
assign lsbAddBase          = lsbAddBaseReg;
assign lsbAddBaseConstrtId = lsbAddBaseConstrtIdReg;
assign lsbAddOffset        = lsbAddOffsetReg;
assign lsbAddDataHasDep    = lsbAddDataHasDepReg;
assign lsbAddData          = lsbAddDataReg;
assign lsbAddDataConstrtId = lsbAddDataConstrtIdReg;
assign lsbAddOp            = lsbAddOpReg;

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
wire [31:0] unsignedImm   = {20'b0, instrReg[31:20]};
wire [31:0] branchDiff    = {{20{instrReg[31]}}, instrReg[7], instrReg[30:25], instrReg[11:8], 1'b0};
wire [31:0] storeDiff     = {{20{instrReg[31]}}, instrReg[31:25], instrReg[11:7]};
wire [31:0] shiftAmount   = {27'b0, instrReg[24:20]};
wire        regUpdate     = rd != 5'b00000;
wire        rs1Constraint = rs1Dirty &&
                            !((rsUpdate  && (rs1Dependency == rsUpdateRobId)) ||
                              (lsbUpdate && (rs1Dependency == lsbUpdateRobId)));
wire [31:0] rs1RealValue  = rs1Dirty ?
                              (rsUpdate  && (rs1Dependency == rsUpdateRobId)) ? rsUpdateVal :
                              (lsbUpdate && (rs1Dependency == lsbUpdateRobId)) ? lsbUpdateVal : 0 :
                            rs1Value;
wire        rs2Constraint = rs2Dirty &&
                            !((rsUpdate  && (rs2Dependency == rsUpdateRobId)) ||
                              (lsbUpdate && (rs2Dependency == lsbUpdateRobId)));
wire [31:0] rs2RealValue = rs2Dirty ?
                              (rsUpdate  && (rs2Dependency == rsUpdateRobId)) ? rsUpdateVal :
                              (lsbUpdate && (rs2Dependency == lsbUpdateRobId)) ? lsbUpdateVal : 0 :
                            rs2Value;

always @(posedge clockIn) begin
  robAddIndexReg <= robNext;
  if (resetIn || clearIn) begin
    PC               <= clearIn ? newPc : 32'b0;
    stall            <= 1'b0;
    stallDependency  <= 4'b0000;
    instrRegValid    <= 1'b0;
    robAddValidReg   <= 1'b0;
    rsAddValidReg    <= 1'b0;
    rfUpdateValidReg <= 1'b0;
    lsbAddValidReg   <= 1'b0;
    pending          <= 1'b0;
  end else if (readyIn) begin
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
          7'b1100011: pending <= 1'b1; // branch
          7'b1101111: pending <= 1'b1; // JAL
          7'b1100111: pending <= 1'b1; // JALR
          default:    PC <= PC + 4; // Other instructions
        endcase
`ifdef PRINT_INSTRUCTION_TYPE
        case (instrIn[6:0])
          7'b0110111: $display("LUI(%h): %h", PC, instrIn);
          7'b0010111: $display("AUIPC(%h): %h", PC, instrIn);
          7'b1100011: $display("branch(%h): %h", PC, instrIn);
          7'b1101111: $display("JAL(%h): %h", PC, instrIn);
          7'b1100111: $display("JALR(%h): %h", PC, instrIn);
          7'b0000011: $display("load(%h): %h", PC, instrIn);
          7'b0100011: $display("store(%h): %h", PC, instrIn);
          7'b0010011: $display("immediate(%h): %h", PC, instrIn);
          7'b0110011: $display("calculate(%h): %h", PC, instrIn);
        endcase
`endif
      end else begin
       instrRegValid <= 1'b0;
      end
    end

    // Decode and issue
    if (instrRegValid) begin
      rsAddRobIndexReg <= robNext;
      robInstrAddrReg  <= instrAddrReg;
      case (op1)
        7'b0110111: begin // LUI
          robAddValidReg   <= regUpdate;
          robAddTypeReg    <= 2'b00; // Register write
          robValueReg      <= upperImm;
          destReg          <= rd;
          robAddReadyReg   <= 1'b1;
          rfUpdateValidReg <= regUpdate;
          rsAddValidReg    <= 1'b0;
          lsbAddValidReg   <= 1'b0;
        end
        7'b0010111: begin // AUIPC
          robAddValidReg   <= regUpdate;
          robAddTypeReg    <= 2'b00; // Register write
          robValueReg      <= instrAddrReg + upperImm;
          destReg          <= rd;
          robAddReadyReg   <= 1'b1;
          rfUpdateValidReg <= regUpdate;
          rsAddValidReg    <= 1'b0;
          lsbAddValidReg   <= 1'b0;
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
          lsbAddValidReg   <= 1'b0;
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
          lsbAddValidReg   <= 1'b0;
          if (rs1Constraint) begin
            stall           <= 1'b1;
            stallDependency <= rs1Dependency;
          end else begin
            PC <= rs1RealValue + signedExtImm;
          end
        end
        7'b1100011: begin // branch
          robAddValidReg   <= 1'b1;
          pending          <= 1'b0;
          PC               <= jump ? PC + branchDiff : PC + 4;
          robAddTypeReg    <= 2'b01; // Branch
          robAddReadyReg   <= 1'b0;
          jumpReg          <= jump;
          robAddrReg       <= jump ? PC + 4 : PC + branchDiff;
          rfUpdateValidReg <= 1'b0;
          rsAddValidReg    <= 1'b1;
          lsbAddValidReg   <= 1'b0;
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
        7'b0000011: begin // load
          robAddValidReg         <= 1'b1;
          robAddTypeReg          <= 2'b00; // Register write
          robAddReadyReg         <= 1'b0;
          destReg                <= rd;
          rfUpdateValidReg       <= 1'b1;
          rsAddValidReg          <= 1'b0;
          lsbAddValidReg         <= 1'b1;
          lsbAddReadWriteReg     <= 1'b1; // Read
          lsbAddRobIdReg         <= robNext;
          lsbAddBaseHasDepReg    <= rs1Constraint;
          lsbAddBaseReg          <= rs1RealValue;
          lsbAddBaseConstrtIdReg <= rs1Dependency;
          lsbAddOffsetReg        <= signedExtImm;
          lsbAddDataHasDepReg    <= 1'b0;
          case (op2)
            3'b000: lsbAddOpReg <= 3'b000; // Byte
            3'b001: lsbAddOpReg <= 3'b001; // Halfword
            3'b010: lsbAddOpReg <= 3'b010; // Word
            3'b100: lsbAddOpReg <= 3'b011; // Unsigned Byte
            3'b101: lsbAddOpReg <= 3'b100; // Unsigned Halfword
          endcase
        end
        7'b0100011: begin // store
          robAddValidReg         <= 1'b1;
          robAddTypeReg          <= 2'b10; // Memory write
          robAddReadyReg         <= 1'b0;
          rfUpdateValidReg       <= 1'b0;
          rsAddValidReg          <= 1'b0;
          lsbAddValidReg         <= 1'b1;
          lsbAddReadWriteReg     <= 1'b0; // Write
          lsbAddRobIdReg         <= robNext;
          lsbAddBaseHasDepReg    <= rs1Constraint;
          lsbAddBaseReg          <= rs1RealValue;
          lsbAddBaseConstrtIdReg <= rs1Dependency;
          lsbAddOffsetReg        <= storeDiff;
          lsbAddDataHasDepReg    <= rs2Constraint;
          lsbAddDataReg          <= rs2RealValue;
          lsbAddDataConstrtIdReg <= rs2Dependency;
          case (op2)
            3'b000: lsbAddOpReg <= 3'b000; // Byte
            3'b001: lsbAddOpReg <= 3'b001; // Halfword
            3'b010: lsbAddOpReg <= 3'b010; // Word
          endcase
        end
        7'b0010011: begin // immediate
          robAddValidReg   <= 1'b1;
          robAddTypeReg    <= 2'b00; // Register write
          robAddReadyReg   <= 1'b0;
          destReg          <= rd;
          rfUpdateValidReg <= regUpdate;
          rsAddValidReg    <= 1'b1;
          lsbAddValidReg   <= 1'b0;
          rsAddHasDep1Reg  <= rs1Constraint;
          rsAddHasDep2Reg  <= 1'b0;
          rsAddVal1Reg     <= rs1RealValue;
          rsAddConstrt1Reg <= rs1Dependency;
          case (op2)
            3'b000: begin // ADDI
              rsAddOpReg       <= 4'b0000; // ADD
              rsAddVal2Reg     <= signedExtImm;
            end
            3'b010: begin // SLTI
              rsAddOpReg       <= 4'b1010; // SLT
              rsAddVal2Reg     <= signedExtImm;
            end
            3'b011: begin // SLTIU
              rsAddOpReg       <= 4'b1011; // SLTU
              rsAddVal2Reg     <= unsignedImm;
            end
            3'b100: begin // XORI
              rsAddOpReg       <= 4'b0010; // XOR
              rsAddVal2Reg     <= signedExtImm;
            end
            3'b110: begin // ORI
              rsAddOpReg       <= 4'b0011; // OR
              rsAddVal2Reg     <= signedExtImm;
            end
            3'b111: begin // ANDI
              rsAddOpReg       <= 4'b0100; // AND
              rsAddVal2Reg     <= signedExtImm;
            end
            3'b001: begin // SLLI
              rsAddOpReg       <= 4'b0101; // SLL
              rsAddVal2Reg     <= shiftAmount;
            end
            3'b101: begin // SRLI/SRAI
              rsAddVal2Reg <= shiftAmount;
              case (op3)
                7'b0000000: rsAddOpReg <= 4'b0110; // SRL
                7'b0100000: rsAddOpReg <= 4'b0111; // SRA
              endcase
            end
          endcase
        end
        7'b0110011: begin // calculate
          robAddValidReg   <= 1'b1;
          robAddTypeReg    <= 2'b00; // Register write
          robAddReadyReg   <= 1'b0;
          destReg          <= rd;
          rfUpdateValidReg <= regUpdate;
          rsAddValidReg    <= 1'b1;
          lsbAddValidReg   <= 1'b0;
          rsAddHasDep1Reg  <= rs1Constraint;
          rsAddHasDep2Reg  <= rs2Constraint;
          rsAddVal1Reg     <= rs1RealValue;
          rsAddVal2Reg     <= rs2RealValue;
          rsAddConstrt1Reg <= rs1Dependency;
          rsAddConstrt2Reg <= rs2Dependency;
          case (op2)
            3'b000: case (op3)
              7'b0000000: rsAddOpReg <= 4'b0000; // ADD
              7'b0100000: rsAddOpReg <= 4'b0001; // SUB
            endcase
            3'b001: rsAddOpReg <= 4'b0101; // SLL
            3'b010: rsAddOpReg <= 4'b1010; // SLT
            3'b011: rsAddOpReg <= 4'b1011; // SLTU
            3'b100: rsAddOpReg <= 4'b0010; // XOR
            3'b101: case (op3)
              7'b0000000: rsAddOpReg <= 4'b0110; // SRL
              7'b0100000: rsAddOpReg <= 4'b0111; // SRA
            endcase
            3'b110: rsAddOpReg <= 4'b0011; // OR
            3'b111: rsAddOpReg <= 4'b0100; // AND
          endcase
        end
      endcase
    end else begin
      robAddValidReg   <= 1'b0;
      rsAddValidReg    <= 1'b0;
      rfUpdateValidReg <= 1'b0;
      lsbAddValidReg   <= 1'b0;
    end
  end
end
endmodule
