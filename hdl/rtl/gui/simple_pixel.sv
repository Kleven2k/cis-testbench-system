
`default_nettype none
`timescale 1ns/1ps

module simple_pixel #(
    parameter CORDW=12,     // coordinate width
    parameter H_RES=1280,   // horizontal screen resolution
    parameter V_RES=720    // vertical screen resolution
    ) (
    input wire logic clk_pix,               // pixel clock
    input wire logic [CORDW-1:0] sx,        // horizontal screen position
    input wire logic [CORDW-1:0] sy,        // verticals screen position

    input wire logic [11:0]    pixel_mem [0:63],

    input wire logic [11:0] volt_sensor,    // volt for the image sensor output
    input wire logic [11:0] volt_temp,      // volt for the temperature
    input wire logic [15:0] delay_time,     // delay time
    
    output     logic [3:0] gray_out         // grayscale brightness output
    );    

    // Define thresholds (e.g., mid-voltage around 0.5V = 2048)
    //localparam logic [11:0] THRESHOLD = 12'd2048;

    // Sensor display cover ~2/3 of the screen
    localparam int BOX_W = (H_RES*2)/3;
    localparam int BOX_H = (V_RES*2)/3;

    localparam int BOX_X0 = (H_RES-BOX_W)/2;
    localparam int BOX_X1 = (H_RES+BOX_W)/2;
    localparam int BOX_Y0 = (V_RES-BOX_H)/2;
    localparam int BOX_Y1 = (V_RES+BOX_H)/2;

    // Grid: 8 x 8
    localparam int GRID_COLS = 8;
    localparam int GRID_ROWS = 8;

    localparam int CELL_W = BOX_W / GRID_COLS;
    localparam int CELL_H = BOX_H / GRID_ROWS;

    logic in_sensor_region;
    always_comb begin 
        in_sensor_region = (sx >= BOX_X0 && sx < BOX_X1 &&
                            sy >= BOX_Y0 && sy < BOX_Y1);
    end 

    // Compute which cell we are in
    int col, row;
    int pixel_index;

    always_comb begin
        int x_rel, y_rel;
        gray_out = 4'b0000;     // default black

        if (in_sensor_region) begin
            x_rel = int'(sx) - BOX_X0;
            y_rel = int'(sy) - BOX_Y0;

            // Column: boundary comparisons against compile-time constants.
            // Avoids a slow integer divider carry chain (was 15 CARRY4 stages).
            if      (x_rel >= 7 * CELL_W) col = 7;
            else if (x_rel >= 6 * CELL_W) col = 6;
            else if (x_rel >= 5 * CELL_W) col = 5;
            else if (x_rel >= 4 * CELL_W) col = 4;
            else if (x_rel >= 3 * CELL_W) col = 3;
            else if (x_rel >= 2 * CELL_W) col = 2;
            else if (x_rel >= 1 * CELL_W) col = 1;
            else                           col = 0;

            // Row: same approach
            if      (y_rel >= 7 * CELL_H) row = 7;
            else if (y_rel >= 6 * CELL_H) row = 6;
            else if (y_rel >= 5 * CELL_H) row = 5;
            else if (y_rel >= 4 * CELL_H) row = 4;
            else if (y_rel >= 3 * CELL_H) row = 3;
            else if (y_rel >= 2 * CELL_H) row = 2;
            else if (y_rel >= 1 * CELL_H) row = 1;
            else                           row = 0;

            if (col < GRID_COLS && row < GRID_ROWS) begin
                pixel_index = row * GRID_COLS + col; // 0..63

                // Use top 4 bits of pixel memory as brightness
                gray_out = ~pixel_mem[pixel_index][11:8];
            end
        end
    end

    /*
    // set screen region
    logic region_sensor;
    always_comb begin 
        region_sensor = (sx >= BOX_X0 && sx < BOX_X1 && 
                         sy >= BOX_Y0 && sy < BOX_Y1);
    end 

    logic region_temp, region_delay;
    always_comb begin 
        region_temp = (sy >= V_RES-32 && sy < V_RES-16);

        region_delay = (sy >= V_RES-16 && sy < V_RES-0);
    end 

    // Use MSBs of voltage to get 4-bit brightness (0 = black, 15 = white)
    always_comb begin 
        gray_out = 4'b0000;    // default black

        if (region_sensor) 
            gray_out = ~volt_sensor[11:8];     // top 4 bits

        else if (region_temp || region_delay)
            gray_out = 4'b1111;
    end 
    */
endmodule