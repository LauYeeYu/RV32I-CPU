# Register File

The register file stores everything about data registers, including the
current value of registers, and each constraint of registers (if one
has). According to the specification of RV32I (unprivileged ISA), there
are 32 registers with 32-bit width.

## Register File Module

The Register File module is located at `src/register_file.v`.

The register file module handles the dependency of registers.

Please note that the value of register0 is always 0.

The interfaces are listed below:

```verilog
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
endmodule
```

On the same stage as instruction fetch, the register file module will check
the dependency of registers and ask the status of the data from the
[Reorder Buffer module](reorder_buffer.md) through `robRs1Dep` and
`robRs2Dep`. A value (through `rs1Value` or `rs2Value`) will be sent to the
[Instruction Unit module](instruction_unit.md) if the data is ready, or the
index of the constraint (through `rs1Dependency` or `rs2Dependency`) in the
[Reorder Buffer module](reorder_buffer.md).

When the `rfUpdateValid` signal (from the
[Instruction Unit module](instruction_unit.md)) is high, the register file
module will update the constraint of the register.

When the `regUpdateValid` signal (from the
[Reorder Buffer module](reorder_buffer.md)) is high, the register file
module will update the value of the register.

There is a combination circuit that handles the request from the
[Load & Store Buffer module](load_store_buffer.md) to read the value of a
register. The `lsbRegIndex` is the index of the register, and the
`lsbRegValue` is the value of the register. Please note that the dependency
of the register needn't be cared about.
