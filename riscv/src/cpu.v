// RISCV32I CPU top module
// port modification allowed for debugging purposes

module cpu(
  input  wire        clk_in,         // system clock signal
  input  wire        rst_in,         // reset signal
  input  wire        rdy_in,         // ready signal, pause cpu when low

  input  wire [ 7:0] mem_din,        // data input bus
  output wire [ 7:0] mem_dout,       // data output bus
  output wire [31:0] mem_a,          // address bus (only 17:0 is used)
  output wire        mem_wr,         // write/read signal (1 for write)

  input  wire        io_buffer_full, // 1 if uart buffer is full

  output wire [31:0] dbgreg_dout     // cpu register output (debugging demo)
);

// implementation goes here

// Specifications:
// - Pause cpu(freeze pc, registers, etc.) when rdy_in is low
// - Memory read result will be returned in the next cycle. Write takes 1 cycle(no need to wait)
// - Memory is of size 128KB, with valid address ranging from 0x0 to 0x20000
// - I/O port is mapped to address higher than 0x30000 (mem_a[17:16]==2'b11)
// - 0x30000 read: read a byte from input
// - 0x30000 write: write a byte to output (write 0x00 is ignored)
// - 0x30004 read: read clocks passed since cpu starts (in dword, 4 bytes)
// - 0x30004 write: indicates program stop (will output '\0' through uart tx)

// parameters
parameter CACHE_BLOCK_WIDTH = 4;
parameter ICACHE_WIDTH      = 5;
parameter DCACHE_WIDTH      = 5;
parameter ROB_WIDTH         = 4;
parameter RS_WIDTH          = 4;
parameter LSB_WIDTH         = 4;
parameter RS_OP_WIDTH       = 4;
parameter ROB_OP_WIDTH      = 2;
parameter LSB_OP_WIDTH      = 3;
parameter PREDICTOR_WIDTH   = 12;

// things about wrong prediction
wire clear;
wire mergedReset = clear | rst_in; // For reservation station & load store buffer
wire [31:0] newPC;

// Broadcasting wires
// For Reservation Station
wire                   rsUpdate;
wire [ROB_WIDTH-1:0]   rsUpdateRobId;
wire [31:0]            rsUpdateValue;
wire                   rsFull;
wire                   rsAddValid;
wire [RS_OP_WIDTH-1:0] rsAddOp;
wire [ROB_WIDTH-1:0]   rsAddRobIndex;
wire [31:0]            rsAddVal1;
wire                   rsAddHasDep1;
wire [ROB_WIDTH-1:0]   rsAddConstrt1;
wire [31:0]            rsAddVal2;
wire                   rsAddHasDep2;
wire [ROB_WIDTH-1:0]   rsAddConstrt2;

// For Load & Store Buffer
wire                    lsbUpdate;
wire [ROB_WIDTH-1:0]    lsbUpdateRobId;
wire [31:0]             lsbUpdateValue;
wire                    lsbFull;
wire                    lsbAddValid;
wire                    lsbAddReadWrite;
wire [ROB_WIDTH-1:0]    lsbAddRobId;
wire                    lsbAddBaseHasDep;
wire [31:0]             lsbAddBase;
wire [ROB_WIDTH-1:0]    lsbAddBaseConstrtId;
wire [31:0]             lsbAddOffset;
wire                    lsbAddDataHasDep;
wire [31:0]             lsbAddData;
wire [ROB_WIDTH-1:0]    lsbAddDataConstrtId;
wire [LSB_OP_WIDTH-1:0] lsbAddOp;

// For Reorder Buffer
wire [ROB_WIDTH-1:0]    nextRobId;
wire                    robFull;
wire [ROB_WIDTH-1:0]    robBeginId;
wire                    robBeginValid;
wire                    robAddValid;
wire [ROB_WIDTH-1:0]    robAddIndex;
wire [ROB_OP_WIDTH-1:0] robAddType;
wire                    robAddReady;
wire [31:0]             robAddValue;
wire                    robAddJump;
wire [4:0]              robAddDest;
wire [31:0]             robAddAddr;
wire [31:0]             robAddInstrAddr;

// For Predictor
wire        predictorUpdateValid;
wire [31:0] predictorUpdateInstrAddr;
wire        taken;
wire        predicted;

