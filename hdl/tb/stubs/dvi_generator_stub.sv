timeunit 1ns;
timeprecision 1ps;

module dvi_generator (
    input  logic clk_pix,
    input  logic clk_pix_5x,
    input  logic rst_pix,
    input  logic de,
    input  logic [7:0] data_in_ch0,
    input  logic [7:0] data_in_ch1,
    input  logic [7:0] data_in_ch2,
    input  logic [1:0] ctrl_in_ch0,
    input  logic [1:0] ctrl_in_ch1,
    input  logic [1:0] ctrl_in_ch2,
    output logic tmds_ch0_serial,
    output logic tmds_ch1_serial,
    output logic tmds_ch2_serial,
    output logic tmds_clk_serial
);
    always_ff @(posedge clk_pix_5x) begin
        tmds_ch0_serial <= ^data_in_ch0;
        tmds_ch1_serial <= ^data_in_ch1;
        tmds_ch2_serial <= ^data_in_ch2;
        tmds_clk_serial <= ~tmds_clk_serial;
    end
endmodule
