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
    // Per-dimension storage cap (matrices per size), comes from setting_mode
    input wire [4:0] dim_limit_per_size,
    
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

// Per-dimension counters and replacement pointers (indexed by {rows, cols})
localparam DIM_INDEX_WIDTH = 10; // 5 bits rows + 5 bits cols
localparam DIM_SPACE = 1 << DIM_INDEX_WIDTH; // 1024 entries
localparam PTR_WIDTH = 5; // supports up to 32 slots
(* ram_style = "distributed" *) reg [7:0] dim_count [0:DIM_SPACE-1];
(* ram_style = "distributed" *) reg [PTR_WIDTH-1:0] dim_repl_ptr [0:DIM_SPACE-1];

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
reg [9:0] dim_index;
reg [7:0] dim_limit_ext;
reg [3:0] selected_slot;
reg [11:0] selected_addr;
integer init_i;
integer search_i;
integer dim_i;
reg [4:0] old_rows_reg;
reg [4:0] old_cols_reg;
reg [9:0] old_idx_reg;
reg [9:0] new_idx_reg;

// Find next slot of the same dimension (wrap around), used for replacement pointer advance
function [PTR_WIDTH-1:0] find_next_same_dim;
    input [PTR_WIDTH-1:0] start_slot;
    input [4:0] rows;
    input [4:0] cols;
    integer offset;
    reg [PTR_WIDTH-1:0] idx;
    reg found;
begin
    find_next_same_dim = start_slot;
    found = 1'b0;
    for (offset = 1; offset <= MAX_STORAGE_MATRICES; offset = offset + 1) begin
        idx = start_slot + offset;
        if (idx >= MAX_STORAGE_MATRICES) begin
            idx = idx - MAX_STORAGE_MATRICES;
        end
        if (!found && matrix_valid[idx] && matrix_rows[idx] == rows && matrix_cols[idx] == cols) begin
            find_next_same_dim = idx;
            found = 1'b1;
        end
    end
end
endfunction

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
        // Initialize per-dimension tracking
        for (dim_i = 0; dim_i < DIM_SPACE; dim_i = dim_i + 1) begin
            dim_count[dim_i] <= 8'd0;
            dim_repl_ptr[dim_i] <= {PTR_WIDTH{1'b0}};
        end
        
        alloc_valid <= 1'b0;
        alloc_slot <= 4'hF;
        alloc_addr <= 12'd0;
    end else begin
        // Default outputs
        alloc_valid <= 1'b0;
        alloc_slot <= 4'hF;
        alloc_addr <= 12'd0;

        // Dimension index and limit
        dim_index = {alloc_m, alloc_n};
        dim_limit_ext = {3'd0, dim_limit_per_size};
        
        // Handle allocation requests
        if (alloc_req) begin
            // Compute required storage size (m*n)
            required_size = {8'd0, alloc_m} * {8'd0, alloc_n};

            // Replacement path when per-dimension cap is reached
            if (dim_count[dim_index] >= dim_limit_ext && dim_limit_ext != 0) begin
                selected_slot = dim_repl_ptr[dim_index][3:0];
                selected_addr = matrix_start_addr[selected_slot];
                alloc_slot <= selected_slot;
                alloc_addr <= selected_addr;
                alloc_valid <= 1'b1;

                // Advance replacement pointer to next same-dimension matrix
                dim_repl_ptr[dim_index] <= find_next_same_dim(dim_repl_ptr[dim_index], alloc_m, alloc_n);
            end else begin
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

                    // Initialize replacement pointer when first slot of a dimension is allocated
                    if (dim_count[dim_index] == 0) begin
                        dim_repl_ptr[dim_index] <= temp_slot;
                    end
                end
            end
        end
        
        // Handle commit requests
        if (commit_req && commit_slot < MAX_STORAGE_MATRICES) begin
            // Track old dimension for count maintenance
            old_rows_reg = matrix_rows[commit_slot];
            old_cols_reg = matrix_cols[commit_slot];
            old_idx_reg = {old_rows_reg, old_cols_reg};
            new_idx_reg = {commit_m, commit_n};

            // Decrement old dimension count when replacing with different dimension
            if (matrix_valid[commit_slot] && old_idx_reg != new_idx_reg && dim_count[old_idx_reg] != 0) begin
                dim_count[old_idx_reg] <= dim_count[old_idx_reg] - 1'b1;
                // Move pointer forward if it was pointing here
                if (dim_repl_ptr[old_idx_reg][3:0] == commit_slot) begin
                    dim_repl_ptr[old_idx_reg] <= find_next_same_dim(commit_slot[3:0], old_rows_reg, old_cols_reg);
                end
            end

            // Increment new dimension count on first-time occupancy
            if (!matrix_valid[commit_slot]) begin
                dim_count[new_idx_reg] <= dim_count[new_idx_reg] + 1'b1;
                if (dim_count[new_idx_reg] == 0) begin
                    dim_repl_ptr[new_idx_reg] <= commit_slot[3:0];
                end
            end

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
