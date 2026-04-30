`timescale 1ns/1ps
`default_nettype none

// Simulation wrapper for control_regs.
// All ports are exposed directly — no serial encoding needed since the
// DUT takes pre-decoded uart_write_en / uart_addr / uart_data bytes.

module control_regs_tb_wrapper (
    input  logic        clk,
    input  logic        rst,

    // Button pulses
    input  logic        delay_up,
    input  logic        delay_down,
    input  logic        dwell_up,
    input  logic        dwell_down,
    input  logic        start_btn,

    // Switches
    input  logic        sw_read_mode,
    input  logic        sw_cds_enable,

    // UART write interface
    input  logic        uart_write_en,
    input  logic [7:0]  uart_addr,
    input  logic [7:0]  uart_data,

    // UART read interface
    input  logic [7:0]  read_addr,
    output logic [7:0]  read_data,

    // Outputs to sensor_ctrl
    output logic [15:0] exposure_us,
    output logic [15:0] dwell_us,
    output logic [7:0]  reset_us,
    output logic [7:0]  cds_delay_us,
    output logic        read_mode,
    output logic        cds_enable,
    output logic        photosense_mode,
    output logic [1:0]  disp_gain,
    output logic        invert_pol,
    output logic        start_pulse,
    output logic        soft_reset
);

    control_regs u_dut (
        .clk            (clk),
        .rst            (rst),
        .delay_up       (delay_up),
        .delay_down     (delay_down),
        .dwell_up       (dwell_up),
        .dwell_down     (dwell_down),
        .start_btn      (start_btn),
        .sw_read_mode   (sw_read_mode),
        .sw_cds_enable  (sw_cds_enable),
        .uart_write_en  (uart_write_en),
        .uart_addr      (uart_addr),
        .uart_data      (uart_data),
        .read_addr      (read_addr),
        .read_data      (read_data),
        .exposure_us    (exposure_us),
        .dwell_us       (dwell_us),
        .reset_us       (reset_us),
        .cds_delay_us   (cds_delay_us),
        .read_mode      (read_mode),
        .cds_enable     (cds_enable),
        .photosense_mode(photosense_mode),
        .disp_gain      (disp_gain),
        .invert_pol     (invert_pol),
        .start_pulse    (start_pulse),
        .soft_reset     (soft_reset)
    );

    initial begin
        $dumpfile("sim_build/dump.vcd");
        $dumpvars(0, control_regs_tb_wrapper);
    end

endmodule

`default_nettype wire