// Instruction Fetch
wire [31:0] fetchInstrAddr;
wire        fetchInstrValidToIu;
wire [31:0] fetchInstr;
wire [4:0]  fetchRs1 = fetchInstr[19:15];
wire [4:0]  fetchRs2 = fetchInstr[24:20];

// Load & Store Buffer x Cache
wire [1:0]  dataAccessType;
wire        dataReadWrite;
wire [31:0] dataAddr;
wire [31:0] dataToCache;
wire        dataValidToLsb;
wire [31:0] dataToLsb;
wire        dataWriteSuccess;

// Instruction Unit x Reorder Buffer
wire                 iuReqRobReady;
wire [31:0]          iuReqRobValue;
wire [ROB_WIDTH-1:0] iuReqRobId;

// Instruction Unit x Register File
wire                 rs1Dirty;
wire [ROB_WIDTH-1:0] rs1Dependency;
wire [31:0]          rs1Value;
wire                 rs2Dirty;
wire [ROB_WIDTH-1:0] rs2Dependency;
wire [31:0]          rs2Value;
wire                 rfUpdateValid;
wire [4:0]           rfUpdateDest;
wire [ROB_WIDTH-1:0] rfUpdateRobId;

// Register x Reorder Buffer
wire                 regUpdateValid;
wire [4:0]           regUpdateDest;
wire [31:0]          regUpdateValue;
wire [ROB_WIDTH-1:0] regUpdateRobId;
wire                 robRs1Ready;
wire [31:0]          robRs1Value;
wire [ROB_WIDTH-1:0] robRs1Dep;
wire                 robRs2Ready;
wire [31:0]          robRs2Value;
wire [ROB_WIDTH-1:0] robRs2Dep;

Cache #(
  .BLOCK_WIDTH  (CACHE_BLOCK_WIDTH),
  .BLOCK_SIZE   (2**CACHE_BLOCK_WIDTH),
  .ICACHE_WIDTH (ICACHE_WIDTH),
  .DCACHE_WIDTH (DCACHE_WIDTH)
) cache(
  .clkIn         (clk_in),
  .resetIn       (rst_in),
  .clearIn       (clear),
  .readyIn       (rdy_in),
  .memIn         (mem_din),
  .instrAddrIn   (fetchInstrAddr),
  .accessType    (dataAccessType),
  .readWriteIn   (dataReadWrite),
  .dataAddrIn    (dataAddr),
  .dataIn        (dataToCache),
  .readWriteOut  (mem_wr),
  .memAddr       (mem_a),
  .memOut        (mem_dout),
  .instrOutValid (fetchInstrValidToIu),
  .instrOut      (fetchInstr),
  .dataOutValid  (dataValidToLsb),
  .dataOut       (dataToLsb),
  .dataWriteSuc  (dataWriteSuccess)
);

