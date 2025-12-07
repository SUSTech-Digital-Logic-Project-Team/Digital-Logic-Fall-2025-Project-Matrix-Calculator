`timescale 1ns / 1ps
`include "matrix_pkg.vh"

module matrix_op_transpose #(
    parameter ELEMENT_WIDTH = `ELEMENT_WIDTH,
    parameter ADDR_WIDTH = `BRAM_ADDR_WIDTH
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    output reg done,
    
    input wire [4:0] dim_m, // Input rows (extended to 5 bits)
    input wire [4:0] dim_n, // Input cols (extended to 5 bits)
    input wire [ADDR_WIDTH-1:0] addr_op1,
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
    reg [2:0] state;
    
    localparam S_IDLE = 0, S_READ = 1, S_WAIT = 2, S_WRITE = 3, S_NEXT = 4, S_DONE = 5;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done <= 0;
            mem_rd_en <= 0;
            mem_wr_en <= 0;
            i <= 0;
            j <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 0;
                    if (start) begin
                        i <= 0;
                        j <= 0;
                        state <= S_READ;
                    end
                end
                
                S_READ: begin
                    mem_rd_en <= 1;
                    mem_rd_addr <= addr_op1 + (i * dim_n) + j;
                    state <= S_WAIT;
                end
                
                S_WAIT: begin
                    mem_rd_en <= 0;
                    state <= S_WRITE;
                end
                
                S_WRITE: begin
                    mem_wr_en <= 1;
                    // Transpose: Write to (j, i) in a (N x M) matrix
                    // Address = base + j * M + i
                    mem_wr_addr <= addr_res + (j * dim_m) + i;
                    mem_wr_data <= mem_rd_data;
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
                            state <= S_READ;
                        end
                    end else begin
                        j <= j + 1;
                        state <= S_READ;
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
