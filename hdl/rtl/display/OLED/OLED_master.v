`timescale 1ns / 1ps

// OLED_master — drives the 128x32 OLED on the Nexys Video board.
//
// Displays four rows of 16 characters:
//   Row 0: "Exp:  XXXXX us  "   exposure time
//   Row 1: "Dwl:  XXXXX us  "   dwell time
//   Row 2: "State: XXXXXXXX "   FSM state name
//   Row 3: "CDS: ON  Rem:OFF"   CDS and remote mode flags
//
// Responsiveness fix: the 1-second post-splash delay has been removed.
// The display redraws immediately whenever any input changes.

module OLED_master (
    input  clk,
    input  rstn,

    input [15:0] exposure_us,
    input [15:0] dwell_us,
    // FSM state one-hot flags from sensor_ctrl
    input        idle_state,
    input        reset_state,
    input        cds_state,
    input        exposure_state,
    input        readout_state,
    input        single_pix_state,
    // Mode flags
    input        cds_enable,
    input        remote_mode,

    output oled_sdin,
    output oled_sclk,
    output oled_dc,
    output oled_res,
    output oled_vbat,
    output oled_vdd
);

    // -------------------------------------------------------------------------
    // State machine codes
    // -------------------------------------------------------------------------
    localparam  Idle               = 0;
    localparam  Init               = 1;
    localparam  ActiveWriteAlpha   = 2;
    localparam  ActiveUpdateAlpha  = 3;
    localparam  ActiveDelayAlpha   = 4;
    localparam  ActiveWriteSplash  = 5;
    localparam  ActiveUpdateSplash = 6;
    localparam  ActiveWait         = 8;
    localparam  Done               = 9;
    localparam  Write              = 11;
    localparam  WriteWait          = 12;
    localparam  UpdateWait         = 13;
    localparam  DelayWait          = 14;

    localparam  SPLASH = 1, ALPHA = 0;

    // -------------------------------------------------------------------------
    // ALPHA (init) screen — fixed
    // -------------------------------------------------------------------------
    localparam alpha_str1     = "       UIO      ";
    localparam alpha_str1_len = 16;
    localparam alpha_str2     = "  CIS Testbench ";
    localparam alpha_str2_len = 16;
    localparam alpha_str3     = "                ";
    localparam alpha_str3_len = 16;
    localparam alpha_str4     = " Initializing...";
    localparam alpha_str4_len = 16;

    // -------------------------------------------------------------------------
    // SPLASH screen — rows 0/3 fixed, rows 1/2 updated dynamically
    // -------------------------------------------------------------------------
    localparam  splash_str1     = "Exp:            ";
    localparam  splash_str1_len = 16;
    reg [8*16-1:0] splash_str2  = "Dwl:            ";
    reg [8*16-1:0] splash_str3  = "State:          ";
    reg [8*16-1:0] splash_str4  = "CDS:    Rem:    ";

    // -------------------------------------------------------------------------
    // BCD pipeline — converts a 16-bit value to 5 decimal digit registers.
    // Uses only subtraction (no division) to avoid long carry chains.
    // Triggered by redraw_req; takes 5 cycles to complete.
    // Outputs: bcd_exp[4:0], bcd_dwl[4:0] — each digit is 0-9.
    // -------------------------------------------------------------------------
    reg        bcd_start = 0;
    reg [2:0]  bcd_phase = 0;   // 0=idle, 1-5=computing digit 4 down to 0
    reg [15:0] bcd_rem_exp, bcd_rem_dwl;
    reg [3:0]  bcd_exp [0:4];   // digit 4=ten-thousands .. digit 0=units
    reg [3:0]  bcd_dwl [0:4];
    reg        bcd_done = 0;

    // Subtraction-based digit extraction: one digit per clock cycle.
    // Each cycle: count how many times the place value fits, store digit,
    // leave remainder for next cycle.
    function automatic [19:0] extract_digit(
        input [15:0] val, input [15:0] place);
        // Returns {digit[3:0], remainder[15:0]}
        reg [3:0]  d;
        reg [15:0] r;
        begin
            d = 0; r = val;
            if (r >= place * 9) begin d = 9; r = r - place * 9; end
            else if (r >= place * 8) begin d = 8; r = r - place * 8; end
            else if (r >= place * 7) begin d = 7; r = r - place * 7; end
            else if (r >= place * 6) begin d = 6; r = r - place * 6; end
            else if (r >= place * 5) begin d = 5; r = r - place * 5; end
            else if (r >= place * 4) begin d = 4; r = r - place * 4; end
            else if (r >= place * 3) begin d = 3; r = r - place * 3; end
            else if (r >= place * 2) begin d = 2; r = r - place * 2; end
            else if (r >= place)     begin d = 1; r = r - place;     end
            extract_digit = {d, r};
        end
    endfunction

    always @(posedge clk) begin
        bcd_done <= 0;
        if (redraw_req) begin
            bcd_start <= 1;
        end
        if (bcd_start) begin
            bcd_phase    <= 1;
            bcd_rem_exp  <= exposure_us;
            bcd_rem_dwl  <= dwell_us;
            bcd_start    <= 0;
        end else begin
            case (bcd_phase)
                1: begin
                    {bcd_exp[4], bcd_rem_exp} <= extract_digit(bcd_rem_exp, 16'd10000);
                    {bcd_dwl[4], bcd_rem_dwl} <= extract_digit(bcd_rem_dwl, 16'd10000);
                    bcd_phase <= 2;
                end
                2: begin
                    {bcd_exp[3], bcd_rem_exp} <= extract_digit(bcd_rem_exp, 16'd1000);
                    {bcd_dwl[3], bcd_rem_dwl} <= extract_digit(bcd_rem_dwl, 16'd1000);
                    bcd_phase <= 3;
                end
                3: begin
                    {bcd_exp[2], bcd_rem_exp} <= extract_digit(bcd_rem_exp, 16'd100);
                    {bcd_dwl[2], bcd_rem_dwl} <= extract_digit(bcd_rem_dwl, 16'd100);
                    bcd_phase <= 4;
                end
                4: begin
                    {bcd_exp[1], bcd_rem_exp} <= extract_digit(bcd_rem_exp, 16'd10);
                    {bcd_dwl[1], bcd_rem_dwl} <= extract_digit(bcd_rem_dwl, 16'd10);
                    bcd_phase <= 5;
                end
                5: begin
                    bcd_exp[0] <= bcd_rem_exp[3:0];
                    bcd_dwl[0] <= bcd_rem_dwl[3:0];
                    bcd_phase  <= 0;
                    bcd_done   <= 1;
                end
                default: bcd_phase <= 0;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Detect any display-relevant input change
    // -------------------------------------------------------------------------
    reg [15:0] exposure_prev, dwell_prev;
    reg        idle_prev, reset_prev, cds_st_prev, exp_st_prev, ro_prev, sp_prev;
    reg        cds_en_prev, remote_prev;

    wire inputs_changed =
        (exposure_us    != exposure_prev)   ||
        (dwell_us       != dwell_prev)      ||
        (idle_state     != idle_prev)       ||
        (reset_state    != reset_prev)      ||
        (cds_state      != cds_st_prev)     ||
        (exposure_state != exp_st_prev)     ||
        (readout_state  != ro_prev)         ||
        (single_pix_state != sp_prev)       ||
        (cds_enable     != cds_en_prev)     ||
        (remote_mode    != remote_prev);

    // One-cycle pulse on change — triggers BCD pipeline
    reg inputs_changed_d;
    always @(posedge clk) inputs_changed_d <= inputs_changed;
    wire redraw_req = inputs_changed && !inputs_changed_d;

    // Redraw the display once BCD digits are ready
    wire redraw_pulse = bcd_done;

    always @(posedge clk) begin
        exposure_prev   <= exposure_us;
        dwell_prev      <= dwell_us;
        idle_prev       <= idle_state;
        reset_prev      <= reset_state;
        cds_st_prev     <= cds_state;
        exp_st_prev     <= exposure_state;
        ro_prev         <= readout_state;
        sp_prev         <= single_pix_state;
        cds_en_prev     <= cds_enable;
        remote_prev     <= remote_mode;
    end

    // -------------------------------------------------------------------------
    // Build display strings on redraw_pulse
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (redraw_pulse) begin
            // Row 1: "Dwl: XXXXX us  "
            splash_str2[15*8 +: 8] <= "D";
            splash_str2[14*8 +: 8] <= "w";
            splash_str2[13*8 +: 8] <= "l";
            splash_str2[12*8 +: 8] <= ":";
            splash_str2[11*8 +: 8] <= " ";
            splash_str2[10*8 +: 8] <= 8'd48 + {4'b0, bcd_dwl[4]};
            splash_str2[ 9*8 +: 8] <= 8'd48 + {4'b0, bcd_dwl[3]};
            splash_str2[ 8*8 +: 8] <= 8'd48 + {4'b0, bcd_dwl[2]};
            splash_str2[ 7*8 +: 8] <= 8'd48 + {4'b0, bcd_dwl[1]};
            splash_str2[ 6*8 +: 8] <= 8'd48 + {4'b0, bcd_dwl[0]};
            splash_str2[ 5*8 +: 8] <= " ";
            splash_str2[ 4*8 +: 8] <= "u";
            splash_str2[ 3*8 +: 8] <= "s";
            splash_str2[ 2*8 +: 8] <= " ";
            splash_str2[ 1*8 +: 8] <= " ";
            splash_str2[ 0*8 +: 8] <= " ";

            // Row 2: "State: XXXXXXXX"
            splash_str3[15*8 +: 8] <= "S";
            splash_str3[14*8 +: 8] <= "t";
            splash_str3[13*8 +: 8] <= "a";
            splash_str3[12*8 +: 8] <= "t";
            splash_str3[11*8 +: 8] <= "e";
            splash_str3[10*8 +: 8] <= ":";
            splash_str3[ 9*8 +: 8] <= " ";
            if (idle_state) begin
                splash_str3[ 8*8 +: 8] <= "I";
                splash_str3[ 7*8 +: 8] <= "d";
                splash_str3[ 6*8 +: 8] <= "l";
                splash_str3[ 5*8 +: 8] <= "e";
                splash_str3[ 4*8 +: 8] <= " ";
                splash_str3[ 3*8 +: 8] <= " ";
                splash_str3[ 2*8 +: 8] <= " ";
                splash_str3[ 1*8 +: 8] <= " ";
                splash_str3[ 0*8 +: 8] <= " ";
            end else if (reset_state) begin
                splash_str3[ 8*8 +: 8] <= "R";
                splash_str3[ 7*8 +: 8] <= "e";
                splash_str3[ 6*8 +: 8] <= "s";
                splash_str3[ 5*8 +: 8] <= "e";
                splash_str3[ 4*8 +: 8] <= "t";
                splash_str3[ 3*8 +: 8] <= " ";
                splash_str3[ 2*8 +: 8] <= " ";
                splash_str3[ 1*8 +: 8] <= " ";
                splash_str3[ 0*8 +: 8] <= " ";
            end else if (cds_state) begin
                splash_str3[ 8*8 +: 8] <= "C";
                splash_str3[ 7*8 +: 8] <= "D";
                splash_str3[ 6*8 +: 8] <= "S";
                splash_str3[ 5*8 +: 8] <= " ";
                splash_str3[ 4*8 +: 8] <= " ";
                splash_str3[ 3*8 +: 8] <= " ";
                splash_str3[ 2*8 +: 8] <= " ";
                splash_str3[ 1*8 +: 8] <= " ";
                splash_str3[ 0*8 +: 8] <= " ";
            end else if (exposure_state) begin
                splash_str3[ 8*8 +: 8] <= "I";
                splash_str3[ 7*8 +: 8] <= "n";
                splash_str3[ 6*8 +: 8] <= "t";
                splash_str3[ 5*8 +: 8] <= "e";
                splash_str3[ 4*8 +: 8] <= "g";
                splash_str3[ 3*8 +: 8] <= "r";
                splash_str3[ 2*8 +: 8] <= "a";
                splash_str3[ 1*8 +: 8] <= "t";
                splash_str3[ 0*8 +: 8] <= "e";
            end else if (readout_state) begin
                splash_str3[ 8*8 +: 8] <= "R";
                splash_str3[ 7*8 +: 8] <= "e";
                splash_str3[ 6*8 +: 8] <= "a";
                splash_str3[ 5*8 +: 8] <= "d";
                splash_str3[ 4*8 +: 8] <= "o";
                splash_str3[ 3*8 +: 8] <= "u";
                splash_str3[ 2*8 +: 8] <= "t";
                splash_str3[ 1*8 +: 8] <= " ";
                splash_str3[ 0*8 +: 8] <= " ";
            end else if (single_pix_state) begin
                splash_str3[ 8*8 +: 8] <= "S";
                splash_str3[ 7*8 +: 8] <= "i";
                splash_str3[ 6*8 +: 8] <= "n";
                splash_str3[ 5*8 +: 8] <= "g";
                splash_str3[ 4*8 +: 8] <= "l";
                splash_str3[ 3*8 +: 8] <= "e";
                splash_str3[ 2*8 +: 8] <= "P";
                splash_str3[ 1*8 +: 8] <= "x";
                splash_str3[ 0*8 +: 8] <= " ";
            end else begin
                splash_str3[ 8*8 +: 8] <= "?";
                splash_str3[ 7*8 +: 8] <= " ";
                splash_str3[ 6*8 +: 8] <= " ";
                splash_str3[ 5*8 +: 8] <= " ";
                splash_str3[ 4*8 +: 8] <= " ";
                splash_str3[ 3*8 +: 8] <= " ";
                splash_str3[ 2*8 +: 8] <= " ";
                splash_str3[ 1*8 +: 8] <= " ";
                splash_str3[ 0*8 +: 8] <= " ";
            end

            // Row 3: "CDS:ON  Rem:OFF" or variants
            splash_str4[15*8 +: 8] <= "C";
            splash_str4[14*8 +: 8] <= "D";
            splash_str4[13*8 +: 8] <= "S";
            splash_str4[12*8 +: 8] <= ":";
            splash_str4[11*8 +: 8] <= cds_enable ? "O" : "O";
            splash_str4[10*8 +: 8] <= cds_enable ? "N" : "F";
            splash_str4[ 9*8 +: 8] <= cds_enable ? " " : "F";
            splash_str4[ 8*8 +: 8] <= " ";
            splash_str4[ 7*8 +: 8] <= "R";
            splash_str4[ 6*8 +: 8] <= "e";
            splash_str4[ 5*8 +: 8] <= "m";
            splash_str4[ 4*8 +: 8] <= ":";
            splash_str4[ 3*8 +: 8] <= remote_mode ? "O" : "O";
            splash_str4[ 2*8 +: 8] <= remote_mode ? "N" : "F";
            splash_str4[ 1*8 +: 8] <= remote_mode ? " " : "F";
            splash_str4[ 0*8 +: 8] <= " ";
        end
    end

    // Also build row 0 (exposure) separately — same trigger
    // splash_str1 is fixed label "Exp:  " — we write digits into ctrl signals directly
    // We use a separate reg to hold the current exposure digits for the write logic
    reg [8*16-1:0] splash_str1_dyn = "Exp:            ";
    always @(posedge clk) begin
        if (redraw_pulse) begin
            splash_str1_dyn[15*8 +: 8] <= "E";
            splash_str1_dyn[14*8 +: 8] <= "x";
            splash_str1_dyn[13*8 +: 8] <= "p";
            splash_str1_dyn[12*8 +: 8] <= ":";
            splash_str1_dyn[11*8 +: 8] <= " ";
            splash_str1_dyn[10*8 +: 8] <= 8'd48 + {4'b0, bcd_exp[4]};
            splash_str1_dyn[ 9*8 +: 8] <= 8'd48 + {4'b0, bcd_exp[3]};
            splash_str1_dyn[ 8*8 +: 8] <= 8'd48 + {4'b0, bcd_exp[2]};
            splash_str1_dyn[ 7*8 +: 8] <= 8'd48 + {4'b0, bcd_exp[1]};
            splash_str1_dyn[ 6*8 +: 8] <= 8'd48 + {4'b0, bcd_exp[0]};
            splash_str1_dyn[ 5*8 +: 8] <= " ";
            splash_str1_dyn[ 4*8 +: 8] <= "u";
            splash_str1_dyn[ 3*8 +: 8] <= "s";
            splash_str1_dyn[ 2*8 +: 8] <= " ";
            splash_str1_dyn[ 1*8 +: 8] <= " ";
            splash_str1_dyn[ 0*8 +: 8] <= " ";
        end
    end

    // -------------------------------------------------------------------------
    // OLEDCtrl interface signals
    // -------------------------------------------------------------------------
    wire        rst;
    assign      rst = ~rstn;

    reg  [3:0]  state      = Idle;
    reg  [3:0]  after_state;
    reg         screen_select = ALPHA;

    reg         delay_start   = 0;
    reg  [11:0] delay_time_ms = 0;
    wire        delay_done;

    reg         update_start     = 0;
    reg         update_clear     = 0;
    wire        update_ready;
    reg         disp_on_start    = 0;
    wire        disp_on_ready;
    reg         disp_off_start   = 0;
    wire        disp_off_ready;
    reg         toggle_disp_start = 0;
    wire        toggle_disp_ready;
    reg         write_start      = 0;
    wire        write_ready;
    reg  [8:0]  write_base_addr  = 0;
    reg  [7:0]  write_ascii_data = 0;

    wire        init_done  = disp_off_ready | toggle_disp_ready | write_ready | update_ready;
    wire        init_ready = disp_on_ready;

    // -------------------------------------------------------------------------
    // Character select (combinatorial)
    // -------------------------------------------------------------------------
    always @(write_base_addr)
        if (screen_select == SPLASH)
            case (write_base_addr[8:7])
            0: write_ascii_data = 8'hff & (splash_str1_dyn >> ({3'b0, (16 - 1 - write_base_addr[6:3])} << 3));
            1: write_ascii_data = 8'hff & (splash_str2     >> ({3'b0, (16 - 1 - write_base_addr[6:3])} << 3));
            2: write_ascii_data = 8'hff & (splash_str3     >> ({3'b0, (16 - 1 - write_base_addr[6:3])} << 3));
            3: write_ascii_data = 8'hff & (splash_str4     >> ({3'b0, (16 - 1 - write_base_addr[6:3])} << 3));
            endcase
        else
            case (write_base_addr[8:7])
            0: write_ascii_data = 8'hff & (alpha_str1 >> ({3'b0, (alpha_str1_len - 1 - write_base_addr[6:3])} << 3));
            1: write_ascii_data = 8'hff & (alpha_str2 >> ({3'b0, (alpha_str2_len - 1 - write_base_addr[6:3])} << 3));
            2: write_ascii_data = 8'hff & (alpha_str3 >> ({3'b0, (alpha_str3_len - 1 - write_base_addr[6:3])} << 3));
            3: write_ascii_data = 8'hff & (alpha_str4 >> ({3'b0, (alpha_str4_len - 1 - write_base_addr[6:3])} << 3));
            endcase

    // -------------------------------------------------------------------------
    // State machine
    // -------------------------------------------------------------------------
    reg once = 1;
    always @(posedge clk)
        case (state)
            Idle: begin
                if ((rst || once) && init_ready) begin
                    disp_on_start <= 1'b1;
                    state <= Init;
                    once  <= 1'b0;
                end
            end
            Init: begin
                disp_on_start <= 1'b0;
                if (!rst && init_done)
                    state <= ActiveWriteAlpha;
            end
            ActiveWriteAlpha: begin
                write_start    <= 1'b1;
                write_base_addr <= 'b0;
                screen_select  <= ALPHA;
                after_state    <= ActiveUpdateAlpha;
                state          <= WriteWait;
            end
            ActiveUpdateAlpha: begin
                after_state  <= ActiveDelayAlpha;
                state        <= UpdateWait;
                update_start <= 1'b1;
                update_clear <= 1'b0;
            end
            ActiveDelayAlpha: begin
                after_state    <= ActiveWriteSplash;
                state          <= DelayWait;
                delay_start    <= 1'b1;
                delay_time_ms  <= 4000;
            end
            ActiveWriteSplash: begin
                write_start    <= 1'b1;
                write_base_addr <= 'b0;
                screen_select  <= SPLASH;
                after_state    <= ActiveUpdateSplash;
                state          <= WriteWait;
            end
            ActiveUpdateSplash: begin
                // Go straight to ActiveWait — no delay after splash
                after_state  <= ActiveWait;
                state        <= UpdateWait;
                update_start <= 1'b1;
                update_clear <= 1'b0;
            end
            ActiveWait: begin
                if (redraw_pulse) begin
                    write_base_addr <= 'b0;
                    screen_select   <= SPLASH;
                    after_state     <= ActiveUpdateSplash;
                    state           <= WriteWait;
                end else if (rst && disp_off_ready) begin
                    disp_off_start <= 1'b1;
                    state          <= Done;
                end
            end
            Write: begin
                write_start     <= 1'b1;
                write_base_addr <= write_base_addr + 9'h8;
                state           <= WriteWait;
            end
            DelayWait: begin
                delay_start <= 1'b0;
                if (delay_done)
                    state <= after_state;
            end
            WriteWait: begin
                write_start <= 1'b0;
                if (write_ready)
                    if (write_base_addr == 9'h1f8)
                        state <= after_state;
                    else
                        state <= Write;
            end
            UpdateWait: begin
                update_start <= 0;
                if (update_ready)
                    state <= after_state;
            end
            Done: begin
                disp_off_start <= 1'b0;
                if (!rst && disp_on_ready)
                    state <= Idle;
            end
            default: state <= Idle;
        endcase

    // -------------------------------------------------------------------------
    // Sub-modules
    // -------------------------------------------------------------------------
    OLED_ctrl OLED (
        .clk                (clk),
        .write_start        (write_start),
        .write_ascii_data   (write_ascii_data),
        .write_base_addr    (write_base_addr),
        .write_ready        (write_ready),
        .update_start       (update_start),
        .update_ready       (update_ready),
        .update_clear       (update_clear),
        .disp_on_start      (disp_on_start),
        .disp_on_ready      (disp_on_ready),
        .disp_off_start     (disp_off_start),
        .disp_off_ready     (disp_off_ready),
        .toggle_disp_start  (toggle_disp_start),
        .toggle_disp_ready  (toggle_disp_ready),
        .SDIN               (oled_sdin),
        .SCLK               (oled_sclk),
        .DC                 (oled_dc),
        .RES                (oled_res),
        .VBAT               (oled_vbat),
        .VDD                (oled_vdd)
    );

    delay_ms DELAY (
        clk,
        delay_time_ms,
        delay_start,
        delay_done
    );

endmodule
