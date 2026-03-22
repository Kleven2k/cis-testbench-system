

`default_nettype none
`timescale 1ns/1ps

// OBUFDS is documented in Xilinx UG471

module tmds_out (
    input  wire logic tmds,     // TMDS signal
    output      logic pin_p,    // positive differential signal pin
    output      logic pin_n     // negative differential signal pin
    );

    OBUFDS #(.IOSTANDARD("TMDS_33"))
        tmds_obufds (.I(tmds), .O(pin_p), .OB(pin_n));

endmodule