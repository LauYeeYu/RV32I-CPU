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
module LoadStoreBuffer
#(
  parameter ENTRY_WIDTH = 3,
  parameter ROB_WIDTH = 3,
  parameter ADDR_WIDTH = 17
)
(
  input  wire                  clkIn,             // system clock (from CPU)
  input  wire                  resetIn,           // resetIn (from CPU)
  input  wire                  readyIn,           // ready signal (from CPU)  
  input  wire                  clearIn,           // clear signal (for wrong branch prediction)
  input  wire                  loadStoreIn,       // read/write select (load: 1, store: 0)
  input  wire [1:0]            accessTypeIn,      // load type (none: 2'b00, byte: 2'b01, half word: 2'b10, word: 2'b11)
  input  wire [31:0]           baseIn,            // base address (from Instruction Unit)
  input  wire [ROB_WIDTH-1:0]  baseConstraintIn,  // base constraint (from Instruction Unit)
  input  wire [31:0]           offsetIn,          // offset (from Instruction Unit)
  input  wire [31:0]           valueIn,           // value (from Instruction Unit)
  input  wire [ROB_WIDTH-1:0]  valueConstraintIn, // value constraint (from Instruction Unit)
  input  wire                  updateValidIn,     // update valid signal (from Reorder Buffer)
  input  wire [ROB_WIDTH-1:0]  updateIndexIn,     // update constraint (from Reorder Buffer)
  input  wire [31:0]           updateValueIn,     // update value (from Reorder Buffer)
  input  wire                  dataWriteSuc,      // data write success signal (from Cache)
  input  wire                  dataReadValidIn,   // data read valid signal (from Cache)
  input  wire [31:0]           dataReadIn,        // data read output (from Cache)
  output wire                  readWriteOut,      // read/write select (read: 1, write: 0)
  output wire [1:0]            accessTypeOut,     // load type (none: 2'b00, byte: 2'b01, half word: 2'b10, word: 2'b11)
  output wire [ADDR_WIDTH-1:0] addrOut,           // address (to Cache)
  output wire [31:0]           valueOut,          // value (to Cache)
  output wire                  dataValidOut,      // data valid signal (to RoB)
  output wire [31:0]           dataOut,           // data output (to RoB)
  output wire [ROB_WIDTH-1:0]  dataConstraintOut, // data constraint (to RoB)
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
will read data from the [Cache module](cache.md) or put the data to
[Cache module](cache.md).
