RISCV_TOOLCHAIN = /opt/riscv
RISCV_VERSION = $(shell ls $(RISCV_TOOLCHAIN)/lib/gcc/riscv32-unknown-elf/)
RISCV_BIN_PREFIX = $(addsuffix /bin/riscv32-unknown-elf-, $(RISCV_TOOLCHAIN))
RISCV_LIB = $(addsuffix /riscv32-unknown-elf/lib/, $(RISCV_TOOLCHAIN))
RISCV_GCC_LIB = $(addsuffix $(addprefix /lib/gcc/riscv32-unknown-elf/, $(RISCV_VERSION)), $(RISCV_TOOLCHAIN))

SRC = src
TESTSPACE = testspace
SIM_TESTCASE = testcase/sim
FPGA_TESTCASE = testcase/fpga
SIM = sim
SYS = sys

SRC_FILES = $(shell find $(SRC) -name '*.v')
SRC_HEADERS = $(shell find $(SRC) -name '*.vh')
SIM_FILES = $(shell find $(SIM) -name '*.v')
SYS_FILES = $(shell find $(SYS) -name '*.h')
TESTCASE_C = $(shell ls $(SIM_TESTCASE)/*$(name)*.c)
TESTCASE_O = $(TESTCASE_C:.c=.o)
TESTCASE_OM = $(TESTCASE_C:.c=.om)
TESTCASE_DATA = $(TESTCASE_C:.c=.data)
TESTCASE_DUMP = $(TESTCASE_C:.c=.dump)

.PHONY: _no_testcase_name_check
_no_testcase_name_check:
	@$(if $(strip $(name)),, echo 'Missing Testcase Name')
	@$(if $(strip $(name)),, exit 1)

# All build result are put at testspace
.PHONY: build_sim
build_sim: $(SIM)/testbench.v $(SRC_FILES) $(SRC_HEADERS)
	iverilog -o $(TESTSPACE)/test $(VERILOG_FLAGS) $^

$(SYS)/rom.o: $(SYS)/rom.s
	$(RISCV_BIN_PREFIX)as -o $@ -march=rv32i $^

.precious: %.o
%.o: %.c $(SYS_FILES)
	$(RISCV_BIN_PREFIX)gcc -o $@ -DSIM -I $(SYS) -c $< -O2 -march=rv32i -mabi=ilp32 -Wall

.precious: %.om
%.om: sys/memory.ld %.o sys/rom.o
	$(RISCV_BIN_PREFIX)ld -T $^ -L $(RISCV_LIB) -L $(RISCV_GCC_LIB) -lc -lgcc -lm -lnosys -o $@

.precious: %.data
%.data: %.om
	$(RISCV_BIN_PREFIX)objcopy -O verilog $< $@

.precious: $(TESTSPACE)/test.dump
%.dump: %.om
	$(RISCV_BIN_PREFIX)objdump -D $< > $@

.PHONY: move_testcase
move_testcase: $(TESTCASE_OM) $(TESTCASE_DATA) $(TESTCASE_DUMP)
	cp $(TESTCASE_OM) $(TESTSPACE)/test.om
	cp $(TESTCASE_DATA) $(TESTSPACE)/test.data
	cp $(TESTCASE_DUMP) $(TESTSPACE)/test.dump

.PHONY: build_sim_test
build_sim_test: _no_testcase_name_check build_sim move_testcase

run_sim: build_sim_test
	@echo "------------------ Running Testcase $(TESTCASE) ------------------"
	@cd $(TESTSPACE) && ./test

.PHONY: clean
clean:
	rm -f $(SYS)/rom.o $(TESTSPACE)/test* $(SIM_TESTCASE)/*.om $(SIM_TESTCASE)/*.o $(SIM_TESTCASE)/*.data $(SIM_TESTCASE)/*.dump

.PHONY: test_sim
test_sim: run_sim
