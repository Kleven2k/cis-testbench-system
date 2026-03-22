`default_nettype none
`timescale 1ns/1ps

module async_reset (
    input  wire logic clk,          // clock
    input  wire logic rst_in,       // asynchronous reset input
    output logic rst_out = 1'b1  // synchronized reset output
);

    (* ASYNC_REG = "TRUE" *) logic [1:0] rst_shf = 2'b11;

    always_ff @(posedge clk or posedge rst_in) begin
        if (rst_in)
            {rst_out, rst_shf} <= 3'b111;
        else
            {rst_out, rst_shf} <= {rst_shf, 1'b0};
    end

endmodule
