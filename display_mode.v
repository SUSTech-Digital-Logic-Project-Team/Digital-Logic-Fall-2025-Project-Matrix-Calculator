// ========================================
// Matrix Display Mode (Optimized for Multi-digit)
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
    
    // UART interface
    input wire [7:0] rx_data,
    input wire rx_valid,
    output reg clear_rx_buffer,
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
           READ_DATA = 4'd3, CONVERT_DATA = 4'd4, SEND_DIGITS = 4'd5, DONE = 4'd6;

// Internal variables
reg [3:0] display_m, display_n;
reg [7:0] display_count; // Current element index
reg [7:0] bin_value;     // Latch data from memory
reg [1:0] digit_index;   // 0:Hundreds, 1:Tens, 2:Units, 3:Space
reg [3:0] bcd_hund, bcd_tens, bcd_unit; // Digits

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sub_state <= IDLE;
        mem_rd_en <= 1'b0;
        tx_start <= 1'b0;
        error_code <= `ERR_NONE;
        digit_index <= 2'd0;
    end else if (mode_active) begin
        tx_start <= 1'b0;
        mem_rd_en <= 1'b0;
        
        case (sub_state)
            IDLE: begin
                sub_state <= SHOW_COUNT;
            end
            
            SHOW_COUNT: begin
                if (!tx_busy) begin
                    tx_data <= "T"; // Header indicating start
                    tx_start <= 1'b1;
                    sub_state <= WAIT_SELECT;
                end
            end
            
            WAIT_SELECT: begin
                // Auto-select slot 0 for demo (optimize this later for user selection)
                query_slot <= 4'd0; 
                if (query_valid) begin
                    display_m <= query_m;
                    display_n <= query_n;
                    display_count <= 8'd0;
                    sub_state <= READ_DATA;
                end else begin
                     // If slot 0 is empty, just finish
                    sub_state <= DONE;
                end
            end
            
            READ_DATA: begin
                if (display_count < (display_m * display_n)) begin
                    mem_rd_en <= 1'b1;
                    mem_rd_addr <= query_addr + display_count;
                    sub_state <= CONVERT_DATA;
                end else begin
                    sub_state <= DONE;
                end
            end
            
            CONVERT_DATA: begin
                // Wait one cycle for RAM data (assuming 1 cycle latency)
                // Also prepare BCD digits
                bin_value <= mem_rd_data;
                
                // Simple Binary to BCD (supports 0-255)
                // For synthesis, constant division is okay for small widths
                bcd_hund <= mem_rd_data / 100;
                bcd_tens <= (mem_rd_data % 100) / 10;
                bcd_unit <= mem_rd_data % 10;
                
                digit_index <= 2'd0; // Reset digit counter
                sub_state <= SEND_DIGITS;
            end
            
            SEND_DIGITS: begin
                if (!tx_busy) begin
                    case (digit_index)
                        2'd0: begin // Send Hundreds (if non-zero)
                            if (bcd_hund > 0) begin
                                tx_data <= {4'd3, bcd_hund}; // ASCII '0'-'9'
                                tx_start <= 1'b1;
                            end
                            digit_index <= 2'd1;
                        end
                        2'd1: begin // Send Tens (if needed)
                            if (bcd_tens > 0 || bcd_hund > 0) begin
                                tx_data <= {4'd3, bcd_tens};
                                tx_start <= 1'b1;
                            end
                            digit_index <= 2'd2;
                        end
                        2'd2: begin // Send Units (Always send)
                            tx_data <= {4'd3, bcd_unit};
                            tx_start <= 1'b1;
                            digit_index <= 2'd3;
                        end
                        2'd3: begin // Send Space
                            tx_data <= 8'h20; // Space
                            tx_start <= 1'b1;
                            // Done with this number, read next
                            display_count <= display_count + 1'b1;
                            sub_state <= READ_DATA;
                        end
                    endcase
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