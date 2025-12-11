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
    input wire [4:0] config_max_dim,   // Extended to 5 bits
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
    output reg [4:0] commit_m,          // Extended to 5 bits
    output reg [4:0] commit_n,          // Extended to 5 bits
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
localparam IDLE = 4'd0, WAIT_COUNT = 4'd1, WAIT_COUNT_CONT = 4'd2,
           WAIT_M = 4'd3, WAIT_N = 4'd4, 
           ALLOC = 4'd5, GEN_LATCH = 4'd6, SEND_VAL = 4'd7, 
           SEND_SPACE = 4'd8, SEND_NEWLINE = 4'd9, 
           COMMIT = 4'd10, DONE = 4'd11,
           WAIT_M_CONT = 4'd12, WAIT_N_CONT = 4'd13,
           BATCH_NEXT = 4'd14, BATCH_SEP = 4'd15;  // States for multi-digit input and batch looping

// Internal state
reg [4:0] gen_m, gen_n;       // Extended to 5 bits for dim up to 16
reg [7:0] gen_count;
reg [ADDR_WIDTH-1:0] gen_addr;
reg [3:0] gen_slot;
reg [3:0] latched_val;
reg [4:0] col_count;          // Extended to 5 bits for dim up to 16
reg [7:0] input_accum;        // Accumulator for multi-digit input / batch count
reg [7:0] batch_total;
reg [7:0] batch_idx;

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
        input_accum <= 8'd0;
        batch_total <= 8'd0;
        batch_idx <= 8'd0;
    end else if (mode_active) begin
        tx_start <= 1'b0;
        alloc_req <= 1'b0;
        commit_req <= 1'b0;
        mem_wr_en <= 1'b0;
        clear_rx_buffer <= 1'b0;
        
        case (sub_state)
            IDLE: begin
                sub_state <= WAIT_COUNT;
                input_accum <= 8'd0;
                batch_total <= 8'd0;
                batch_idx <= 8'd0;
            end
            
            WAIT_COUNT: begin
                if (timeout_reset) begin
                    sub_state <= IDLE;
                end else if (rx_done) begin
                    if (rx_data >= "0" && rx_data <= "9") begin
                        input_accum <= (rx_data - "0");
                        clear_rx_buffer <= 1'b1;
                        sub_state <= WAIT_COUNT_CONT;
                        error_code <= `ERR_NONE;
                    end else begin
                        clear_rx_buffer <= 1'b1;
                        error_code <= `ERR_DIM_RANGE;
                        if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                    end
                end
            end

            WAIT_COUNT_CONT: begin
                if (timeout_reset) begin
                    sub_state <= IDLE;
                end else if (rx_done) begin
                    if (rx_data >= "0" && rx_data <= "9") begin
                        input_accum <= (input_accum * 10) + (rx_data - "0");
                        clear_rx_buffer <= 1'b1;
                    end else if (rx_data == " " || rx_data == 8'h0D || rx_data == 8'h0A) begin
                        if (input_accum == 0) begin
                            error_code <= `ERR_DIM_RANGE;
                            if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                            input_accum <= 8'd0;
                            sub_state <= WAIT_COUNT;
                        end else begin
                            batch_total <= input_accum;
                            input_accum <= 8'd0;
                            clear_rx_buffer <= 1'b1;
                            sub_state <= WAIT_M;
                            error_code <= `ERR_NONE;
                        end
                    end else begin
                        clear_rx_buffer <= 1'b1;
                        error_code <= `ERR_DIM_RANGE;
                        if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                        input_accum <= 8'd0;
                        sub_state <= WAIT_COUNT;
                    end
                end
            end

            WAIT_M: begin
                if (timeout_reset) begin
                    sub_state <= IDLE;
                end else if (rx_done) begin
                    if (rx_data >= "0" && rx_data <= "9") begin
                        // First digit received, store it and wait for more or terminator
                        input_accum <= (rx_data - "0");
                        clear_rx_buffer <= 1'b1;
                        sub_state <= WAIT_M_CONT;
                        error_code <= `ERR_NONE;
                    end else begin
                        clear_rx_buffer <= 1'b1;
                        error_code <= `ERR_DIM_RANGE;
                        if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                    end
                end
            end
            
            WAIT_M_CONT: begin
                // Continue reading M: expect more digits or terminator (space/enter)
                if (timeout_reset) begin
                    sub_state <= IDLE;
                end else if (rx_done) begin
                    if (rx_data >= "0" && rx_data <= "9") begin
                        // Another digit: accumulate (input_accum * 10 + new_digit)
                        input_accum <= (input_accum * 10) + (rx_data - "0");
                        clear_rx_buffer <= 1'b1;
                        // Stay in WAIT_M_CONT for potential more digits
                    end else if (rx_data == " " || rx_data == 8'h0D || rx_data == 8'h0A) begin
                        // Terminator received: validate and move to WAIT_N
                        if (input_accum > config_max_dim || input_accum == 0) begin
                            error_code <= `ERR_DIM_RANGE;
                            if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                            input_accum <= 8'd0;
                            sub_state <= WAIT_M;
                        end else begin
                            gen_m <= input_accum[4:0];
                            input_accum <= 8'd0;
                            clear_rx_buffer <= 1'b1;
                            sub_state <= WAIT_N;
                            error_code <= `ERR_NONE;
                        end
                    end else begin
                        // Invalid character
                        clear_rx_buffer <= 1'b1;
                        error_code <= `ERR_DIM_RANGE;
                        if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                        input_accum <= 8'd0;
                        sub_state <= WAIT_M;
                    end
                end
            end
            
            WAIT_N: begin
                if (timeout_reset) begin
                    sub_state <= IDLE;
                end else if (rx_done) begin
                    if (rx_data >= "0" && rx_data <= "9") begin
                        // First digit received, store it and wait for more or terminator
                        input_accum <= (rx_data - "0");
                        clear_rx_buffer <= 1'b1;
                        sub_state <= WAIT_N_CONT;
                        error_code <= `ERR_NONE;
                    end else if (rx_data == " " || rx_data == 8'h0D || rx_data == 8'h0A) begin
                        // Skip leading whitespace
                        clear_rx_buffer <= 1'b1;
                    end else begin
                        clear_rx_buffer <= 1'b1;
                        error_code <= `ERR_DIM_RANGE;
                        if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                    end
                end
            end
            
            WAIT_N_CONT: begin
                // Continue reading N: expect more digits or terminator (space/enter)
                if (timeout_reset) begin
                    sub_state <= IDLE;
                end else if (rx_done) begin
                    if (rx_data >= "0" && rx_data <= "9") begin
                        // Another digit: accumulate
                        input_accum <= (input_accum * 10) + (rx_data - "0");
                        clear_rx_buffer <= 1'b1;
                        // Stay in WAIT_N_CONT
                    end else if (rx_data == " " || rx_data == 8'h0D || rx_data == 8'h0A) begin
                        // Terminator received: validate and move to ALLOC
                        if (input_accum > config_max_dim || input_accum == 0) begin
                            error_code <= `ERR_DIM_RANGE;
                            if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                            input_accum <= 8'd0;
                            sub_state <= WAIT_N;
                        end else begin
                            gen_n <= input_accum[4:0];
                            input_accum <= 8'd0;
                            clear_rx_buffer <= 1'b1;
                            alloc_req <= 1'b1;
                            sub_state <= ALLOC;
                            error_code <= `ERR_NONE;
                        end
                    end else begin
                        // Invalid character
                        clear_rx_buffer <= 1'b1;
                        error_code <= `ERR_DIM_RANGE;
                        if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                        input_accum <= 8'd0;
                        sub_state <= WAIT_N;
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
                    tx_data <= 8'h20; // Space
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
                sub_state <= BATCH_NEXT;
            end

            BATCH_NEXT: begin
                if (batch_idx + 1 >= batch_total) begin
                    sub_state <= DONE;
                end else begin
                    batch_idx <= batch_idx + 1'b1;
                    sub_state <= BATCH_SEP;
                end
            end

            BATCH_SEP: begin
                if (!tx_busy) begin
                    tx_data <= 8'h0A; // Blank line between matrices
                    tx_start <= 1'b1;
                    sub_state <= ALLOC;
                end
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
