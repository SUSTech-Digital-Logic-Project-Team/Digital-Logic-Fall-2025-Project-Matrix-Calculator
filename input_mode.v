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
    
    // Error and state output
    output reg [3:0] error_code,
    output reg [3:0] sub_state
);

// State definitions
localparam IDLE = 4'd0,
           PARSE_M = 4'd1,
           PARSE_N = 4'd2,
           CHECK_DIM = 4'd3,
           WAIT_ALLOC = 4'd4,
           PARSE_DATA = 4'd5,
           COMMIT = 4'd6,
           DONE = 4'd7,
           ERROR = 4'd8;

// Streaming parse registers
reg [7:0] parse_accum;        // Accumulator for multi-digit number (e.g., "12" -> 12)
reg [3:0] input_m, input_n;
reg [7:0] total_elements;     // Pre-computed M*N to avoid repeated multiply
reg [7:0] elements_written;   // Count of elements written to BRAM
reg [3:0] input_matrix_slot;
reg [ADDR_WIDTH-1:0] input_alloc_addr;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sub_state <= IDLE;
        parse_accum <= 8'd0;
        input_m <= 4'd0;
        input_n <= 4'd0;
        total_elements <= 8'd0;
        elements_written <= 8'd0;
        input_matrix_slot <= 4'd0;
        input_alloc_addr <= {ADDR_WIDTH{1'b0}};
        mem_wr_en <= 1'b0;
        mem_wr_addr <= {ADDR_WIDTH{1'b0}};
        mem_wr_data <= {ELEMENT_WIDTH{1'b0}};
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
                if (rx_done) begin
                    if (rx_data == 8'h20) begin // 空格键作为分隔符
                        input_m <= parse_accum[3:0];
                        parse_accum <= 8'd0;
                        sub_state <= PARSE_N;
                    end else if (rx_data >= "0" && rx_data <= "9") begin
                        // Streaming accumulate: M = M*10 + digit
                        // Optimize multiply-by-10 as shift-add: x*10 = (x<<3) + (x<<1)
                        
                        parse_accum <= {parse_accum[4:0], 3'd0} + {6'd0, parse_accum[1:0]} + (rx_data - "0");
                    end
                    // 发送确认信息：回显接收到的数据
                    if (!tx_busy) begin
                        tx_data <= rx_data; // 回显接收到的字符
                        tx_start <= 1'b1;
                    end
                end
            end
            
            PARSE_N: begin
                if (rx_done) begin
                    if (rx_data == 8'h20) begin // 空格键作为分隔符
                        input_n <= parse_accum[3:0];
                        parse_accum <= 8'd0;
                        sub_state <= CHECK_DIM;
                    end else if (rx_data >= "0" && rx_data <= "9") begin
                        parse_accum <= {parse_accum[4:0], 3'd0} + {6'd0, parse_accum[1:0]} + (rx_data - "0");
                    end
                    // 发送确认信息：回显接收到的数据
                    if (!tx_busy) begin
                        tx_data <= rx_data; // 回显接收到的字符
                        tx_start <= 1'b1;
                    end
                end
            end
            
            CHECK_DIM: begin
                if (input_m == 4'd0 || input_m > config_max_dim ||
                    input_n == 4'd0 || input_n > config_max_dim) begin
                    error_code <= `ERR_DIM_RANGE;
                    sub_state <= ERROR;
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
                if (alloc_valid) begin
                    input_alloc_addr <= alloc_addr;
                    input_matrix_slot <= alloc_slot;
                    elements_written <= 8'd0;
                    alloc_req <= 1'b0;
                    sub_state <= PARSE_DATA;
                end else if (!alloc_valid && alloc_req) begin
                    // Allocation failed (no space)
                    error_code <= `ERR_NO_SPACE;
                    alloc_req <= 1'b0;
                    sub_state <= ERROR;
                end
            end
            
            PARSE_DATA: begin
                if (rx_done) begin
                    if (rx_data >= "0" && rx_data <= "9") begin
                        // Single-digit immediate value
                        if ((rx_data - "0") > {4'd0, config_max_value}) begin
                            error_code <= `ERR_VALUE_RANGE;
                            sub_state <= ERROR;
                        end else if (elements_written < total_elements) begin
                            // Write directly to BRAM (streaming, no buffer)
                            mem_wr_en <= 1'b1;
                            mem_wr_addr <= input_alloc_addr + elements_written;
                            mem_wr_data <= rx_data - "0";
                            elements_written <= elements_written + 1'b1;
                            
                            // Check if done
                            if ((elements_written + 1'b1) >= total_elements) begin
                                sub_state <= COMMIT;
                            end
                        end
                    end
                    // Ignore non-digit characters (spaces, commas, newlines are skipped)
                    // 发送确认信息：回显接收到的数据
                    if (!tx_busy) begin
                        tx_data <= rx_data; // 回显接收到的字符
                        tx_start <= 1'b1;
                    end
                end
            end
            
            COMMIT: begin
                commit_req <= 1'b1;
                commit_slot <= input_matrix_slot;
                commit_m <= input_m;
                commit_n <= input_n;
                commit_addr <= input_alloc_addr;
                sub_state <= DONE;
            end
            
            DONE: begin
                commit_req <= 1'b0;
                if (!tx_busy) begin
                    tx_data <= 8'b01000011;  // Success indicator ('C')
                    tx_start <= 1'b1;
                    sub_state <= IDLE;
                end
            end
            
            ERROR: begin
                // Stay in error until mode exits or reset
                commit_req <= 1'b0;
                alloc_req <= 1'b0;
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
