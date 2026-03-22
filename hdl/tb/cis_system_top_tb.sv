`timescale 1ns/1ps
module cis_system_top_tb;

    // -----------------------------
    // Parameters
    // -----------------------------
    parameter CORDW = 12;

    // -----------------------------
    // Signals
    // -----------------------------
    logic clk_100m;
    logic btn_rst_n;

    logic [1:0] xa_p, xa_n;

    logic btn_start;
    logic btn_delay_up, btn_delay_down;
    logic btn_dwell_delay_up, btn_dwell_delay_down;

    logic [6:0] sw;

    logic [7:0] ja;

    // OLED
    logic oled_sdin, oled_sclk, oled_dc, oled_res, oled_vbat, oled_vdd;

    // UART
    logic uart_rx_in, uart_tx_out;

    logic hdmi_tx_ch0_p, hdmi_tx_ch0_n;
    logic hdmi_tx_ch1_p, hdmi_tx_ch1_n;
    logic hdmi_tx_ch2_p, hdmi_tx_ch2_n;
    logic hdmi_tx_clk_p, hdmi_tx_clk_n;

    // -----------------------------
    // Clock generation
    // -----------------------------
    initial clk_100m = 0;
    always #5 clk_100m = ~clk_100m; // 100 MHz

    // -----------------------------
    // Reset generation
    // -----------------------------
    initial begin
        btn_rst_n = 1;
        #100;           // hold reset for 100 ns
        btn_rst_n = 0;
    end 

    // -----------------------------
    // Stimulus
    // -----------------------------
    initial begin 
        // Initialize inputs
        xa_p = 2'b00;
        xa_n = 2'b00;
        btn_start = 0;
        btn_delay_up = 0;
        btn_delay_down = 0;
        btn_dwell_delay_up = 0;
        btn_dwell_delay_down = 0;
        uart_rx_in = 1;  // idle high
        sw = 7'b0;

        // Wait for reset release
        @(negedge btn_rst_n)

        // Example: press start button after 200 ns
        #200;
        btn_start = 1;
        #10;
        btn_start = 0;

        // Example: Toggle a delay button
        #1000;
        btn_delay_up = 1;
        #10;
        btn_delay_up = 0;

        // Run simulation long enough to observe ADC cycles
      #100000;
        $finish;
    end 

    // -----------------------------
    // Instantiate the DUT
    // -----------------------------
    cis_system_top #(
        .CORDW(CORDW)
    ) dut (
        .clk_100m(clk_100m),
        .btn_rst_n(btn_rst_n),
        .xa_p(xa_p),
        .xa_n(xa_n),
        .btn_start(btn_start),
        .btn_delay_up(btn_delay_up),
        .btn_delay_down(btn_delay_down),
        .btn_dwell_delay_up(btn_dwell_delay_up),
        .btn_dwell_delay_down(btn_dwell_delay_down),
        .sw(sw),
        .ja(ja),
        .hdmi_tx_ch0_p(hdmi_tx_ch0_p),
        .hdmi_tx_ch0_n(hdmi_tx_ch0_n),
        .hdmi_tx_ch1_p(hdmi_tx_ch1_p),
        .hdmi_tx_ch1_n(hdmi_tx_ch1_n),
        .hdmi_tx_ch2_p(hdmi_tx_ch2_p),
        .hdmi_tx_ch2_n(hdmi_tx_ch2_n),
        .hdmi_tx_clk_p(hdmi_tx_clk_p),
        .hdmi_tx_clk_n(hdmi_tx_clk_n),
        .oled_sdin(oled_sdin),
        .oled_sclk(oled_sclk),
        .oled_dc(oled_dc),
        .oled_res(oled_res),
        .oled_vbat(oled_vbat),
        .oled_vdd(oled_vdd),
        .uart_rx_in(uart_rx_in),
        .uart_tx_out(uart_tx_out)
    );

    // -----------------------------
    // Monitoring (optional)
    // -----------------------------
    initial begin
        $monitor("Time=%0t | sensor_out=%0h temp_out=%0h px=%0d py=%0d", 
                  $time, dut.sensor_out, dut.temp_out, dut.px, dut.py);
    end

endmodule