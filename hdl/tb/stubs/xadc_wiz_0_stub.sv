timeunit 1ns;
timeprecision 1ps;

module xadc_wiz_0 (
    input  logic [6:0]  daddr_in,
    input  logic        dclk_in,
    input  logic        den_in,
    input  logic [15:0] di_in,
    input  logic        dwe_in,
    input  logic        vp_in,
    input  logic        vn_in,
    input  logic        reset_in,
    output logic        busy_out,
    input  logic        vauxp0,
    input  logic        vauxn0,
    input  logic        vauxp1,
    input  logic        vauxn1,
    output logic [15:0] do_out,
    output logic        eoc_out,
    output logic [4:0]  channel_out,
    output logic        drdy_out,
    output logic        eos_out,
    output logic        ot_out,
    output logic        vccaux_alarm_out,
    output logic        vccint_alarm_out,
    output logic        user_temp_alarm_out,
    output logic        alarm_out
);

    logic [15:0] adc_val = 16'h8000;

    always_ff @(posedge dclk_in) begin 
        eoc_out  <= 1'b1;
        drdy_out <= 1'b1;
        adc_val  <= adc_val + 16'h0100;
        do_out   <= adc_val;
    end 

    assign busy_out = 0;
    assign channel_out = 0;
    assign eos_out = 0;
    assign ot_out = 0;
    assign vccaux_alarm_out = 0;
    assign vccint_alarm_out = 0;
    assign user_temp_alarm_out = 0;
    assign alarm_out = 0;

endmodule