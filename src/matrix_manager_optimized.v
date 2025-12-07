// ========================================
// Optimized Matrix Manager with BRAM Support
// Purpose: Manage matrix metadata using distributed RAM (small tables)
// while data storage uses BRAM
// ========================================

`timescale 1ns / 1ps
`include "matrix_pkg.vh"

module matrix_manager_optimized #(
    parameter MAX_STORAGE_MATRICES = `MAX_STORAGE_MATRICES,
    parameter MAX_ELEMENTS = 4096,
    parameter ELEMENT_WIDTH = `ELEMENT_WIDTH
)(
    input wire clk,
    input wire rst_n,
    
    // ========================================
    // Matrix Allocation Interface
    // ========================================
    input wire alloc_req,
    input wire [4:0] alloc_m,           // requested rows (extended to 5 bits)
    input wire [4:0] alloc_n,           // requested columns (extended to 5 bits)
    output reg [3:0] alloc_slot,        // allocated slot index (0-19)
    output reg [11:0] alloc_addr,       // allocated start address in BRAM
    output reg alloc_valid,             // allocation success flag
    
    // ========================================
    // Matrix Commit Interface
    // ========================================
    input wire commit_req,
    input wire [3:0] commit_slot,
    input wire [4:0] commit_m,          // extended to 5 bits
    input wire [4:0] commit_n,          // extended to 5 bits
    input wire [11:0] commit_addr,
    
    // ========================================
    // Matrix Query Interface
    // ========================================
    input wire [3:0] query_slot,
    output wire query_valid,
    output wire [4:0] query_m,          // extended to 5 bits
    output wire [4:0] query_n,          // extended to 5 bits
    output wire [11:0] query_addr,
    output wire [7:0] query_element_count,
    
    // ========================================
    // Statistics Interface
    // ========================================
    output wire [7:0] total_matrix_count
);

// ========================================
// Matrix Directory Storage (using distributed RAM)
// These are small tables, so distributed RAM is fine
// ========================================
(* ram_style = "distributed" *) reg matrix_valid [0:MAX_STORAGE_MATRICES-1];
(* ram_style = "distributed" *) reg [4:0] matrix_rows [0:MAX_STORAGE_MATRICES-1];  // extended to 5 bits
(* ram_style = "distributed" *) reg [4:0] matrix_cols [0:MAX_STORAGE_MATRICES-1];  // extended to 5 bits
(* ram_style = "distributed" *) reg [11:0] matrix_start_addr [0:MAX_STORAGE_MATRICES-1];
(* ram_style = "distributed" *) reg [11:0] matrix_end_addr [0:MAX_STORAGE_MATRICES-1];

// ========================================
// Query Output Combinational Logic
// ========================================
assign query_valid = matrix_valid[query_slot];
assign query_m = matrix_rows[query_slot];
assign query_n = matrix_cols[query_slot];
assign query_addr = matrix_start_addr[query_slot];
assign query_element_count = (matrix_end_addr[query_slot] - matrix_start_addr[query_slot]);

// (Removed unsynthesizable function-style searches; replaced with inline loops)

// ========================================
// Allocation Logic
// ========================================
reg [3:0] temp_slot;
reg [11:0] temp_addr;
reg [11:0] required_size;
integer init_i;
integer search_i;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // Initialize all slots as invalid
        for (init_i = 0; init_i < MAX_STORAGE_MATRICES; init_i = init_i + 1) begin
            matrix_valid[init_i] <= 1'b0;
            matrix_rows[init_i] <= 4'd0;
            matrix_cols[init_i] <= 4'd0;
            matrix_start_addr[init_i] <= 12'd0;
            matrix_end_addr[init_i] <= 12'd0;
        end
        
        alloc_valid <= 1'b0;
        alloc_slot <= 4'hF;
        alloc_addr <= 12'd0;
    end else begin
        // Default outputs
        alloc_valid <= 1'b0;
        alloc_slot <= 4'hF;
        alloc_addr <= 12'd0;
        
        // Handle allocation requests
        if (alloc_req) begin
            // Compute required storage size (m*n)
            required_size = {8'd0, alloc_m} * {8'd0, alloc_n};

            // Find first free slot (priority: lowest index)
            temp_slot = 4'hF;
            for (search_i = 0; search_i < MAX_STORAGE_MATRICES; search_i = search_i + 1) begin
                if (!matrix_valid[search_i] && temp_slot == 4'hF) begin
                    temp_slot = search_i[3:0];
                end
            end

            // Find next free address (allocate after the furthest end address)
            temp_addr = 12'd0;
            for (search_i = 0; search_i < MAX_STORAGE_MATRICES; search_i = search_i + 1) begin
                if (matrix_valid[search_i] && matrix_end_addr[search_i] > temp_addr) begin
                    temp_addr = matrix_end_addr[search_i];
                end
            end

            // Check capacity and acknowledge allocation
            if (temp_slot != 4'hF && (temp_addr + required_size) <= MAX_ELEMENTS) begin
                alloc_slot <= temp_slot;
                alloc_addr <= temp_addr;
                alloc_valid <= 1'b1;
            end
        end
        
        // Handle commit requests
        if (commit_req && commit_slot < MAX_STORAGE_MATRICES) begin
            matrix_valid[commit_slot] <= 1'b1;
            matrix_rows[commit_slot] <= commit_m;
            matrix_cols[commit_slot] <= commit_n;
            matrix_start_addr[commit_slot] <= commit_addr;
            matrix_end_addr[commit_slot] <= commit_addr + {8'd0, commit_m} * {8'd0, commit_n};
        end
    end
end

// ========================================
// Total Matrix Count 
// ========================================
integer count_i;
reg [7:0] total_count_comb;

always @(*) begin
    total_count_comb = 8'd0;
    for (count_i = 0; count_i < MAX_STORAGE_MATRICES; count_i = count_i + 1) begin
        if (matrix_valid[count_i]) begin
            total_count_comb = total_count_comb + 1'b1;
        end
    end
end

assign total_matrix_count = total_count_comb;

endmodule
