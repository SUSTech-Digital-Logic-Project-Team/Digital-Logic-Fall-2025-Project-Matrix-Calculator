// ========================================
// UART transceiver module
// Purpose: Handle UART TX and RX at specified baud rate
// ========================================

`timescale 1ns / 1ps

module uart_module #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD_RATE = 115200
)(
    input wire clk,
    input wire rst_n,
    
    // UART physical interface
    input wire uart_rx,
    output wire uart_tx,
    
    // RX interface
    output wire [7:0] rx_data,
    output wire rx_done,
    
    // TX interface
    input wire [7:0] tx_data,
    input wire tx_start,
    output wire tx_busy
);

    // Instantiate UART RX
    uart_rx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uart_receiver (
        .clk(clk),
        .rst_n(rst_n),
        .rx(uart_rx),
        .rx_data(rx_data),
        .rx_done(rx_done)
    );

    // Instantiate UART TX
    uart_tx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uart_transmitter (
        .clk(clk),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx(uart_tx),
        .tx_busy(tx_busy)
    );

endmodule
