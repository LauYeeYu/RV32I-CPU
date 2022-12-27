# Load & Store Buffer

The Load & Store Buffer is a buffer for load and store instructions. It
handles everything related to load and store instructions.

## Load & Store Buffer Operator
| num | binary |     operator      |
|:---:|:------:|:-----------------:|
|  0  | `000`  |       byte        |
|  1  | `001`  |     half word     |
|  2  | `010`  |       word        |
|  3  | `011`  |   unsigned byte   |
|  4  | `100`  | unsigned halfword |
|  5  | `101`  |     reserved      |
|  6  | `110`  |     reserved      |
|  7  | `111`  |     reserved      |

## Load & Store Buffer Module

The Load & Store Buffer module is located at `src/load_store_buffer.v`.

The Load & Store Buffer module is a module that handles load and store
instructions. To prevent data incoherence, the Load & Store Buffer module
will process the requests precisely according to the order.

Since the Tomasulo algorithm is used, the Load & Store Buffer module will
only process instructions that are marked as ready.

Every entry is sent from the [Instruction Unit](instruction_unit.md).

For store instructions, the entry will be marked as ready when the
corresponding entry in [Reorder Buffer](reorder_buffer.md) is committed.
Then the Load & Store Buffer module will send the data to the
[Cache module](cache.md) when the data is ready. The Load & Store Buffer
module will then stall until the `dataWriteSuc` signal is high.

For load instructions, The Load & Store Buffer module will send the data
to the [Register File module](register_file.md) when the data is ready.

The interfaces are listed below:
```verilog
module LoadStoreBuffer #(
  parameter ROB_WIDTH = 4,
  parameter LSB_WIDTH = 4,
  parameter LSB_SIZE = 2**LSB_WIDTH,
  parameter ROB_OP_WIDTH = 2,
  parameter LSB_OP_WIDTH = 3
) (
  input  wire                 resetIn,      // resetIn
  input  wire                 clockIn,      // clockIn
  output wire                 lsbUpdate,    // load & store buffer update signal
  output wire [ROB_WIDTH-1:0] lsbRobIndex,  // load & store buffer rob index
  output wire [31:0]          lsbUpdateVal, // load & store buffer value

  // DCache part
  input  wire        dataValid,    // data input valid signal
  input  wire [31:0] dataIn,       // data
  input  wire        dataWriteSuc, // data write success sign
  output wire [1:0]  accessType,   // access type (none: 2'b00, byte: 2'b01, half word: 2'b10, word: 2'b11)
  output wire        readWriteOut, // read/write select (read: 1, write: 0)
  output wire [31:0] dataAddr,     // data address
  output wire [31:0] dataOut,      // data to write

  // Reorder Buffer part
  input wire [ROB_WIDTH-1:0] robBeginId,    // begin index of the load & store buffer
  input wire                 robBeginValid, // has committed signal

  // Reservation Station part
  input  wire                    rsUpdate,    // reservation station update signal
  input  wire [ROB_WIDTH-1:0]    rsRobIndex,  // reservation station rob index
  input  wire [31:0]             rsUpdateVal, // reservation station value

  // Instruction Unit part
  input  wire                    addValid,         // Instruction Unit add valid signal
  input  wire                    addReadWrite,     // Instruction Unit read/write select
  input  wire [ROB_WIDTH-1:0]    addRobId,         // Instruction Unit rob index
  input  wire                    addBaseHasDep,    // Instruction Unit has dependency
  input  wire [31:0]             addBase,          // Instruction Unit add base addr
  input  wire [ROB_WIDTH-1:0]    addBaseConstrtId, // Instruction Unit add constraint index (RoB)
  input  wire [31:0]             addOffset,        // Instruction Unit add offset
  input  wire                    addDataHasDep,    // Instruction Unit has dependency
  input  wire [31:0]             addData,          // Instruction Unit add data
  input  wire [ROB_WIDTH-1:0]    addDataConstrtId, // Instruction Unit add constraint index (RoB)
  input  wire [LSB_OP_WIDTH-1:0] addOp,            // Instruction Unit add op
  output wire                    full              // full signal
);
endmodule
```

If the `resetIn` signal is high, or the `clearIn` signal is high, the
Load & Store Buffer module will clear all entries.

If the `accessTypeIn` signal is not `2'b00`, the Load & Store Buffer module
will process the entry. If the `loadStoreIn` signal is high, a load entry
be added; otherwise, a store entry will be added.

If the `updateValidIn` signal is high, the Load & Store Buffer module will
update the corresponding entry.

If the `dataWriteSuc` signal is high, the Load & Store Buffer module will
clear the top entry.

If the `dataReadValidIn` signal is high, the Load & Store Buffer module
will update the corresponding entry.

For the data that will be read or written, the Load & Store Buffer module
will read data from the [DCache module](cache.md#data-cache) or put the
data to [DCache module](cache.md#data-cache).
