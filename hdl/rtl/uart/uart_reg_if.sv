`default_nettype none
`timescale 1ns/1ps

module uart_reg_if (
    input  wire logic        clk,
    input  wire logic        rst,

    input  wire logic [7:0]  rx_data,
    input  wire logic        rx_valid,

    output      logic [7:0]  tx_data,
    output      logic        tx_start,
    input  wire logic        tx_busy,

    output      logic        write_en,
    output      logic [7:0]  write_addr,
    output      logic [7:0]  write_data,

    output      logic [7:0]  read_addr,
    input  wire logic [7:0]  read_data
);

    typedef enum logic [3:0] {
        S_IDLE,
        S_GET_ADDR,
        S_GET_DATA,
        S_WAIT_FOOTER,
        S_TX_HDR,
        S_TX_ADDR,
        S_TX_DATA,
        S_TX_FOOTER
    } state_t;

    state_t state;

    logic [7:0] addr_reg;
    logic [7:0] data_reg;
    logic       is_read;

    // tx_busy_d: 1-cycle delayed tx_busy.
    // tx_done: fires only on the falling edge of tx_busy (or first time in S_TX_HDR).
    // This prevents the next TX state from firing in the same cycle that uart_tx
    // first asserts tx_busy, which would cause it to miss the tx_start pulse.
    logic tx_busy_d;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) tx_busy_d <= 1'b0;
        else     tx_busy_d <= tx_busy;
    end
    wire tx_done = !tx_busy && (tx_busy_d || state == S_TX_HDR);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state    <= S_IDLE;
            write_en <= 0;
            tx_start <= 0;
        end else begin
            write_en <= 0;
            tx_start <= 0;

            case (state)

                // ------------------------------------------------
                // RX SECTION
                // ------------------------------------------------
                S_IDLE:
                    if (rx_valid) begin
                        if (rx_data == 8'hAA) begin
                            is_read <= 0;
                            state   <= S_GET_ADDR;
                        end
                        else if (rx_data == 8'hBB) begin
                            is_read <= 1;
                            state   <= S_GET_ADDR;
                        end
                    end

                S_GET_ADDR:
                    if (rx_valid) begin
                        addr_reg <= rx_data;
                        if (is_read)
                            state <= S_WAIT_FOOTER;
                        else
                            state <= S_GET_DATA;
                    end

                S_GET_DATA:
                    if (rx_valid) begin
                        data_reg <= rx_data;
                        state    <= S_WAIT_FOOTER;
                    end

                S_WAIT_FOOTER:
                    if (rx_valid) begin
                        if (rx_data == 8'h55) begin
                            if (is_read) begin
                                read_addr <= addr_reg;
                                state     <= S_TX_HDR;
                            end else begin
                                write_en   <= 1;
                                write_addr <= addr_reg;
                                write_data <= data_reg;
                                state      <= S_IDLE;
                            end
                        end else begin
                            state <= S_IDLE;
                        end
                    end

                // ------------------------------------------------
                // TX SECTION (Read Response)
                // ------------------------------------------------
                S_TX_HDR:
                    if (tx_done) begin
                        tx_data  <= 8'hCC;
                        tx_start <= 1;
                        state    <= S_TX_ADDR;
                    end

                S_TX_ADDR:
                    if (tx_done) begin
                        tx_data  <= addr_reg;
                        tx_start <= 1;
                        state    <= S_TX_DATA;
                    end

                S_TX_DATA:
                    if (tx_done) begin
                        tx_data  <= read_data;
                        tx_start <= 1;
                        state    <= S_TX_FOOTER;
                    end

                S_TX_FOOTER:
                    if (tx_done) begin
                        tx_data  <= 8'h55;
                        tx_start <= 1;
                        state    <= S_IDLE;
                    end
            endcase
        end
    end

endmodule

`default_nettype wire