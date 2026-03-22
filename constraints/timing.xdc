###############################################################################
# timing.xdc
# Purpose: Timing constraints for cis_testbench_system on Nexys Video Artix-7
#
# IMPORTANT: After synthesis, run the following in the Tcl console to verify
# your exact MMCM pin paths before implementing:
#   get_pins -hierarchical -filter {NAME =~ *MMCME2*}
# Then update the create_generated_clock pin paths below to match.
###############################################################################

# ------------------------------------------------------------------------------
# Primary clock: 100 MHz on-board oscillator
# ------------------------------------------------------------------------------
create_clock -name clk_100m -period 10.000 [get_ports clk_100m]

# ------------------------------------------------------------------------------
# Pixel clock: generated from MMCM (e.g. 74.25 MHz for 720p60 = 13.468 ns)
# Adjust -period to match your MMCM CLKOUT1 configuration.
# Adjust pin path to match your actual MMCM instance hierarchy.
# ------------------------------------------------------------------------------
create_generated_clock -name clk_pix \
    -source [get_pins clk_pix_inst/MMCME2_BASE_inst/CLKIN1] \
    -master_clock clk_100m \
    [get_pins clk_pix_inst/MMCME2_BASE_inst/CLKOUT1]

# ------------------------------------------------------------------------------
# 5x pixel clock: for TMDS OSERDESE2 serializer (e.g. 371.25 MHz for 720p60)
# Adjust pin path to match your actual MMCM instance hierarchy.
# ------------------------------------------------------------------------------
create_generated_clock -name clk_pix_5x \
    -source [get_pins clk_pix_inst/MMCME2_BASE_inst/CLKIN1] \
    -master_clock clk_100m \
    [get_pins clk_pix_inst/MMCME2_BASE_inst/CLKOUT0]

# ------------------------------------------------------------------------------
# Clock domain crossing: treat all three domains as asynchronous.
# This prevents Vivado from reporting false timing violations across domains
# and is correct since MMCM output clocks are phase-aligned but CDC crossings
# in your design are handled explicitly.
# ------------------------------------------------------------------------------
set_clock_groups -asynchronous \
    -group [get_clocks clk_100m] \
    -group [get_clocks clk_pix] \
    -group [get_clocks clk_pix_5x]

# ------------------------------------------------------------------------------
# Input/Output delay constraints (adjust values to match your sensor interface
# timing requirements once characterised)
# ------------------------------------------------------------------------------
# Example: XADC auxiliary inputs have no setup/hold requirement (analog)
# No set_input_delay needed for xa_p / xa_n

# UART: relaxed I/O timing (low-speed async interface)
set_input_delay  -clock clk_100m -max 2.0 [get_ports uart_rx_in]
# UART TX is async serial at 115200 baud - no tight output timing needed
set_false_path -to [get_ports uart_tx_out]

# Buttons and switches: false paths (async, debounced in RTL)
set_false_path -from [get_ports btn_*]
set_false_path -from [get_ports sw[*]]

# Reset: false path (async reset, synchronised in RTL)
set_false_path -from [get_ports btn_rst_n]

# OLED SPI runs at ~1 MHz - no timing relationship to the 100 MHz clock
set_false_path -to [get_ports oled_*]

# OLED exposure-to-display string: integer division path, only updates on
# rare exposure_pulse events. Allow 2 clock cycles to close timing.
set_multicycle_path -setup 2 -from [get_cells {u_oled/exposure_latched_reg[*]}] -to [get_cells {u_oled/splash_str2_reg[*]}]
set_multicycle_path -hold  1 -from [get_cells {u_oled/exposure_latched_reg[*]}] -to [get_cells {u_oled/splash_str2_reg[*]}]

# HDMI outputs: timing is governed by clk_pix_5x via OSERDESE2.
# TMDS pins are purely output-registered — no additional I/O delay needed
# beyond what the generated clock constraint provides.
set_false_path -to [get_ports hdmi_tx_*]
