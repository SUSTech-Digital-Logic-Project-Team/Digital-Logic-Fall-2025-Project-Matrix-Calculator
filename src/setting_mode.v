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
    input wire btn_confirm,
    
    // UART receive interface
    input wire [7:0] rx_data,
    input wire rx_done,
    output reg clear_rx_buffer,
    
    // UART transmit interface
    output reg [7:0] tx_data,
    output reg tx_start,
    input wire tx_busy,
    
    // Configuration output
    output reg [4:0] config_max_dim,
    output reg [4:0] config_max_value,
    output reg [4:0] config_matrices_per_size,
    output reg [4:0] config_error_seconds,
    
    // Error and state output
    output reg [3:0] error_code,
    output reg [3:0] sub_state
);

// State definitions
localparam IDLE = 4'd0, WAIT_MAX_DIM = 4'd1, WAIT_MAX_VAL = 4'd2,
           WAIT_MAT_PER_SIZE = 4'd3, WAIT_ERR_TIME = 4'd4,
           CONFIRM = 4'd5, DONE = 4'd6, APPLY = 4'd7;

// Internal configuration
reg [7:0] cfg_max_dim;
reg [3:0] cfg_max_value;
reg [3:0] cfg_matrices_per_size;
reg [4:0] cfg_error_seconds;
reg [7:0] parse_accum;        // Accumulator for multi-digit number

