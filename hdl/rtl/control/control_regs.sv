`default_nettype none
`timescale 1ns/1ps

module control_regs (
    input  wire logic        clk,
    input  wire logic        rst,

    // Button pulses
    input  wire logic        delay_up,
    input  wire logic        delay_down,
    input  wire logic        dwell_up,
    input  wire logic        dwell_down,
    input  wire logic        start_btn,

    input  wire logic        sw_read_mode,
    input  wire logic        sw_cds_enable,

    // UART write interface
    input  wire logic        uart_write_en,
    input  wire logic [7:0]  uart_addr,
    input  wire logic [7:0]  uart_data,

    // UART read interface
    input  wire logic [7:0]  read_addr,
    output      logic [7:0]  read_data,

    // Outputs to sensor_ctrl
    output      logic [15:0] exposure_us,
    output      logic [15:0] dwell_us,
    output      logic [7:0]  reset_us,
    output      logic [7:0]  cds_delay_us,
    output      logic        read_mode,
    output      logic        cds_enable,
    output      logic        photosense_mode,
    output      logic [1:0]  disp_gain,
    output      logic        invert_pol,    // REG_MODE[4]: 1 = higher ADC → brighter
    output      logic        start_pulse,
    output      logic        soft_reset
);

    // ============================================================
    // Register File (8 x 8-bit)
    // ============================================================
    logic [7:0] regfile [0:7];

    // CTRL register bits
    // regfile[0]
    // bit0 = start
    // bit1 = soft reset
    // bit2 = cds_enable
    // bit7 = remote_mode

    logic remote_mode;
    assign remote_mode = regfile[0][7];

    // ============================================================
    // UART WRITE HANDLING
    // ============================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            integer i;
            for (i = 0; i < 8; i = i + 1)
                regfile[i] <= 8'd0;
            regfile[5] <= 8'h02;  // photosense_mode = 1 by default (bit 1)
        end else begin
            if (uart_write_en) begin
                // Always allow writing CTRL (needed to enable remote mode)
                if (uart_addr == 8'h00)
                    regfile[0] <= uart_data;

                // Other registers only writable in remote mode
                else if (remote_mode && uart_addr < 8)
                    regfile[uart_addr] <= uart_data;
            end
        end
    end

    // ============================================================
    // UART READ HANDLING
    // ============================================================
    always_comb begin
        if (read_addr < 8)
            read_data = regfile[read_addr];
        else
            read_data = 8'h00;
    end

    // ============================================================
    // Exposure & Dwell Configuration
    // ============================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            exposure_us <= 16'd100;
            dwell_us    <= 16'd100;
        end else begin
            if (!remote_mode) begin
                // Manual button control
                if (delay_up)
                    exposure_us <= exposure_us + 16'd10;

                if (delay_down && exposure_us > 16'd10)
                    exposure_us <= exposure_us - 16'd10;

                if (dwell_up)
                    dwell_us <= dwell_us + 16'd10;

                if (dwell_down && dwell_us > 16'd10)
                    dwell_us <= dwell_us - 16'd10;
            end else begin
                // Remote mode uses register values
                exposure_us <= {regfile[2], regfile[1]};
                dwell_us    <= {regfile[4], regfile[3]};
            end
        end
    end

    // ============================================================
    // Reset & CDS Delay Configuration
    // ============================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            reset_us     <= 8'd10;
            cds_delay_us <= 8'd2;
        end else if (remote_mode) begin
            reset_us     <= regfile[6];
            cds_delay_us <= regfile[7];
        end
    end

    // ============================================================
    // Mode Selection
    // ============================================================
    always_comb begin
        if (remote_mode) begin
            read_mode  = regfile[5][0];
            cds_enable = regfile[0][2];
        end else begin
            read_mode  = sw_read_mode;
            cds_enable = sw_cds_enable;
        end
        // display config always comes from register (no physical switch)
        photosense_mode = regfile[5][1];
        disp_gain       = regfile[5][3:2];
        invert_pol      = regfile[5][4];
    end

    // ============================================================
    // Start Pulse Generation (Edge Detect)
    // ============================================================
    logic start_prev;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            start_prev  <= 1'b0;
            start_pulse <= 1'b0;
        end else begin
            if (remote_mode) begin
                start_prev  <= regfile[0][0];
                start_pulse <= regfile[0][0] & ~start_prev;
            end else begin
                start_pulse <= start_btn;
            end
        end
    end

    // ============================================================
    // Soft Reset
    // ============================================================
    assign soft_reset = remote_mode ? regfile[0][1] : 1'b0;

endmodule

`default_nettype wire