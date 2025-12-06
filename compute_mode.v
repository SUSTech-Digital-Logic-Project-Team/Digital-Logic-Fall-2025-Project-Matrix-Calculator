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
    
    // Allocation/Commit Interface
    output reg alloc_req,
    output reg [3:0] alloc_m,
    output reg [3:0] alloc_n,
    input wire [3:0] alloc_slot,
    input wire [ADDR_WIDTH-1:0] alloc_addr,
    input wire alloc_valid,
    
    output reg commit_req,
    output reg [3:0] commit_slot,
    output reg [3:0] commit_m,
    output reg [3:0] commit_n,
    output reg [ADDR_WIDTH-1:0] commit_addr,
    
    // Memory interface
    output reg mem_rd_en,
    output reg [ADDR_WIDTH-1:0] mem_rd_addr,
    input wire [ELEMENT_WIDTH-1:0] mem_rd_data,
    
    output reg mem_wr_en,
    output reg [ADDR_WIDTH-1:0] mem_wr_addr,
    output reg [ELEMENT_WIDTH-1:0] mem_wr_data,
    
    output reg [3:0] error_code,
    output reg [3:0] sub_state,
    
    // Error recovery signal
    input wire timeout_reset
);

// State definitions
localparam IDLE = 4'd0, 
           SELECT_OP = 4'd1,      
           SELECT_MATRIX = 4'd2, 
           READ_OP = 4'd3,
           EXECUTE = 4'd4, 
           SEND_RESULT = 4'd5, 
           DONE = 4'd6;
// Operation
localparam OP_TRANSPOSE = 4'd1,
           OP_ADD = 4'd2,
           OP_SCALAR_MUL = 4'd3,
           OP_MUL = 4'd4,
           OP_CONV = 4'd5;

// Internal button debounce/edge detection (simple version)
reg btn_prev;
wire btn_posedge = btn_confirm && !btn_prev;

// Registers for SELECT_MATRIX logic
reg [5:0] sel_step;
reg [4:0] scan_slot;
reg [3:0] iter_m, iter_n;
reg [7:0] current_count;
reg [3:0] target_m, target_n;
reg [3:0] op1_m, op1_n; // New registers to store Op1 dimensions
reg [3:0] op1_slot, op2_slot;
reg [7:0] scalar_val;
reg [7:0] match_idx;
reg [7:0] user_sel_idx;
reg [3:0] print_r, print_c;
reg [3:0] print_step;
reg [11:0] print_addr;

// Registers for EXECUTE/SEND_RESULT
reg [7:0] res_send_idx;
reg [7:0] read_idx;
reg [3:0] exec_state;
reg [ADDR_WIDTH-1:0] addr_op1_reg, addr_op2_reg, addr_res_reg;
reg [3:0] res_slot;
reg start_op;
wire done_op;

// Operation Modules Signals
wire op_rd_en_add, op_wr_en_add, done_add;
wire [ADDR_WIDTH-1:0] op_rd_addr_add, op_wr_addr_add;
wire [ELEMENT_WIDTH-1:0] op_wr_data_add;

wire op_rd_en_smul, op_wr_en_smul, done_smul;
wire [ADDR_WIDTH-1:0] op_rd_addr_smul, op_wr_addr_smul;
wire [ELEMENT_WIDTH-1:0] op_wr_data_smul;

wire op_rd_en_trans, op_wr_en_trans, done_trans;
wire [ADDR_WIDTH-1:0] op_rd_addr_trans, op_wr_addr_trans;
wire [ELEMENT_WIDTH-1:0] op_wr_data_trans;

wire op_rd_en_mul, op_wr_en_mul, done_mul;
wire [ADDR_WIDTH-1:0] op_rd_addr_mul, op_wr_addr_mul;
wire [ELEMENT_WIDTH-1:0] op_wr_data_mul;

wire op_rd_en_conv, op_wr_en_conv, done_conv;
wire [ADDR_WIDTH-1:0] op_rd_addr_conv, op_wr_addr_conv;
wire [ELEMENT_WIDTH-1:0] op_wr_data_conv;

// Instantiations
matrix_op_add op_add_inst (
    .clk(clk), .rst_n(rst_n), .start(start_op && selected_op_type == OP_ADD), .done(done_add),
    .dim_m(target_m), .dim_n(target_n),
    .addr_op1(addr_op1_reg), .addr_op2(addr_op2_reg), .addr_res(addr_res_reg),
    .mem_rd_en(op_rd_en_add), .mem_rd_addr(op_rd_addr_add), .mem_rd_data(mem_rd_data),
    .mem_wr_en(op_wr_en_add), .mem_wr_addr(op_wr_addr_add), .mem_wr_data(op_wr_data_add)
);

matrix_op_scalar_mul op_smul_inst (
    .clk(clk), .rst_n(rst_n), .start(start_op && selected_op_type == OP_SCALAR_MUL), .done(done_smul),
    .dim_m(target_m), .dim_n(target_n),
    .addr_op1(addr_op1_reg), .scalar_val(scalar_val), .addr_res(addr_res_reg),
    .mem_rd_en(op_rd_en_smul), .mem_rd_addr(op_rd_addr_smul), .mem_rd_data(mem_rd_data),
    .mem_wr_en(op_wr_en_smul), .mem_wr_addr(op_wr_addr_smul), .mem_wr_data(op_wr_data_smul)
);

