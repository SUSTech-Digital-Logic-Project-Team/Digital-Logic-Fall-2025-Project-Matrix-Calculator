// ========================================
// Matrix Display Mode (RESTRUCTURED)
// Purpose: Display matrix information and contents
// ========================================

`timescale 1ns / 1ps
`include "matrix_pkg.vh"

module display_mode #(
    parameter ELEMENT_WIDTH = `ELEMENT_WIDTH,
    parameter ADDR_WIDTH = `BRAM_ADDR_WIDTH,
    parameter MAX_STORAGE_MATRICES = `MAX_STORAGE_MATRICES
)(
    input wire clk,
    input wire rst_n,
    input wire mode_active,
    
    // UART receive interface
    input wire [7:0] rx_data,
    input wire rx_valid,
    output reg clear_rx_buffer,
    
    // UART transmit interface
    output reg [7:0] tx_data,
    output reg tx_start,
    input wire tx_busy,
    
    // Matrix manager interface
    input wire [7:0] total_matrix_count,
    output reg [3:0] query_slot,
    input wire query_valid,
    input wire [3:0] query_m,
    input wire [3:0] query_n,
    input wire [ADDR_WIDTH-1:0] query_addr,
    input wire [7:0] query_element_count,
    
    // Memory read interface
    output reg mem_rd_en,
    output reg [ADDR_WIDTH-1:0] mem_rd_addr,
    input wire [ELEMENT_WIDTH-1:0] mem_rd_data,
    
    // Error and state output
    output reg [3:0] error_code,
    output reg [3:0] sub_state
);

// State definitions
localparam IDLE = 4'd0, SHOW_COUNT = 4'd1, WAIT_SELECT = 4'd2,
           READ_DATA = 4'd3, SEND_DATA = 4'd4, DONE = 4'd5;

// Internal state
reg [3:0] display_m, display_n;
reg [7:0] display_count;
reg [3:0] display_row, display_col;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sub_state <= IDLE;
        mem_rd_en <= 1'b0;
        tx_start <= 1'b0;
        error_code <= `ERR_NONE;
    end else if (mode_active) begin
        tx_start <= 1'b0;
        mem_rd_en <= 1'b0;
        
        case (sub_state)
            IDLE: begin
                sub_state <= SHOW_COUNT;
            end
            
            SHOW_COUNT: begin
                if (!tx_busy) begin
                    tx_data <= "T";
                    tx_start <= 1'b1;
                    sub_state <= WAIT_SELECT;
                end
            end
            
            WAIT_SELECT: begin
                // Placeholder: wait for user to select matrix
                query_slot <= 4'd0;
                display_m <= query_m;
                display_n <= query_n;
                display_count <= 8'd0;
                display_row <= 4'd0;
                display_col <= 4'd0;
                sub_state <= READ_DATA;
            end
            
            READ_DATA: begin
                if (display_count < (display_m * display_n)) begin
                    mem_rd_en <= 1'b1;
                    mem_rd_addr <= query_addr + display_count;
                    display_count <= display_count + 1'b1;
                    sub_state <= SEND_DATA;
                end else begin
                    sub_state <= DONE;
                end
            end
            
            SEND_DATA: begin
                if (!tx_busy) begin
                    tx_data <= mem_rd_data + "0";
                    tx_start <= 1'b1;
                    sub_state <= READ_DATA;
                end
            end
            
            DONE: begin
                sub_state <= IDLE;
            end
            
            default: sub_state <= IDLE;
        endcase
    end else begin
        sub_state <= IDLE;
        mem_rd_en <= 1'b0;
    end
end

endmodule
