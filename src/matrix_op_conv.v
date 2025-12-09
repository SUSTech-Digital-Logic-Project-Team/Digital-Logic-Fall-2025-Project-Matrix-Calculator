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
    
    // Clock cycle counter output
    output reg [31:0] cycle_count
);

    reg [4:0] i, j;  // Extended to 5 bits for dim up to 16 (now represents output position)
    reg [3:0] ki, kj; // Kernel indices 0..2
    reg [3:0] state;
    reg [15:0] acc;
    reg [ELEMENT_WIDTH-1:0] val_a;
    
    // Output dimensions (input_dim - 2 for valid convolution)
    wire [4:0] out_m = dim_m - 2;
    wire [4:0] out_n = dim_n - 2;
    
    // Source indices in input image
    // When output position is (i, j), the kernel center in input is at (i+1, j+1)
    // Kernel offset from center: ki-1, kj-1 (for ki,kj in 0..2)
    // So input position = (i+1 + ki-1, j+1 + kj-1) = (i+ki, j+kj)
    wire [4:0] src_row = i + ki;
    wire [4:0] src_col = j + kj;
    
    // Cycle counter
    reg [31:0] cycle_counter;
    reg counting;
    
    localparam S_IDLE = 0, 
               S_INIT_PIXEL = 1,
               S_READ_A = 2, S_WAIT_A = 3,
               S_READ_K = 4, S_WAIT_K = 5,
               S_MAC = 6,
               S_NEXT_KERNEL = 7,
               S_WRITE = 8,
               S_NEXT_PIXEL = 9,
               S_DONE = 10;
               
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done <= 0;
            mem_rd_en <= 0;
            mem_wr_en <= 0;
            i <= 0; j <= 0;
            ki <= 0; kj <= 0;
            acc <= 0;
            cycle_counter <= 0;
            cycle_count <= 0;
            counting <= 0;
        end else begin
            // Count cycles while processing
            if (counting) begin
                cycle_counter <= cycle_counter + 1;
            end
            
            case (state)
                S_IDLE: begin
                    done <= 0;
                    if (start) begin
                        i <= 0; j <= 0;
                        cycle_counter <= 0;
                        counting <= 1;
                        state <= S_INIT_PIXEL;
                    end
                end
                
                S_INIT_PIXEL: begin
                    acc <= 0;
                    ki <= 0; kj <= 0;
                    state <= S_READ_A;
                end
                
                // No bounds check needed - all positions are valid in valid convolution
                S_READ_A: begin
                    mem_rd_en <= 1;
                    // Input position = (i + ki, j + kj)
                    mem_rd_addr <= addr_op1 + (src_row * dim_n) + src_col;
                    state <= S_WAIT_A;
                end
                
                S_WAIT_A: begin
                    mem_rd_en <= 0;
                    state <= S_READ_K;
                end
                
                S_READ_K: begin
                    val_a <= mem_rd_data; // Store A pixel
                    mem_rd_en <= 1;
                    // Kernel is 3x3. Index = ki * 3 + kj
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
                            state <= S_READ_A;
                        end
                    end else begin
                        kj <= kj + 1;
                        state <= S_READ_A;
                    end
                end
                
                S_WRITE: begin
                    mem_wr_en <= 1;
                    // Output position (i, j) in result matrix of size out_m x out_n
                    mem_wr_addr <= addr_res + (i * out_n) + j;
                    mem_wr_data <= acc[7:0];
                    state <= S_NEXT_PIXEL;
                end
                
                S_NEXT_PIXEL: begin
                    mem_wr_en <= 0;
                    if (j == out_n - 1) begin
                        j <= 0;
                        if (i == out_m - 1) begin
                            counting <= 0;
                            cycle_count <= cycle_counter + 1; // Save final count
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
                    if (!start) state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
