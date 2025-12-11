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
    input wire [7:0] config_matrices_per_size,
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
    
    // Memory read interface
    output reg mem_rd_en,
    output reg [ADDR_WIDTH-1:0] mem_rd_addr,
    input wire [ELEMENT_WIDTH-1:0] mem_rd_data,
    
    // Error recovery signal
    input wire timeout_reset,

    // State and Error
    output reg [3:0] sub_state,
    output reg [3:0] error_code
);

// State definitions
localparam IDLE = 4'd0,
           PARSE_M = 4'd1,
           PARSE_N = 4'd2,
           CHECK_DIM = 4'd3,
           WAIT_ALLOC = 4'd4,
           GEN_LATCH = 4'd5,
           PARSE_GEN_COUNT = 4'd6,
           COMMIT = 4'd7,
           DISPLAY_MATRIX = 4'd8,
           DONE = 4'd9;

// Internal state
reg [4:0] gen_m, gen_n;       // Extended to 5 bits for dim up to 16
reg [7:0] gen_count;          // Number of matrices to generate
reg [ADDR_WIDTH-1:0] gen_addr;
reg [8:0] total_elements;
reg [3:0] gen_slot;

// Parsing state
reg [7:0] parse_accum;        // Accumulator for multi-digit number
reg digit_received;           // Flag for digit reception
reg [7:0] elements_written;   // Counter for elements written

// Allocation state
reg alloc_m, alloc_n;         // Allocation dimensions

