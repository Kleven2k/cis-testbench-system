
`default_nettype none
`timescale 1ns/1ps

module simple_pixel #(
    parameter CORDW    = 12,   // coordinate width
    parameter H_RES    = 1280, // horizontal screen resolution
    parameter V_RES    = 720,  // vertical screen resolution
    parameter GRID_COLS = 8,   // sensor columns
    parameter GRID_ROWS = 8    // sensor rows
    ) (
    input wire logic clk_pix,               // pixel clock
    input wire logic [CORDW-1:0] sx,        // horizontal screen position
    input wire logic [CORDW-1:0] sy,        // vertical screen position

    input wire logic [11:0]    pixel_mem [0:GRID_COLS*GRID_ROWS-1],

    // Auto-range references — updated once per completed scan frame.
    // frame_min / frame_max exclude blanked (ISFET) pixels when photosense_mode=1.
    input wire logic [11:0] frame_min,      // darkest pixel value in last frame
    input wire logic [11:0] frame_max,      // brightest pixel value in last frame

    input wire logic [11:0] volt_sensor,    // volt for the image sensor output
    input wire logic [11:0] volt_temp,      // volt for the temperature
    input wire logic [15:0] delay_time,     // delay time
    input wire logic        photosense_mode, // 1 = blank checkerboard positions
    input wire logic        invert_pol,     // 0 = lower ADC → brighter (default)
                                            // 1 = higher ADC → brighter (standard CMOS)
    input wire logic [1:0]  disp_gain,      // extra sensitivity boost (0=none … 3=8×)

    output     logic [3:0] gray_out         // grayscale brightness output
    );

    // Sensor display covers ~2/3 of the screen, centered
    localparam int BOX_W  = (H_RES*2)/3;
    localparam int BOX_H  = (V_RES*2)/3;
    localparam int BOX_X0 = (H_RES - BOX_W)/2;
    localparam int BOX_X1 = (H_RES + BOX_W)/2;
    localparam int BOX_Y0 = (V_RES - BOX_H)/2;
    localparam int BOX_Y1 = (V_RES + BOX_H)/2;
    localparam int CELL_W = BOX_W / GRID_COLS;  // ≈ 106 px
    localparam int CELL_H = BOX_H / GRID_ROWS;  // = 60 px

    // Bottom fraction of each cell reserved for the intensity bar
    localparam int BAR_H = CELL_H / 5;  // 12 px at 720p

    // Pre-computed cell boundary positions — constants so no multiplier is inferred
    localparam int CX1  = 1*CELL_W;  localparam int CX2  = 2*CELL_W;
    localparam int CX3  = 3*CELL_W;  localparam int CX4  = 4*CELL_W;
    localparam int CX5  = 5*CELL_W;  localparam int CX6  = 6*CELL_W;
    localparam int CX7  = 7*CELL_W;  localparam int CX8  = 8*CELL_W;
    localparam int CX9  = 9*CELL_W;  localparam int CX10 = 10*CELL_W;
    localparam int CX11 = 11*CELL_W; localparam int CX12 = 12*CELL_W;
    localparam int CX13 = 13*CELL_W; localparam int CX14 = 14*CELL_W;
    localparam int CX15 = 15*CELL_W;

    localparam int CY1  = 1*CELL_H;  localparam int CY2  = 2*CELL_H;
    localparam int CY3  = 3*CELL_H;  localparam int CY4  = 4*CELL_H;
    localparam int CY5  = 5*CELL_H;  localparam int CY6  = 6*CELL_H;
    localparam int CY7  = 7*CELL_H;  localparam int CY8  = 8*CELL_H;
    localparam int CY9  = 9*CELL_H;  localparam int CY10 = 10*CELL_H;
    localparam int CY11 = 11*CELL_H; localparam int CY12 = 12*CELL_H;
    localparam int CY13 = 13*CELL_H; localparam int CY14 = 14*CELL_H;
    localparam int CY15 = 15*CELL_H;

    // ─────────────────────────────────────────────────────────────────────────
    // Auto-range scaling
    //
    // frame_range = frame_max - frame_min.  We find the position of the MSB
    // (leading bit) to determine a power-of-2 divisor, then apply disp_gain
    // as an additional left-shift (boost) before clamping to 4 bits.
    //
    // Result: at disp_gain=0 the pixel that differs most from the dark end
    // maps to gray=7..15 (half to full scale).  disp_gain=1/2/3 doubles that.
    // ─────────────────────────────────────────────────────────────────────────
    logic [11:0] frame_range;
    assign frame_range = frame_max - frame_min;  // 0 when frame is uniform

    // Leading-bit position of frame_range (clamp minimum to 3 so shift >= 0)
    logic [3:0] lead_bit;
    always_comb begin
        if      (frame_range[11]) lead_bit = 4'd11;
        else if (frame_range[10]) lead_bit = 4'd10;
        else if (frame_range[9])  lead_bit = 4'd9;
        else if (frame_range[8])  lead_bit = 4'd8;
        else if (frame_range[7])  lead_bit = 4'd7;
        else if (frame_range[6])  lead_bit = 4'd6;
        else if (frame_range[5])  lead_bit = 4'd5;
        else if (frame_range[4])  lead_bit = 4'd4;
        else                      lead_bit = 4'd3;  // minimum — avoids left-shift underflow
    end

    // ─────────────────────────────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────
    // Stage 1 (combinatorial): decode pixel coordinates from screen position.
    // Registered at end of stage to break the long sx→gray_out path.
    // ─────────────────────────────────────────────────────────────────────────
    logic        in_region;
    logic [$clog2(GRID_COLS)-1:0] col_comb, row_comb;
    logic [11:0] x_in_comb, y_in_comb;
    logic        valid_comb;

    always_comb begin
        int x_rel, y_rel;
        in_region  = (sx >= BOX_X0 && sx < BOX_X1 &&
                      sy >= BOX_Y0 && sy < BOX_Y1);
        col_comb   = '0;
        row_comb   = '0;
        x_in_comb  = '0;
        y_in_comb  = '0;
        valid_comb = 1'b0;

        if (in_region) begin
            x_rel = int'(sx) - BOX_X0;
            y_rel = int'(sy) - BOX_Y0;

            if      (GRID_COLS > 15 && x_rel >= CX15) col_comb = 4'd15;
            else if (GRID_COLS > 14 && x_rel >= CX14) col_comb = 4'd14;
            else if (GRID_COLS > 13 && x_rel >= CX13) col_comb = 4'd13;
            else if (GRID_COLS > 12 && x_rel >= CX12) col_comb = 4'd12;
            else if (GRID_COLS > 11 && x_rel >= CX11) col_comb = 4'd11;
            else if (GRID_COLS > 10 && x_rel >= CX10) col_comb = 4'd10;
            else if (GRID_COLS > 9  && x_rel >= CX9)  col_comb = 4'd9;
            else if (GRID_COLS > 8  && x_rel >= CX8)  col_comb = 4'd8;
            else if (GRID_COLS > 7  && x_rel >= CX7)  col_comb = 4'd7;
            else if (GRID_COLS > 6  && x_rel >= CX6)  col_comb = 4'd6;
            else if (GRID_COLS > 5  && x_rel >= CX5)  col_comb = 4'd5;
            else if (GRID_COLS > 4  && x_rel >= CX4)  col_comb = 4'd4;
            else if (GRID_COLS > 3  && x_rel >= CX3)  col_comb = 4'd3;
            else if (GRID_COLS > 2  && x_rel >= CX2)  col_comb = 4'd2;
            else if (GRID_COLS > 1  && x_rel >= CX1)  col_comb = 4'd1;
            else                                       col_comb = 4'd0;

            if      (GRID_ROWS > 15 && y_rel >= CY15) row_comb = 4'd15;
            else if (GRID_ROWS > 14 && y_rel >= CY14) row_comb = 4'd14;
            else if (GRID_ROWS > 13 && y_rel >= CY13) row_comb = 4'd13;
            else if (GRID_ROWS > 12 && y_rel >= CY12) row_comb = 4'd12;
            else if (GRID_ROWS > 11 && y_rel >= CY11) row_comb = 4'd11;
            else if (GRID_ROWS > 10 && y_rel >= CY10) row_comb = 4'd10;
            else if (GRID_ROWS > 9  && y_rel >= CY9)  row_comb = 4'd9;
            else if (GRID_ROWS > 8  && y_rel >= CY8)  row_comb = 4'd8;
            else if (GRID_ROWS > 7  && y_rel >= CY7)  row_comb = 4'd7;
            else if (GRID_ROWS > 6  && y_rel >= CY6)  row_comb = 4'd6;
            else if (GRID_ROWS > 5  && y_rel >= CY5)  row_comb = 4'd5;
            else if (GRID_ROWS > 4  && y_rel >= CY4)  row_comb = 4'd4;
            else if (GRID_ROWS > 3  && y_rel >= CY3)  row_comb = 4'd3;
            else if (GRID_ROWS > 2  && y_rel >= CY2)  row_comb = 4'd2;
            else if (GRID_ROWS > 1  && y_rel >= CY1)  row_comb = 4'd1;
            else                                       row_comb = 4'd0;

            x_in_comb  = x_rel - col_comb * CELL_W;
            y_in_comb  = y_rel - row_comb * CELL_H;
            valid_comb = 1'b1;
        end
    end

    // Pipeline register — breaks sx→gray_out combinatorial path
    logic [$clog2(GRID_COLS)-1:0] col_r, row_r;
    logic [11:0] x_in_r, y_in_r;
    logic        valid_r;
    always_ff @(posedge clk_pix) begin
        col_r   <= col_comb;
        row_r   <= row_comb;
        x_in_r  <= x_in_comb;
        y_in_r  <= y_in_comb;
        valid_r <= valid_comb;
    end

    // ─────────────────────────────────────────────────────────────────────────
    // Stage 2 (combinatorial): pixel lookup and brightness computation.
    // Inputs are registered col/row so this path starts from a flip-flop.
    // ─────────────────────────────────────────────────────────────────────────
    always_comb begin
        logic [11:0] raw;
        logic [11:0] dev;
        logic [15:0] boosted;
        logic [3:0]  base_gray;

        gray_out = 4'h0;

        if (valid_r) begin
            raw = pixel_mem[row_r * GRID_COLS + col_r];

            if (invert_pol)
                dev = (raw > frame_min) ? (raw - frame_min) : 12'h0;
            else
                dev = (raw < frame_max) ? (frame_max - raw) : 12'h0;

            case (lead_bit)
                4'd11: base_gray = dev[11:8];
                4'd10: base_gray = dev[10:7];
                4'd9:  base_gray = dev[9:6];
                4'd8:  base_gray = dev[8:5];
                4'd7:  base_gray = dev[7:4];
                4'd6:  base_gray = dev[6:3];
                4'd5:  base_gray = dev[5:2];
                4'd4:  base_gray = dev[4:1];
                default: base_gray = dev[3:0];
            endcase

            boosted = {12'h0, base_gray} << disp_gain;
            dev     = (|boosted[15:4]) ? 12'hFFF : {8'h0, boosted[3:0]};

            if (x_in_r == 0 || y_in_r == 0) begin
                gray_out = 4'h4;
            end else if (photosense_mode && ((row_r + col_r) % 2 == 0)) begin
                gray_out = 4'h0;
            end else if (y_in_r >= (CELL_H - BAR_H)) begin
                if (x_in_r < int'({dev[3:0], 3'b000}))
                    gray_out = 4'hF;
                else
                    gray_out = 4'h1;
            end else begin
                gray_out = dev[3:0];
            end
        end
    end
endmodule
