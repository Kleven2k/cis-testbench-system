`timescale 1ns/1ps
`default_nettype none

// Simulation wrapper for uart_reg_if.
// Uses fast clocks: CLK_FREQ=10 MHz, BAUD=1 Mbaud -> 10 cycles/bit.
// The test drives a "host TX" uart_tx to send frames into the DUT's RX,
// and a "host RX" uart_rx to capture the DUT's response bytes.
//
// register_mem is a simple 256-entry RAM exposed to the test so it can
// pre-load read_data and inspect write results.

module uart_reg_if_tb_wrapper (
    input  logic        clk,
    input  logic        rst,

    // Host → DUT: test drives these to inject serial frames
    input  logic        host_tx_start,
    input  logic [7:0]  host_tx_data,
    output logic        host_tx_busy,

    // DUT → Host: captured response bytes
    output logic [7:0]  host_rx_data,
    output logic        host_rx_valid,

    // Register memory: write side (inspect from test)
    output logic        write_en,
    output logic [7:0]  write_addr,
    output logic [7:0]  write_data,

    // Register memory: read side (pre-load from test)
    input  logic [7:0]  read_addr_override,   // unused in DUT path — DUT drives read_addr
    input  logic [7:0]  mem_write_data,        // value to store at mem_write_addr
    input  logic [7:0]  mem_write_addr,
    input  logic        mem_write_en           // strobe to write into read_mem
);

    localparam CLK_FREQ = 10_000_000;
    localparam BAUD     = 1_000_000;

    // ── Host TX (test → DUT RX) ───────────────────────────────────────────
    logic serial_host_to_dut;

    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) u_host_tx (
        .clk     (clk),
        .rst     (rst),
        .tx_start(host_tx_start),
        .data_in (host_tx_data),
        .tx      (serial_host_to_dut),
        .tx_busy (host_tx_busy)
    );

    // ── DUT RX glue ───────────────────────────────────────────────────────
    logic [7:0] dut_rx_data;
    logic       dut_rx_valid;

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) u_dut_rx (
        .clk       (clk),
        .rst       (rst),
        .rx        (serial_host_to_dut),
        .data_out  (dut_rx_data),
        .data_valid(dut_rx_valid)
    );

    // ── DUT TX glue ───────────────────────────────────────────────────────
    logic serial_dut_to_host;
    logic dut_tx_start, dut_tx_busy;
    logic [7:0] dut_tx_data;

    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) u_dut_tx (
        .clk     (clk),
        .rst     (rst),
        .tx_start(dut_tx_start),
        .data_in (dut_tx_data),
        .tx      (serial_dut_to_host),
        .tx_busy (dut_tx_busy)
    );

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) u_host_rx (
        .clk       (clk),
        .rst       (rst),
        .rx        (serial_dut_to_host),
        .data_out  (host_rx_data),
        .data_valid(host_rx_valid)
    );

    // ── Read memory (pre-loaded by test) ─────────────────────────────────
    logic [7:0] read_mem [0:255];
    logic [7:0] dut_read_addr;
    logic [7:0] dut_read_data;

    always_comb dut_read_data = read_mem[dut_read_addr];

    always_ff @(posedge clk) begin
        if (mem_write_en)
            read_mem[mem_write_addr] <= mem_write_data;
    end

    // ── DUT ───────────────────────────────────────────────────────────────
    uart_reg_if u_dut (
        .clk       (clk),
        .rst       (rst),
        .rx_data   (dut_rx_data),
        .rx_valid  (dut_rx_valid),
        .tx_data   (dut_tx_data),
        .tx_start  (dut_tx_start),
        .tx_busy   (dut_tx_busy),
        .write_en  (write_en),
        .write_addr(write_addr),
        .write_data(write_data),
        .read_addr (dut_read_addr),
        .read_data (dut_read_data)
    );

    initial begin
        $dumpfile("sim_build/dump.vcd");
        $dumpvars(0, uart_reg_if_tb_wrapper);
    end

endmodule

`default_nettype wire
