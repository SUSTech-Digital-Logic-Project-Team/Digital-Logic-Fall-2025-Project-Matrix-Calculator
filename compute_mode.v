// ========================================
// Matrix Compute Mode (Interaction Optimized)
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
    
    // New Inputs for Interaction
    input wire [2:0] dip_sw,
    input wire btn_confirm,
    output reg [3:0] selected_op_type, // Output to display
    
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
    
    // Memory interface
    output reg mem_rd_en,
    output reg [ADDR_WIDTH-1:0] mem_rd_addr,
    input wire [ELEMENT_WIDTH-1:0] mem_rd_data,
    
    output reg [3:0] error_code,
    output reg [3:0] sub_state
);

// State definitions
localparam IDLE = 4'd0, 
           SELECT_OP = 4'd1,      // New: Select Add/Mul/etc.
           SELECT_MATRIX = 4'd2, 
           READ_OP = 4'd3,
           EXECUTE = 4'd4, 
           SEND_RESULT = 4'd5, 
           DONE = 4'd6;

// Internal button debounce/edge detection (simple version)
reg btn_prev;
wire btn_posedge = btn_confirm && !btn_prev;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sub_state <= IDLE;
        mem_rd_en <= 1'b0;
        tx_start <= 1'b0;
        error_code <= `ERR_NONE;
        selected_op_type <= 4'd0;
        btn_prev <= 1'b0;
    end else if (mode_active) begin
        btn_prev <= btn_confirm;
        tx_start <= 1'b0;
        mem_rd_en <= 1'b0;
        
        case (sub_state)
            IDLE: begin
                // Reset op type display on entry
                selected_op_type <= 4'd0; 
                sub_state <= SELECT_OP;
            end
            
            SELECT_OP: begin
                // Continuously update OP type based on switches
                // User toggles switches, sees LED/Seg change, then presses Confirm
                selected_op_type <= {1'b0, dip_sw}; 
                
                if (btn_posedge) begin
                    sub_state <= SELECT_MATRIX;
                end
            end
            
            SELECT_MATRIX: begin
                // Placeholder: Logic to select input matrices would go here
                query_slot <= 4'd0; // Default to slot 0 for now
                sub_state <= EXECUTE;
            end
            
            EXECUTE: begin
                // CALCULATION LOGIC PENDING
                // For now, pass through
                sub_state <= SEND_RESULT;
            end
            
            SEND_RESULT: begin
                if (!tx_busy) begin
                    tx_data <= "R"; // R for Result
                    tx_start <= 1'b1;
                    sub_state <= DONE;
                end
            end
            
            DONE: begin
                // Wait here or go back to IDLE
                 if (btn_posedge) sub_state <= IDLE;
            end
            
            default: sub_state <= IDLE;
        endcase
    end else begin
        sub_state <= IDLE;
        btn_prev <= 1'b0;
    end
end

endmodule