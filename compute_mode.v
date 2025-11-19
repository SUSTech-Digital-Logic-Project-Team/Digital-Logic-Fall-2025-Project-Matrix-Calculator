// ========================================
// Matrix Compute Mode (RESTRUCTURED)
// Purpose: Handle matrix computation operations
// ========================================

`timescale 1ns / 1ps
`include "matrix_pkg.vh"

module compute_mode #(
    parameter ELEMENT_WIDTH = `ELEMENT_WIDTH,
    parameter ADDR_WIDTH = `BRAM_ADDR_WIDTH
)(
    input wire clk,
    input wire rst_n,
    input wire mode_active,
    input wire [3:0] config_max_dim,
    input wire [3:0] op_type,
    
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
localparam IDLE = 4'd0, SELECT_MATRIX = 4'd1, READ_OP = 4'd2,
           EXECUTE = 4'd3, SEND_RESULT = 4'd4, DONE = 4'd5;

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
                sub_state <= SELECT_MATRIX;
            end
            
            SELECT_MATRIX: begin
                query_slot <= 4'd0;
                sub_state <= READ_OP;
            end
            
            READ_OP: begin
                // Operation type is passed as parameter
                sub_state <= EXECUTE;
            end
            
            EXECUTE: begin
                // Placeholder for execution logic
                sub_state <= SEND_RESULT;
            end
            
            SEND_RESULT: begin
                if (!tx_busy) begin
                    tx_data <= "R";
                    tx_start <= 1'b1;
                    sub_state <= DONE;
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
