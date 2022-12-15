module InstructionUnit(
  input  wire        resetIn,       // resetIn
  input  wire        clockIn,       // clockIn
  input  wire        instrInValid,  // instruction valid signal (icache)
  input  wire [31:0] instrIn,       // data valid signal (icache)
  input  wire [31:0] instrAddr,     // instruction address (icache)
  input  wire        rsFull,        // reservation station full signal
  input  wire        robFull,       // reorder buffer full signal
  input  wire        robReady,      // reorder buffer ready signal
  input  wire [3:0]  robNext,       // reorder buffer next free slot
  input  wire [31:0] robValue,      // reorder buffer value
  input  wire        lsbFull,       // load/store buffer full signal
  input  wire        jump,          // jump signal (predictor)
  output wire        instrOutValid, // instruction output valid signal (PC)
  output wire [31:0] instrAddrOut,  // instruction address (PC)
  output wire [3:0]  robRequest     // reorder buffer request
);

reg [31:0] PC;
reg [31:0] instrReg; // for instrction decode and issue
reg        instrRegValid;
reg        stall;
reg [3:0]  stallDependency;

assign instrOutValid = ~stall;
assign instrAddrOut  = PC;
assign robRequest    = stallDependency;

// Utensils for fetching instruction
wire lsbUsed = (instrIn[6:0] == 7'b0000011) || (instrIn[6:0] == 7'b0100011);
wire rsUsed  = (instrIn[6:0] == 7'b0110011) || (instrIn[6:0] == 7'b0010011);
wire full    = robFull || (lsbUsed && lsbFull) || (rsUsed && rsFull);

// Utensils for decoding instruction
wire [4:0]  rd           = instrReg[11:7];
wire [4:0]  rs1          = instrReg[19:15];
wire [4:0]  rs2          = instrReg[24:20];
wire [6:0]  op1          = instrReg[6:0];
wire [2:0]  op2          = instrReg[14:12];
wire [6:0]  op3          = instrReg[31:25];
wire [11:0] imm          = instrReg[31:20];
wire [31:0] upperImm     = {instrReg[31:12], 12'b0};
wire [31:0] jalImm       = {{12{instrReg[31]}}, instrReg[19:12], instrReg[20], instrReg[30:21], 1'b0};
wire [31:0] signedExtImm = {{20{instrReg[31]}}, instrReg[31:20]};
wire [31:0] branchDiff   = {{20{instrReg[31]}}, instrReg[7], instrReg[30:25], instrReg[11:8], 1'b0};
wire [31:0] storeDiff    = {{20{instrReg[31]}}, instrReg[31:25], instrReg[11:7]};
wire [31:0] shiftAmount  = {27'b0, instrReg[24:20]};

always @(posedge clockIn) begin
  if (resetIn) begin
    PC              <= 32'b0;
    stall           <= 1'b0;
    stallDependency <= 4'b0000;
    instrRegValid   <= 1'b0;
  end else begin
    if (stall && robReady) begin
      stall         <= 1'b0;
      instrRegValid <= 1'b1;
    end else if (~full && instrInValid) begin
      instrReg <= instrIn;
      instrRegValid <= 1'b1;
      if (instrIn[6:0] == 7'b1100011) begin // branch
        PC <= jump ? PC + branchDiff : PC + 4;
      end else if (instrIn[6:0] == 7'b1100111) begin // JALR
        stall           <= 1'b1;
        stallDependency <= instrRegValid ? robNext + 1 : robNext;
      end else begin // Other instructions
        PC <= PC + 4;
      end
    end else begin
      instrRegValid <= 1'b0;
    end
  end
end
endmodule