matrix_op_transpose op_trans_inst (
    .clk(clk), .rst_n(rst_n), .start(start_op && selected_op_type == OP_TRANSPOSE), .done(done_trans),
    .dim_m(target_m), .dim_n(target_n),
    .addr_op1(addr_op1_reg), .addr_res(addr_res_reg),
    .mem_rd_en(op_rd_en_trans), .mem_rd_addr(op_rd_addr_trans), .mem_rd_data(mem_rd_data),
    .mem_wr_en(op_wr_en_trans), .mem_wr_addr(op_wr_addr_trans), .mem_wr_data(op_wr_data_trans)
);

matrix_op_mul op_mul_inst (
    .clk(clk), .rst_n(rst_n), .start(start_op && selected_op_type == OP_MUL), .done(done_mul),
    .dim_m(target_m), .dim_n(target_n), .dim_p(target_n), 
    .addr_op1(addr_op1_reg), .addr_op2(addr_op2_reg), .addr_res(addr_res_reg),
    .mem_rd_en(op_rd_en_mul), .mem_rd_addr(op_rd_addr_mul), .mem_rd_data(mem_rd_data),
    .mem_wr_en(op_wr_en_mul), .mem_wr_addr(op_wr_addr_mul), .mem_wr_data(op_wr_data_mul)
);

matrix_op_conv op_conv_inst (
    .clk(clk), .rst_n(rst_n), .start(start_op && selected_op_type == OP_CONV), .done(done_conv),
    .dim_m(target_m), .dim_n(target_n),
    .addr_op1(addr_op1_reg), .addr_op2(addr_op2_reg), .addr_res(addr_res_reg),
    .mem_rd_en(op_rd_en_conv), .mem_rd_addr(op_rd_addr_conv), .mem_rd_data(mem_rd_data),
    .mem_wr_en(op_wr_en_conv), .mem_wr_addr(op_wr_addr_conv), .mem_wr_data(op_wr_data_conv)
);

assign done_op = done_add | done_smul | done_trans | done_mul | done_conv;

reg internal_rd_en;
reg [ADDR_WIDTH-1:0] internal_rd_addr;

