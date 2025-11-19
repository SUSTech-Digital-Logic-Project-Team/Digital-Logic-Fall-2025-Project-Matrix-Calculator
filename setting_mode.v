// ========================================
// Matrix Setting Mode (RESTRUCTURED)
// Purpose: Configure system parameters
// ========================================

`timescale 1ns / 1ps
`include "matrix_pkg.vh"

module setting_mode #(
    parameter ELEMENT_WIDTH = `ELEMENT_WIDTH
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
    
    // Configuration output
    output reg [3:0] config_max_dim,
    output reg [3:0] config_max_value,
    output reg [3:0] config_matrices_per_size,
    
    // Error and state output
    output reg [3:0] error_code,
    output reg [3:0] sub_state
);

// State definitions
localparam IDLE = 4'd0, WAIT_MAX_DIM = 4'd1, WAIT_MAX_VAL = 4'd2,
           WAIT_MAT_PER_SIZE = 4'd3, CONFIRM = 4'd4, DONE = 4'd5;

// Internal configuration
reg [3:0] cfg_max_dim;
reg [3:0] cfg_max_value;
reg [3:0] cfg_matrices_per_size;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sub_state <= IDLE;
        config_max_dim <= `DEFAULT_MAX_DIM;
        config_max_value <= `DEFAULT_MAX_VALUE;
        config_matrices_per_size <= `DEFAULT_MATRICES_PER_SIZE;
        tx_start <= 1'b0;
        error_code <= `ERR_NONE;
    end else if (mode_active) begin
        tx_start <= 1'b0;
        
        case (sub_state)
            IDLE: begin
                cfg_max_dim <= config_max_dim;
                cfg_max_value <= config_max_value;
                cfg_matrices_per_size <= config_matrices_per_size;
                sub_state <= WAIT_MAX_DIM;
            end
            
            WAIT_MAX_DIM: begin
                // Placeholder: wait for max_dim input
                cfg_max_dim <= `DEFAULT_MAX_DIM;
                sub_state <= WAIT_MAX_VAL;
            end
            
            WAIT_MAX_VAL: begin
                // Placeholder: wait for max_value input
                cfg_max_value <= `DEFAULT_MAX_VALUE;
                sub_state <= WAIT_MAT_PER_SIZE;
            end
            
            WAIT_MAT_PER_SIZE: begin
                // Placeholder: wait for matrices_per_size input
                cfg_matrices_per_size <= `DEFAULT_MATRICES_PER_SIZE;
                sub_state <= CONFIRM;
            end
            
            CONFIRM: begin
                if (!tx_busy) begin
                    tx_data <= "S";
                    tx_start <= 1'b1;
                    config_max_dim <= cfg_max_dim;
                    config_max_value <= cfg_max_value;
                    config_matrices_per_size <= cfg_matrices_per_size;
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
    end
end

endmodule