InstructionUnit #(
  .ROB_WIDTH    (ROB_WIDTH),
  .LSB_WIDTH    (LSB_WIDTH),
  .RS_OP_WIDTH  (RS_OP_WIDTH),
  .ROB_OP_WIDTH (ROB_OP_WIDTH),
  .LSB_OP_WIDTH (LSB_OP_WIDTH)
) instructionUnit(
  .resetIn (rst_in),
  .clockIn (clk_in),
  .readyIn (rdy_in),
  .clearIn (clear),
  .newPc   (newPC),
  // For Cache
  .instrInValid (fetchInstrValidToIu),
  .instrIn      (fetchInstr),
  .instrAddrOut (fetchInstrAddr),
  // For Reservation Station
  .rsFull        (rsFull),
  .rsUpdate      (rsUpdate),
  .rsUpdateRobId (rsUpdateRobId),
  .rsUpdateVal   (rsUpdateValue),
  .rsAddValid    (rsAddValid),
  .rsAddOp       (rsAddOp),
  .rsAddRobIndex (rsAddRobIndex),
  .rsAddVal1     (rsAddVal1),
  .rsAddHasDep1  (rsAddHasDep1),
  .rsAddConstrt1 (rsAddConstrt1),
  .rsAddVal2     (rsAddVal2),
  .rsAddHasDep2  (rsAddHasDep2),
  .rsAddConstrt2 (rsAddConstrt2),
  // For Reorder Buffer
  .robFull         (robFull),
  .robNext         (nextRobId),
  .robReady        (iuReqRobReady),
  .robValue        (iuReqRobValue),
  .robRequest      (iuReqRobId),
  .robAddValid     (robAddValid),
  .robAddIndex     (robAddIndex),
  .robAddType      (robAddType),
  .robAddReady     (robAddReady),
  .robAddValue     (robAddValue),
  .robAddJump      (robAddJump),
  .robAddDest      (robAddDest),
  .robAddAddr      (robAddAddr),
  .robAddInstrAddr (robAddInstrAddr),
  // For Load & Store Buffer
  .lsbFull             (lsbFull),
  .lsbUpdate           (lsbUpdate),
  .lsbUpdateRobId      (lsbUpdateRobId),
  .lsbUpdateVal        (lsbUpdateValue),
  .lsbAddValid         (lsbAddValid),
  .lsbAddReadWrite     (lsbAddReadWrite),
  .lsbAddRobId         (lsbAddRobId),
  .lsbAddBaseHasDep    (lsbAddBaseHasDep),
  .lsbAddBase          (lsbAddBase),
  .lsbAddBaseConstrtId (lsbAddBaseConstrtId),
  .lsbAddOffset        (lsbAddOffset),
  .lsbAddDataHasDep    (lsbAddDataHasDep),
  .lsbAddData          (lsbAddData),
  .lsbAddDataConstrtId (lsbAddDataConstrtId),
  .lsbAddOp            (lsbAddOp),
  // For Register File
  .rs1Dirty     (rs1Dirty),
  .rs1Dependency (rs1Dependency),
  .rs1Value      (rs1Value),
  .rs2Dirty      (rs2Dirty),
  .rs2Dependency (rs2Dependency),
  .rs2Value      (rs2Value),
  .rfUpdateValid (rfUpdateValid),
  .rfUpdateDest  (rfUpdateDest),
  .rfUpdateRobId (rfUpdateRobId),
  // For Predictor
  .jump (predicted)
);

Predictor #(
  .LOCAL_WIDTH (PREDICTOR_WIDTH),
  .LOCAL_SIZE  (2**PREDICTOR_WIDTH)
) predictor(
  .resetIn     (rst_in),
  .clockIn     (clk_in),
  .readyIn     (rdy_in),
  .instrPos    (fetchInstrAddr[PREDICTOR_WIDTH+1:2]),
  .updateValid (predictorUpdateValid),
  .updateInstr (predictorUpdateInstrAddr),
  .jump        (predicted),
  .taken       (taken)
);

RegisterFile #(
  .ROB_WIDTH (ROB_WIDTH)
) registerFile(
  .resetIn (rst_in),
  .clockIn (clk_in),
  .clearIn (clear),
  .readyIn (rdy_in),
  .reg1    (fetchRs1),
  .reg2    (fetchRs2),
  // For Instruciton Unit
  .rfUpdateValid (rfUpdateValid),
  .rfUpdateDest  (rfUpdateDest),
  .rfUpdateRobId (rfUpdateRobId),
  .rs1Dirty      (rs1Dirty),
  .rs1Dependency (rs1Dependency),
  .rs1Value      (rs1Value),
  .rs2Dirty      (rs2Dirty),
  .rs2Dependency (rs2Dependency),
  .rs2Value      (rs2Value),
  // For Reorder Buffer
  .regUpdateValid (regUpdateValid),
  .regUpdateDest  (regUpdateDest),
  .regUpdateRobId (regUpdateRobId),
  .regUpdateValue (regUpdateValue),
  .robRs1Ready    (robRs1Ready),
  .robRs1Value    (robRs1Value),
  .robRs1Dep      (robRs1Dep),
  .robRs2Ready    (robRs2Ready),
  .robRs2Value    (robRs2Value),
  .robRs2Dep      (robRs2Dep)
);