// Prompt display counter (for message cycling)
reg [2:0] message_state;
reg [4:0] print_step;
localparam MSG_DIM = 3'd0, MSG_VALUE = 3'd1, MSG_MATRICES = 3'd2, MSG_ERR_TIME = 3'd3, MSG_CONFIRM = 3'd4;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sub_state <= IDLE;
        config_max_dim <= `DEFAULT_MAX_DIM;
        config_max_value <= `DEFAULT_MAX_VALUE;
        config_matrices_per_size <= `DEFAULT_MATRICES_PER_SIZE;
        config_error_seconds <= `DEFAULT_ERROR_SECONDS;
        cfg_max_dim <= `DEFAULT_MAX_DIM;
        cfg_max_value <= `DEFAULT_MAX_VALUE;
        cfg_matrices_per_size <= `DEFAULT_MATRICES_PER_SIZE;
        cfg_error_seconds <= `DEFAULT_ERROR_SECONDS;
        tx_start <= 1'b0;
        tx_data <= 8'd0;
        error_code <= `ERR_NONE;
        parse_accum <= 8'd0;
        message_state <= MSG_DIM;
        print_step <= 5'd0;
        clear_rx_buffer <= 1'b0;
    end else if (mode_active) begin
        // Default one-shot signals
        tx_start <= 1'b0;
        clear_rx_buffer <= 1'b0;
        
        case (sub_state)
            IDLE: begin
                cfg_max_dim <= `DEFAULT_MAX_DIM;
                cfg_max_value <= `DEFAULT_MAX_VALUE;
                cfg_matrices_per_size <= `DEFAULT_MATRICES_PER_SIZE;
                cfg_error_seconds <= `DEFAULT_ERROR_SECONDS;
                parse_accum <= 8'd0;
                error_code <= `ERR_NONE;
                message_state <= MSG_DIM;
                print_step <= 5'd0;
                sub_state <= WAIT_MAX_DIM;
            end
            
            WAIT_MAX_DIM: begin
                // Send prompt for max dimension
                if (!tx_busy && !tx_start) begin
                    case (message_state)
                        MSG_DIM: begin
                            tx_data <= "D";  // 'D' for Dimension
                            tx_start <= 1'b1;
                            message_state <= MSG_DIM + 1;
                        end
                        default: begin
                            // Prompt sent, wait for input
                            if (rx_done) begin
                                if (rx_data >= "0" && rx_data <= "9") begin
                                    // Parse digit: accumulate using multiply-by-10 = (x<<3)+(x<<1)
                                    parse_accum <= (parse_accum << 3) + (parse_accum << 1) + (rx_data - "0");
                                end else if (rx_data == 8'h20) begin
                                    // Enter key - confirm the value
                                    if (parse_accum > 0 && parse_accum <= `MAX_POSSIBLE_DIM) begin
                                        cfg_max_dim <= parse_accum[3:0];
                                        parse_accum <= 8'd0;
                                        message_state <= MSG_VALUE;
                                        sub_state <= WAIT_MAX_VAL;
                                    end else begin
                                        // Invalid dimension
                                        error_code <= `ERR_DIM_RANGE;
                                        parse_accum <= 8'd0;
                                        message_state <= MSG_DIM;
                                    end
                                    clear_rx_buffer <= 1'b1;
                                end
                            end
                        end
                    endcase
                end
            end
            
            WAIT_MAX_VAL: begin
                // Send prompt for max value
                if (!tx_busy && !tx_start) begin
                    case (message_state)
                        MSG_VALUE: begin
                            tx_data <= "V";  // 'V' for Value
                            tx_start <= 1'b1;
                            message_state <= MSG_VALUE + 1;
                        end
                        default: begin
                            // Prompt sent, wait for input
                            if (rx_done) begin
                                if (rx_data >= "0" && rx_data <= "9") begin
                                    // Parse digit
                                    parse_accum <= (parse_accum << 3) + (parse_accum << 1) + (rx_data - "0");
                                end else if (rx_data == 8'h20) begin
                                    // Enter key - confirm the value
                                    if (parse_accum > 0 && parse_accum <= 255) begin
                                        cfg_max_value <= parse_accum[3:0];
                                        parse_accum <= 8'd0;
                                        message_state <= MSG_MATRICES;
                                        sub_state <= WAIT_MAT_PER_SIZE;
                                    end else begin
                                        // Invalid value
                                        error_code <= `ERR_VALUE_RANGE;
                                        parse_accum <= 8'd0;
                                        message_state <= MSG_VALUE;
                                    end
                                    clear_rx_buffer <= 1'b1;
                                end
                            end
                        end
                    endcase
                end
            end
            
            WAIT_MAT_PER_SIZE: begin
                // Send prompt for matrices per size
                if (!tx_busy && !tx_start) begin
                    case (message_state)
                        MSG_MATRICES: begin
                            tx_data <= "M";  // 'M' for Matrices
                            tx_start <= 1'b1;
                            message_state <= MSG_MATRICES + 1;
                        end
                        default: begin
                            // Prompt sent, wait for input
                            if (rx_done) begin
                                if (rx_data >= "0" && rx_data <= "9") begin
                                    // Parse digit
                                    parse_accum <= (parse_accum << 3) + (parse_accum << 1) + (rx_data - "0");
                                end else if (rx_data == 8'h20) begin
                                    // Enter key - confirm the value
                                    if (parse_accum > 0 && parse_accum <= 20) begin
                                        cfg_matrices_per_size <= parse_accum[3:0];
                                        parse_accum <= 8'd0;
                                        message_state <= MSG_ERR_TIME;
                                        sub_state <= WAIT_ERR_TIME;
                                    end else begin
                                        // Invalid matrices per size
                                        error_code <= `ERR_NO_SPACE;
                                        parse_accum <= 8'd0;
                                        message_state <= MSG_MATRICES;
                                    end
                                    clear_rx_buffer <= 1'b1;
                                end
                            end
                        end
                    endcase
                end
            end

            WAIT_ERR_TIME: begin
                // Send prompt for error countdown seconds
                if (!tx_busy && !tx_start) begin
                    case (message_state)
                        MSG_ERR_TIME: begin
                            tx_data <= "T";  // 'T' for timer seconds
                            tx_start <= 1'b1;
                            message_state <= MSG_ERR_TIME + 1;
                        end
                        default: begin
                            if (rx_done) begin
                                if (rx_data >= "0" && rx_data <= "9") begin
                                    parse_accum <= (parse_accum << 3) + (parse_accum << 1) + (rx_data - "0");
                                end else if (rx_data == 8'h20) begin
                                    if (parse_accum >= `MIN_ERROR_SECONDS && parse_accum <= `MAX_ERROR_SECONDS) begin
                                        cfg_error_seconds <= parse_accum[4:0];
                                        parse_accum <= 8'd0;
                                        message_state <= MSG_CONFIRM;
                                        sub_state <= CONFIRM;
                                    end else begin
                                        error_code <= `ERR_VALUE_RANGE;
                                        parse_accum <= 8'd0;
                                        message_state <= MSG_ERR_TIME;
                                    end
                                    clear_rx_buffer <= 1'b1;
                                end
                            end
                        end
                    endcase
                end
            end
            
            CONFIRM: begin
                // Wait for confirmation button
                if (btn_confirm) begin
                    sub_state <= APPLY;
                    print_step <= 0;
                end
            end

            APPLY: begin
                // Send confirmation message 'S' and echo settings
                if (!tx_busy && !tx_start) begin
                    case (print_step)
                        0: begin
                            // Apply the configuration
                            config_max_dim <= cfg_max_dim;
                            config_max_value <= cfg_max_value;
                            config_matrices_per_size <= cfg_matrices_per_size;
                            config_error_seconds <= cfg_error_seconds;
                            error_code <= `ERR_NONE;
                            
                            tx_data <= "S";
                            tx_start <= 1'b1;
                            print_step <= 1;
                        end
                        1: begin tx_data <= 8'h20; tx_start <= 1'b1; print_step <= 2; end
                        
                        // Echo Max Dim (up to 3 digits)
                        2: begin
                            if (cfg_max_dim >= 100) begin
                                tx_data <= (cfg_max_dim / 100) + "0";
                                tx_start <= 1'b1;
                            end
                            print_step <= 3;
                        end
                        3: begin
                            if (cfg_max_dim >= 10) begin
                                tx_data <= ((cfg_max_dim / 10) % 10) + "0";
                                tx_start <= 1'b1;
                            end
                            print_step <= 4;
                        end
                        4: begin
                            tx_data <= (cfg_max_dim % 10) + "0";
                            tx_start <= 1'b1;
                            print_step <= 5;
                        end
                        5: begin tx_data <= 8'h20; tx_start <= 1'b1; print_step <= 6; end
                        
                        // Echo Max Value (up to 3 digits)
                        6: begin
                            if (cfg_max_value >= 100) begin
                                tx_data <= (cfg_max_value / 100) + "0";
                                tx_start <= 1'b1;
                            end
                            print_step <= 7;
                        end
                        7: begin
                            if (cfg_max_value >= 10) begin
                                tx_data <= ((cfg_max_value / 10) % 10) + "0";
                                tx_start <= 1'b1;
                            end
                            print_step <= 8;
                        end
                        8: begin
                            tx_data <= (cfg_max_value % 10) + "0";
                            tx_start <= 1'b1;
                            print_step <= 9;
                        end
                        9: begin tx_data <= 8'h20; tx_start <= 1'b1; print_step <= 10; end
                        
                        // Echo Matrices Per Size (up to 2 digits)
                        10: begin
                            if (cfg_matrices_per_size >= 10) begin
                                tx_data <= (cfg_matrices_per_size / 10) + "0";
                                tx_start <= 1'b1;
                            end
                            print_step <= 11;
                        end
                        11: begin
                            tx_data <= (cfg_matrices_per_size % 10) + "0";
                            tx_start <= 1'b1;
                            print_step <= 12;
                        end
                        12: begin tx_data <= 8'h20; tx_start <= 1'b1; print_step <= 13; end

                        // Echo Error Countdown Seconds (5-15)
                        13: begin
                            if (cfg_error_seconds >= 10) begin
                                tx_data <= (cfg_error_seconds / 10) + "0";
                                tx_start <= 1'b1;
                            end
                            print_step <= 14;
                        end
                        14: begin
                            tx_data <= (cfg_error_seconds % 10) + "0";
                            tx_start <= 1'b1;
                            print_step <= 15;
                        end

                        // Newline
                        15: begin tx_data <= 8'h0D; tx_start <= 1'b1; print_step <= 16; end
                        16: begin tx_data <= 8'h0A; tx_start <= 1'b1; print_step <= 17; end
                        
                        17: begin
                            sub_state <= DONE;
                            print_step <= 0;
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
        parse_accum <= 8'd0;
        message_state <= MSG_DIM;
    end
end

endmodule
