// ========================================
// Optimized BRAM Memory Pool Module
// Purpose: Provide dual-port Block RAM for matrix storage with 
// careful synthesis guidance to ensure BRAM utilization (not LUT)
// ========================================

`timescale 1ns / 1ps

module bram_memory_pool #(
    parameter DATA_WIDTH = 4,
    parameter ADDR_WIDTH = 12,          // 4K BRAM addresses (typical for Artix-7)
    parameter DEPTH = 4096
)(
    input wire clk,
    input wire rst_n,
    
    // Port A (Read/Write) - higher priority
    input wire a_en,
    input wire a_we,
    input wire [ADDR_WIDTH-1:0] a_addr,
    input wire [DATA_WIDTH-1:0] a_din,
    output reg [DATA_WIDTH-1:0] a_dout,
    
    // Port B (Read only)
    input wire b_en,
    input wire [ADDR_WIDTH-1:0] b_addr,
    output reg [DATA_WIDTH-1:0] b_dout
);

// ========================================
// Synthesis Attributes for BRAM Inference
// ========================================
(* ram_style = "block" *) reg [DATA_WIDTH-1:0] bram_mem [0:DEPTH-1];

// ========================================
// Port A: Read/Write Port (synchronous)
// ========================================
always @(posedge clk) begin
    if (a_en) begin
        if (a_we) begin
            // Write operation
            bram_mem[a_addr] <= a_din;
            a_dout <= a_din;  // Write-through behavior
        end else begin
            // Read operation
            a_dout <= bram_mem[a_addr];
        end
    end
end

// ========================================
// Port B: Read-only Port (synchronous)
// ========================================
always @(posedge clk) begin
    if (b_en) begin
        b_dout <= bram_mem[b_addr];
    end
end

// ========================================
// Optional: Initialization (if needed)
// ========================================
integer i;
initial begin
    for (i = 0; i < DEPTH; i = i + 1) begin
        bram_mem[i] = {DATA_WIDTH{1'b0}};
    end
end

endmodule
