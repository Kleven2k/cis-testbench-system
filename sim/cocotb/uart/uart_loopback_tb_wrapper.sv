`timescale 1ns/1ps

// Loopback wrapper: TX output wired directly to RX input.
// Uses fast simulation parameters (CLK_FREQ=10M, BAUD=1M → 10 cycles/bit).
module uart_loopback_tb_wrapper (
    input  logic        clk,
    input  logic        rst,

    // TX side
    input  logic        tx_start,
    input  logic [7:0]  data_in,
    output logic        tx_busy,

    // RX side (loopback result)
    output logic [7:0]  data_out,
    output logic        data_valid
);

    localparam CLK_FREQ = 10_000_000;
    localparam BAUD     = 1_000_000;  // 10 cycles/bit — fast simulation

    logic tx_wire;

    uart_tx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD    (BAUD)
    ) u_tx (
        .clk     (clk),
        .rst     (rst),
        .tx_start(tx_start),
        .data_in (data_in),
        .tx      (tx_wire),
        .tx_busy (tx_busy)
    );

    uart_rx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD    (BAUD)
    ) u_rx (
        .clk       (clk),
        .rst       (rst),
        .rx        (tx_wire),
        .data_out  (data_out),
        .data_valid(data_valid)
    );

    initial begin
        $dumpfile("sim_build/dump.vcd");
        $dumpvars(0, uart_loopback_tb_wrapper);
    end

endmodule
