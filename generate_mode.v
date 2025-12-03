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
    input wire rx_done,
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
    
    // Error recovery signal
    input wire timeout_reset,

    // State and Error
    output reg [3:0] sub_state,
    output reg [3:0] error_code
);

// State definitions
localparam IDLE = 4'd0, WAIT_M = 4'd1, WAIT_N = 4'd2, 
           ALLOC = 4'd3, GEN_LATCH = 4'd4, SEND_VAL = 4'd5, 
           SEND_SPACE = 4'd6, SEND_NEWLINE = 4'd7, 
           COMMIT = 4'd8, DONE = 4'd9;

// Internal state
reg [3:0] gen_m, gen_n;
reg [7:0] gen_count;
reg [ADDR_WIDTH-1:0] gen_addr;
reg [3:0] gen_slot;
reg [3:0] latched_val;
reg [3:0] col_count;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sub_state <= IDLE;
        alloc_req <= 1'b0;
        commit_req <= 1'b0;
        mem_wr_en <= 1'b0;
        tx_start <= 1'b0;
        error_code <= `ERR_NONE;
        clear_rx_buffer <= 1'b0;
        col_count <= 4'd0;
    end else if (mode_active) begin
        tx_start <= 1'b0;
        alloc_req <= 1'b0;
        commit_req <= 1'b0;
        mem_wr_en <= 1'b0;
        clear_rx_buffer <= 1'b0;
        
        case (sub_state)
            IDLE: begin
                sub_state <= WAIT_M;
            end
            
            WAIT_M: begin
                if (timeout_reset) begin
                    sub_state <= IDLE;
                end else if (rx_done) begin
                    if (rx_data >= "0" && rx_data <= "9") begin
                        if (rx_data[3:0] > config_max_dim || rx_data[3:0] == 0) begin
                            error_code <= `ERR_DIM_RANGE;
                            if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                        end else begin
                            gen_m <= rx_data[3:0];
                            clear_rx_buffer <= 1'b1;
                            sub_state <= WAIT_N;
                            error_code <= `ERR_NONE;
                        end
                    end else begin
                        clear_rx_buffer <= 1'b1;
                        error_code <= `ERR_DIM_RANGE;
                        if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                    end
                end
            end
            
            WAIT_N: begin
                if (timeout_reset) begin
                    sub_state <= IDLE;
                end else if (rx_done) begin
                    if (rx_data >= "0" && rx_data <= "9") begin
                        if (rx_data[3:0] > config_max_dim || rx_data[3:0] == 0) begin
                            error_code <= `ERR_DIM_RANGE;
                            if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                        end else begin
                            gen_n <= rx_data[3:0];
                            clear_rx_buffer <= 1'b1;
                            alloc_req <= 1'b1;
                            sub_state <= ALLOC;
                            error_code <= `ERR_NONE;
                        end
                    end else begin
                        clear_rx_buffer <= 1'b1;
                        error_code <= `ERR_DIM_RANGE;
                        if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                    end
                end
            end
            
            ALLOC: begin
                alloc_req <= 1'b1;
                if (alloc_valid) begin
                    gen_addr <= alloc_addr;
                    gen_slot <= alloc_slot;
                    gen_count <= 8'd0;
                    col_count <= 4'd0;
                    sub_state <= GEN_LATCH;
                end
            end
            
            GEN_LATCH: begin
                latched_val <= random_value;
                mem_wr_en <= 1'b1;
                mem_wr_addr <= gen_addr + gen_count;
                mem_wr_data <= random_value;
                sub_state <= SEND_VAL;
            end

            SEND_VAL: begin
                if (!tx_busy) begin
                    tx_data <= (latched_val < 10) ? (latched_val + "0") : (latched_val - 10 + "A");
                    tx_start <= 1'b1;
                    sub_state <= SEND_SPACE;
                end
            end

            SEND_SPACE: begin
                if (!tx_busy) begin
                    tx_data <= " ";
                    tx_start <= 1'b1;
                    if (col_count == gen_n - 1) begin
                        sub_state <= SEND_NEWLINE;
                    end else begin
                        col_count <= col_count + 1'b1;
                        gen_count <= gen_count + 1'b1;
                        if (gen_count == (gen_m * gen_n) - 1)
                            sub_state <= COMMIT;
                        else
                            sub_state <= GEN_LATCH;
                    end
                end
            end

            SEND_NEWLINE: begin
                if (!tx_busy) begin
                    tx_data <= 8'h0A; // Newline
                    tx_start <= 1'b1;
                    col_count <= 4'd0;
                    gen_count <= gen_count + 1'b1;
                    if (gen_count == (gen_m * gen_n) - 1)
                        sub_state <= COMMIT;
                    else
                        sub_state <= GEN_LATCH;
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
