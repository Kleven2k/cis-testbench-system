`default_nettype none
`timescale 1ns/1ps

module xadc_wrapper (
    input wire logic xadc_clk,
    input wire logic [1:0] xa_p,
    input wire logic [1:0] xa_n,

    output     logic [11:0] sensor_out,     // Signal from the image sensor
    output     logic [11:0] temp_out        // Signal to read the temperature 
);

    // Handshake signals
    wire enable, ready;
    wire [15:0] xadc_data;
    reg   [6:0] xadc_addr = 7'h10;

    // Instatiate XADC wizard
    xadc_wiz_0 XADC (
        .daddr_in(xadc_addr),
        .dclk_in(xadc_clk),
        .den_in(enable),
        .di_in(16'h0000),
        .dwe_in(1'b0),
        .vp_in(1'b0),
        .vn_in(1'b0),
        .busy_out(),
        .vauxp0(xa_p[1]),
        .vauxn0(xa_n[1]),
        .vauxp1(xa_p[0]),
        .vauxn1(xa_n[0]),
        .do_out(xadc_data),
        .eoc_out(enable),
        .channel_out(),
        .drdy_out(ready)
    );

    // XADC read logic
    always_ff @(posedge xadc_clk) begin 
        if (ready) begin 
            case (xadc_addr)
                // Read temperature output
                7'h11: temp_out   <= xadc_data[15:4];   // VAUX1 (pins 1/7)
                // Read img sensor output
                7'h10: sensor_out <= xadc_data[15:4];   // VAUX0 (pins 2/8)   
                
            endcase
        end 
    end 

    // cycle through ADC channels
    always_ff @(posedge xadc_clk) begin 
        if (ready) begin 
            case (xadc_addr)
                7'h11: xadc_addr <= 7'h10;  // Last address goes out and load new address in
                7'h10: xadc_addr <= 7'h11;
                default: xadc_addr <= 7'h10;
            endcase
        end 
    end

endmodule    