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
    output reg [7:0] rx_data,
    output reg rx_valid,
    
    // TX interface
    input wire [7:0] tx_data,
    input wire tx_start,
    output reg tx_busy
);

// Calculate baud rate divisor
localparam BAUD_DIV = CLK_FREQ / BAUD_RATE;
localparam HALF_BAUD_DIV = BAUD_DIV / 2;

// ========================================
// UART Receiver
// ========================================
reg [15:0] rx_clk_div;
reg [3:0] rx_bit_cnt;
reg [7:0] rx_shift_reg;
reg [1:0] rx_state;
reg [1:0] uart_rx_sync;

localparam RX_IDLE = 2'd0, RX_START = 2'd1, RX_DATA = 2'd2, RX_STOP = 2'd3;

// Synchronize UART RX input
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        uart_rx_sync <= 2'b11;
    end else begin
        uart_rx_sync <= {uart_rx_sync[0], uart_rx};
    end
end

wire uart_rx_sync_val = uart_rx_sync[1];

// UART RX state machine
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_state <= RX_IDLE;
        rx_clk_div <= 16'd0;
        rx_bit_cnt <= 4'd0;
        rx_shift_reg <= 8'd0;
        rx_data <= 8'd0;
        rx_valid <= 1'b0;
    end else begin
        rx_valid <= 1'b0;
        
        case (rx_state)
            RX_IDLE: begin
                rx_clk_div <= 16'd0;
                rx_bit_cnt <= 4'd0;
                if (!uart_rx_sync_val) begin  // Start bit detected
                    rx_state <= RX_START;
                end
            end
            
            RX_START: begin
                if (rx_clk_div == HALF_BAUD_DIV - 1) begin
                    rx_clk_div <= 16'd0;
                    if (!uart_rx_sync_val) begin  // Verify start bit
                        rx_state <= RX_DATA;
                    end else begin
                        rx_state <= RX_IDLE;
                    end
                end else begin
                    rx_clk_div <= rx_clk_div + 1'b1;
                end
            end
            
            RX_DATA: begin
                if (rx_clk_div == BAUD_DIV - 1) begin
                    rx_clk_div <= 16'd0;
                    rx_shift_reg <= {uart_rx_sync_val, rx_shift_reg[7:1]};
                    rx_bit_cnt <= rx_bit_cnt + 1'b1;
                    
                    if (rx_bit_cnt == 4'd7) begin
                        rx_state <= RX_STOP;
                    end
                end else begin
                    rx_clk_div <= rx_clk_div + 1'b1;
                end
            end
            
            RX_STOP: begin
                if (rx_clk_div == BAUD_DIV - 1) begin
                    rx_clk_div <= 16'd0;
                    rx_state <= RX_IDLE;
                    if (uart_rx_sync_val) begin  // Valid stop bit
                        rx_data <= rx_shift_reg;
                        rx_valid <= 1'b1;
                    end
                end else begin
                    rx_clk_div <= rx_clk_div + 1'b1;
                end
            end
        endcase
    end
end

// ========================================
// UART Transmitter
// ========================================
reg [15:0] tx_clk_div;
reg [3:0] tx_bit_cnt;
reg [7:0] tx_shift_reg;
reg [1:0] tx_state;
reg tx_reg;

localparam TX_IDLE = 2'd0, TX_START = 2'd1, TX_DATA = 2'd2, TX_STOP = 2'd3;

assign uart_tx = tx_reg;

// UART TX state machine
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_state <= TX_IDLE;
        tx_clk_div <= 16'd0;
        tx_bit_cnt <= 4'd0;
        tx_shift_reg <= 8'd0;
        tx_reg <= 1'b1;
        tx_busy <= 1'b0;
    end else begin
        case (tx_state)
            TX_IDLE: begin
                tx_reg <= 1'b1;
                tx_clk_div <= 16'd0;
                tx_bit_cnt <= 4'd0;
                
                if (tx_start) begin
                    tx_shift_reg <= tx_data;
                    tx_busy <= 1'b1;
                    tx_state <= TX_START;
                end else begin
                    tx_busy <= 1'b0;
                end
            end
            
            TX_START: begin
                tx_reg <= 1'b0;  // Start bit
                if (tx_clk_div == BAUD_DIV - 1) begin
                    tx_clk_div <= 16'd0;
                    tx_state <= TX_DATA;
                end else begin
                    tx_clk_div <= tx_clk_div + 1'b1;
                end
            end
            
            TX_DATA: begin
                tx_reg <= tx_shift_reg[0];
                if (tx_clk_div == BAUD_DIV - 1) begin
                    tx_clk_div <= 16'd0;
                    tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
                    tx_bit_cnt <= tx_bit_cnt + 1'b1;
                    
                    if (tx_bit_cnt == 4'd7) begin
                        tx_state <= TX_STOP;
                    end
                end else begin
                    tx_clk_div <= tx_clk_div + 1'b1;
                end
            end
            
            TX_STOP: begin
                tx_reg <= 1'b1;  // Stop bit
                if (tx_clk_div == BAUD_DIV - 1) begin
                    tx_clk_div <= 16'd0;
                    tx_state <= TX_IDLE;
                    tx_busy <= 1'b0;
                end else begin
                    tx_clk_div <= tx_clk_div + 1'b1;
                end
            end
        endcase
    end
end

endmodule
