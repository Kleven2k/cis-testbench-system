# ============================================================
# cocotb Makefile — sensor_ctrl unit test
# Run from this directory: make
# ============================================================

SIM           ?= modelsim
TOPLEVEL_LANG  = vhdl

# Path from sim/cocotb/sensor_ctrl/ to repo root
ROOT = ../../..

VHDL_SOURCES = $(abspath $(ROOT)/hdl/rtl/control/sensor_ctrl.vhd)

TOPLEVEL = sensor_ctrl
MODULE   = test_sensor_ctrl

# Dump waveforms for GTKwave
VSIM_ARGS = -do wave.do

include $(shell cocotb-config --makefiles)/Makefile.sim
