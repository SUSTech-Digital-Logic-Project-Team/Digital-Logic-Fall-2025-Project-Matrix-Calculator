// ========================================
// Matrix Input Mode Module (RESTRUCTURED - STREAMING PARSER)
// Purpose: Handle user input matrix logic with BRAM support
// LUT-optimized: streaming parse, no buffer arrays, direct BRAM write
// ========================================

`timescale 1ns / 1ps
`include "matrix_pkg.vh"

module input_mode #(
    parameter ELEMENT_WIDTH = `ELEMENT_WIDTH,
    parameter ADDR_WIDTH = `BRAM_ADDR_WIDTH
)(
    input wire clk,
    input wire rst_n,
    input wire mode_active,
    
    // Configuration parameters
    input wire [3:0] config_max_dim,
    input wire [3:0] config_max_value,
    
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
    output reg [3:0] alloc_m,
    output reg [3:0] alloc_n,
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
    
    // Memory read interface (for display)
    output reg mem_rd_en,
    output reg [ADDR_WIDTH-1:0] mem_rd_addr,
    input wire [ELEMENT_WIDTH-1:0] mem_rd_data,
    
    // Error and state output
    output reg [3:0] error_code,
    output reg [3:0] sub_state,
    
    // Error recovery signal
    input wire timeout_reset
);

// State definitions
localparam IDLE = 4'd0,
           PARSE_M = 4'd1,
           PARSE_N = 4'd2,
           CHECK_DIM = 4'd3,
           WAIT_ALLOC = 4'd4,
           PARSE_DATA = 4'd5,
           FILL_ZEROS = 4'd6,
           COMMIT = 4'd7,
           DISPLAY_MATRIX = 4'd8,
           DONE = 4'd9;

// Streaming parse registers
reg [7:0] parse_accum;        // Accumulator for multi-digit number (e.g., "12" -> 12)
reg [3:0] input_m, input_n;
reg [7:0] total_elements;     // Pre-computed M*N to avoid repeated multiply
reg [7:0] elements_written;   // Count of elements written to BRAM
reg [3:0] input_matrix_slot;
reg [ADDR_WIDTH-1:0] input_alloc_addr;
reg digit_received; // Flag to track if we are currently parsing a number

