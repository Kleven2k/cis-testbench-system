`default_nettype none
`timescale 1ns/1ps

module cis_system_top #(
    parameter CORDW = 12
)(
    //-------------------------------------------------------------------------
    // Clock and Reset
    //-------------------------------------------------------------------------
    input  wire logic clk_100m,       // 100 Mhz clock
    input  wire logic btn_rst_n,      // reset button

    //-------------------------------------------------------------------------
    // XADC Interface (using VAUX0 and VAUX1 in wrapper)
    //-------------------------------------------------------------------------
    input  wire logic [1:0] xa_p,
    input  wire logic [1:0] xa_n,

    //-------------------------------------------------------------------------
    // Analog-to-Digital Outputs
    //-------------------------------------------------------------------------
    //output wire      [11:0] sensor_out,
    //output wire      [11:0] temp_out, 

    //-------------------------------------------------------------------------
    // GPIO
    //-------------------------------------------------------------------------
    // Buttons
    input  wire logic btn_start,             // Start button
    input  wire logic btn_delay_up,          // Add delay button
    input  wire logic btn_delay_down,        // Subtract delay button
    input  wire logic btn_dwell_delay_up,      // Add CDS delay button
    input  wire logic btn_dwell_delay_down,    // Subtract CDS delay button

    // Switches
    input  wire logic [6:0] sw,              // Switches for pixel select and mode

    // PMOD JA Header
    output     logic [7:0] ja,

    //-------------------------------------------------------------------------
    // HDMI Outputs
    //-------------------------------------------------------------------------
    output      logic hdmi_tx_ch0_p,  // HDMI source channel 0 diff+
    output      logic hdmi_tx_ch0_n,  // HDMI source channel 0 diff-
    output      logic hdmi_tx_ch1_p,  // HDMI source channel 1 diff+
    output      logic hdmi_tx_ch1_n,  // HDMI source channel 1 diff-
    output      logic hdmi_tx_ch2_p,  // HDMI source channel 2 diff+
    output      logic hdmi_tx_ch2_n,  // HDMI source channel 2 diff-
    output      logic hdmi_tx_clk_p,  // HDMI source clock diff+
    output      logic hdmi_tx_clk_n,   // HDMI source clock diff-

    // OLED outputs
    output      logic oled_sdin,
    output      logic oled_sclk,
    output      logic oled_dc,
    output      logic oled_res,
    output      logic oled_vbat,
    output      logic oled_vdd,

    //-------------------------------------------------------------------------
    // UART
    //-------------------------------------------------------------------------
    input  wire logic uart_rx_in,   // This is FPGA TX pin (goes to PC RX)
    output wire logic uart_tx_out     // This is FPGA RX pin (comes from PC TX)
);


    //-------------------------------------------------------------------------
    // Clock Generation (720p video clock)
    //-------------------------------------------------------------------------
    logic clk_pix;
    logic clk_pix_5x;
    logic clk_pix_locked;
    clk_720p clk_pix_inst (
        .clk_100m(clk_100m),
        .rst(!btn_rst_n),  // Reset button is active low
        .clk_pix(clk_pix),
        .clk_pix_5x(clk_pix_5x),
        .clk_pix_locked(clk_pix_locked)
    );

    // Display sync signals and coordinates
    //localparam CORDW = 12;  // Screen coordinate width in bits
    logic [CORDW-1:0] sx, sy;
    logic hsync, vsync, de;
    simple_720p display_inst (
        .clk_pix(clk_pix),
        .rst_pix(!clk_pix_locked),  // Wait for clock lock
        .sx(sx),
        .sy(sy),
        .hsync(hsync),
        .vsync(vsync),
        .de(de)
    );

    // Screen dimensions (must match display_inst)
    localparam H_RES = 1280;  // Horizontal screen resolution
    localparam V_RES = 720;  // Vertical screen resolution

    logic frame;  // High for one clock tick at the start of vertical blanking
    always_comb frame = (sy == V_RES && sx == 0);

    //-------------------------------------------------------------------------
    // Debounce buttons
    //-------------------------------------------------------------------------
    logic start_btn_ondn;   // Start button debounce (start puls)

    debounce db_btn_start (.clk(clk_pix), .in(btn_start), .out(), .ondn(start_btn_ondn), .onup());  
    
    // Example: create a start pulse on button press
    logic start_pulse;
    always_ff @(posedge clk_pix) begin
        start_pulse <= start_btn_ondn;  // pulse goes high for 1 cycle on press
    end  

    // Delay buttons debounce (buttons to make delay times configurable)
    logic delay_up_dn, delay_down_dn;
    //logic cds_up_dn, cds_down_dn;
    logic dwell_up_dn, dwell_down_dn;

    debounce db_delay_up   (.clk(clk_pix), .in(btn_delay_up), .out(), .ondn(delay_up_dn), .onup());
    debounce db_delay_down (.clk(clk_pix), .in(btn_delay_down), .out(), .ondn(delay_down_dn), .onup());
    //debounce db_cds_up     (.clk(clk_pix), .in(btn_cds_delay_up), .out(), .ondn(cds_up_dn), .onup());
    //debounce db_cds_down   (.clk(clk_pix), .in(btn_cds_delay_down), .out(), .ondn(cds_down_dn), .onup());
    debounce db_dwell_up   (.clk(clk_pix), .in(btn_dwell_delay_up), .out(), .ondn(dwell_up_dn), .onup());
    debounce db_dwell_down (.clk(clk_pix), .in(btn_dwell_delay_down), .out(), .ondn(dwell_down_dn), .onup());


    //-------------------------------------------------------------------------
    // XADC Interface Wrapper
    //-------------------------------------------------------------------------
    // Handshake signals
    wire enable, ready;
    wire [15:0] xadc_data;
    reg   [6:0] xadc_addr = 7'h10;

    // Instatiate XADC wizard
    xadc_wiz_0 XADC (
        .daddr_in(xadc_addr),
        .dclk_in(clk_100m),
        .den_in(enable),
        .di_in(16'h0000),
        .dwe_in(1'b0),
        .vp_in(1'b0),
        .vn_in(1'b0),
        .reset_in(1'b0),
        .busy_out(),
        .vauxp0(xa_p[1]),
        .vauxn0(xa_n[1]),
        .vauxp1(xa_p[0]),
        .vauxn1(xa_n[0]),
        .do_out(xadc_data),
        .eoc_out(enable),
        .channel_out(),
        .drdy_out(ready),
        .eos_out(),              // unused
        .ot_out(),               // unused
        .vccaux_alarm_out(),     // unused
        .vccint_alarm_out(),     // unused
        .user_temp_alarm_out(),  // unused
        .alarm_out()             // unused
    );

    logic [CORDW-1:0] sensor_out;
    logic [CORDW-1:0] temp_out;

    // XADC read logic
    always_ff @(posedge clk_100m) begin 
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
    always_ff @(posedge clk_100m) begin 
        if (ready) begin 
            case (xadc_addr)
                7'h11: xadc_addr <= 7'h10;  // Last address goes out and load new address in
                7'h10: xadc_addr <= 7'h11;
                default: xadc_addr <= 7'h10;
            endcase
        end 
    end
    
    wire [11:0] sensor_out_sync;
    wire [11:0] temp_out_sync;

    // Generate a single-cycle valid pulse whenever new ADC data arrives
    wire xadc_data_valid = ready;  // `ready` pulses each valid XADC sample

    cdc_adc_sync u_adc_cdc (
        .clk_src(clk_100m),
        .clk_dst(clk_pix),
        .data_sensor_in(sensor_out),
        .data_temp_in(temp_out),
        .data_valid(xadc_data_valid),
        .data_sensor_out(sensor_out_sync),
        .data_temp_out(temp_out_sync)
    );


    logic[3:0] gray_pix;

    //logic [11:0] volt_sensor, volt_temp;
    // Delay configuration
    //logic [15:0] delay_time_cfg = 16'd5;     // default
    //logic [15:0] cds_delay_time_cfg = 16'd10;  // default

    // draw voltages
    simple_pixel #(.CORDW(CORDW), .H_RES(H_RES)) simple_pixel_inst (
        .clk_pix(clk_pix),
        .sx(sx),
        .sy(sy),
        .pixel_mem(pixel_mem),
        .volt_sensor(sensor_out_sync),
        .volt_temp(temp_out_sync),
        .delay_time(exposure_us),
        .gray_out(gray_pix)
    );

    // paint grayscale: use gray_pix for R, G, B
    logic [3:0] paint_r, paint_g, paint_b;
    always_comb begin
        paint_r = gray_pix;
        paint_g = gray_pix;
        paint_b = gray_pix;
    end

    // display colour: paint colour but black in blanking interval
    logic [3:0] display_r, display_g, display_b;
    always_comb begin
        display_r = (de) ? paint_r : 4'h0;
        display_g = (de) ? paint_g : 4'h0;
        display_b = (de) ? paint_b : 4'h0;
    end

    // DVI signals (8 bits per colour channel)
    logic [7:0] dvi_r, dvi_g, dvi_b;
    logic dvi_hsync, dvi_vsync, dvi_de;
    always_ff @(posedge clk_pix) begin
        dvi_hsync <= hsync;
        dvi_vsync <= vsync;
        dvi_de <= de;
        dvi_r <= { 2{ display_r } };
        dvi_g <= { 2{ display_g } };
        dvi_b <= { 2{ display_b } };
    end 

    // TMDS encoding and serialization
    logic tmds_ch0_serial, tmds_ch1_serial, tmds_ch2_serial, tmds_clk_serial;
    dvi_generator dvi_out (
        .clk_pix(clk_pix),
        .clk_pix_5x(clk_pix_5x),
        .rst_pix(!clk_pix_locked),
        .de(dvi_de),
        .data_in_ch0(dvi_b),
        .data_in_ch1(dvi_g),
        .data_in_ch2(dvi_r),
        .ctrl_in_ch0({dvi_vsync, dvi_hsync}),
        .ctrl_in_ch1(2'b00),
        .ctrl_in_ch2(2'b00),
        .tmds_ch0_serial,
        .tmds_ch1_serial,
        .tmds_ch2_serial,
        .tmds_clk_serial
    );

    // TMDS output pins
    tmds_out tmds_ch0 (.tmds(tmds_ch0_serial),
        .pin_p(hdmi_tx_ch0_p), .pin_n(hdmi_tx_ch0_n));
    tmds_out tmds_ch1 (.tmds(tmds_ch1_serial),
        .pin_p(hdmi_tx_ch1_p), .pin_n(hdmi_tx_ch1_n));
    tmds_out tmds_ch2 (.tmds(tmds_ch2_serial),
        .pin_p(hdmi_tx_ch2_p), .pin_n(hdmi_tx_ch2_n));
    tmds_out tmds_clk (.tmds(tmds_clk_serial),
        .pin_p(hdmi_tx_clk_p), .pin_n(hdmi_tx_clk_n));

    //-------------------------------------------------------------------------
    // Control Signals Interface
    //-------------------------------------------------------------------------
    logic nRES, nTX;
    logic [2:0] AX, AY;

    // FSM done signals
    logic done, exposure_done, cds_done, single_done;

    // FSM States
    logic idle_state, reset_state, cds_state, exposure_state, readout_state, single_pix_state;

    // Pixel counters
    logic [2:0] px, py;

    logic [15:0] exposure_us;
    logic [15:0] pixel_dwell_us;
    logic [7:0]  reset_us_wire;
    logic [7:0]  cds_delay_us_wire;

    logic [5:0] pixel_index;
    logic       pixel_step;

    //-------------------------------------------------------------------------
    // Pixels
    //-------------------------------------------------------------------------
    logic [11:0] pixel_mem [0:63];

    always_ff @(posedge clk_pix or negedge btn_rst_n) begin
        if (!btn_rst_n) begin
            integer i;
            for (i = 0; i < 64; i = i + 1)
                pixel_mem[i] <= 12'd0;
        end else begin
            // Write exactly one sample at end of each dwell
            if (readout_state && pixel_step) begin
                pixel_mem[pixel_index] <= sensor_out_sync;
            end
        end
    end

    /*
    // Counters to update the button presses
    always_ff @(posedge clk_pix or negedge btn_rst_n) begin
        if (!btn_rst_n) begin
            exposure_us <= 16'd100;       // default 8us exposure 
            //exposure_cds_us <= 16'd4;   // default 4us cds reset
            pixel_dwell_us <= 16'd100;    // default 2us dwell per pixel
        end else begin 
            if (delay_up_dn)  
                exposure_us <= exposure_us + 16'd10;

            if (delay_down_dn) 
                exposure_us <= (exposure_us > 10) ? exposure_us - 16'd10 : 16'd10;

            if (dwell_up_dn)  
                pixel_dwell_us <= pixel_dwell_us + 16'd10;

            if (dwell_down_dn) 
                pixel_dwell_us <= (pixel_dwell_us > 10) ? pixel_dwell_us - 16'd10 : 16'd10;
        end 
    end
    */

    logic read_mode_final;
    logic cds_final;
    logic start_combined;
    logic rst_uart;

    sensor_ctrl u_sensor_ctrl (
        .clk  (clk_pix),
        .rst  (!btn_rst_n | rst_uart),

        .start(start_combined),
        .read_mode (read_mode_final),
        .cds_enable(cds_final),

        .delay_time      (exposure_us),
        .cds_delay_us    (cds_delay_us_wire),
        .reset_us        (reset_us_wire),
        .pixel_dwell_time(pixel_dwell_us),

        .pixel_index(pixel_index),
        .pixel_step (pixel_step),
        
        .done         (done),
        .exposure_done(exposure_done),
        .cds_done     (cds_done),
        .single_done  (single_done),
        .nRES(nRES),
        .nTX (nTX),
        .AX  (AX),
        .AY  (AY),
        .px  (px),
        .py  (py),
        .px_select(sw[4:2]),
        .py_select(sw[6:4]),
        .idle_state       (idle_state),
        .reset_state      (reset_state),
        .cds_state        (cds_state),
        .exposure_state   (exposure_state),
        .readout_state    (readout_state),
        .single_pix_state (single_pix_state)
    );

    // PMODs Headers Pin-Assignment
    assign ja[0] = AY[0];   // AY0 -> JA1
    assign ja[1] = AY[1];   // AY1 -> JA2
    assign ja[2] = AY[2];   // AY2 -> JA3
    assign ja[3] = nTX;     // nTX -> JA4
    assign ja[4] = AX[0];   // AX0 -> JA7
    assign ja[5] = AX[1];   // AX1 -> JA8
    assign ja[6] = AX[2];   // AX2 -> JA9
    assign ja[7] = nRES;    // nRES -> JA10

    //-------------------------------------------------------------------------
    // OLED Control
    //-------------------------------------------------------------------------

    OLED_master u_oled (
        .clk         (clk_100m),
        .rstn        (btn_rst_n),
        .exposure_us (exposure_us),
        .oled_sdin   (oled_sdin),
        .oled_sclk   (oled_sclk),
        .oled_dc     (oled_dc),
        .oled_res    (oled_res),
        .oled_vbat   (oled_vbat),
        .oled_vdd    (oled_vdd)
    );

        //-------------------------------------------------------------------------
    // UART
    //-------------------------------------------------------------------------

    logic [7:0] uart_rx_data;
    logic       uart_rx_valid;

    logic [7:0] uart_tx_data;
    logic       uart_tx_start;
    logic       uart_tx_busy;

    uart_top #(
        .CLK_FREQ(100_000_000),
        .BAUD(115200)
    ) u_uart (
        .clk(clk_100m),
        .rst(!btn_rst_n),
        .rx(uart_rx_in),
        .tx(uart_tx_out),
        .rx_data(uart_rx_data),
        .rx_valid(uart_rx_valid),
        .tx_data(uart_tx_data),
        .tx_start(uart_tx_start),
        .tx_busy(uart_tx_busy)
    );

    // ------------------------------------------------------------
    // Register interface wiring
    // ------------------------------------------------------------

    logic        uart_write_en;
    logic [7:0]  uart_write_addr;
    logic [7:0]  uart_write_data;

    logic [7:0]  uart_read_addr;
    logic [7:0]  uart_read_data;

    uart_reg_if u_uart_if (
        .clk(clk_100m),
        .rst(!btn_rst_n),

        // RX
        .rx_data(uart_rx_data),
        .rx_valid(uart_rx_valid),

        // TX
        .tx_data(uart_tx_data),
        .tx_start(uart_tx_start),
        .tx_busy(uart_tx_busy),

        // WRITE
        .write_en(uart_write_en),
        .write_addr(uart_write_addr),
        .write_data(uart_write_data),

        // READ (no read_req anymore!)
        .read_addr(uart_read_addr),
        .read_data(uart_read_data)
    );

    control_regs u_control_regs (
        .clk(clk_100m),
        .rst(!btn_rst_n),

        .delay_up(delay_up_dn),
        .delay_down(delay_down_dn),
        .dwell_up(dwell_up_dn),
        .dwell_down(dwell_down_dn),
        .start_btn(start_pulse),

        .sw_read_mode(sw[0]),
        .sw_cds_enable(sw[1]),

        .uart_write_en(uart_write_en),
        .uart_addr(uart_write_addr),
        .uart_data(uart_write_data),

        .read_addr(uart_read_addr),
        .read_data(uart_read_data),

        .exposure_us (exposure_us),
        .dwell_us    (pixel_dwell_us),
        .reset_us    (reset_us_wire),
        .cds_delay_us(cds_delay_us_wire),
        .read_mode   (read_mode_final),
        .cds_enable(cds_final),
        .start_pulse(start_combined),
        .soft_reset(rst_uart)
    );

endmodule