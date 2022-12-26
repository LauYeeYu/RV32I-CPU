# Cache

Cache includes instruction cache (icache) and data cache (dcache).

In this design, every data is read from cache. Instruction cache is read
only, while data cache can be either written or read.

## Cache Module

The Cache module is located at `src/cache.v`.

Cache module, linked to RAM is the only way to access memory. Cache module
have two submodule - [`icache`](#instruction-cache) and
[`dcache`](#data-cache).

The [Instruction Cache module](#instruction-cache) handles instruction
requests from the [Instruction Unit](instruction_unit.md), while the
[Data Cache module](#data-cache) handles data requests from the
[Load/Store Buffer](load_store_buffer.md).

When the [Instruction Cache module](#instruction-cache) and the
[Data Cache module](#data-cache) wants data at the same time, the Cache
module will prioritise the [Data Cache module](#data-cache) to avoid the
endless request from the [Instruction Unit](instruction_unit.md).

The interfaces are listed below:
```verilog
module Cache #(
  parameter BLOCK_WIDTH = 4,
  parameter BLOCK_SIZE = 2**BLOCK_WIDTH,
  parameter ICACHE_WIDTH = 8,
  parameter DCACHE_WIDTH = 9
) (
  input  wire        clkIn,         // system clock (from CPU)
  input  wire        resetIn,       // resetIn (from CPU)
  input  wire        readyIn,       // ready signal (from CPU)
  input  wire [7:0]  memIn,         // data from RAM
  input  wire        instrInValid,  // instruction valid signal (Instruction Unit)
  input  wire [31:0] instrAddrIn,   // instruction address (Instruction Unit)
  input  wire [1:0]  accessType,    // access type (none: 2'b00, byte: 2'b01, half word: 2'b10, word: 2'b11)
  input  wire        readWriteIn,   // read/write select (read: 1, write: 0)
  input  wire [31:0] dataAddrIn,    // data address (from Load Store Buffer)
  input  wire [31:0] dataIn,        // data to write (from Load Store Buffer)
  output wire        readWriteOut,  // read/write select (read: 1, write: 0)
  output wire [31:0] memAddr,       // memory address
  output wire [7:0]  memOut,        // write data to RAM
  output wire        instrOutValid, // instruction output valid signal (Instruction Unit)
  output wire [31:0] instrOut,      // instruction (Instruction Unit)
  output wire        dataOutValid,  // data output valid signal (Load Store Buffer)
  output wire [31:0] dataOut,       // data (Load Store Buffer)
  output wire        dataWriteSuc   // data write success signal (Load Store Buffer)
);
endmodule
```

If the `resetIn` signal is high, the Cache module will reset all stored cache.

The whole Cache module is on if and only if `readyIn` is high.

The `memIn` signal is the data from RAM. Note that the data is sent one clock
after the request is sent.

When the `instrInValid` signal is high, the Cache module will find the data in
the [Instruction Cache module](#instruction-cache) and send it through the
`instrOut` signal (the `instrOutValid` is high then).

When the `dataValid` signal is high, the Cache module will find the data in
the [Data Cache module](#data-cache) and send it through the `dataOut` signal
(the `dataOutValid` is high then).

When the dcache module encounters IO port data, the cache module will handle
this request instead.

## Instruction Cache

The Instruction Cache module is located at `src/icache.v`.

Since instruction cache needs absolutely minimum time to access, it is
designed to be direct-mapped.

Instruction cache works when `instrInValid` is high. When `instrInValid`
is high, the instruction cache will check the tag of the address. If the
tag is correct, the instruction cache will return the data. If the tag is
incorrect, the `miss` signal will be high, and the
[Cache module](#cache-module) will read the data from RAM and send the data
through `memDataIn` (`memDataValid` is set high then).

The interfaces are listed below:
```verilog
module ICache #(
  parameter BLOCK_WIDTH = 4,
  parameter BLOCK_SIZE = 2**BLOCK_WIDTH,
  parameter CACHE_WIDTH = 8,
  parameter CACHE_SIZE = 2**CACHE_WIDTH
) (
  input  wire                            clkIn,         // system clock (from CPU)
  input  wire                            resetIn,       // resetIn
  input  wire                            instrInValid,  // instruction valid signal (Instruction Unit)
  input  wire [31:0]           instrAddrIn,   // instruction address (Instruction Unit)
  input  wire                            memDataValid,  // data valid signal (Instruction Unit)
  input  wire [31:BLOCK_WIDTH] memAddr,       // memory address
  input  wire [BLOCK_SIZE*8-1:0]         memDataIn,     // data to loaded from RAM
  output wire                            miss,          // miss signal
  output wire                            instrOutValid, // instruction output valid signal (Instruction Unit)
  output wire [31:0]                     instrOut,      // instruction (Instruction Unit)
  output wire [31:0]           instrAddrOut   // instruction address (Instruction Unit)
);
endmodule
```

If the `resetIn` signal is high, the instruction cache will reset all stored
cache.

When the `instrInValid` signal is high, the instruction cache will check the
tag of the address. If the tag is correct, the instruction cache will return
the data through `instrOut` (`instrOutValid` is also set high). If the tag is
incorrect, the `miss` signal will be high, and the
[Cache module](#cache-module) will read the data from RAM and send the data
through `memDataIn` (`memDataValid` is set high then).

## Data Cache

The Data Cache module is located at `src/dcache.v`.

Data cache is designed to be direct mapping. The Data Cache module is capable
of handling both read and write requests.

The data is always aligned to the lower end. To be specific, if the data is
of byte size, the data is well at `[7:0]`. If the data is of half word size,
the data is well at `[15:0]`. If the data is of word size, the data is well
at `[31:0]`.

Data Cache module will not synchronise with the memory as soon as possible,
it will wait until the data must be removed from the cache. Therefore, when
data is written to the cache, there is a *dirty tag* to indicate that the
data is not the same as the data in the memory.

The interfaces are listed below:
```verilog
module DCache #(
  parameter BLOCK_WIDTH = 4,
  parameter BLOCK_SIZE = 2**BLOCK_WIDTH,
  parameter CACHE_WIDTH = 9,
  parameter CACHE_SIZE = 2**CACHE_WIDTH
) (
  input  wire                    clkIn,             // system clock (from CPU)
  input  wire                    resetIn,           // resetIn
  input  wire [1:0]              accessType,        // access type (none: 2'b00, byte: 2'b01, half word: 2'b10, word: 2'b11)
  input  wire                    readWriteIn,       // read/write select (read: 1, write: 0)
  input  wire [31:0]             dataAddrIn,        // data address (Load & Store Buffer)
  input  wire [31:0]             dataIn,            // data to write
  input  wire                    memDataValid,      // data valid signal
  input  wire [31:BLOCK_WIDTH]   memAddr,           // memory address
  input  wire [BLOCK_SIZE*8-1:0] memDataIn,         // data to loaded from RAM
  input  wire                    acceptWrite,       // write accept signal (Cache)
  input  wire                    mutableMemInValid, // mutable memory valid signal
  input  wire [31:0]             mutableMemDataIn,  // data to load from IO
  input  wire                    mutableWriteSuc,   // mutable write success signal
  output wire                    miss,              // miss signal (for input and output)
  output wire [31:BLOCK_WIDTH]   missAddr,          // miss address (for input and output)
  output wire                    readWriteOut,      // read/write select for mem (read: 1, write: 0)
  output wire [31:BLOCK_WIDTH]   memAddrOut,        // data address
  output wire [BLOCK_SIZE*8-1:0] memOut,            // data to write
  output wire                    dataOutValid,      // data output valid signal (Load & Store Buffer)
  output wire [31:0]             dataOut,           // data (Load & Store Buffer)
  output wire                    dataWriteSuc       // data write success signal (Load Store Buffer)
);
endmodule
```

If the `resetIn` signal is high, the data cache will reset all stored cache.

The module will work when the `accessType` signal is not `2'b00`. `2'b01` means
the operation is done in byte, `2'b10` means the operation is done in half word,
and `2'b11` means the operation is done in word.

For the I/O port data (called *mutable* in cache module), the dcache module
will wait for the cache to send the data back (using `mutableMemInValid`,
`mutableMemDataIn` and `mutableWriteSuc`).

For the read operation (when `readWriteIn` is high), the data cache will check
whether the data is in the cache. If the data is in the cache, the data cache
will return the data through `dataOut` (`dataOutValid` is also set high). If
the data is not in the cache, the `miss` signal will be high, and the
[Cache module](#cache-module) will read the data from RAM and send the data
through `memDataIn` (`memDataValid` is set high then).

For the write operation (when `readWriteIn` is low), the data cache will check
whether the data is in the cache. If the data is in the cache, the data cache
will write the data to the cache, and set the `dataWriteSuc` high for one clock.
If the data is not in the cache, the `miss` signal will be high, and the
[Cache module](#cache-module) will read the data from RAM and send the data
through `memDataIn` (`memDataValid` is set high then). After the data is put
into the cache, the data cache will write the data to the cache, and set the
`dataWriteSuc` high for one clock.

On cache miss: If the block is dirty, the data cache will set the
`readWriteOut` to high, and set the dirty tag to low first. Then, whether
the block is dirty or not, the data cache will set the `readWriteOut` to low,
and wait for the data from the [Cache module](#cache-module) through
`memDataIn` (`memDataValid` is set high then).
