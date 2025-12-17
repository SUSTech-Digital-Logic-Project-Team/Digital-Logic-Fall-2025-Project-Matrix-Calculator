`timescale 1ns / 1ps
`include "matrix_pkg.vh"

module matrix_op_conv #(
    parameter ELEMENT_WIDTH = `ELEMENT_WIDTH,
    parameter ADDR_WIDTH = `BRAM_ADDR_WIDTH
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    output reg done,
    
    input wire [4:0] dim_m, // Rows of A (extended to 5 bits)
    input wire [4:0] dim_n, // Cols of A (extended to 5 bits)
    
    input wire [ADDR_WIDTH-1:0] addr_op1, // Matrix A (Image)
    input wire [ADDR_WIDTH-1:0] addr_op2, // Matrix B (Kernel 3x3)
    input wire [ADDR_WIDTH-1:0] addr_res, // Matrix C (Result)
    
    // Memory interface
    output reg mem_rd_en,
    output reg [ADDR_WIDTH-1:0] mem_rd_addr,
    input wire [ELEMENT_WIDTH-1:0] mem_rd_data,
    
    output reg mem_wr_en,
    output reg [ADDR_WIDTH-1:0] mem_wr_addr,
    output reg [ELEMENT_WIDTH-1:0] mem_wr_data,
    output reg [12:0] clock_cyc
);

    reg [4:0] i, j;  // Extended to 5 bits for dim up to 16
    reg [3:0] ki, kj; // Kernel indices 0..2
    reg [3:0] state;
    reg [15:0] acc;
    reg [ELEMENT_WIDTH-1:0] val_a;
    reg [12:0] clock_cycles;
    
    // Signed indices for boundary check
    reg signed [5:0] row_idx, col_idx;
    
    localparam S_IDLE = 0, 
               S_INIT_PIXEL = 1,
               S_CHECK_BOUNDS = 2,
               S_READ_A = 3, S_WAIT_A = 4,
               S_READ_K = 5, S_WAIT_K = 6,
               S_MAC = 7,
               S_NEXT_KERNEL = 8,
               S_WRITE = 9,
               S_NEXT_PIXEL = 10,
               S_DONE = 11;
               
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done <= 0;
            mem_rd_en <= 0;
            mem_wr_en <= 0;
            i <= 0; j <= 0;
            ki <= 0; kj <= 0;
            acc <= 0;
            clock_cycles <= 0;
        end else begin
            if(state != S_IDLE && state != S_DONE) begin
                clock_cycles <= clock_cycles + 1;
            end else if(state == S_IDLE && start) begin
                clock_cycles <= 0;
            end

            case (state)
                S_IDLE: begin
                    done <= 0;
                    if (start) begin
                        // For valid-only convolution, need at least 3x3 input
                        if (dim_m < 3 || dim_n < 3) begin
                            state <= S_DONE;
                        end else begin
                            i <= 1; // start from row 1 (skip top border)
                            j <= 1; // start from col 1 (skip left border)
                            state <= S_INIT_PIXEL;
                        end
                    end
                end
                
                S_INIT_PIXEL: begin
                    acc <= 0;
                    ki <= 0; kj <= 0;
                    state <= S_CHECK_BOUNDS;
                end
                
                S_CHECK_BOUNDS: begin
                    // Valid-only convolution: i,j are already away from borders
                    row_idx = {2'b0, i} + {2'b0, ki} - 6'd1;
                    col_idx = {2'b0, j} + {2'b0, kj} - 6'd1;
                    state <= S_READ_A;
                end

                S_READ_A: begin
                    mem_rd_en <= 1;
                    mem_rd_addr <= addr_op1 + (row_idx[3:0] * dim_n) + col_idx[3:0];
                    state <= S_WAIT_A;
                end
                
                S_WAIT_A: begin
                    mem_rd_en <= 0;
                    state <= S_READ_K;
                end
                
                S_READ_K: begin
                    val_a <= mem_rd_data; // Store A pixel
                    mem_rd_en <= 1;
                    // Kernel is assumed 3x3. Index = ki * 3 + kj
                    // If Op2 is larger, we only use top-left 3x3.
                    mem_rd_addr <= addr_op2 + (ki * 3) + kj;
                    state <= S_WAIT_K;
                end
                
                S_WAIT_K: begin
                    mem_rd_en <= 0;
                    state <= S_MAC;
                end
                
                S_MAC: begin
                    acc <= acc + (val_a * mem_rd_data);
                    state <= S_NEXT_KERNEL;
                end
                
                S_NEXT_KERNEL: begin
                    if (kj == 2) begin
                        kj <= 0;
                        if (ki == 2) begin
                            state <= S_WRITE;
                        end else begin
                            ki <= ki + 1;
                            state <= S_CHECK_BOUNDS;
                        end
                    end else begin
                        kj <= kj + 1;
                        state <= S_CHECK_BOUNDS;
                    end
                end
                //Inside the kernel, j move from 0 to 2, and then go to 0, repeat for 3 times
                
                S_WRITE: begin
                    mem_wr_en <= 1;
                    // Output matrix size is (dim_m-2) x (dim_n-2), address uses zero-based output indices
                    mem_wr_addr <= addr_res + ((i - 1) * (dim_n - 2)) + (j - 1);
                    mem_wr_data <= acc[7:0];
                    state <= S_NEXT_PIXEL;
                end

                S_NEXT_PIXEL: begin
                    mem_wr_en <= 0;
                    if (j == dim_n - 2) begin
                        j <= 1;
                        if (i == dim_m - 2) begin
                            state <= S_DONE;
                        end else begin
                            i <= i + 1;
                            state <= S_INIT_PIXEL;
                        end
                    end else begin
                        j <= j + 1;
                        state <= S_INIT_PIXEL;
                    end
                end
                
                S_DONE: begin
                    done <= 1;
                    clock_cyc <= clock_cycles;
                    if (!start) state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
