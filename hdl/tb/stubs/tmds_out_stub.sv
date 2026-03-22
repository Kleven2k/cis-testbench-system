timeunit 1ns;
timeprecision 1ps;

module tmds_out(input logic tmds, output logic pin_p, pin_n);
    assign pin_p = tmds;
    assign pin_n = ~tmds;
endmodule
