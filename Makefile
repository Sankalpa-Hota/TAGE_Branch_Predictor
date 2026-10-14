# make            -> run every testbench (Verilator)
# make SIM=icarus -> run with Icarus Verilog
# make top | table | bimodal | fold | sram
# make lint       -> Verilator -Wall on the RTL
# make vectors    -> regenerate tests/*.txt (python3 scripts/gen_tests.py)
# Waveforms: build/<tb>.fst
SIM    ?= verilator
SEED   ?= 1
export PATH := /opt/homebrew/bin:$(PATH)
BREW   := $(shell brew --prefix 2>/dev/null || echo /opt/homebrew)
VFLAGS := --binary --timing --trace-fst -Wno-fatal -Wno-lint -Wno-style -j 0 \
          -CFLAGS -I$(BREW)/include -LDFLAGS -L$(BREW)/lib

PKG := rtl/tage_pkg.sv
RTL := $(PKG) rtl/sram_1r1w.sv rtl/folded_history.sv rtl/tage_bimodal.sv rtl/tage_table.sv rtl/tage_top.sv

all: sram fold bimodal table top

sram:    ; @$(MAKE) --no-print-directory run TOP=tb_sram_1r1w      SRCS="rtl/sram_1r1w.sv tb/tb_sram_1r1w.sv"
fold:    ; @$(MAKE) --no-print-directory run TOP=tb_folded_history SRCS="rtl/folded_history.sv tb/tb_folded_history.sv"
bimodal: ; @$(MAKE) --no-print-directory run TOP=tb_tage_bimodal   SRCS="$(PKG) rtl/sram_1r1w.sv rtl/tage_bimodal.sv tb/tb_tage_bimodal.sv"
table:   ; @$(MAKE) --no-print-directory run TOP=tb_tage_table     SRCS="$(PKG) rtl/sram_1r1w.sv rtl/tage_table.sv tb/tb_tage_table.sv"
top:     ; @$(MAKE) --no-print-directory run TOP=tb_tage_top       SRCS="$(RTL) tb/tb_tage_top.sv"

run:
	@mkdir -p build
ifeq ($(SIM),icarus)
	iverilog -g2012 -o build/$(TOP).vvp -s $(TOP) $(SRCS)
	vvp -n build/$(TOP).vvp -fst
else
	verilator $(VFLAGS) --Mdir build/$(TOP) --top-module $(TOP) $(SRCS) -o sim
	./build/$(TOP)/sim +verilator+seed+$(SEED) +verilator+error+limit+20
endif

lint:
	verilator --lint-only -Wall --top-module tage_top $(RTL)

vectors:
	python3 scripts/gen_tests.py $(SEED)

clean:
	rm -rf build

.PHONY: all sram fold bimodal table top run lint vectors clean
