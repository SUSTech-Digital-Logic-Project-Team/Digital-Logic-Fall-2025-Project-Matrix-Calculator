// ========================================
// Matrix Compute Mode (Optimized with BRAM Writeback)
// Supports: Add, Multiply, Scalar Multiply, Transpose
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

    // DIP switches and buttons
    input wire [2:0] dip_sw,
    input wire btn_confirm,
    output reg [3:0] selected_op_type, 

    // UART interface
    input wire [7:0] rx_data,
    input wire rx_done,
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

    // BRAM interface
    output reg mem_rd_en,
    output reg [ADDR_WIDTH-1:0] mem_rd_addr,
    input wire [ELEMENT_WIDTH-1:0] mem_rd_data,
    output reg mem_a_we,
    output reg [ADDR_WIDTH-1:0] mem_a_addr,
    output reg [ELEMENT_WIDTH-1:0] mem_a_din,

    output reg [3:0] error_code,
    output reg [3:0] sub_state
);

// State definitions
localparam IDLE           = 4'd0,
           SELECT_OP      = 4'd1,
           SELECT_MATRIX1 = 4'd2,
           SELECT_MATRIX2 = 4'd3,
           READ_OP        = 4'd4,
           EXECUTE        = 4'd5,
           SEND_RESULT    = 4'd6,
           DONE           = 4'd7;

reg btn_prev;
wire btn_posedge = btn_confirm && !btn_prev;

reg [3:0] matrix1_m, matrix1_n, matrix2_m, matrix2_n;
reg [ELEMENT_WIDTH-1:0] matrix1 [0:`MAX_POSSIBLE_DIM*`MAX_POSSIBLE_DIM-1];
reg [ELEMENT_WIDTH-1:0] matrix2 [0:`MAX_POSSIBLE_DIM*`MAX_POSSIBLE_DIM-1];
reg [ELEMENT_WIDTH-1:0] result_matrix [0:`MAX_POSSIBLE_DIM*`MAX_POSSIBLE_DIM-1];

integer i, j, k;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sub_state <= IDLE;
        selected_op_type <= 4'd0;
        error_code <= `ERR_NONE;
        mem_rd_en <= 1'b0;
        mem_a_we <= 1'b0;
        tx_start <= 1'b0;
        btn_prev <= 1'b0;
    end else if (mode_active) begin
        btn_prev <= btn_confirm;
        tx_start <= 1'b0;
        mem_rd_en <= 1'b0;
        mem_a_we <= 1'b0;

        case(sub_state)
            IDLE: begin
                selected_op_type <= 4'd0;
                error_code <= `ERR_NONE;
                sub_state <= SELECT_OP;
            end

            SELECT_OP: begin
                case(dip_sw)
                    3'd1: selected_op_type <= `OP_ADD;
                    3'd2: selected_op_type <= `OP_MATRIX_MUL;
                    3'd3: selected_op_type <= `OP_TRANSPOSE;
                    3'd4: selected_op_type <= `OP_SCALAR_MUL;
                    default: selected_op_type <= 4'd0;
                endcase
                if(btn_posedge) begin
                    if(selected_op_type == 4'd0) begin
                        error_code <= `ERR_INVALID_OP;
                        sub_state <= IDLE;
                    end else if(selected_op_type == `OP_TRANSPOSE || selected_op_type == `OP_SCALAR_MUL) begin
                        sub_state <= SELECT_MATRIX1;
                    end else begin
                        sub_state <= SELECT_MATRIX1;
                    end
                end
            end

            SELECT_MATRIX1: begin
                query_slot <= 4'd0; // 默认选择 slot0
                if(query_valid) begin
                    matrix1_m <= query_m;
                    matrix1_n <= query_n;
                    for(i=0;i<matrix1_m*matrix1_n;i=i+1) matrix1[i] <= mem_rd_data; // 简化读取
                    sub_state <= (selected_op_type == `OP_TRANSPOSE || selected_op_type == `OP_SCALAR_MUL) ? EXECUTE : SELECT_MATRIX2;
                end
            end

            SELECT_MATRIX2: begin
                query_slot <= 4'd1; // 默认选择 slot1
                if(query_valid) begin
                    matrix2_m <= query_m;
                    matrix2_n <= query_n;
                    for(i=0;i<matrix2_m*matrix2_n;i=i+1) matrix2[i] <= mem_rd_data; // 简化读取
                    sub_state <= EXECUTE;
                end
            end

            EXECUTE: begin
                case(selected_op_type)
                    `OP_ADD: begin
                        if(matrix1_m != matrix2_m || matrix1_n != matrix2_n) begin
                            error_code <= `ERR_DIM_MISMATCH;
                            sub_state <= DONE;
                        end else begin
                            for(i=0;i<matrix1_m;i=i+1)
                                for(j=0;j<matrix1_n;j=j+1)
                                    result_matrix[i*matrix1_n+j] <= matrix1[i*matrix1_n+j] + matrix2[i*matrix1_n+j];
                        end
                    end

                    `OP_MATRIX_MUL: begin
                        if(matrix1_n != matrix2_m) begin
                            error_code <= `ERR_DIM_MISMATCH;
                            sub_state <= DONE;
                        end else begin
                            for(i=0;i<matrix1_m;i=i+1)
                                for(j=0;j<matrix2_n;j=j+1) begin
                                    result_matrix[i*matrix2_n+j] <= 0;
                                    for(k=0;k<matrix1_n;k=k+1)
                                        result_matrix[i*matrix2_n+j] <= result_matrix[i*matrix2_n+j] + matrix1[i*matrix1_n+k]*matrix2[k*matrix2_n+j];
                                end
                        end
                    end

                    `OP_TRANSPOSE: begin
                        for(i=0;i<matrix1_m;i=i+1)
                            for(j=0;j<matrix1_n;j=j+1)
                                result_matrix[j*matrix1_m+i] <= matrix1[i*matrix1_n+j];
                    end

                    `OP_SCALAR_MUL: begin
                        // 假设串口输入 rx_data 为标量
                        for(i=0;i<matrix1_m*matrix1_n;i=i+1)
                            result_matrix[i] <= matrix1[i]*rx_data;
                    end

                    default: begin
                        error_code <= `ERR_INVALID_OP;
                        sub_state <= DONE;
                    end
                endcase

                // 写回 BRAM（Port A）
                for(i=0;i<matrix1_m*matrix2_n;i=i+1) begin
                    mem_a_we <= 1'b1;
                    mem_a_addr <= query_addr + i; // 默认写回 slot0
                    mem_a_din <= result_matrix[i];
                end

                sub_state <= SEND_RESULT;
            end

            SEND_RESULT: begin
                if(!tx_busy) begin
                    tx_data <= "R"; 
                    tx_start <= 1'b1;
                    sub_state <= DONE;
                end
            end

            DONE: begin
                if(btn_posedge) sub_state <= IDLE;
            end

            default: sub_state <= IDLE;
        endcase
    end else begin
        sub_state <= IDLE;
        btn_prev <= 1'b0;
    end
end

endmodule