// Display formatting registers
reg [3:0] display_row;        // Current row being displayed
reg [3:0] display_col;        // Current column being displayed
reg [3:0] display_step;       // Sub-state for formatting (0=newline, 1=space, 2=digit)
reg [ELEMENT_WIDTH-1:0] display_value;  // Current element value to display

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sub_state <= IDLE;
        parse_accum <= 8'd0;
        digit_received <= 1'b0;
        input_m <= 4'd0;
        input_n <= 4'd0;
        total_elements <= 8'd0;
        elements_written <= 8'd0;
        input_matrix_slot <= 4'd0;
        input_alloc_addr <= {ADDR_WIDTH{1'b0}};
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
                input_m <= 4'd0;
                input_n <= 4'd0;
                total_elements <= 8'd0;
                elements_written <= 8'd0;
                error_code <= `ERR_NONE;
                alloc_req <= 1'b0;
                commit_req <= 1'b0;
                sub_state <= PARSE_M;
                
            end
            
            PARSE_M: begin
                if (timeout_reset) begin
                    sub_state <= IDLE;
                end else if (rx_done) begin
                    if (rx_data == 8'h20) begin // 空格键作为分隔符
                        input_m <= parse_accum[3:0];
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
                        input_n <= parse_accum[3:0];
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
                // Debug echo first
                // if (!tx_busy && !tx_start) begin
                //    tx_data <= "L"; // 回显：进入CHECK_DIM状态
                //    tx_start <= 1'b1;
                // end
                
                // Then check dimensions
                if (input_m == 4'd0 || input_m > config_max_dim ||
                    input_n == 4'd0 || input_n > config_max_dim) begin
                    error_code <= `ERR_DIM_RANGE;
                    // Reset to PARSE_M to allow user to re-enter dimensions
                    sub_state <= PARSE_M;
                    parse_accum <= 8'd0;
                    input_m <= 4'd0;
                    input_n <= 4'd0;
                    if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end // Echo '!'
                end else begin
                    // Pre-compute total elements to avoid repeated multiply
                    total_elements <= {4'd0, input_m} * {4'd0, input_n};
                    alloc_req <= 1'b1;
                    alloc_m <= input_m;
                    alloc_n <= input_n;
                    sub_state <= WAIT_ALLOC;
                end
            end
            
            WAIT_ALLOC: begin
                alloc_req <= 1'b1;
                
                // Debug echo
                // if (!tx_busy && !tx_start) begin
                //    tx_data <= "W"; // 回显：进入WAIT_ALLOC状态
                //    tx_start <= 1'b1;
                // end
                
                if (alloc_valid) begin
                    input_alloc_addr <= alloc_addr;
                    input_matrix_slot <= alloc_slot;
                    elements_written <= 8'd0;
                    alloc_req <= 1'b0;
                    sub_state <= PARSE_DATA;
                    parse_accum <= 8'd0;
                    digit_received <= 1'b0;
                end
                // Note: If allocation fails, alloc_valid will remain low
                // You may want to add a timeout counter here if needed
            end
            
            PARSE_DATA: begin
                if (timeout_reset) begin
                    sub_state <= IDLE;
                end else if (rx_done) begin
                    if (rx_data >= "0" && rx_data <= "9") begin
                        if (error_code != `ERR_NONE) begin
                            // Error recovery: if in error state, try to start a new number
                            // Check if the single digit is valid
                            if (({4'd0, rx_data} - 8'd48) <= {4'd0, config_max_value}) begin
                                parse_accum <= rx_data - "0";
                                error_code <= `ERR_NONE;
                                digit_received <= 1'b1;
                            end else begin
                                // Still invalid even as a single digit
                                if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                            end
                        end else begin
                            // Normal accumulation
                            // Check if adding this digit exceeds max value
                            // Note: parse_accum * 10 + digit
                            if (({8'd0, parse_accum} * 16'd10 + {8'd0, rx_data} - 16'd48) > {12'd0, config_max_value}) begin
                                 error_code <= `ERR_VALUE_RANGE;
                                 if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end // Echo '!'
                                 // Stay in PARSE_DATA, do not update accum, wait for valid input
                            end else begin
                                 parse_accum <= parse_accum * 8'd10 + (rx_data - "0");
                                 digit_received <= 1'b1;
                                 error_code <= `ERR_NONE;
                            end
                        end
                    end else if (rx_data == 8'h20) begin // Space
                        if (error_code == `ERR_NONE) begin
                            if (digit_received) begin
                                if (elements_written < total_elements) begin
                                    mem_wr_en <= 1'b1;
                                    mem_wr_addr <= input_alloc_addr + elements_written;
                                    mem_wr_data <= parse_accum;
                                    elements_written <= elements_written + 1'b1;
                                    
                                    // Check if done
                                    if ((elements_written + 1'b1) >= total_elements) begin
                                        sub_state <= COMMIT;
                                    end
                                end
                                parse_accum <= 8'd0;
                                digit_received <= 1'b0;
                            end
                            // If space received without digits (e.g. multiple spaces), just ignore.
                        end
                        // If error exists, do nothing (maintain error state)
                    end else if (rx_data == 8'h0D || rx_data == 8'h0A) begin // Enter
                        if (error_code == `ERR_NONE) begin
                            if (digit_received) begin
                                // Write the pending number
                                if (elements_written < total_elements) begin
                                    mem_wr_en <= 1'b1;
                                    mem_wr_addr <= input_alloc_addr + elements_written;
                                    mem_wr_data <= parse_accum;
                                    elements_written <= elements_written + 1'b1;
                                    
                                    if ((elements_written + 1'b1) >= total_elements) begin
                                        sub_state <= COMMIT;
                                    end else begin
                                        sub_state <= FILL_ZEROS;
                                    end
                                end else begin
                                    // Should not happen if logic is correct (checked < total_elements)
                                    sub_state <= COMMIT;
                                end
                            end else begin
                                // No pending number
                                if (elements_written < total_elements) begin
                                    sub_state <= FILL_ZEROS;
                                end else begin
                                    sub_state <= COMMIT;
                                end
                            end
                            parse_accum <= 8'd0;
                            digit_received <= 1'b0;
                        end
                        // If error exists, do nothing (maintain error state)
                    end else begin
                        // Invalid character received (not a digit, not space, not enter)
                        error_code <= `ERR_VALUE_RANGE; // Or define a new error code like ERR_INVALID_CHAR
                        if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end // Echo '!'
                        // Stay in PARSE_DATA
                    end
                end else if (error_code != `ERR_NONE) begin
                    // Keep error code until timeout_reset or valid input
                end
            end
            
            FILL_ZEROS: begin
                // Fill remaining elements with zeros
                if (elements_written < total_elements) begin
                    mem_wr_en <= 1'b1;
                    mem_wr_addr <= input_alloc_addr + elements_written;
                    mem_wr_data <= {ELEMENT_WIDTH{1'b0}}; // Write 0
                    elements_written <= elements_written + 1'b1;
                end else begin
                    // Done filling
                    sub_state <= COMMIT;
                end
            end
            
            COMMIT: begin
                commit_req <= 1'b1;
                commit_slot <= input_matrix_slot;
                commit_m <= input_m;
                commit_n <= input_n;
                commit_addr <= input_alloc_addr;
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
                        mem_rd_addr <= input_alloc_addr + ({4'd0, display_row} * {4'd0, input_n}) + {8'd0, display_col};
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
                            if (display_col == input_n - 1) begin
                                // End of row
                                display_col <= 4'd0;
                                if (display_row == input_m - 1) begin
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
                    
                    4'd8: begin // Final line feed, then done
                        if (!tx_busy && !tx_start) begin
                            tx_data <= 8'h0A;
                            tx_start <= 1'b1;
                            mem_rd_en <= 1'b0;
                            sub_state <= DONE;
                        end
                    end
                    
                    default: display_step <= 4'd0;
                endcase
            end
            
            DONE: begin
                commit_req <= 1'b0;
                // if (!tx_busy) begin
                //    tx_data <= "D";  // Success indicator ('D')
                //    tx_start <= 1'b1;
                //    sub_state <= IDLE;
                // end
                sub_state <= IDLE;
            end
            
            default: sub_state <= IDLE;
        endcase
    end else begin
        // Mode inactive: reset to idle
        sub_state <= IDLE;
        parse_accum <= 8'd0;
        input_m <= 4'd0;
        input_n <= 4'd0;
        total_elements <= 8'd0;
        elements_written <= 8'd0;
        mem_wr_en <= 1'b0;
        alloc_req <= 1'b0;
        commit_req <= 1'b0;
        error_code <= `ERR_NONE;
    end
end

endmodule
