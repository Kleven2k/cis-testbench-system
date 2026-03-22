

module cdc_adc_sync (
    input wire clk_src,     // XADC clock (100 MHz)
    input wire clk_dst,     // Pixel clock
    input wire [11:0] data_sensor_in,
    input wire [11:0] data_temp_in,
    input wire        data_valid, 
    output reg [11:0] data_sensor_out,
    output reg [11:0] data_temp_out
);
    
    // Toggle flag in source domain
    reg toggle_src = 0;
    always_ff @(posedge clk_src)
        if (data_valid)
            toggle_src <= ~toggle_src;

    // Synchronize toggle into destination domain
    reg [2:0] toggle_sync = 0;
    always_ff @(posedge clk_dst)
        toggle_sync <= {toggle_sync[1:0], toggle_src};

    wire toggle_edge = toggle_sync[2] ^ toggle_sync[1];

    // REgister data when edge detected
    reg [11:0] data_sensor_buf, data_temp_buf;
    always_ff @(posedge clk_src)
        if (data_valid) begin 
            data_sensor_buf <= data_sensor_in;
            data_temp_buf   <= data_temp_in;
        end 

    // Stage 1: capture data_buf into destination domain on toggle edge
    reg [11:0] data_sensor_dst, data_temp_dst;
    always_ff @(posedge clk_dst)
        if (toggle_edge) begin
            data_sensor_dst <= data_sensor_buf;
            data_temp_dst   <= data_temp_buf;
        end

    // Stage 2: register output one cycle later so data has fully settled
    always_ff @(posedge clk_dst) begin
        data_sensor_out <= data_sensor_dst;
        data_temp_out   <= data_temp_dst;
    end
endmodule

