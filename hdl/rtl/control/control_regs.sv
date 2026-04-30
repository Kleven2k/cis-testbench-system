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

    // Switch inputs (new mapping)
    //   sw[0] = cds_enable
    //   sw[1] = photosense_mode
    //   sw[2] = invert_pol
    input  wire logic        sw_cds_enable,
    input  wire logic        sw_photosense,
    input  wire logic        sw_invert_pol,

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
    output      logic        read_mode,       // remote only
    output      logic        cds_enable,
    output      logic        photosense_mode,
    output      logic [1:0]  disp_gain,
    output      logic        invert_pol,
    output      logic        start_pulse,
    output      logic        soft_reset,
    output      logic        remote_mode_out,

    // Runtime grid size outputs (to sensor_ctrl)
    output      logic [7:0]  active_cols,
    output      logic [7:0]  active_rows
);

    // ============================================================
    // Register File (10 x 8-bit)
    // ============================================================
    // 0x00  CTRL:     [7]=remote_mode [2]=cds_enable [1]=soft_reset [0]=start
    // 0x01  EXP_LO:   exposure_us[7:0]
    // 0x02  EXP_HI:   exposure_us[15:8]
    // 0x03  DWELL_LO: dwell_us[7:0]
    // 0x04  DWELL_HI: dwell_us[15:8]
    // 0x05  MODE:     [4]=invert_pol [3:2]=disp_gain [1]=photosense [0]=read_mode
    // 0x06  RESET_US
    // 0x07  CDS_DELAY
    // 0x08  ACTIVE_COLS  (1-64, runtime grid width)
    // 0x09  ACTIVE_ROWS  (1-64, runtime grid height)
    localparam int NREGS = 10;
    logic [7:0] regfile [0:NREGS-1];

    logic remote_mode;
    assign remote_mode = regfile[0][7];

    // ============================================================
    // UART WRITE HANDLING
    // ============================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            integer i;
            for (i = 0; i < NREGS; i = i + 1)
                regfile[i] <= 8'd0;
            regfile[5] <= 8'h02;   // photosense_mode = 1 by default
            regfile[8] <= 8'd8;    // active_cols = 8 by default
            regfile[9] <= 8'd8;    // active_rows = 8 by default
        end else begin
            if (uart_write_en) begin
                // CTRL always writable (needed to enter remote mode)
                if (uart_addr == 8'h00)
                    regfile[0] <= uart_data;
                // All others only in remote mode
                else if (remote_mode && uart_addr < NREGS)
                    regfile[uart_addr] <= uart_data;
            end
        end
    end

    // ============================================================
    // UART READ HANDLING
    // ============================================================
    always_comb begin
        if (read_addr < NREGS)
            read_data = regfile[read_addr];
        else
            read_data = 8'h00;
    end

    // ============================================================
    // Exposure & Dwell
    // ============================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            exposure_us <= 16'd100;
            dwell_us    <= 16'd100;
        end else begin
            if (!remote_mode) begin
                if (delay_up)
                    exposure_us <= exposure_us + 16'd10;
                if (delay_down && exposure_us > 16'd10)
                    exposure_us <= exposure_us - 16'd10;
                if (dwell_up)
                    dwell_us <= dwell_us + 16'd10;
                if (dwell_down && dwell_us > 16'd10)
                    dwell_us <= dwell_us - 16'd10;
            end else begin
                exposure_us <= {regfile[2], regfile[1]};
                dwell_us    <= {regfile[4], regfile[3]};
            end
        end
    end

    // ============================================================
    // Reset & CDS Delay (remote only)
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
    // Mode outputs
    // Local mode: switches drive cds_enable, photosense, invert_pol
    // Remote mode: register file is authoritative for everything
    // read_mode is remote-only (single pixel without PC is not useful)
    // ============================================================
    always_comb begin
        if (remote_mode) begin
            cds_enable      = regfile[0][2];
            photosense_mode = regfile[5][1];
            invert_pol      = regfile[5][4];
            read_mode       = regfile[5][0];
        end else begin
            cds_enable      = sw_cds_enable;
            photosense_mode = sw_photosense;
            invert_pol      = sw_invert_pol;
            read_mode       = 1'b0;   // full-frame only without PC
        end
        // Display gain always from register (no physical switch)
        disp_gain = regfile[5][3:2];
    end

    // ============================================================
    // Active grid size — always from register file (remote sets it,
    // defaults to 8x8 on reset, local mode uses the same stored value)
    // ============================================================
    assign active_cols = (regfile[8] == 8'd0) ? 8'd8 : regfile[8];
    assign active_rows = (regfile[9] == 8'd0) ? 8'd8 : regfile[9];

    // ============================================================
    // Start Pulse
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
    // Soft Reset & Remote Mode output
    // ============================================================
    assign soft_reset      = remote_mode ? regfile[0][1] : 1'b0;
    assign remote_mode_out = remote_mode;

endmodule

`default_nettype wire
