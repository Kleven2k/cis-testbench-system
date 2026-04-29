
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
    logic in_region;
    always_comb
        in_region = (sx >= BOX_X0 && sx < BOX_X1 &&
                     sy >= BOX_Y0 && sy < BOX_Y1);

    int col, row, pixel_idx;

    always_comb begin
        int x_rel, y_rel, x_in, y_in;
        logic [11:0] raw;
        logic [11:0] dev;       // deviation from "dark" end of range, 0 = black
        logic [15:0] boosted;   // dev after disp_gain left-shift (extra bits for saturation)
        logic [3:0]  base_gray; // auto-scaled 4-bit gray before boost

        gray_out = 4'h0;

        if (in_region) begin
            x_rel = int'(sx) - BOX_X0;
            y_rel = int'(sy) - BOX_Y0;

            // Column decoder
            if      (x_rel >= 7*CELL_W) col = 7;
            else if (x_rel >= 6*CELL_W) col = 6;
            else if (x_rel >= 5*CELL_W) col = 5;
            else if (x_rel >= 4*CELL_W) col = 4;
            else if (x_rel >= 3*CELL_W) col = 3;
            else if (x_rel >= 2*CELL_W) col = 2;
            else if (x_rel >= 1*CELL_W) col = 1;
            else                         col = 0;

            // Row decoder
            if      (y_rel >= 7*CELL_H) row = 7;
            else if (y_rel >= 6*CELL_H) row = 6;
            else if (y_rel >= 5*CELL_H) row = 5;
            else if (y_rel >= 4*CELL_H) row = 4;
            else if (y_rel >= 3*CELL_H) row = 3;
            else if (y_rel >= 2*CELL_H) row = 2;
            else if (y_rel >= 1*CELL_H) row = 1;
            else                         row = 0;

            if (col < GRID_COLS && row < GRID_ROWS) begin
                pixel_idx = row * GRID_COLS + col;
                raw       = pixel_mem[pixel_idx];
                x_in      = x_rel - col * CELL_W;
                y_in      = y_rel - row * CELL_H;

                // ── Compute deviation from the "dark" end of the range ────────
                // invert_pol=0 (default, lower ADC = more light):
                //   dark end = frame_max; dev = frame_max - raw, clamp 0
                // invert_pol=1 (higher ADC = more light, standard CMOS):
                //   dark end = frame_min; dev = raw - frame_min, clamp 0
                if (invert_pol)
                    dev = (raw > frame_min) ? (raw - frame_min) : 12'h0;
                else
                    dev = (raw < frame_max) ? (frame_max - raw) : 12'h0;

                // ── Auto-scale dev to 4-bit gray ─────────────────────────────
                // Shift right by (lead_bit - 3) so the brightest pixel maps to
                // gray 8..15.  lead_bit tracks the MSB of frame_range so this
                // adapts automatically to any sensor output voltage swing.
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

                // ── disp_gain: boost contrast beyond auto-scale ───────────────
                // Useful when the frame_range is small (flat scene, low contrast).
                // 0=×1  1=×2  2=×4  3=×8
                boosted = {12'h0, base_gray} << disp_gain;
                dev     = (|boosted[15:4]) ? 12'hFFF : {8'h0, boosted[3:0]};
                // (reuse dev to carry boosted gray into the rendering below)

                // ── Pixel grid lines ─────────────────────────────────────────
                if (x_in == 0 || y_in == 0) begin
                    gray_out = 4'h4;

                end else if (photosense_mode && ((row + col) % 2 == 0)) begin
                    gray_out = 4'h0;  // blank this position

                end else if (y_in >= (CELL_H - BAR_H)) begin
                    // ── Intensity bar (bottom strip) ─────────────────────────
                    // Width ∝ dev[3:0] (the boosted gray, 0-15) scaled to CELL_W.
                    // Empty in darkness (dev=0), full-width at maximum brightness.
                    if (x_in < int'({dev[3:0], 3'b000}))   // dev*8, max=120 < CELL_W≈106 → ok
                        gray_out = 4'hF;
                    else
                        gray_out = 4'h1;

                end else begin
                    // ── Grayscale image ──────────────────────────────────────
                    gray_out = dev[3:0];
                end
            end
        end
    end
endmodule
