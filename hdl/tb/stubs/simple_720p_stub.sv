timeunit 1ns;
timeprecision 1ps;

module simple_720p (
    input  logic clk_pix,
    input  logic rst_pix,
    output logic [11:0] sx,
    output logic [11:0] sy,
    output logic hsync,
    output logic vsync,
    output logic de
);
    always_ff @(posedge clk_pix) begin 
        if (rst_pix) begin 
            sx <= 0; sy <= 0;
        end else begin 
            sx <= sx + 1;
            if (sx == 1280) begin 
                sx <= 0;
                sy <= sy + 1;
            end 
        end 
        de <= 1;
        hsync <= 0;
        vsync <= 0;
    end 
endmodule