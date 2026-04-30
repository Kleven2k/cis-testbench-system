`timescale 1ns/1ps
`default_nettype none

// Simulation wrapper for cdc_adc_sync.
// clk_src = 100 MHz (10 ns), clk_dst = 74.25 MHz (~13.47 ns).
// The test drives data_sensor_in / data_temp_in / data_valid on clk_src
// and reads data_sensor_out / data_temp_out on clk_dst.

module cdc_adc_sync_tb_wrapper (
    input  logic        clk_src,
    input  logic        clk_dst,
    input  logic [11:0] data_sensor_in,
    input  logic [11:0] data_temp_in,
    input  logic        data_valid,
    output logic [11:0] data_sensor_out,
    output logic [11:0] data_temp_out
);

    cdc_adc_sync u_dut (
        .clk_src        (clk_src),
        .clk_dst        (clk_dst),
        .data_sensor_in (data_sensor_in),
        .data_temp_in   (data_temp_in),
        .data_valid     (data_valid),
        .data_sensor_out(data_sensor_out),
        .data_temp_out  (data_temp_out)
    );

    initial begin
        $dumpfile("sim_build/dump.vcd");
        $dumpvars(0, cdc_adc_sync_tb_wrapper);
    end

endmodule

`default_nettype wire
