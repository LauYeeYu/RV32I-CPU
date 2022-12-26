# Reorder Buffer

The Reorder Buffer (RoB) is a first-in-first-out queue that commits the result
of each instruction in the order that they were issued. When the predicted
result of a conditional branch is wrong, the Reorder Buffer will send a signal
to revert the instructions that issues after the branch.

## Reorder Buffer Operators

| num | binary |    operator    |
|:---:|:------:|:--------------:|
|  0  |  `00`  | register write |
|  1  |  `01`  |     branch     |
|  2  |  `10`  |  memory write  |
|  3  |  `11`  |    reserved    |

For memory writing instructions, the value is used as the index in the
[Load & Store Buffer](load_store_buffer.md).

## Reorder Buffer Module

The Reorder Buffer module is located at `src/reorder_buffer.v`.

The Reorder Buffer module is a module that handles the commit of instructions.
To prevent data incoherence, the Reorder Buffer module will commit the
instructions precisely according to the order.

The interfaces are listed below:
    
```verilog
module ReorderBuffer #(
  parameter ROB_WIDTH = 4,
  parameter ROB_SIZE = 2**ROB_WIDTH,
  parameter ROB_OP_WIDTH = 2
) (
  input  wire resetIn, // resetIn
  input  wire clockIn, // clockIn
  output wire clear,   // clear signal (when branch prediction is wrong)
  output wire newPc,   // the correct PC value

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
endmodule
```

For instructions that write registers (calculations and load instructions),
the Reorder Buffer module will send the result to the
[Register File module](register_file.md) when the result is ready.

For instructions that write memory (store instructions), the Reorder Buffer
module will send the signal `writeValid` to the
[Load & Store Buffer module](load_store_buffer.md) when the result is ready.

For instructions that are branches, the Reorder Buffer module will check
whether the predicted result is correct. If the predicted result is wrong,
the Reorder Buffer module will set the signal `clear` high and send the
correct PC value to the `newPc` signal.
