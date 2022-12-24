# Reservation Station & ALU

## Reservation Station Operators
| num | binary  |        operator        | abbr |
|:---:|:-------:|:----------------------:|:----:|
|  0  | `0000`  |          add           | ADD  |
|  1  | `0001`  |          sub           | SUB  |
|  2  | `0010`  |          xor           | XOR  |
|  3  | `0011`  |           or           |  OR  |
|  4  | `0100`  |          and           | AND  |
|  5  | `0101`  |   shift left logical   | SLL  |
|  6  | `0110`  |  shift right logical   | SRL  |
|  7  | `0111`  | shift right arithmetic | SRA  |
|  8  | `1000`  |         equal          |  EQ  |
|  9  | `1001`  |       not equal        |  NE  |
| 10  | `1010`  |       less than        |  LT  |
| 11  | `1011`  |   less than unsigned   | LTU  |
| 12  | `1100`  |        reserved        |  -   |
| 13  | `1101`  |        reserved        |  -   |
| 14  | `1110`  |        reserved        |  -   |
| 15  | `1111`  |        reserved        |  -   |

## Reservation Station Module

The Reservation Station module is located at `src/reservation_station.v`.

The reservation station have 16 lines of data. The number cannot be modified
easily because there is some hard-coded logic in the reservation station.

The ALU section is also included in the Reservation Station Module in order
to reduce the number of wires and the latency caused by the distance of wires.

The interfaces are listed below:
    
```verilog
module ReservationStation #(
parameter RS_OP_WITDTH = 4,
parameter RS_WIDTH = 4,
parameter ROB_WIDTH = 4
) (
input  wire resetIn,   // reset signal
input  wire clockIn,   // clock signal

// Instruction Unit part
input  wire                    addValid,    // add valid signal
input  wire [RS_OP_WITDTH-1:0] addOp,       // add op
input  wire [ROB_WIDTH-1:0]    addRobIndex, // add rob index
input  wire [31:0]             addVal1,     // add value1
input  wire                    addHasDep1,  // add value1 dependency
input  wire [ROB_WIDTH-1:0]    addConstrt1, // add value1 constraint
input  wire [31:0]             addVal2,     // add value2
input  wire                    addHasDep2,  // add value2 dependency
input  wire [ROB_WIDTH-1:0]    addConstrt2, // add value2 constraint
output wire                    full,        // full signal
output wire                    update,      // update signal
output wire [ROB_WIDTH-1:0]    updateRobId, // rob index
output wire [31:0]             updateVal,   // value

// Load & Store Buffer part
input  wire                    lsbUpdate,    // load & store buffer update signal
input  wire [ROB_WIDTH-1:0]    lsbRobIndex,  // load & store buffer rob index
input  wire [31:0]             lsbUpdateVal  // load & store buffer value
);
endmodule
```

On the positive edge of the clock signal, the module will do several things
- adds new line if the `addValid` is high,
- pushes a line that both values are ready to the ALU section,
- updates the value that constrained by the update data from
  [Load & Store Buffer](load_store_buffer.md),
- updates the value that constrained by the data calculated last clock,
- sends the updated data out.