// Final MUX
always @(*) begin
    if (sub_state == EXECUTE) begin
        case (selected_op_type)
            OP_ADD: begin
                mem_rd_en = op_rd_en_add; mem_rd_addr = op_rd_addr_add;
                mem_wr_en = op_wr_en_add; mem_wr_addr = op_wr_addr_add; mem_wr_data = op_wr_data_add;
            end
            OP_SCALAR_MUL: begin
                mem_rd_en = op_rd_en_smul; mem_rd_addr = op_rd_addr_smul;
                mem_wr_en = op_wr_en_smul; mem_wr_addr = op_wr_addr_smul; mem_wr_data = op_wr_data_smul;
            end
            OP_TRANSPOSE: begin
                mem_rd_en = op_rd_en_trans; mem_rd_addr = op_rd_addr_trans;
                mem_wr_en = op_wr_en_trans; mem_wr_addr = op_wr_addr_trans; mem_wr_data = op_wr_data_trans;
            end
            OP_MUL: begin
                mem_rd_en = op_rd_en_mul; mem_rd_addr = op_rd_addr_mul;
                mem_wr_en = op_wr_en_mul; mem_wr_addr = op_wr_addr_mul; mem_wr_data = op_wr_data_mul;
            end
            OP_CONV: begin
                mem_rd_en = op_rd_en_conv; mem_rd_addr = op_rd_addr_conv;
                mem_wr_en = op_wr_en_conv; mem_wr_addr = op_wr_addr_conv; mem_wr_data = op_wr_data_conv;
            end
            default: begin
                mem_rd_en = 0; mem_rd_addr = 0;
                mem_wr_en = 0; mem_wr_addr = 0; mem_wr_data = 0;
            end
        endcase
    end else begin
        mem_rd_en = internal_rd_en;
        mem_rd_addr = internal_rd_addr;
        mem_wr_en = 0;
        mem_wr_addr = 0;
        mem_wr_data = 0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sub_state <= IDLE;
        internal_rd_en <= 1'b0;
        tx_start <= 1'b0;
        btn_prev <= 1'b0;
        alloc_req <= 0;
        commit_req <= 0;
        start_op <= 0;
    end else if (mode_active) begin
        btn_prev <= btn_confirm;
        tx_start <= 1'b0;
        internal_rd_en <= 1'b0;
        alloc_req <= 0;
        commit_req <= 0;
        start_op <= 0;
        
        case (sub_state)
            IDLE: begin
                selected_op_type <= 4'd0;
                error_code <= `ERR_NONE;
                res_send_idx <= 8'd0;
                read_idx <= 8'd0;
                exec_state <= 4'd0;
                sub_state <= SELECT_OP;
            end

            SELECT_OP: begin
                case (dip_sw)
                    3'd1: selected_op_type <= OP_TRANSPOSE;
                    3'd2: selected_op_type <= OP_ADD;
                    3'd3: selected_op_type <= OP_SCALAR_MUL;
                    3'd4: selected_op_type <= OP_MUL;
                    3'd5: selected_op_type <= OP_CONV;
                    default: selected_op_type <= 4'd0;
                endcase

                if (btn_posedge && selected_op_type != 4'd0) begin
                    sub_state <= SELECT_MATRIX;
                    sel_step <= 0;
                end
            end
            
            SELECT_MATRIX: begin
                if (timeout_reset) begin
                    sub_state <= IDLE;
                end else begin
                    case (sel_step)
                        // PHASE 1: STATISTICS
                    5'd0: begin // Init
                        iter_m <= 1;
                        iter_n <= 1;
                        scan_slot <= 0;
                        current_count <= 0;
                        sel_step <= 5'd1;
                    end
                    
                    5'd1: begin // Set query
                        query_slot <= scan_slot[3:0];
                        sel_step <= 5'd2; 
                    end
                    
                    5'd2: begin // Check result
                        if (query_valid && query_m == iter_m && query_n == iter_n)
                            current_count <= current_count + 1;
                            
                        if (scan_slot == 15) begin 
                            if (current_count > 0) sel_step <= 5'd3; 
                            else sel_step <= 5'd4; 
                        end else begin
                            scan_slot <= scan_slot + 1;
                            sel_step <= 5'd1;
                        end
                    end
                    
                    5'd3: begin // Print "M N : C"
                        if (!tx_busy) begin
                            case (print_step)
                                0: begin tx_data <= iter_m + "0"; tx_start <= 1; print_step <= 1; end
                                1: begin tx_data <= 8'h20; tx_start <= 1; print_step <= 2; end
                                2: begin tx_data <= iter_n + "0"; tx_start <= 1; print_step <= 3; end
                                3: begin tx_data <= 8'h20; tx_start <= 1; print_step <= 4; end
                                4: begin tx_data <= ":"; tx_start <= 1; print_step <= 5; end
                                5: begin tx_data <= 8'h20; tx_start <= 1; print_step <= 6; end
                                6: begin tx_data <= current_count + "0"; tx_start <= 1; print_step <= 7; end
                                7: begin tx_data <= 8'h0D; tx_start <= 1; print_step <= 8; end 
                                8: begin tx_data <= 8'h0A; tx_start <= 1; print_step <= 0; sel_step <= 5'd4; end 
                            endcase
                        end
                    end
                    
                    5'd4: begin // Next dim
                        scan_slot <= 0;
                        current_count <= 0;
                        if (iter_n < config_max_dim) begin
                            iter_n <= iter_n + 1;
                            sel_step <= 5'd1;
                        end else if (iter_m < config_max_dim) begin
                            iter_m <= iter_m + 1;
                            iter_n <= 1;
                            sel_step <= 5'd1;
                        end else begin
                            sel_step <= 5'd5; 
                        end
                    end

                    // PHASE 2: INPUT DIMENSIONS
                    5'd5: begin 
                        if (rx_done) begin
                            if (rx_data >= "0" && rx_data <= "9") begin
                                if ((rx_data - "0") > config_max_dim || (rx_data - "0") == 0) begin
                                    error_code <= `ERR_DIM_RANGE;
                                    if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                                end else begin
                                    target_m <= rx_data - "0";
                                    sel_step <= 5'd6;
                                    error_code <= `ERR_NONE;
                                end
                            end else begin
                                error_code <= `ERR_DIM_RANGE;
                                if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                            end
                        end
                    end
                    
                    5'd6: begin 
                        if (rx_done) begin
                            if (rx_data >= "0" && rx_data <= "9") begin
                                if ((rx_data - "0") > config_max_dim || (rx_data - "0") == 0) begin
                                    error_code <= `ERR_DIM_RANGE;
                                    if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                                end else begin
                                    target_n <= rx_data - "0";
                                    sel_step <= 5'd7;
                                    scan_slot <= 0;
                                    match_idx <= 1;
                                    error_code <= `ERR_NONE;
                                end
                            end else begin
                                error_code <= `ERR_DIM_RANGE;
                                if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                            end
                        end
                    end

                    // PHASE 3: LIST MATRICES
                    5'd7: begin 
                        query_slot <= scan_slot[3:0];
                        sel_step <= 5'd8;
                    end
                    
                    5'd8: begin 
                        if (query_valid && query_m == target_m && query_n == target_n) begin
                            print_addr <= query_addr;
                            print_r <= 0;
                            print_c <= 0;
                            sel_step <= 5'd9;
                        end else begin
                            if (scan_slot == 15) sel_step <= 5'd13; 
                            else begin
                                scan_slot <= scan_slot + 1;
                                sel_step <= 5'd7;
                            end
                        end
                    end
                    
                    5'd9: begin // Print Index
                        if (!tx_busy) begin
                            tx_data <= match_idx + "0"; 
                            tx_start <= 1;
                            sel_step <= 5'd21; // Send Newline
                        end
                    end

                    5'd21: begin // Send Newline after Index
                        if (!tx_busy) begin
                            tx_data <= 8'h0D; // CR
                            tx_start <= 1;
                            sel_step <= 5'd23;
                        end
                    end

                    5'd23: begin // Send LF
                        if (!tx_busy) begin
                            tx_data <= 8'h0A; // LF
                            tx_start <= 1;
                            sel_step <= 5'd10;
                        end
                    end
                    
                    5'd10: begin // Print Matrix Content (Read BRAM)
                        internal_rd_en <= 1;
                        internal_rd_addr <= print_addr + (print_r * target_n) + print_c;
                        sel_step <= 5'd11;
                    end
                    
                    5'd11: begin // Wait read
                        sel_step <= 5'd12;
                        print_step <= 0;
                    end
                    
                    5'd12: begin // Send Element
                        if (!tx_busy) begin
                            if (mem_rd_data >= 100) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 100) + "0"; tx_start <= 1; print_step <= 1; end
                                    1: begin tx_data <= ((mem_rd_data % 100) / 10) + "0"; tx_start <= 1; print_step <= 2; end
                                    2: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; print_step <= 0; sel_step <= 5'd22; end
                                endcase
                            end else if (mem_rd_data >= 10) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 10) + "0"; tx_start <= 1; print_step <= 1; end
                                    1: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; print_step <= 0; sel_step <= 5'd22; end
                                endcase
                            end else begin
                                tx_data <= mem_rd_data + "0";
                                tx_start <= 1;
                                sel_step <= 5'd22;
                            end
                        end
                    end

                    5'd22: begin // Check Row End
                        if (print_c == target_n - 1) begin
                             if (!tx_busy) begin
                                 tx_data <= 8'h0D; // CR
                                 tx_start <= 1;
                                 sel_step <= 5'd24;
                             end
                        end else begin
                             if (!tx_busy) begin
                                 tx_data <= " "; // Space between elements
                                 tx_start <= 1;
                                 print_c <= print_c + 1;
                                 sel_step <= 5'd10;
                             end
                        end
                    end

                    5'd24: begin // Send LF
                        if (!tx_busy) begin
                            tx_data <= 8'h0A; // LF
                            tx_start <= 1;
                            print_c <= 0;
                            if (print_r == target_m - 1) begin
                                match_idx <= match_idx + 1;
                                // FIX: Only increment scan_slot if we are done printing this matrix
                                if (scan_slot == 15) sel_step <= 5'd13;
                                else begin
                                    scan_slot <= scan_slot + 1;
                                    sel_step <= 5'd7;
                                end
                            end else begin
                                print_r <= print_r + 1;
                                sel_step <= 5'd10; 
                            end
                        end
                    end

                    // PHASE 4: SELECT OPERANDS
                    5'd13: begin // Wait Selection 1
                        if (rx_done) begin
                            if (rx_data >= "0" && rx_data <= "9") begin
                                user_sel_idx <= rx_data - "0";
                                scan_slot <= 0;
                                match_idx <= 1;
                                sel_step <= 5'd14; 
                                error_code <= `ERR_NONE;
                            end else begin
                                error_code <= `ERR_VALUE_RANGE;
                                if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                            end
                        end
                    end
                    
                    5'd14: begin // Find Slot for Sel 1
                        query_slot <= scan_slot[3:0];
                        sel_step <= 6'd15;
                    end
                    
                    5'd15: begin
                        if (query_valid && query_m == target_m && query_n == target_n) begin
                            if (match_idx == user_sel_idx) begin
                                op1_slot <= scan_slot[3:0];
                                op1_m <= target_m; // Save Op1 dimensions
                                op1_n <= target_n;
                                if (selected_op_type == OP_TRANSPOSE || selected_op_type == OP_SCALAR_MUL) begin
                                    if (selected_op_type == OP_SCALAR_MUL) sel_step <= 6'd43; // Wait RX low then 19
                                    else sel_step <= 6'd25; // Print Op1
                                end else if (selected_op_type == OP_MUL) begin
                                    // For Matrix Mul, we need to select 2nd matrix with potentially different dims
                                    // Reset stats and go to stats phase for 2nd operand
                                    sel_step <= 6'd44; 
                                end else begin
                                    sel_step <= 6'd42; // Wait RX low then 16
                                end
                            end else begin
                                match_idx <= match_idx + 1;
                                if (scan_slot == 15) begin
                                    scan_slot <= 0;
                                    sel_step <= 6'd13;
                                end else begin
                                    scan_slot <= scan_slot + 1;
                                    sel_step <= 6'd14;
                                end
                            end
                        end else begin
                            if (scan_slot == 15) begin
                                // Not found, reset or handle error
                                scan_slot <= 0;
                                sel_step <= 6'd13; // Go back to wait input
                            end else begin
                                scan_slot <= scan_slot + 1;
                                sel_step <= 6'd14;
                            end
                        end
                    end

                    // ==========================================
                    // NEW: Stats & Selection for 2nd Operand (Mul)
                    // ==========================================
                    6'd44: begin // Init Stats for Op2
                        iter_m <= 1;
                        iter_n <= 1;
                        scan_slot <= 0;
                        current_count <= 0;
                        sel_step <= 6'd45;
                    end
                    
                    6'd45: begin // Set query
                        query_slot <= scan_slot[3:0];
                        sel_step <= 6'd46; 
                    end
                    
                    6'd46: begin // Check result
                        if (query_valid && query_m == iter_m && query_n == iter_n)
                            current_count <= current_count + 1;
                            
                        if (scan_slot == 15) begin 
                            if (current_count > 0) sel_step <= 6'd47; 
                            else sel_step <= 6'd48; 
                        end else begin
                            scan_slot <= scan_slot + 1;
                            sel_step <= 6'd45;
                        end
                    end
                    
                    6'd47: begin // Print "M N : C"
                        if (!tx_busy) begin
                            case (print_step)
                                0: begin tx_data <= iter_m + "0"; tx_start <= 1; print_step <= 1; end
                                1: begin tx_data <= 8'h20; tx_start <= 1; print_step <= 2; end
                                2: begin tx_data <= iter_n + "0"; tx_start <= 1; print_step <= 3; end
                                3: begin tx_data <= 8'h20; tx_start <= 1; print_step <= 4; end
                                4: begin tx_data <= ":"; tx_start <= 1; print_step <= 5; end
                                5: begin tx_data <= 8'h20; tx_start <= 1; print_step <= 6; end
                                6: begin tx_data <= current_count + "0"; tx_start <= 1; print_step <= 7; end
                                7: begin tx_data <= 8'h0D; tx_start <= 1; print_step <= 8; end 
                                8: begin tx_data <= 8'h0A; tx_start <= 1; print_step <= 0; sel_step <= 6'd48; end 
                            endcase
                        end
                    end
                    
                    6'd48: begin // Next dim
                        scan_slot <= 0;
                        current_count <= 0;
                        if (iter_n < config_max_dim) begin
                            iter_n <= iter_n + 1;
                            sel_step <= 6'd45;
                        end else if (iter_m < config_max_dim) begin
                            iter_m <= iter_m + 1;
                            iter_n <= 1;
                            sel_step <= 6'd45;
                        end else begin
                            sel_step <= 6'd49; // Wait for Op2 Dims
                        end
                    end

                    6'd49: begin // Wait Op2 M
                        if (rx_done) begin
                            if (rx_data >= "0" && rx_data <= "9") begin
                                // For Mul, Op2 M must match Op1 N (target_n)
                                // But user might input it anyway. We can check or overwrite.
                                // Let's overwrite target_m/n for Op2 selection context
                                // Store Op1 dims if needed? Op1 slot is stored.
                                // target_m <= rx_data - "0"; // User input M
                                // Actually for Mul: Op1 is (M x N), Op2 must be (N x P)
                                // So Op2 M MUST be equal to Op1 N.
                                // We can skip asking for M, or ask and verify.
                                // Let's ask for P (Op2 N).
                                // But to be consistent with UI, maybe ask both?
                                // Let's assume user inputs M then N.
                                if ((rx_data - "0") == target_n) begin
                                    // Valid M for Op2
                                    sel_step <= 6'd50;
                                    error_code <= `ERR_NONE;
                                end else begin
                                    // Invalid M for Mul, maybe error or retry?
                                    // For now, just retry
                                    // sel_step <= 6'd49;
                                    error_code <= `ERR_DIM_RANGE;
                                    if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                                end
                                clear_rx_buffer <= 1;
                            end else begin
                                error_code <= `ERR_DIM_RANGE;
                                if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                            end
                        end
                    end
                    
                    6'd50: begin // Wait Op2 N (P)
                        if (!rx_done) begin // Wait for rx_done to clear from previous step
                             sel_step <= 6'd51;
                        end
                    end

                    6'd51: begin
                        if (rx_done) begin
                            if (rx_data >= "0" && rx_data <= "9") begin
                                if ((rx_data - "0") > config_max_dim || (rx_data - "0") == 0) begin
                                    error_code <= `ERR_DIM_RANGE;
                                    if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                                end else begin
                                    target_m <= target_n; // Op2 M = Op1 N
                                    target_n <= rx_data - "0"; // Op2 N = P
                                    sel_step <= 6'd52;
                                    scan_slot <= 0;
                                    match_idx <= 1;
                                    error_code <= `ERR_NONE;
                                end
                            end else begin
                                error_code <= `ERR_DIM_RANGE;
                                if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                            end
                        end
                    end

                    6'd52: begin // List Matrices for Op2
                        query_slot <= scan_slot[3:0];
                        sel_step <= 6'd53;
                    end
                    
                    6'd53: begin 
                        if (query_valid && query_m == target_m && query_n == target_n) begin
                            print_addr <= query_addr;
                            print_r <= 0;
                            print_c <= 0;
                            sel_step <= 6'd54;
                        end else begin
                            if (scan_slot == 15) sel_step <= 6'd42; // Go to Wait Sel 2 (reusing state 16 via 42)
                            else begin
                                scan_slot <= scan_slot + 1;
                                sel_step <= 6'd52;
                            end
                        end
                    end
                    
                    6'd54: begin // Print Index
                        if (!tx_busy) begin
                            tx_data <= match_idx + "0"; 
                            tx_start <= 1;
                            sel_step <= 6'd55; 
                        end
                    end

                    6'd55: begin // Send Newline after Index
                        if (!tx_busy) begin
                            tx_data <= 8'h0D; // CR
                            tx_start <= 1;
                            sel_step <= 6'd56;
                        end
                    end

                    6'd56: begin // Send LF
                        if (!tx_busy) begin
                            tx_data <= 8'h0A; // LF
                            tx_start <= 1;
                            sel_step <= 6'd57;
                        end
                    end
                    
                    6'd57: begin // Print Matrix Content (Read BRAM)
                        internal_rd_en <= 1;
                        internal_rd_addr <= print_addr + (print_r * target_n) + print_c;
                        sel_step <= 6'd58;
                    end
                    
                    6'd58: begin // Wait read
                        sel_step <= 6'd59;
                        print_step <= 0;
                    end
                    
                    6'd59: begin // Send Element
                        if (!tx_busy) begin
                            if (mem_rd_data >= 100) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 100) + "0"; tx_start <= 1; print_step <= 1; end
                                    1: begin tx_data <= ((mem_rd_data % 100) / 10) + "0"; tx_start <= 1; print_step <= 2; end
                                    2: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; print_step <= 0; sel_step <= 6'd60; end
                                endcase
                            end else if (mem_rd_data >= 10) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 10) + "0"; tx_start <= 1; print_step <= 1; end
                                    1: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; print_step <= 0; sel_step <= 6'd60; end
                                endcase
                            end else begin
                                tx_data <= mem_rd_data + "0";
                                tx_start <= 1;
                                sel_step <= 6'd60;
                            end
                        end
                    end

                    6'd60: begin // Check Row End
                        if (print_c == target_n - 1) begin
                             if (!tx_busy) begin
                                 tx_data <= 8'h0D; // CR
                                 tx_start <= 1;
                                 sel_step <= 6'd61;
                             end
                        end else begin
                             if (!tx_busy) begin
                                 tx_data <= " "; // Space between elements
                                 tx_start <= 1;
                                 print_c <= print_c + 1;
                                 sel_step <= 6'd57;
                             end
                        end
                    end

                    6'd61: begin // Send LF
                        if (!tx_busy) begin
                            tx_data <= 8'h0A; // LF
                            tx_start <= 1;
                            print_c <= 0;
                            if (print_r == target_m - 1) begin
                                match_idx <= match_idx + 1;
                                if (scan_slot == 15) sel_step <= 6'd42; // Go to Wait Sel 2
                                else begin
                                    scan_slot <= scan_slot + 1;
                                    sel_step <= 6'd52;
                                end
                            end else begin
                                print_r <= print_r + 1;
                                sel_step <= 6'd57; 
                            end
                        end
                    end
                    
                    5'd16: begin // Wait Selection 2
                        if (rx_done) begin
                            if (rx_data >= "0" && rx_data <= "9") begin
                                user_sel_idx <= rx_data - "0";
                                scan_slot <= 0;
                                match_idx <= 1;
                                sel_step <= 6'd17;
                                error_code <= `ERR_NONE;
                            end else begin
                                error_code <= `ERR_VALUE_RANGE;
                                if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                            end
                        end
                    end
                    
                    5'd17: begin // Find Slot for Sel 2
                         query_slot <= scan_slot[3:0];
                         sel_step <= 6'd18;
                    end
                    
                    5'd18: begin
                        if (query_valid && query_m == target_m && query_n == target_n) begin
                            if (match_idx == user_sel_idx) begin
                                op2_slot <= scan_slot[3:0];
                                sel_step <= 6'd25; // Print Op1 then Op2
                            end else begin
                                match_idx <= match_idx + 1;
                                if (scan_slot == 15) begin
                                    scan_slot <= 0;
                                    sel_step <= 6'd16;
                                end else begin
                                    scan_slot <= scan_slot + 1;
                                    sel_step <= 6'd17;
                                end
                            end
                        end else begin
                            if (scan_slot == 15) begin
                                scan_slot <= 0;
                                sel_step <= 6'd16; // Go back to wait input 2
                            end else begin
                                scan_slot <= scan_slot + 1;
                                sel_step <= 6'd17;
                            end
                        end
                    end
                    
                    5'd19: begin // Wait Scalar
                        if (rx_done) begin
                            if (rx_data >= "0" && rx_data <= "9") begin
                                scalar_val <= rx_data - "0";
                                sel_step <= 6'd25; // Print Op1 then Scalar
                                error_code <= `ERR_NONE;
                            end else begin
                                error_code <= `ERR_VALUE_RANGE;
                                if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                            end
                        end
                    end
                    
                    5'd20: begin // Confirm
                        if (btn_posedge) begin
                            sub_state <= EXECUTE;
                            exec_state <= 0;
                        end
                    end

                    // ==========================================
                    // NEW: Print Selected Operands Sequence
                    // ==========================================
                    
                    // --- Print Op1 ---
                    6'd25: begin 
                        query_slot <= op1_slot;
                        sel_step <= 6'd26;
                    end
                    
                    6'd26: begin
                        print_addr <= query_addr;
                        print_r <= 0;
                        print_c <= 0;
                        sel_step <= 6'd27;
                    end
                    
                    6'd27: begin // Read BRAM
                        internal_rd_en <= 1;
                        internal_rd_addr <= print_addr + (print_r * op1_n) + print_c;
                        sel_step <= 6'd28;
                    end
                    
                    6'd28: begin // Wait read
                        sel_step <= 6'd29;
                        print_step <= 0;
                    end
                    
                    6'd29: begin // Send Element
                        if (!tx_busy) begin
                            if (mem_rd_data >= 100) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 100) + "0"; tx_start <= 1; print_step <= 1; end
                                    1: begin tx_data <= ((mem_rd_data % 100) / 10) + "0"; tx_start <= 1; print_step <= 2; end
                                    2: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; print_step <= 0; sel_step <= 6'd30; end
                                endcase
                            end else if (mem_rd_data >= 10) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 10) + "0"; tx_start <= 1; print_step <= 1; end
                                    1: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; print_step <= 0; sel_step <= 6'd30; end
                                endcase
                            end else begin
                                tx_data <= mem_rd_data + "0";
                                tx_start <= 1;
                                sel_step <= 6'd30;
                            end
                        end
                    end

                    6'd30: begin // Check Row End
                        if (print_c == op1_n - 1) begin
                             if (!tx_busy) begin
                                 tx_data <= 8'h0D; // CR
                                 tx_start <= 1;
                                 sel_step <= 6'd31;
                             end
                        end else begin
                             if (!tx_busy) begin
                                 tx_data <= " "; // Space
                                 tx_start <= 1;
                                 print_c <= print_c + 1;
                                 sel_step <= 6'd27;
                             end
                        end
                    end

                    6'd31: begin // Send LF
                        if (!tx_busy) begin
                            tx_data <= 8'h0A; // LF
                            tx_start <= 1;
                            print_c <= 0;
                            if (print_r == op1_m - 1) begin
                                // Op1 Done. Next?
                                if (selected_op_type == OP_TRANSPOSE) sel_step <= 6'd20;
                                else if (selected_op_type == OP_SCALAR_MUL) sel_step <= 6'd39;
                                else sel_step <= 6'd32; // Print Op2
                            end else begin
                                print_r <= print_r + 1;
                                sel_step <= 6'd27; 
                            end
                        end
                    end

                    // --- Print Op2 ---
                    6'd32: begin 
                        query_slot <= op2_slot;
                        sel_step <= 6'd33;
                    end
                    
                    6'd33: begin
                        print_addr <= query_addr;
                        print_r <= 0;
                        print_c <= 0;
                        sel_step <= 6'd34;
                    end
                    
                    6'd34: begin // Read BRAM
                        internal_rd_en <= 1;
                        internal_rd_addr <= print_addr + (print_r * target_n) + print_c;
                        sel_step <= 6'd35;
                    end
                    
                    6'd35: begin // Wait read
                        sel_step <= 6'd36;
                        print_step <= 0;
                    end
                    
                    6'd36: begin // Send Element
                        if (!tx_busy) begin
                            if (mem_rd_data >= 100) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 100) + "0"; tx_start <= 1; print_step <= 1; end
                                    1: begin tx_data <= ((mem_rd_data % 100) / 10) + "0"; tx_start <= 1; print_step <= 2; end
                                    2: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; print_step <= 0; sel_step <= 6'd37; end
                                endcase
                            end else if (mem_rd_data >= 10) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 10) + "0"; tx_start <= 1; print_step <= 1; end
                                    1: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; print_step <= 0; sel_step <= 6'd37; end
                                endcase
                            end else begin
                                tx_data <= mem_rd_data + "0";
                                tx_start <= 1;
                                sel_step <= 6'd37;
                            end
                        end
                    end

                    6'd37: begin // Check Row End
                        if (print_c == target_n - 1) begin
                             if (!tx_busy) begin
                                 tx_data <= 8'h0D; // CR
                                 tx_start <= 1;
                                 sel_step <= 6'd38;
                             end
                        end else begin
                             if (!tx_busy) begin
                                 tx_data <= " "; // Space
                                 tx_start <= 1;
                                 print_c <= print_c + 1;
                                 sel_step <= 6'd34;
                             end
                        end
                    end

                    6'd38: begin // Send LF
                        if (!tx_busy) begin
                            tx_data <= 8'h0A; // LF
                            tx_start <= 1;
                            print_c <= 0;
                            if (print_r == target_m - 1) begin
                                // Op2 Done.
                                sel_step <= 6'd20;
                            end else begin
                                print_r <= print_r + 1;
                                sel_step <= 6'd34; 
                            end
                        end
                    end

                    // --- Print Scalar ---
                    6'd39: begin 
                        if (!tx_busy) begin
                            tx_data <= scalar_val + "0";
                            tx_start <= 1;
                            sel_step <= 6'd40;
                        end
                    end
                    
                    6'd40: begin
                        if (!tx_busy) begin
                            tx_data <= 8'h0D;
                            tx_start <= 1;
                            sel_step <= 6'd41;
                        end
                    end
                    
                    6'd41: begin
                        if (!tx_busy) begin
                            tx_data <= 8'h0A;
                            tx_start <= 1;
                            sel_step <= 6'd20;
                        end
                    end

                    // ==========================================
                    // NEW: Wait for RX Done to Clear (Debounce)
                    // ==========================================
                    6'd42: begin // Wait for !rx_done before Op2
                        if (!rx_done) sel_step <= 6'd16;
                    end

                    6'd43: begin // Wait for !rx_done before Scalar
                        if (!rx_done) sel_step <= 6'd19;
                    end
                    
                endcase
                end
            end

            EXECUTE: begin
                case (exec_state)
                    0: begin // Get Op1 Addr
                        query_slot <= op1_slot;
                        exec_state <= 1;
                    end
                    1: begin
                        addr_op1_reg <= query_addr;
                        if (selected_op_type != OP_TRANSPOSE && selected_op_type != OP_SCALAR_MUL) begin
                            exec_state <= 2;
                        end else begin
                            exec_state <= 4; 
                        end
                    end
                    2: begin // Get Op2 Addr
                        query_slot <= op2_slot;
                        exec_state <= 3;
                    end
                    3: begin
                        addr_op2_reg <= query_addr;
                        exec_state <= 4;
                    end
                    4: begin // Alloc Result
                        alloc_req <= 1;
                        if (selected_op_type == OP_TRANSPOSE) begin
                            alloc_m <= target_n;
                            alloc_n <= target_m;
                        end else begin
                            alloc_m <= target_m;
                            alloc_n <= target_n;
                        end
                        exec_state <= 5;
                    end
                    5: begin
                        if (alloc_valid) begin
                            alloc_req <= 0;
                            res_slot <= alloc_slot;
                            addr_res_reg <= alloc_addr;
                            exec_state <= 6;
                        end
                    end
                    6: begin // Start Op
                        start_op <= 1;
                        exec_state <= 7;
                    end
                    7: begin
                        start_op <= 0;
                        if (done_op) exec_state <= 8;
                    end
                    8: begin // Commit
                        commit_req <= 1;
                        commit_slot <= res_slot;
                        if (selected_op_type == OP_TRANSPOSE) begin
                            commit_m <= target_n;
                            commit_n <= target_m;
                        end else begin
                            commit_m <= target_m;
                            commit_n <= target_n;
                        end
                        commit_addr <= addr_res_reg;
                        exec_state <= 9;
                    end
                    9: begin
                        commit_req <= 0;
                        // Prepare for printing result
                        print_addr <= addr_res_reg;
                        print_r <= 0;
                        print_c <= 0;
                        
                        // Set dimensions for printing
                        if (selected_op_type == OP_TRANSPOSE) begin
                            iter_m <= target_n; 
                            iter_n <= target_m; 
                        end else begin
                            iter_m <= target_m;
                            iter_n <= target_n;
                        end
                        
                        res_send_idx <= 0;
                        sub_state <= SEND_RESULT;
                    end
                endcase
            end

            SEND_RESULT: begin
                case (res_send_idx)
                    0: begin // Send Result Slot
                        if (!tx_busy) begin
                            tx_data <= res_slot + "0"; 
                            tx_start <= 1;
                            res_send_idx <= 1;
                        end
                    end
                    1: begin // Send CR
                         if (!tx_busy) begin
                            tx_data <= 8'h0D; 
                            tx_start <= 1;
                            res_send_idx <= 7;
                        end
                    end
                    7: begin // Send LF
                         if (!tx_busy) begin
                            tx_data <= 8'h0A; 
                            tx_start <= 1;
                            res_send_idx <= 2;
                        end
                    end
                    2: begin // Read BRAM
                        internal_rd_en <= 1;
                        internal_rd_addr <= print_addr + (print_r * iter_n) + print_c;
                        res_send_idx <= 3;
                    end
                    3: begin // Wait for Read
                        internal_rd_en <= 0;
                        res_send_idx <= 4;
                        print_step <= 0;
                    end
                    4: begin // Send Data
                        if (!tx_busy) begin
                            if (mem_rd_data >= 100) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 100) + "0"; tx_start <= 1; print_step <= 1; end
                                    1: begin tx_data <= ((mem_rd_data % 100) / 10) + "0"; tx_start <= 1; print_step <= 2; end
                                    2: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; print_step <= 0; res_send_idx <= 6; end
                                endcase
                            end else if (mem_rd_data >= 10) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 10) + "0"; tx_start <= 1; print_step <= 1; end
                                    1: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; print_step <= 0; res_send_idx <= 6; end
                                endcase
                            end else begin
                                tx_data <= mem_rd_data + "0";
                                tx_start <= 1;
                                res_send_idx <= 6;
                            end
                        end
                    end
                    6: begin // Check Row End
                        if (print_c == iter_n - 1) begin
                            if (!tx_busy) begin
                                tx_data <= 8'h0D; // CR
                                tx_start <= 1;
                                res_send_idx <= 8;
                            end
                        end else begin
                            if (!tx_busy) begin
                                tx_data <= " "; // Space
                                tx_start <= 1;
                                print_c <= print_c + 1;
                                res_send_idx <= 2; 
                            end
                        end
                    end
                    8: begin // Send LF
                        if (!tx_busy) begin
                            tx_data <= 8'h0A; // LF
                            tx_start <= 1;
                            print_c <= 0;
                            if (print_r == iter_m - 1) begin
                                res_send_idx <= 5; 
                            end else begin
                                print_r <= print_r + 1;
                                res_send_idx <= 2; 
                            end
                        end
                    end
                    5: begin // Done
                        sub_state <= DONE;
                    end
                endcase
            end

            DONE: begin
                 if (btn_posedge) sub_state <= IDLE;
            end

            default: sub_state <= IDLE;
        endcase
    end else begin
        sub_state <= IDLE;
        btn_prev <= btn_confirm;
    end
end

endmodule