ReorderBuffer #(
  .ROB_WIDTH    (ROB_WIDTH),
  .ROB_SIZE     (2**ROB_WIDTH),
  .ROB_OP_WIDTH (ROB_OP_WIDTH)
) reorderBuffer(
  .resetIn (rst_in),
  .clockIn (clk_in),
  .readyIn (rdy_in),
  .clear   (clear),
  .newPc   (newPC),
  // For Reservation Station
  .rsUpdate    (rsUpdate),
  .rsRobIndex  (rsUpdateRobId),
  .rsUpdateVal (rsUpdateValue),
  // For Load & Store Buffer
  .lsbUpdate    (lsbUpdate),
  .lsbRobIndex  (lsbUpdateRobId),
  .lsbUpdateVal (lsbUpdateValue),
  .robBeginId   (robBeginId),
  .beginValid   (robBeginValid),
  // For Instruction Unit
  .request      (iuReqRobId),
  .reqReady     (iuReqRobReady),
  .reqValue     (iuReqRobValue),
  .addValid     (robAddValid),
  .addIndex     (robAddIndex),
  .addType      (robAddType),
  .addReady     (robAddReady),
  .addValue     (robAddValue),
  .addJump      (robAddJump),
  .addDest      (robAddDest),
  .addAddr      (robAddAddr),
  .addInstrAddr (robAddInstrAddr),
  .full         (robFull),
  .next         (nextRobId),
  // For Predictor
  .predictUpdValid (predictorUpdateValid),
  .updInstrAddr    (predictorUpdateInstrAddr),
  .jumpResult      (taken),
  // For Register File
  .regUpdateValid (regUpdateValid),
  .regUpdateDest  (regUpdateDest),
  .regUpdateRobId (regUpdateRobId),
  .regValue       (regUpdateValue),
  .rs1Ready       (robRs1Ready),
  .rs1Value       (robRs1Value),
  .rs1Dep         (robRs1Dep),
  .rs2Ready       (robRs2Ready),
  .rs2Value       (robRs2Value),
  .rs2Dep         (robRs2Dep)
);

ReservationStation #(
  .RS_OP_WIDTH (RS_OP_WIDTH),
  .RS_WIDTH    (RS_WIDTH),
  .ROB_WIDTH   (ROB_WIDTH)
) reservationStation(
  .resetIn (mergedReset),
  .clockIn (clk_in),
  .readyIn (rdy_in),
  // For Instruction Unit
  .addValid    (rsAddValid),
  .addOp       (rsAddOp),
  .addRobIndex (rsAddRobIndex),
  .addVal1     (rsAddVal1),
  .addHasDep1  (rsAddHasDep1),
  .addConstrt1 (rsAddConstrt1),
  .addVal2     (rsAddVal2),
  .addHasDep2  (rsAddHasDep2),
  .addConstrt2 (rsAddConstrt2),
  .full        (rsFull),
  .update      (rsUpdate),
  .updateRobId (rsUpdateRobId),
  .updateVal   (rsUpdateValue),
  // For Load & Store Buffer
  .lsbUpdate    (lsbUpdate),
  .lsbRobIndex  (lsbUpdateRobId),
  .lsbUpdateVal (lsbUpdateValue)
);

LoadStoreBuffer #(
  .ROB_WIDTH (ROB_WIDTH),
  .LSB_WIDTH (LSB_WIDTH),
  .LSB_SIZE  (2**LSB_WIDTH),
  .LSB_OP_WIDTH (LSB_OP_WIDTH)
) loadStoreBuffer(
  .resetIn      (rst_in),
  .clearIn      (clear),
  .clockIn      (clk_in),
  .readyIn      (rdy_in),
  .lsbUpdate    (lsbUpdate),
  .lsbRobIndex  (lsbUpdateRobId),
  .lsbUpdateVal (lsbUpdateValue),
  // For DCache
  .dataValid    (dataValidToLsb),
  .dataIn       (dataToLsb),
  .dataWriteSuc (dataWriteSuccess),
  .accessType   (dataAccessType),
  .readWriteOut (dataReadWrite),
  .dataAddr     (dataAddr),
  .dataOut      (dataToCache),
  // For Reorder Buffer
  .robBeginId    (robBeginId),
  .robBeginValid (robBeginValid),
  // For Reservation Station
  .rsUpdate    (rsUpdate),
  .rsRobIndex  (rsUpdateRobId),
  .rsUpdateVal (rsUpdateValue),
  // For Instruction Unit
  .addValid         (lsbAddValid),
  .addReadWrite     (lsbAddReadWrite),
  .addRobId         (lsbAddRobId),
  .addBaseHasDep    (lsbAddBaseHasDep),
  .addBase          (lsbAddBase),
  .addBaseConstrtId (lsbAddBaseConstrtId),
  .addOffset        (lsbAddOffset),
  .addDataHasDep    (lsbAddDataHasDep),
  .addData          (lsbAddData),
  .addDataConstrtId (lsbAddDataConstrtId),
  .addOp            (lsbAddOp),
  .full             (lsbFull)
);

endmodule
