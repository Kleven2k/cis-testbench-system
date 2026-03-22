timeunit 1ns;
timeprecision 1ps;

module clk_720p (
    input  logic clk_100m,
    input  logic rst,
    output logic clk_pix,
    output logic clk_pix_5x,
    output logic clk_pix_locked
);
    initial clk_pix = 0;
    always #13.5 clk_pix = ~clk_pix;    // ~74 MHz-ish

    initial clk_pix_5x = 0;
    always #2.7 clk_pix_5x = ~clk_pix_5x;

    initial begin 
        clk_pix_locked = 0;
        #200 clk_pix_locked = 1;
    end 
endmodule