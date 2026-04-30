# ============================================================
# build.tcl — Vivado non-project batch build for CIS Testbench
#
# Runs: synth → opt → place → phys_opt → route → phys_opt → bitstream
# Each invocation writes to a timestamped runs/build_YYYYMMDD_HHMMSS/
# directory so previous builds are never overwritten.
#
# Usage (from repo root):
#   vivado -mode batch -source scripts/build.tcl
# ============================================================

set PART "xc7a200tsbg484-1"
set TOP  "cis_system_top"

# ── Timestamped output directory ──────────────────────────────────────────────
set TS      [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set RUN_DIR "runs/build_$TS"
file mkdir $RUN_DIR

puts "============================================================"
puts " CIS TESTBENCH BUILD"
puts " Part:    $PART"
puts " Top:     $TOP"
puts " Out dir: $RUN_DIR"
puts "============================================================"

# ── IP Cores ──────────────────────────────────────────────────────────────────
# XADC Wizard
read_ip cis_testbench_system.srcs/sources_1/ip/xadc_wiz_0/xadc_wiz_0.xci

# Block RAMs (OLED char library, init sequence ROM, pixel buffer)
read_ip hdl/rtl/display/OLED/ip/charLib/charLib.xci
read_ip hdl/rtl/display/OLED/ip/init_sequence_rom/init_sequence_rom.xci
read_ip hdl/rtl/display/OLED/ip/pixel_buffer/pixel_buffer.xci

generate_target all [get_ips]

# ── Sources — common ──────────────────────────────────────────────────────────
read_verilog -sv hdl/rtl/common/debounce.sv
read_verilog -sv hdl/rtl/common/async_reset.sv
read_verilog    hdl/rtl/common/sync_pulse.v

# ── Sources — clock ───────────────────────────────────────────────────────────
read_verilog -sv hdl/rtl/clock/clk_720p.sv

# ── Sources — interface ───────────────────────────────────────────────────────
read_verilog -sv hdl/rtl/interface/cdc_adc_sync.sv

# ── Sources — UART ────────────────────────────────────────────────────────────
read_verilog -sv hdl/rtl/uart/uart_rx.sv
read_verilog -sv hdl/rtl/uart/uart_tx.sv
read_verilog -sv hdl/rtl/uart/uart_top.sv
read_verilog -sv hdl/rtl/uart/uart_reg_if.sv

# ── Sources — control (mixed language) ────────────────────────────────────────
read_vhdl       hdl/rtl/control/sensor_ctrl.vhd
read_verilog -sv hdl/rtl/control/control_regs.sv

# ── Sources — OLED display driver ─────────────────────────────────────────────
read_verilog    hdl/rtl/display/OLED/delay_ms.v
read_verilog    hdl/rtl/display/OLED/SpiCtrl.v
read_verilog    hdl/rtl/display/OLED/OLED_ctrl.v
read_verilog    hdl/rtl/display/OLED/OLED_master.v

# ── Sources — HDMI display chain ──────────────────────────────────────────────
read_verilog -sv hdl/rtl/display/tmds_encoder_dvi.sv
read_verilog -sv hdl/rtl/display/oserdes_10b.sv
read_verilog -sv hdl/rtl/display/tmds_out.sv
read_verilog -sv hdl/rtl/display/dvi_generator.sv

# ── Sources — video timing and pixel renderer ─────────────────────────────────
read_verilog -sv hdl/rtl/gui/simple_720p.sv
read_verilog -sv hdl/rtl/gui/simple_pixel.sv

# ── Sources — top level (last) ────────────────────────────────────────────────
read_verilog -sv hdl/rtl/top/cis_system_top.sv

# ── Constraints ───────────────────────────────────────────────────────────────
read_xdc constraints/nexys_video.xdc
read_xdc constraints/timing.xdc

# ── Synthesis ─────────────────────────────────────────────────────────────────
puts "\n--- Synthesis ---"
synth_design -top $TOP -part $PART
write_checkpoint -force "$RUN_DIR/post_synth.dcp"
report_utilization    -file "$RUN_DIR/util_synth.rpt"
report_timing_summary -file "$RUN_DIR/timing_synth.rpt"

# ── Implementation ────────────────────────────────────────────────────────────
puts "\n--- Optimize ---"
opt_design

puts "\n--- Place ---"
place_design
write_checkpoint -force "$RUN_DIR/post_place.dcp"
report_timing_summary -file "$RUN_DIR/timing_place.rpt"

puts "\n--- Physical optimization (post-place) ---"
phys_opt_design

puts "\n--- Route ---"
route_design
write_checkpoint -force "$RUN_DIR/post_route.dcp"

puts "\n--- Physical optimization (post-route) ---"
phys_opt_design

# ── Reports ───────────────────────────────────────────────────────────────────
puts "\n--- Reports ---"
report_timing_summary -file "$RUN_DIR/timing.rpt" -warn_on_violation
report_utilization    -file "$RUN_DIR/util.rpt"
report_power          -file "$RUN_DIR/power.rpt"
report_drc            -file "$RUN_DIR/drc.rpt"

# ── Bitstream ─────────────────────────────────────────────────────────────────
puts "\n--- Bitstream ---"
write_bitstream -force "$RUN_DIR/cis_testbench.bit"

puts "\n============================================================"
puts " BUILD COMPLETE: $RUN_DIR/cis_testbench.bit"
puts "============================================================"