// Display state variables
reg [3:0] display_row;
reg [3:0] display_col;
reg [3:0] display_step;
reg [ELEMENT_WIDTH-1:0] display_value;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sub_state <= IDLE;
        parse_accum <= 8'd0;
        gen_m <= 5'd0;
        gen_n <= 5'd0;
        total_elements <= 9'd0;
        gen_slot <= 4'd0;
        gen_addr <= {ADDR_WIDTH{1'b0}};
        display_row <= 4'd0;
        display_col <= 4'd0;
        display_step <= 4'd0;
        display_value <= {ELEMENT_WIDTH{1'b0}};
        mem_wr_en <= 1'b0;
        mem_wr_addr <= {ADDR_WIDTH{1'b0}};
        mem_wr_data <= {ELEMENT_WIDTH{1'b0}};
        mem_rd_addr <= {ADDR_WIDTH{1'b0}};
        alloc_req <= 1'b0;
        alloc_m <= 4'd0;
        alloc_n <= 4'd0;
        commit_req <= 1'b0;
        commit_slot <= 4'd0;
        commit_m <= 4'd0;
        commit_n <= 4'd0;
        commit_addr <= {ADDR_WIDTH{1'b0}};
        tx_start <= 1'b0;
        tx_data <= 8'd0;
        error_code <= `ERR_NONE;
        clear_rx_buffer <= 1'b0;
    end else if (mode_active) begin
        // Default one-shot signals
        tx_start <= 1'b0;
        clear_rx_buffer <= 1'b0;
        mem_wr_en <= 1'b0;
        
        case (sub_state)
            IDLE: begin
                parse_accum <= 8'd0;
                digit_received <= 1'b0;
                gen_m <= 5'd0;
                gen_n <= 5'd0;
                total_elements <= 9'd0;
                elements_written <= 8'd0;
                error_code <= `ERR_NONE;
                alloc_req <= 1'b0;
                commit_req <= 1'b0;
                sub_state <= PARSE_GEN_COUNT;
                
            end

            PARSE_GEN_COUNT: begin 
                if (timeout_reset) begin
                    sub_state <= IDLE;
                end else if (rx_done) begin
                    if (rx_data == 8'h20 && parse_accum <= config_matrices_per_size) begin // 空格键作为分隔符
                        gen_count <= parse_accum[4:0];
                        parse_accum <= 8'd0;
                        sub_state <= PARSE_M;
                        error_code <= `ERR_NONE;
                    end else if (rx_data >= "0" && rx_data <= "9") begin
                        // Streaming accumulate: M = M*10 + digit
                        parse_accum <= parse_accum * 8'd10 + (rx_data - "0");
                        error_code <= `ERR_NONE;
                    end else begin
                        error_code <= `ERR_DIM_RANGE;
                        if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end // Echo '!'
                    end
                end
            end

            
            PARSE_M: begin
                if (timeout_reset) begin
                    sub_state <= IDLE;
                end else if (rx_done) begin
                    if (rx_data == 8'h20) begin // 空格键作为分隔符
                        gen_m <= parse_accum[4:0];
                        parse_accum <= 8'd0;
                        sub_state <= PARSE_N;
                        error_code <= `ERR_NONE;
                    end else if (rx_data >= "0" && rx_data <= "9") begin
                        // Streaming accumulate: M = M*10 + digit
                        parse_accum <= parse_accum * 8'd10 + (rx_data - "0");
                        error_code <= `ERR_NONE;
                    end else begin
                        error_code <= `ERR_DIM_RANGE;
                        if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end // Echo '!'
                    end
                end
            end
            
            PARSE_N: begin
                if (timeout_reset) begin
                    sub_state <= IDLE;
                end else if (rx_done) begin
                    if (rx_data == 8'h20) begin // 空格键作为分隔符
                        gen_n <= parse_accum[4:0];
                        parse_accum <= 8'd0;
                        sub_state <= CHECK_DIM;
                        error_code <= `ERR_NONE;
                    end else if (rx_data >= "0" && rx_data <= "9") begin
                        parse_accum <= parse_accum * 8'd10 + (rx_data - "0");
                        error_code <= `ERR_NONE;
                    end else begin
                        error_code <= `ERR_DIM_RANGE;
                        if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end // Echo '!'
                    end
                end
            end
            
            CHECK_DIM: begin
                if (gen_m == 5'd0 || gen_m > config_max_dim ||
                    gen_n == 5'd0 || gen_n > config_max_dim) begin
                    error_code <= `ERR_DIM_RANGE;
                    // Reset to PARSE_M to allow user to re-enter dimensions
                    sub_state <= PARSE_M;
                    parse_accum <= 8'd0;
                    gen_m <= 5'd0;
                    gen_n <= 5'd0;
                    if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end // Echo '!'
                end else begin
                    // Pre-compute total elements to avoid repeated multiply
                    total_elements <= {4'd0, gen_m} * {4'd0, gen_n};
                    alloc_req <= 1'b1;
                    alloc_m <= gen_m;
                    alloc_n <= gen_n;
                    sub_state <= WAIT_ALLOC;
                end
            end
            
            WAIT_ALLOC: begin
                alloc_req <= 1'b1;
                
                if (alloc_valid) begin
                    gen_addr <= alloc_addr;
                    gen_slot <= alloc_slot;
                    elements_written <= 8'd0;
                    alloc_req <= 1'b0;
                    sub_state <= GEN_LATCH;
                    parse_accum <= 8'd0;
                    digit_received <= 1'b0;
                end
                // Note: If allocation fails, alloc_valid will remain low
                // You may want to add a timeout counter here if needed
            end
            
            GEN_LATCH: begin
                // Latch random value
                if (elements_written < total_elements) begin
                    // Write to memory
                    mem_wr_en <= 1'b1;
                    mem_wr_addr <= gen_addr + {5'd0, elements_written};
                    mem_wr_data <= random_value; // Zero-extend to ELEMENT_WIDTH
                    elements_written <= elements_written + 1'b1;
                end else begin
                    // All elements written
                    sub_state <= COMMIT;
                end
            end
            
            
            COMMIT: begin
                commit_req <= 1'b1;
                commit_slot <= gen_slot;
                commit_m <= gen_m;
                commit_n <= gen_n;
                commit_addr <= gen_addr;
                display_row <= 4'd0;
                display_col <= 4'd0;
                display_step <= 4'd0;
                sub_state <= DISPLAY_MATRIX;
            end
            
            DISPLAY_MATRIX: begin
                commit_req <= 1'b0;
                mem_rd_en <= 1'b1;
                case (display_step)
                    4'd0: begin // Send newline at start of row
                        if (!tx_busy && !tx_start) begin
                            tx_data <= 8'h0D; // Carriage return
                            tx_start <= 1'b1;
                            display_step <= 4'd1;
                        end
                    end
                    
                    4'd1: begin // Send line feed
                        if (!tx_busy && !tx_start) begin
                            tx_data <= 8'h0A; // Line feed
                            tx_start <= 1'b1;
                            display_step <= 4'd2;
                        end
                    end
                    
                    4'd2: begin // Request memory read for current element
                        mem_rd_addr <= gen_addr + ({4'd0, display_row} * {4'd0, gen_n}) + {8'd0, display_col};
                        display_step <= 4'd3;
                    end
                    
                    4'd3: begin // Wait one cycle for BRAM read latency
                        display_step <= 4'd4;
                    end
                    
                    4'd4: begin // Latch data from BRAM
                        display_value <= mem_rd_data;
                        display_step <= 4'd5;
                    end
                    
                    4'd5: begin // Send the digit
                        if (!tx_busy && !tx_start) begin
                            tx_data <= display_value[3:0] + "0"; // Convert to ASCII
                            tx_start <= 1'b1;
                            display_step <= 4'd6;
                        end
                    end
                    
                    4'd6: begin // Send space or move to next row
                        if (!tx_busy && !tx_start) begin
                            if (display_col == gen_n - 1) begin
                                // End of row
                                display_col <= 4'd0;
                                if (display_row == gen_m - 1) begin
                                    // All done
                                    display_step <= 4'd7;
                                end else begin
                                    // Next row
                                    display_row <= display_row + 1'b1;
                                    display_step <= 4'd0;
                                end
                            end else begin
                                // Send space and continue in same row
                                tx_data <= 8'h20; // Space
                                tx_start <= 1'b1;
                                display_col <= display_col + 1'b1;
                                display_step <= 4'd2;
                            end
                        end
                    end
                    
                    4'd7: begin // Final newline
                        if (!tx_busy && !tx_start) begin
                            tx_data <= 8'h0D;
                            tx_start <= 1'b1;
                            display_step <= 4'd8;
                        end
                    end

                    4'd8: begin // Final newline
                        if (!tx_busy && !tx_start) begin
                            tx_data <= 8'h0D;
                            tx_start <= 1'b1;
                            display_step <= 4'd9;
                        end
                    end
                    
                    4'd9: begin // Final line feed, then done
                        if (!tx_busy && !tx_start) begin
                            if (gen_count > 1) begin 
                                // More matrices to generate
                                gen_count <= gen_count - 1'b1;
                                sub_state <= WAIT_ALLOC;
                            end else begin
                                tx_data <= 8'h0A;
                                tx_start <= 1'b1;
                                mem_rd_en <= 1'b0;
                                sub_state <= DONE;
                            end
                        end
                    end
                    
                    default: display_step <= 4'd0;
                endcase
            end
            
            DONE: begin
                commit_req <= 1'b0;
                sub_state <= IDLE;
            end
            
            default: sub_state <= IDLE;
        endcase
    end else begin
        // Mode inactive: reset to idle
        sub_state <= IDLE;
        parse_accum <= 8'd0;
        total_elements <= 8'd0;
        mem_wr_en <= 1'b0;
        alloc_req <= 1'b0;
        commit_req <= 1'b0;
        error_code <= `ERR_NONE;
    end
end

endmodule
