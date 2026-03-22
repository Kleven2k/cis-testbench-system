# ============================================================
# ModelSim compile script — STUB-BASED SIMULATION
# CIS_SYSTEM_TOP
# ============================================================

# ------------------------------------------------------------
# Clean & setup
# ------------------------------------------------------------
quit -sim
vdel -all
vlib work
vmap work work

# ------------------------------------------------------------
# RTL (synthesizable logic ONLY)
# ------------------------------------------------------------

# Common / utility
vlog -sv ../../hdl/rtl/common/async_reset.sv
vlog -sv ../../hdl/rtl/common/sync_pulse.v

# Control
vcom -2008 ../../hdl/rtl/control/sensor_ctrl.vhd

# GUI / pixel logic
vlog -sv ../../hdl/rtl/gui/simple_pixel.sv

# CDC
vlog -sv ../../hdl/rtl/interface/cdc_adc_sync.sv

# Top-level
vlog -sv ../../hdl/rtl/top/cis_system_top.sv

# ------------------------------------------------------------
# STUBS (override IP / physical modules)
# ------------------------------------------------------------
vlog -sv ../../hdl/tb/stubs/clk_720p_stub.sv
vlog -sv ../../hdl/tb/stubs/debounce_stub.sv
vlog -sv ../../hdl/tb/stubs/simple_720p_stub.sv
vlog -sv ../../hdl/tb/stubs/dvi_generator_stub.sv
vlog -sv ../../hdl/tb/stubs/tmds_out_stub.sv
vlog -sv ../../hdl/tb/stubs/xadc_wiz_0_stub.sv

# ------------------------------------------------------------
# Testbench (compile LAST)
# ------------------------------------------------------------
vlog -sv ../../hdl/tb/tb_cis_system_top.sv

# ------------------------------------------------------------
# Run simulation
# ------------------------------------------------------------
vsim -voptargs=+acc work.tb_cis_system_top
add wave -r /*
run -all
