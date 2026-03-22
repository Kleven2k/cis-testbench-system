`timescale 1ns/1ps
`default_nettype none

module tb_cis_system_top;

    // -------------------------------------------------
    // Clocks & Reset
    // -------------------------------------------------
    logic clk_100m;
    logic btn_rst_n;

    // -------------------------------------------------
    // Inputs
    // -------------------------------------------------
    logic [1:0] xa_p, xa_n;
    logic btn_start;
    logic btn_delay_up, btn_delay_down;
    logic btn_cds_delay_up, btn_cds_delay_down;
    logic [6:0] sw;

    // -------------------------------------------------
    // Outputs
    // -------------------------------------------------
    logic [7:0] ja;
    logic hdmi_tx_ch0_p, hdmi_tx_ch0_n;
    logic hdmi_tx_ch1_p, hdmi_tx_ch1_n;
    logic hdmi_tx_ch2_p, hdmi_tx_ch2_n;
    logic hdmi_tx_clk_p, hdmi_tx_clk_n;

    // -------------------------------------------------
    // DUT
    // -------------------------------------------------
    cis_system_top dut (
        .clk_100m(clk_100m),
        .btn_rst_n(btn_rst_n),
        .xa_p(xa_p),
        .xa_n(xa_n),
        .btn_start(btn_start),
        .btn_delay_up(btn_delay_up),
        .btn_delay_down(btn_delay_down),
        .btn_cds_delay_up(btn_cds_delay_up),
        .btn_cds_delay_down(btn_cds_delay_down),
        .sw(sw),
        .ja(ja),
        .hdmi_tx_ch0_p(hdmi_tx_ch0_p),
        .hdmi_tx_ch0_n(hdmi_tx_ch0_n),
        .hdmi_tx_ch1_p(hdmi_tx_ch1_p),
        .hdmi_tx_ch1_n(hdmi_tx_ch1_n),
        .hdmi_tx_ch2_p(hdmi_tx_ch2_p),
        .hdmi_tx_ch2_n(hdmi_tx_ch2_n),
        .hdmi_tx_clk_p(hdmi_tx_clk_p),
        .hdmi_tx_clk_n(hdmi_tx_clk_n)
    );

    // -------------------------------------------------
    // 100 MHz clock
    // -------------------------------------------------
    initial clk_100m = 0;
    always #5 clk_100m = ~clk_100m;

    // -------------------------------------------------
    // Stimulus
    // -------------------------------------------------
    initial begin
        // defaults
        btn_rst_n = 0;
        btn_start = 0;
        btn_delay_up = 0;
        btn_delay_down = 0;
        btn_cds_delay_up = 0;
        btn_cds_delay_down = 0;
        sw = 7'b0;
        xa_p = 2'b0;
        xa_n = 2'b0;

        // Reset
        #100;
        btn_rst_n = 1;

        // Wait for clocks to "lock"
        #1000;

        // Select pixel (px=1, py=2)
        sw[3:1] = 3'd1;
        sw[6:4] = 3'd2;

        // Start capture
        press_button(btn_start, 200);

        // Adjust delays
        press_button(btn_delay_up, 200);
        press_button(btn_cds_delay_up, 200);

        // Run for a few frames
        #500;

        $display("Simulation finished.");
        $stop;
    end

    // -------------------------------------------------
    // Button press helper
    // -------------------------------------------------
    task automatic press_button(
        ref logic btn,
        input time  t
    );
        begin
            btn = 1;
            #(t);
            btn = 0;
        end
    endtask

    // -------------------------------------------------
    // Logging (optional)
    // -------------------------------------------------
    always @(posedge dut.clk_pix) begin 
        if (dut.start_pulse)
            $display("[%0t] START pressed", $time);
        
        if (dut.idle_state)
            $display("[%0t] FSM = IDLE", $time);
    end

endmodule