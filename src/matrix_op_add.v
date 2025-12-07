`timescale 1ns / 1ps
`include "matrix_pkg.vh"

module matrix_op_add #(
    parameter ELEMENT_WIDTH = `ELEMENT_WIDTH,
    parameter ADDR_WIDTH = `BRAM_ADDR_WIDTH
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    output reg done,
    
    input wire [4:0] dim_m,            // Extended to 5 bits
    input wire [4:0] dim_n,            // Extended to 5 bits
    input wire [ADDR_WIDTH-1:0] addr_op1,
    input wire [ADDR_WIDTH-1:0] addr_op2,
    input wire [ADDR_WIDTH-1:0] addr_res,
    
    // Memory interface
    output reg mem_rd_en,
    output reg [ADDR_WIDTH-1:0] mem_rd_addr,
    input wire [ELEMENT_WIDTH-1:0] mem_rd_data,
    
    output reg mem_wr_en,
    output reg [ADDR_WIDTH-1:0] mem_wr_addr,
    output reg [ELEMENT_WIDTH-1:0] mem_wr_data
);

    reg [4:0] i, j;  // Extended to 5 bits for dim up to 16
    reg [3:0] state;
    reg [ELEMENT_WIDTH-1:0] val1;
    reg [ELEMENT_WIDTH-1:0] val2;
    
    localparam S_IDLE = 0, S_READ_1 = 1, S_WAIT_1 = 2, S_WAIT_1_B = 3, S_CAPTURE_1 = 4, S_PRE_READ_2 = 12, S_READ_2 = 5, S_WAIT_2 = 6, S_WAIT_2_B = 7, S_CAPTURE_2 = 8, S_WRITE = 9, S_NEXT = 10, S_DONE = 11;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done <= 0;
            mem_rd_en <= 0;
            mem_wr_en <= 0;
            i <= 0;
            j <= 0;
            val1 <= 0;
            val2 <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 0;
                    if (start) begin
                        i <= 0;
                        j <= 0;
                        state <= S_READ_1;
                    end
                end
                
                S_READ_1: begin
                    mem_rd_en <= 1;
                    mem_rd_addr <= addr_op1 + (i * dim_n) + j;
                    state <= S_WAIT_1;
                end
                
                S_WAIT_1: begin
                    mem_rd_en <= 0;
                    state <= S_WAIT_1_B;
                end

                S_WAIT_1_B: begin
                    state <= S_CAPTURE_1;
                end

                S_CAPTURE_1: begin
                    val1 <= mem_rd_data; // Capture data from READ_1 safely
                    state <= S_PRE_READ_2;
                end

                S_PRE_READ_2: begin
                    state <= S_READ_2;
                end
                
                S_READ_2: begin
                    mem_rd_en <= 1;
                    mem_rd_addr <= addr_op2 + (i * dim_n) + j;
                    state <= S_WAIT_2;
                end
                
                S_WAIT_2: begin
                    mem_rd_en <= 0;
                    state <= S_WAIT_2_B;
                end

                S_WAIT_2_B: begin
                    state <= S_CAPTURE_2;
                end

                S_CAPTURE_2: begin
                    val2 <= mem_rd_data; // Capture data from READ_2 safely
                    state <= S_WRITE;
                end
                
                S_WRITE: begin
                    mem_wr_en <= 1;
                    mem_wr_addr <= addr_res + (i * dim_n) + j;
                    mem_wr_data <= val1 + val2; // val1 + val2
                    state <= S_NEXT;
                end
                
                S_NEXT: begin
                    mem_wr_en <= 0;
                    if (j == dim_n - 1) begin
                        j <= 0;
                        if (i == dim_m - 1) begin
                            state <= S_DONE;
                        end else begin
                            i <= i + 1;
                            state <= S_READ_1;
                        end
                    end else begin
                        j <= j + 1;
                        state <= S_READ_1;
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
