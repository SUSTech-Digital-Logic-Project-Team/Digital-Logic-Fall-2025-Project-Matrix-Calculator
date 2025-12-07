`timescale 1ns / 1ps
`include "matrix_pkg.vh"

module matrix_op_mul #(
    parameter ELEMENT_WIDTH = `ELEMENT_WIDTH,
    parameter ADDR_WIDTH = `BRAM_ADDR_WIDTH
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    output reg done,
    
    input wire [4:0] dim_m, // Rows of A (extended to 5 bits)
    input wire [4:0] dim_n, // Cols of B (extended to 5 bits)
    input wire [4:0] dim_p, // Cols of A / Rows of B (extended to 5 bits)
    
    input wire [ADDR_WIDTH-1:0] addr_op1, // Matrix A
    input wire [ADDR_WIDTH-1:0] addr_op2, // Matrix B
    input wire [ADDR_WIDTH-1:0] addr_res, // Matrix C
    
    // Memory interface
    output reg mem_rd_en,
    output reg [ADDR_WIDTH-1:0] mem_rd_addr,
    input wire [ELEMENT_WIDTH-1:0] mem_rd_data,
    
    output reg mem_wr_en,
    output reg [ADDR_WIDTH-1:0] mem_wr_addr,
    output reg [ELEMENT_WIDTH-1:0] mem_wr_data
);

    reg [4:0] i, j, k;  // Extended to 5 bits for dim up to 16
    reg [3:0] state;
    reg [15:0] acc; // Accumulator
    reg [ELEMENT_WIDTH-1:0] val_a;
    
    localparam S_IDLE = 0, 
               S_INIT_ACC = 1,
               S_READ_A = 2, S_WAIT_A = 3, 
               S_READ_B = 4, S_WAIT_B = 5, 
               S_MAC = 6, 
               S_WRITE = 7, 
               S_NEXT_K = 8, 
               S_NEXT_J = 9, 
               S_NEXT_I = 10, 
               S_DONE = 11;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done <= 0;
            mem_rd_en <= 0;
            mem_wr_en <= 0;
            i <= 0; j <= 0; k <= 0;
            acc <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 0;
                    if (start) begin
                        i <= 0; j <= 0;
                        state <= S_INIT_ACC;
                    end
                end
                
                S_INIT_ACC: begin
                    acc <= 0;
                    k <= 0;
                    state <= S_READ_A;
                end
                
                S_READ_A: begin
                    mem_rd_en <= 1;
                    // A is M x P. Index = i * P + k
                    mem_rd_addr <= addr_op1 + (i * dim_p) + k;
                    state <= S_WAIT_A;
                end
                
                S_WAIT_A: begin
                    mem_rd_en <= 0;
                    state <= S_READ_B;
                end
                
                S_READ_B: begin
                    val_a <= mem_rd_data; // Store A
                    mem_rd_en <= 1;
                    // B is P x N. Index = k * N + j
                    mem_rd_addr <= addr_op2 + (k * dim_n) + j;
                    state <= S_WAIT_B;
                end
                
                S_WAIT_B: begin
                    mem_rd_en <= 0;
                    state <= S_MAC;
                end
                
                S_MAC: begin
                    // Multiply and Accumulate
                    acc <= acc + (val_a * mem_rd_data);
                    state <= S_NEXT_K;
                end
                
                S_NEXT_K: begin
                    if (k == dim_p - 1) begin
                        state <= S_WRITE;
                    end else begin
                        k <= k + 1;
                        state <= S_READ_A;
                    end
                end
                
                S_WRITE: begin
                    mem_wr_en <= 1;
                    // C is M x N. Index = i * N + j
                    mem_wr_addr <= addr_res + (i * dim_n) + j;
                    mem_wr_data <= acc[7:0]; // Truncate to 8 bits
                    state <= S_NEXT_J;
                end
                
                S_NEXT_J: begin
                    mem_wr_en <= 0;
                    if (j == dim_n - 1) begin
                        j <= 0;
                        state <= S_NEXT_I;
                    end else begin
                        j <= j + 1;
                        state <= S_INIT_ACC;
                    end
                end
                
                S_NEXT_I: begin
                    if (i == dim_m - 1) begin
                        state <= S_DONE;
                    end else begin
                        i <= i + 1;
                        state <= S_INIT_ACC;
                    end
                end
                
                S_DONE: begin
                    done <= 1;
                    if (!start) state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
