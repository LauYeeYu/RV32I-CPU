# RV32I CPU

This is a toy RV32I CPU, supporting all RV32I instructions except for the
`FENCE` instruction. It is written in Verilog and is synthesizable.

此爲一個簡易 RV32I CPU，支援所有除 `FENCE` 外的 RV32I 指令。此項目使用 Verilog 編寫，代碼可以綜合並實現。

All the simulation testcases in `riscv/testcase/sim/` are passed and all the
testcases in `riscv/testcase/fpga/` are passed on the FPGA board
(xc7a35tcpg236-1).

已通過所有模擬測試（位於 `riscv/testcase/sim/` 目錄下），及所有 FPGA 測試（位於 `riscv/testcase/fpga/` 目錄下）。

This is an assignment of SJTU ACM class. For more information about this
assignment, click [here](https://github.com/ACMClassCourses/RISCV-CPU).

此項目爲 SJTU ACM 班課程作業。如需獲取更多關於此大作業的内容，點此檢視[詳情](https://github.com/ACMClassCourses/RISCV-CPU)。

## Documents 文檔

All the document is under `docs/` directory.

所有文檔位於 `docs/` 目錄下。

For the documents of development, see the [overview](docs/overview.md) part.
Most of the technical details, including the important logic of each module,
as well as the interface of each module, are well documented.

如需检视开发文檔，請參閱[概述](docs/overview.md)。絕大多數技術細節，包括每個模塊的關鍵邏輯，以及每個模塊的接口，均已在文檔中標明。

## How to Use 使用方法

*All the source code is under `riscv/` directory. Please make sure to be right
at the `riscv/` directory before doing the following things.*

*所有源代碼均位於 `riscv/` 目錄下。請確保在進行下述操作前已經切換到 `riscv/` 目錄下。*

### Simulation 模擬

Replace the `<testcase_name>` with the name of the testcase you want to run
(or the number at the beginning of the file name). You may also use other
testcase by just putting the testcase under `riscv/testcase/sim/` directory.

將 `<testcase_name>` 替換為你想要運行的測試用例名稱（或者是文件名前綴的數字）。你也可以將其他測試用例放在
`riscv/testcase/sim/` 目錄下。

#### Running 運行

```bash
$ make test_sim name=<testcase_name>
```

#### Debugging 調試

```bash
$ make test_sim_debug name=<testcase_name>
```

### FPGA

You may synthesize and implement this project and run it on the FPGA board.
For the board xc7a35tcpg236-1, you can also use the bitstream file in the
project release (named as `bitstream_xc7a35tcpg236-1.bit`).

你可以將此項目綜合並實現，並在 FPGA 板上運行。如果你使用的是 xc7a35tcpg236-1
板，你也可以使用項目發布中的 bitstream 文件（`bitstream_xc7a35tcpg236-1.bit`）。

## Features 特性
*For things about the instructions, see the
[supported instructions](#Supported-Instructions-支援指令) section.*

*有關指令的內容，請參閱[支援指令](#Supported-Instructions-支援指令)部分。*

- Out-of-order execution (Tomasulo algorithm)

  亂序執行（Tomasulo 算法）
- Branch prediction

  分支預測

## Supported Instructions 支援指令

The instructions are all RV32I instructions. See the
[official website](https://riscv.org/) and the
[specification page](https://riscv.org/specifications/) for more information.

支援的指令均爲 RV32I 指令。如需獲取更多關於指令的信息，請參閱[官方網站](https://riscv.org/)和[規範頁面](https://riscv.org/specifications/)。

| Instruction | Description                              |
|:-----------:|------------------------------------------|
|     LUI     | Load Upper Immediate                     |
|    AUIPC    | Add Upper Immediate to PC                |
|     JAL     | Jump and Link                            |
|    JALR     | Jump and Link Register                   |
|     BEQ     | Branch if Equal                          |
|     BNE     | Branch if Not Equal                      |
|     BLT     | Branch if Less Than                      |
|     BGE     | Branch if Greater Than or Equal          |
|    BLTU     | Branch if Less Than Unsigned             |
|    BGEU     | Branch if Greater Than or Equal Unsigned |
|     LB      | Load Byte                                |
|     LH      | Load Halfword                            |
|     LW      | Load Word                                |
|     LBU     | Load Byte Unsigned                       |
|     LHU     | Load Halfword Unsigned                   |
|     SB      | Store Byte                               |
|     SH      | Store Halfword                           |
|     SW      | Store Word                               |
|    ADDI     | Add Immediate                            |
|    SLTI     | Set on Less Than Immediate               |
|    SLTIU    | Set on Less Than Immediate Unsigned      |
|    XORI     | Exclusive OR Immediate                   |
|     ORI     | OR Immediate                             |
|    ANDI     | AND Immediate                            |
|    SLLI     | Shift Left Logical                       |
|    SRLI     | Shift Right Logical                      |
|    SRAI     | Shift Right Arithmetic                   |
|     ADD     | Add                                      |
|     SUB     | Subtract                                 |
|     SLL     | Shift Left Logical                       |
|     SLT     | Set on Less Than                         |
|    SLTU     | Set on Less Than Unsigned                |
|     XOR     | Exclusive OR                             |
|     SRL     | Shift Right Logical                      |
|     SRA     | Shift Right Arithmetic                   |
|     OR      | OR                                       |
|     AND     | AND                                      |

### Instruction Format 指令格式
```text
31           25 24         20 19         15 14 12 11          7 6       0
+--------------+-------------+-------------+-----+-------------+---------+
|                   imm[31:12]                   |     rd      | 0110111 | LUI
|                   imm[31:12]                   |     rd      | 0010111 | AUIPC
|             imm[20|10:1|11|19:12]              |     rd      | 1101111 | JAL
|         imm[11:0]          |     rs1     | 000 |     rd      | 1100111 | JALR 
| imm[12|10:5] |     rs2     |     rs1     | 000 | imm[4:1|11] | 1100011 | BEQ
| imm[12|10:5] |     rs2     |     rs1     | 001 | imm[4:1|11] | 1100011 | BNE
| imm[12|10:5] |     rs2     |     rs1     | 100 | imm[4:1|11] | 1100011 | BLT
| imm[12|10:5] |     rs2     |     rs1     | 101 | imm[4:1|11] | 1100011 | BGE
| imm[12|10:5] |     rs2     |     rs1     | 110 | imm[4:1|11] | 1100011 | BLTU
| imm[12|10:5] |     rs2     |     rs1     | 111 | imm[4:1|11] | 1100011 | BGEU
|         imm[11:0]          |     rs1     | 000 |     rd      | 0000011 | LB
|         imm[11:0]          |     rs1     | 001 |     rd      | 0000011 | LH
|         imm[11:0]          |     rs1     | 010 |     rd      | 0000011 | LW
|         imm[11:0]          |     rs1     | 100 |     rd      | 0000011 | LBU
|         imm[11:0]          |     rs1     | 101 |     rd      | 0000011 | LHU
|  imm[11:5]   |     rs2     |     rs1     | 000 |  imm[4:0]   | 0100011 | SB
|  imm[11:5]   |     rs2     |     rs1     | 001 |  imm[4:0]   | 0100011 | SH
|  imm[11:5]   |     rs2     |     rs1     | 010 |  imm[4:0]   | 0100011 | SW
|         imm[11:0]          |     rs1     | 000 |     rd      | 0010011 | ADDI
|         imm[11:0]          |     rs1     | 010 |     rd      | 0010011 | SLTI
|         imm[11:0]          |     rs1     | 011 |     rd      | 0010011 | SLTIU
|         imm[11:0]          |     rs1     | 100 |     rd      | 0010011 | XORI
|         imm[11:0]          |     rs1     | 110 |     rd      | 0010011 | ORI
|         imm[11:0]          |     rs1     | 111 |     rd      | 0010011 | ANDI
|   0000000    |    shamt    |     rs1     | 001 |     rd      | 0010011 | SLLI
|   0000000    |    shamt    |     rs1     | 101 |     rd      | 0010011 | SRLI
|   0100000    |    shamt    |     rs1     | 101 |     rd      | 0010011 | SRAI
|   0000000    |     rs2     |     rs1     | 000 |     rd      | 0110011 | ADD
|   0100000    |     rs2     |     rs1     | 000 |     rd      | 0110011 | SUB
|   0000000    |     rs2     |     rs1     | 001 |     rd      | 0110011 | SLL
|   0000000    |     rs2     |     rs1     | 010 |     rd      | 0110011 | SLT
|   0000000    |     rs2     |     rs1     | 011 |     rd      | 0110011 | SLTU
|   0000000    |     rs2     |     rs1     | 100 |     rd      | 0110011 | XOR
|   0000000    |     rs2     |     rs1     | 101 |     rd      | 0110011 | SRL
|   0100000    |     rs2     |     rs1     | 101 |     rd      | 0110011 | SRA
|   0000000    |     rs2     |     rs1     | 110 |     rd      | 0110011 | OR
|   0000000    |     rs2     |     rs1     | 111 |     rd      | 0110011 | AND
```
