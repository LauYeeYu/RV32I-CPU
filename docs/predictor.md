# Predictor

The predictor will predict which branch will probably be taken when
encounters branch statement. [Reorder buffer](#reorder-buffer) gives
predictor data to predict.

## Predictor Module

The Predictor Module is located at `src/predictor.v`.

The Predictor Module is a 2-bit saturating counter. It will predict
which branch will probably be taken when encounters branch statement.

The interfaces are listed below:

```verilog
module predictor #(
  parameter LOCAL_WIDTH = 12,
  parameter LOCAL_SIZE = 2**LOCAL_WIDTH,
) (
  input  wire        resetIn,       // resetIn
  input  wire        clockIn,       // clockIn
  input  wire        instrInValid,  // instruction valid signal (icache)
  input  wire [31:0] instrIn,       // data valid signal (icache)
  input  wire [31:0] instrAddr,     // instruction address (icache)
  input  wire        updateValid,   // update valid signal (Reorder Buffer)
  input  wire [31:0] updateInstr,   // instruction (Reorder Buffer)
  input  wire        taken,         // taken signal (Reorder Buffer)
  output wire        jump,          // jump signal
);
endmodule
```