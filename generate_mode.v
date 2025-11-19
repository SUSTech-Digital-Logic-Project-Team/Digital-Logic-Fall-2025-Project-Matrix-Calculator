// ========================================
// Matrix Generation Mode (RESTRUCTURED)
// Purpose: Generate random matrices per user specification
// ========================================

`timescale 1ns / 1ps
`include "matrix_pkg.vh"

module generate_mode #(
    parameter ELEMENT_WIDTH = `ELEMENT_WIDTH,
    parameter ADDR_WIDTH = `BRAM_ADDR_WIDTH
)(
    input wire clk,
    input wire rst_n,
    input wire mode_active,
    
    // Configuration parameters
    input wire [3:0] config_max_dim,
    input wire [3:0] config_max_value,
    input wire [3:0] random_value,
    
    // UART receive interface
    input wire [7:0] rx_data,
    input wire rx_valid,
    output reg clear_rx_buffer,
    
    // UART transmit interface
    output reg [7:0] tx_data,
    output reg tx_start,
    input wire tx_busy,
    
    // Matrix manager interface
    output reg alloc_req,
    input wire [3:0] alloc_slot,
    input wire [ADDR_WIDTH-1:0] alloc_addr,
    input wire alloc_valid,
    output reg commit_req,
    output reg [3:0] commit_slot,
    output reg [3:0] commit_m,
    output reg [3:0] commit_n,
    output reg [ADDR_WIDTH-1:0] commit_addr,
    
    // Memory write interface
    output reg mem_wr_en,
    output reg [ADDR_WIDTH-1:0] mem_wr_addr,
    output reg [ELEMENT_WIDTH-1:0] mem_wr_data,
    
    // Error and state output
    output reg [3:0] error_code,
    output reg [3:0] sub_state
);

// State definitions
localparam IDLE = 4'd0, WAIT_M = 4'd1, WAIT_N = 4'd2, 
           ALLOC = 4'd3, GEN_DATA = 4'd4, COMMIT = 4'd5, DONE = 4'd6;

// Internal state
reg [3:0] gen_m, gen_n;
reg [7:0] gen_count;
reg [ADDR_WIDTH-1:0] gen_addr;
reg [3:0] gen_slot;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sub_state <= IDLE;
        alloc_req <= 1'b0;
        commit_req <= 1'b0;
        mem_wr_en <= 1'b0;
        tx_start <= 1'b0;
        error_code <= `ERR_NONE;
    end else if (mode_active) begin
        tx_start <= 1'b0;
        alloc_req <= 1'b0;
        commit_req <= 1'b0;
        mem_wr_en <= 1'b0;
        
        case (sub_state)
            IDLE: begin
                sub_state <= WAIT_M;
            end
            
            WAIT_M: begin
                // Placeholder for receiving M dimension
                gen_m <= 4'd3;
                sub_state <= WAIT_N;
            end
            
            WAIT_N: begin
                // Placeholder for receiving N dimension
                gen_n <= 4'd3;
                alloc_req <= 1'b1;
                sub_state <= ALLOC;
            end
            
            ALLOC: begin
                alloc_req <= 1'b1;
                if (alloc_valid) begin
                    gen_addr <= alloc_addr;
                    gen_slot <= alloc_slot;
                    gen_count <= 8'd0;
                    sub_state <= GEN_DATA;
                end
            end
            
            GEN_DATA: begin
                if (gen_count < (gen_m * gen_n)) begin
                    mem_wr_en <= 1'b1;
                    mem_wr_addr <= gen_addr + gen_count;
                    mem_wr_data <= random_value;
                    gen_count <= gen_count + 1'b1;
                end else begin
                    sub_state <= COMMIT;
                end
            end
            
            COMMIT: begin
                commit_req <= 1'b1;
                commit_slot <= gen_slot;
                commit_m <= gen_m;
                commit_n <= gen_n;
                commit_addr <= gen_addr;
                sub_state <= DONE;
            end
            
            DONE: begin
                sub_state <= IDLE;
            end
            
            default: sub_state <= IDLE;
        endcase
    end else begin
        sub_state <= IDLE;
        alloc_req <= 1'b0;
        commit_req <= 1'b0;
        mem_wr_en <= 1'b0;
    end
end

endmodule
