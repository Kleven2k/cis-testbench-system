timeunit 1ns;
timeprecision 1ps;

module debounce (
    input  logic clk,
    input  logic in,
    output logic out,
    output logic ondn,
    output logic onup
);
    logic in_d;

    always_ff @(posedge clk) begin
        in_d <= in;
        ondn <= in & ~in_d;
        onup <= ~in & in_d;
        out  <= in;
    end
endmodule
