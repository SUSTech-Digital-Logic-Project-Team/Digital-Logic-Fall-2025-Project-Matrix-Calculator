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
    input wire [4:0] config_max_dim,    // Extended to 5 bits

    // DIP switches and buttons
    input wire [2:0] dip_sw,
    input wire btn_confirm,
    input wire btn_back,
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
    input wire [4:0] query_m,           // Extended to 5 bits
    input wire [4:0] query_n,           // Extended to 5 bits
    input wire [ADDR_WIDTH-1:0] query_addr,
    input wire [7:0] query_element_count,
    
    // Allocation/Commit Interface
    output reg alloc_req,
    output reg [4:0] alloc_m,           // Extended to 5 bits
    output reg [4:0] alloc_n,           // Extended to 5 bits
    input wire [3:0] alloc_slot,
    input wire [ADDR_WIDTH-1:0] alloc_addr,
    input wire alloc_valid,
    
    output reg commit_req,
    output reg [3:0] commit_slot,
    output reg [4:0] commit_m,          // Extended to 5 bits
    output reg [4:0] commit_n,          // Extended to 5 bits
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
    input wire timeout_reset,

    // Random Choosing 
    input wire [1:0] random_number
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
reg [6:0] sel_step;
reg [4:0] scan_slot;
reg [4:0] iter_m, iter_n;     // Extended to 5 bits
reg [7:0] current_count;
reg [4:0] target_m, target_n; // Extended to 5 bits
reg [4:0] op1_m, op1_n;       // Extended to 5 bits
reg [3:0] op1_slot, op2_slot;
reg [7:0] scalar_val;
reg [7:0] match_idx;
reg [7:0] user_sel_idx;
reg [4:0] print_r, print_c;   // Extended to 5 bits for dimensions up to 16
reg [7:0] input_accum; // Accumulator for multi-digit input
reg [3:0] print_step;
reg [11:0] print_addr;
reg tx_pending; // Flag to prevent double-sending before tx_busy goes high

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

wire [4:0] conv_out_m = (op1_m > 5'd2) ? (op1_m - 5'd2) : 5'd0;
wire [4:0] conv_out_n = (op1_n > 5'd2) ? (op1_n - 5'd2) : 5'd0;

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
    .dim_m(op1_m), .dim_n(target_n), .dim_p(op1_n), 
    .addr_op1(addr_op1_reg), .addr_op2(addr_op2_reg), .addr_res(addr_res_reg),
    .mem_rd_en(op_rd_en_mul), .mem_rd_addr(op_rd_addr_mul), .mem_rd_data(mem_rd_data),
    .mem_wr_en(op_wr_en_mul), .mem_wr_addr(op_wr_addr_mul), .mem_wr_data(op_wr_data_mul)
);

matrix_op_conv op_conv_inst (
    .clk(clk), .rst_n(rst_n), .start(start_op && selected_op_type == OP_CONV), .done(done_conv),
    .dim_m(op1_m), .dim_n(op1_n),
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
        tx_pending <= 1'b0;
    end else if (mode_active) begin
        btn_prev <= btn_confirm;
        tx_start <= 1'b0;
        internal_rd_en <= 1'b0;
        // Clear tx_pending when tx_busy goes high (UART acknowledged)
        if (tx_busy) tx_pending <= 1'b0;
        alloc_req <= 0;
        commit_req <= 0;
        start_op <= 0;
        
        // Handle external "back" button: return to operation selection
        if (btn_back) begin
            selected_op_type <= 4'd0;
            error_code <= `ERR_NONE;
            res_send_idx <= 8'd0;
            read_idx <= 8'd0;
            exec_state <= 4'd0;
            sel_step <= 0;
            scan_slot <= 0;
            current_count <= 0;
            input_accum <= 0;
            start_op <= 1'b0;
            tx_pending <= 1'b0;
            alloc_req <= 0;
            commit_req <= 0;
            sub_state <= SELECT_OP;
        end else begin
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
                    5'd0: begin // Init and print total count first
                        iter_m <= 1;
                        iter_n <= 1;
                        scan_slot <= 0;
                        current_count <= 0;
                        input_accum <= 0;
                        if (!tx_busy && !tx_pending) begin
                            case (print_step)
                                0: begin
                                    if (total_matrix_count >= 100) begin
                                        tx_data <= (total_matrix_count / 100) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 1;
                                    end else begin
                                        print_step <= 1;
                                    end
                                end
                                1: begin
                                    if (total_matrix_count >= 10) begin
                                        tx_data <= ((total_matrix_count / 10) % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 2;
                                    end else begin
                                        print_step <= 2;
                                    end
                                end
                                2: begin
                                    tx_data <= (total_matrix_count % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 3;
                                end
                                3: begin
                                    tx_data <= 8'h20; tx_start <= 1; tx_pending <= 1; print_step <= 4;
                                end
                                4: begin
                                    print_step <= 0;
                                    sel_step <= 5'd1;
                                end
                            endcase
                        end
                    end
                    
                    5'd1: begin // Set query
                        query_slot <= scan_slot[3:0];
                        sel_step <= 5'd2; 
                    end
                    
                    5'd2: begin // Check result
                        if (query_valid && query_m == iter_m && query_n == iter_n)
                            current_count <= current_count + 1;
                            
                        if (scan_slot == 15) begin 
                            if (current_count > 0) begin
                                sel_step <= 5'd3;
                                print_step <= 0; // Reset print_step before printing
                            end else begin
                                sel_step <= 5'd4;
                            end
                        end else begin
                            scan_slot <= scan_slot + 1;
                            sel_step <= 5'd1;
                        end
                    end
                    
                    5'd3: begin // Print "M*N*Count" appended to the same line
                        if (!tx_busy && !tx_pending) begin
                            case (print_step)
                                0: begin
                                    if (iter_m >= 10) begin
                                        tx_data <= (iter_m / 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 1;
                                    end else begin
                                        tx_data <= iter_m + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 2;
                                    end
                                end
                                1: begin
                                    tx_data <= (iter_m % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 2;
                                end
                                2: begin tx_data <= "*"; tx_start <= 1; tx_pending <= 1; print_step <= 3; end
                                
                                3: begin
                                    if (iter_n >= 10) begin
                                        tx_data <= (iter_n / 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 4;
                                    end else begin
                                        tx_data <= iter_n + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 5;
                                    end
                                end
                                4: begin tx_data <= (iter_n % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 5; end
                                5: begin tx_data <= "*"; tx_start <= 1; tx_pending <= 1; print_step <= 6; end

                                6: begin
                                    if (current_count >= 100) begin
                                        tx_data <= (current_count / 100) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 7;
                                    end else if (current_count >= 10) begin
                                        tx_data <= (current_count / 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 8;
                                    end else begin
                                        tx_data <= current_count + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 9;
                                    end
                                end
                                7: begin tx_data <= ((current_count / 10) % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 8; end
                                8: begin tx_data <= (current_count % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 9; end

                                9: begin
                                    tx_data <= 8'h20; // trailing space
                                    tx_start <= 1; tx_pending <= 1; print_step <= 0; sel_step <= 5'd4;
                                end
                            endcase
                        end
                    end
                    
                    5'd4: begin // Next dim
                        scan_slot <= 0;
                        current_count <= 0;
                        print_step <= 0;
                        if (iter_n < config_max_dim) begin
                            iter_n <= iter_n + 1;
                            sel_step <= 5'd1;
                        end else if (iter_m < config_max_dim) begin
                            iter_m <= iter_m + 1;
                            iter_n <= 1;
                            sel_step <= 5'd1;
                        end else begin
                            sel_step <= 7'd80; // Finish stats line
                            input_accum <= 0;
                        end
                    end
                    
                    7'd80: begin // Send newline after stats line
                        if (!tx_busy && !tx_pending) begin
                            case (print_step)
                                0: begin tx_data <= 8'h0D; tx_start <= 1; tx_pending <= 1; print_step <= 1; end
                                1: begin tx_data <= 8'h0A; tx_start <= 1; tx_pending <= 1; print_step <= 2; end
                                2: begin print_step <= 0; sel_step <= 5'd5; end
                            endcase
                        end
                    end

                    // PHASE 2: INPUT DIMENSIONS
                    5'd5: begin 
                        if (rx_done) begin
                            if (rx_data >= "0" && rx_data <= "9") begin
                                if (input_accum * 10 + (rx_data - "0") <= config_max_dim) begin
                                    input_accum <= input_accum * 10 + (rx_data - "0");
                                end else begin
                                    error_code <= `ERR_DIM_RANGE;
                                    if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                                    input_accum <= 0;
                                end
                            end else if (rx_data == 8'h20) begin // Space
                                if (input_accum > 0 && input_accum <= config_max_dim) begin
                                    target_m <= input_accum[3:0];
                                    sel_step <= 5'd6;
                                    input_accum <= 0;
                                    error_code <= `ERR_NONE;
                                end else begin
                                    error_code <= `ERR_DIM_RANGE;
                                    if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                                    input_accum <= 0;
                                end
                            end
                        end
                    end
                    
                    5'd6: begin 
                        if (rx_done) begin
                            if (rx_data >= "0" && rx_data <= "9") begin
                                if (input_accum * 10 + (rx_data - "0") <= config_max_dim) begin
                                    input_accum <= input_accum * 10 + (rx_data - "0");
                                end else begin
                                    error_code <= `ERR_DIM_RANGE;
                                    if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                                    input_accum <= 0;
                                end
                            end else if (rx_data == 8'h20) begin // Space
                                if (input_accum > 0 && input_accum <= config_max_dim) begin
                                    target_n <= input_accum[3:0];
                                    sel_step <= 5'd7;
                                    scan_slot <= 0;
                                    match_idx <= 1;
                                    input_accum <= 0;
                                    error_code <= `ERR_NONE;
                                end else begin
                                    error_code <= `ERR_DIM_RANGE;
                                    if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                                    input_accum <= 0;
                                end
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
                        if (!tx_busy && !tx_pending) begin
                            tx_data <= match_idx + "0"; 
                            tx_start <= 1;
                            tx_pending <= 1;
                            sel_step <= 5'd21; // Send Newline
                        end
                    end

                    5'd21: begin // Send Newline after Index
                        if (!tx_busy && !tx_pending) begin
                            tx_data <= 8'h0D; // CR
                            tx_start <= 1;
                            tx_pending <= 1;
                            sel_step <= 5'd23;
                        end
                    end

                    5'd23: begin // Send LF
                        if (!tx_busy && !tx_pending) begin
                            tx_data <= 8'h0A; // LF
                            tx_start <= 1;
                            tx_pending <= 1;
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
                        if (!tx_busy && !tx_pending) begin
                            if (mem_rd_data >= 100) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 100) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 1; end
                                    1: begin tx_data <= ((mem_rd_data % 100) / 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 2; end
                                    2: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 0; sel_step <= 5'd22; end
                                endcase
                            end else if (mem_rd_data >= 10) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 1; end
                                    1: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 0; sel_step <= 5'd22; end
                                endcase
                            end else begin
                                tx_data <= mem_rd_data + "0";
                                tx_start <= 1;
                                tx_pending <= 1;
                                sel_step <= 5'd22;
                            end
                        end
                    end

                    5'd22: begin // Check Row End
                        if (print_c == target_n - 1) begin
                             if (!tx_busy && !tx_pending) begin
                                 tx_data <= 8'h0D; // CR
                                 tx_start <= 1;
                                 tx_pending <= 1;
                                 sel_step <= 5'd24;
                             end
                        end else begin
                             if (!tx_busy && !tx_pending) begin
                                 tx_data <= 8'h20; // Space between elements
                                 tx_start <= 1;
                                 tx_pending <= 1;
                                 print_c <= print_c + 1;
                                 sel_step <= 5'd10;
                             end
                        end
                    end

                    5'd24: begin // Send LF
                        if (!tx_busy && !tx_pending) begin
                            tx_data <= 8'h0A; // LF
                            tx_start <= 1;
                            tx_pending <= 1;
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
                            end else if (rx_data == "R") begin
                                user_sel_idx <= random_number + 1; // Random index between 1-4
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
                                end else if (selected_op_type == OP_ADD) begin
                                    // For Add, 2nd operand has same dims as 1st
                                    // Go to list matrices for Op2 selection
                                    scan_slot <= 0;
                                    match_idx <= 1;
                                    sel_step <= 7'd62; // New state: list matrices for Add Op2
                                end else if (selected_op_type == OP_CONV) begin
                                    // For Convolution, kernel is fixed 3x3
                                    // Wait for rx_done to clear, then go to select kernel
                                    sel_step <= 7'd70;
                                end else begin
                                    // Default case (should not reach here)
                                    sel_step <= 6'd16; 
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
                    6'd44: begin // Init Stats for Op2 and print total count line header
                        iter_m <= 1;
                        iter_n <= 1;
                        scan_slot <= 0;
                        current_count <= 0;
                        if (!tx_busy && !tx_pending) begin
                            case (print_step)
                                0: begin
                                    if (total_matrix_count >= 100) begin
                                        tx_data <= (total_matrix_count / 100) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 1;
                                    end else begin
                                        print_step <= 1;
                                    end
                                end
                                1: begin
                                    if (total_matrix_count >= 10) begin
                                        tx_data <= ((total_matrix_count / 10) % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 2;
                                    end else begin
                                        print_step <= 2;
                                    end
                                end
                                2: begin
                                    tx_data <= (total_matrix_count % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 3;
                                end
                                3: begin
                                    tx_data <= 8'h20; tx_start <= 1; tx_pending <= 1; print_step <= 4;
                                end
                                4: begin
                                    print_step <= 0;
                                    sel_step <= 6'd45;
                                end
                            endcase
                        end
                    end
                    
                    6'd45: begin // Set query
                        query_slot <= scan_slot[3:0];
                        sel_step <= 6'd46; 
                    end
                    
                    6'd46: begin // Check result
                        if (query_valid && query_m == iter_m && query_n == iter_n)
                            current_count <= current_count + 1;
                            
                        if (scan_slot == 15) begin 
                            if (current_count > 0) begin
                                sel_step <= 6'd47;
                                print_step <= 0; // Reset print_step before printing
                            end else begin
                                sel_step <= 6'd48;
                            end
                        end else begin
                            scan_slot <= scan_slot + 1;
                            sel_step <= 6'd45;
                        end
                    end
                    
                    6'd47: begin // Print "M*N*Count" appended to the same line (Op2 stats)
                        if (!tx_busy && !tx_pending) begin
                            case (print_step)
                                0: begin
                                    if (iter_m >= 10) begin
                                        tx_data <= (iter_m / 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 1;
                                    end else begin
                                        tx_data <= iter_m + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 2;
                                    end
                                end
                                1: begin tx_data <= (iter_m % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 2; end
                                2: begin tx_data <= "*"; tx_start <= 1; tx_pending <= 1; print_step <= 3; end

                                3: begin
                                    if (iter_n >= 10) begin
                                        tx_data <= (iter_n / 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 4;
                                    end else begin
                                        tx_data <= iter_n + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 5;
                                    end
                                end
                                4: begin tx_data <= (iter_n % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 5; end
                                5: begin tx_data <= "*"; tx_start <= 1; tx_pending <= 1; print_step <= 6; end

                                6: begin
                                    if (current_count >= 100) begin
                                        tx_data <= (current_count / 100) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 7;
                                    end else if (current_count >= 10) begin
                                        tx_data <= (current_count / 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 8;
                                    end else begin
                                        tx_data <= current_count + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 9;
                                    end
                                end
                                7: begin tx_data <= ((current_count / 10) % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 8; end
                                8: begin tx_data <= (current_count % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 9; end

                                9: begin
                                    tx_data <= 8'h20; // trailing space
                                    tx_start <= 1; tx_pending <= 1; print_step <= 0; sel_step <= 6'd48;
                                end
                            endcase
                        end
                    end
                    
                    6'd48: begin // Next dim
                        scan_slot <= 0;
                        current_count <= 0;
                        print_step <= 0;
                        if (iter_n < config_max_dim) begin
                            iter_n <= iter_n + 1;
                            sel_step <= 6'd45;
                        end else if (iter_m < config_max_dim) begin
                            iter_m <= iter_m + 1;
                            iter_n <= 1;
                            sel_step <= 6'd45;
                        end else begin
                            sel_step <= 7'd81; // Finish stats line for Op2
                            input_accum <= 0;
                        end
                    end
                    
                    7'd81: begin // Send newline after Op2 stats line
                        if (!tx_busy && !tx_pending) begin
                            case (print_step)
                                0: begin tx_data <= 8'h0D; tx_start <= 1; tx_pending <= 1; print_step <= 1; end
                                1: begin tx_data <= 8'h0A; tx_start <= 1; tx_pending <= 1; print_step <= 2; end
                                2: begin print_step <= 0; sel_step <= 6'd49; end
                            endcase
                        end
                    end

                    6'd49: begin // Wait Op2 M
                        if (rx_done) begin
                            if (rx_data >= "0" && rx_data <= "9") begin
                                if (input_accum * 10 + (rx_data - "0") <= config_max_dim) begin
                                    input_accum <= input_accum * 10 + (rx_data - "0");
                                end else begin
                                    error_code <= `ERR_DIM_RANGE;
                                    if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                                    input_accum <= 0;
                                end
                            end else if (rx_data == 8'h20) begin // Space
                                if (input_accum == target_n) begin
                                    // Valid M for Op2
                                    sel_step <= 6'd50;
                                    error_code <= `ERR_NONE;
                                    input_accum <= 0;
                                end else begin
                                    error_code <= `ERR_DIM_RANGE;
                                    if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                                    input_accum <= 0;
                                end
                                clear_rx_buffer <= 1;
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
                                if (input_accum * 10 + (rx_data - "0") <= config_max_dim) begin
                                    input_accum <= input_accum * 10 + (rx_data - "0");
                                end else begin
                                    error_code <= `ERR_DIM_RANGE;
                                    if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                                    input_accum <= 0;
                                end
                            end else if (rx_data == 8'h20) begin // Space
                                if (input_accum > 0 && input_accum <= config_max_dim) begin
                                    target_m <= target_n; // Op2 M = Op1 N
                                    target_n <= input_accum[3:0]; // Op2 N = P
                                    sel_step <= 6'd52;
                                    scan_slot <= 0;
                                    match_idx <= 1;
                                    input_accum <= 0;
                                    error_code <= `ERR_NONE;
                                end else begin
                                    error_code <= `ERR_DIM_RANGE;
                                    if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                                    input_accum <= 0;
                                end
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
                            if (scan_slot == 15) sel_step <= 7'd85; // Wait for rx_done to clear before Sel 2
                            else begin
                                scan_slot <= scan_slot + 1;
                                sel_step <= 6'd52;
                            end
                        end
                    end
                    
                    6'd54: begin // Print Index
                        if (!tx_busy && !tx_pending) begin
                            tx_data <= match_idx + "0"; 
                            tx_start <= 1;
                            tx_pending <= 1;
                            sel_step <= 6'd55; 
                        end
                    end

                    6'd55: begin // Send Newline after Index
                        if (!tx_busy && !tx_pending) begin
                            tx_data <= 8'h0D; // CR
                            tx_start <= 1;
                            tx_pending <= 1;
                            sel_step <= 6'd56;
                        end
                    end

                    6'd56: begin // Send LF
                        if (!tx_busy && !tx_pending) begin
                            tx_data <= 8'h0A; // LF
                            tx_start <= 1;
                            tx_pending <= 1;
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
                        if (!tx_busy && !tx_pending) begin
                            if (mem_rd_data >= 100) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 100) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 1; end
                                    1: begin tx_data <= ((mem_rd_data % 100) / 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 2; end
                                    2: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 0; sel_step <= 6'd60; end
                                endcase
                            end else if (mem_rd_data >= 10) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 1; end
                                    1: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 0; sel_step <= 6'd60; end
                                endcase
                            end else begin
                                tx_data <= mem_rd_data + "0";
                                tx_start <= 1;
                                tx_pending <= 1;
                                sel_step <= 6'd60;
                            end
                        end
                    end

                    6'd60: begin // Check Row End
                        if (print_c == target_n - 1) begin
                             if (!tx_busy && !tx_pending) begin
                                 tx_data <= 8'h0D; // CR
                                 tx_start <= 1;
                                 tx_pending <= 1;
                                 sel_step <= 6'd61;
                             end
                        end else begin
                             if (!tx_busy && !tx_pending) begin
                                 tx_data <= " "; // Space between elements
                                 tx_start <= 1;
                                 tx_pending <= 1;
                                 print_c <= print_c + 1;
                                 sel_step <= 6'd57;
                             end
                        end
                    end

                    6'd61: begin // Send LF
                        if (!tx_busy && !tx_pending) begin
                            tx_data <= 8'h0A; // LF
                            tx_start <= 1;
                            tx_pending <= 1;
                            print_c <= 0;
                            if (print_r == target_m - 1) begin
                                match_idx <= match_idx + 1;
                                if (scan_slot == 15) sel_step <= 7'd85; // Wait for rx_done to clear
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

                    7'd85: begin // Wait for rx_done to clear before Wait Sel 2 (Mul Op2)
                        if (!rx_done) sel_step <= 6'd16;
                    end
                    
                    5'd16: begin // Wait Selection 2
                        if (rx_done) begin
                            if (rx_data >= "0" && rx_data <= "9") begin
                                user_sel_idx <= rx_data - "0";
                                scan_slot <= 0;
                                match_idx <= 1;
                                sel_step <= 6'd17;
                                error_code <= `ERR_NONE;
                            end else if (rx_data == "R") begin
                                user_sel_idx <= random_number + 1; // Random index between 1-4
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
                        // For add: same dims as target_m/target_n; for mul: rows must equal op1_n, cols must equal target_n.
                        if (query_valid && ((selected_op_type == OP_ADD && query_m == target_m && query_n == target_n) ||
                                            (selected_op_type == OP_MUL && query_m == op1_n && query_n == target_n))) begin
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

                    // ==========================================
                    // NEW: List Matrices for Add Op2 (same dims as Op1)
                    // ==========================================
                    7'd62: begin // List Matrices for Add Op2
                        query_slot <= scan_slot[3:0];
                        sel_step <= 7'd63;
                    end
                    
                    7'd63: begin 
                        if (query_valid && query_m == target_m && query_n == target_n) begin
                            print_addr <= query_addr;
                            print_r <= 0;
                            print_c <= 0;
                            sel_step <= 7'd64;
                        end else begin
                            if (scan_slot == 15) sel_step <= 7'd84; // Wait for rx_done to clear
                            else begin
                                scan_slot <= scan_slot + 1;
                                sel_step <= 7'd62;
                            end
                        end
                    end
                    
                    7'd64: begin // Print Index
                        if (!tx_busy && !tx_pending) begin
                            tx_data <= match_idx + "0"; 
                            tx_start <= 1;
                            tx_pending <= 1;
                            sel_step <= 7'd65; 
                        end
                    end

                    7'd65: begin // Send CR after Index
                        if (!tx_busy && !tx_pending) begin
                            tx_data <= 8'h0D; // CR
                            tx_start <= 1;
                            tx_pending <= 1;
                            sel_step <= 7'd66;
                        end
                    end

                    7'd66: begin // Send LF
                        if (!tx_busy && !tx_pending) begin
                            tx_data <= 8'h0A; // LF
                            tx_start <= 1;
                            tx_pending <= 1;
                            sel_step <= 7'd67;
                        end
                    end
                    
                    7'd67: begin // Print Matrix Content (Read BRAM)
                        internal_rd_en <= 1;
                        internal_rd_addr <= print_addr + (print_r * target_n) + print_c;
                        sel_step <= 7'd68;
                    end
                    
                    7'd68: begin // Wait read
                        sel_step <= 7'd69;
                        print_step <= 0;
                    end
                    
                    7'd69: begin // Send Element
                        if (!tx_busy && !tx_pending) begin
                            if (mem_rd_data >= 100) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 100) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 1; end
                                    1: begin tx_data <= ((mem_rd_data % 100) / 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 2; end
                                    2: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 0; sel_step <= 7'd82; end
                                endcase
                            end else if (mem_rd_data >= 10) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 1; end
                                    1: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 0; sel_step <= 7'd82; end
                                endcase
                            end else begin
                                tx_data <= mem_rd_data + "0";
                                tx_start <= 1;
                                tx_pending <= 1;
                                sel_step <= 7'd82;
                            end
                        end
                    end

                    7'd82: begin // Check Row End (Add Op2)
                        if (print_c == target_n - 1) begin
                             if (!tx_busy && !tx_pending) begin
                                 tx_data <= 8'h0D; // CR
                                 tx_start <= 1;
                                 tx_pending <= 1;
                                 sel_step <= 7'd83;
                             end
                        end else begin
                             if (!tx_busy && !tx_pending) begin
                                 tx_data <= " "; // Space between elements
                                 tx_start <= 1;
                                 tx_pending <= 1;
                                 print_c <= print_c + 1;
                                 sel_step <= 7'd67;
                             end
                        end
                    end

                    7'd83: begin // Send LF (Add Op2)
                        if (!tx_busy && !tx_pending) begin
                            tx_data <= 8'h0A; // LF
                            tx_start <= 1;
                            tx_pending <= 1;
                            print_c <= 0;
                            if (print_r == target_m - 1) begin
                                match_idx <= match_idx + 1;
                                if (scan_slot == 15) sel_step <= 7'd84; // Wait for rx_done to clear
                                else begin
                                    scan_slot <= scan_slot + 1;
                                    sel_step <= 7'd62;
                                end
                            end else begin
                                print_r <= print_r + 1;
                                sel_step <= 7'd67; 
                            end
                        end
                    end

                    7'd84: begin // Wait for rx_done to clear before Wait Sel 2 (Add Op2)
                        if (!rx_done) sel_step <= 6'd16;
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
                        if (!tx_busy && !tx_pending) begin
                            if (mem_rd_data >= 100) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 100) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 1; end
                                    1: begin tx_data <= ((mem_rd_data % 100) / 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 2; end
                                    2: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 0; sel_step <= 6'd30; end
                                endcase
                            end else if (mem_rd_data >= 10) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 1; end
                                    1: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 0; sel_step <= 6'd30; end
                                endcase
                            end else begin
                                tx_data <= mem_rd_data + "0";
                                tx_start <= 1;
                                tx_pending <= 1;
                                sel_step <= 6'd30;
                            end
                        end
                    end

                    6'd30: begin // Check Row End
                        if (print_c == op1_n - 1) begin
                             if (!tx_busy && !tx_pending) begin
                                 tx_data <= 8'h0D; // CR
                                 tx_start <= 1;
                                 tx_pending <= 1;
                                 sel_step <= 6'd31;
                             end
                        end else begin
                             if (!tx_busy && !tx_pending) begin
                                 tx_data <= " "; // Space
                                 tx_start <= 1;
                                 tx_pending <= 1;
                                 print_c <= print_c + 1;
                                 sel_step <= 6'd27;
                             end
                        end
                    end

                    6'd31: begin // Send LF
                        if (!tx_busy && !tx_pending) begin
                            tx_data <= 8'h0A; // LF
                            tx_start <= 1;
                            tx_pending <= 1;
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
                        if (!tx_busy && !tx_pending) begin
                            if (mem_rd_data >= 100) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 100) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 1; end
                                    1: begin tx_data <= ((mem_rd_data % 100) / 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 2; end
                                    2: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 0; sel_step <= 6'd37; end
                                endcase
                            end else if (mem_rd_data >= 10) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 1; end
                                    1: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 0; sel_step <= 6'd37; end
                                endcase
                            end else begin
                                tx_data <= mem_rd_data + "0";
                                tx_start <= 1;
                                tx_pending <= 1;
                                sel_step <= 6'd37;
                            end
                        end
                    end

                    6'd37: begin // Check Row End
                        if (print_c == target_n - 1) begin
                             if (!tx_busy && !tx_pending) begin
                                 tx_data <= 8'h0D; // CR
                                 tx_start <= 1;
                                 tx_pending <= 1;
                                 sel_step <= 6'd38;
                             end
                        end else begin
                             if (!tx_busy && !tx_pending) begin
                                 tx_data <= " "; // Space
                                 tx_start <= 1;
                                 tx_pending <= 1;
                                 print_c <= print_c + 1;
                                 sel_step <= 6'd34;
                             end
                        end
                    end

                    6'd38: begin // Send LF
                        if (!tx_busy && !tx_pending) begin
                            tx_data <= 8'h0A; // LF
                            tx_start <= 1;
                            tx_pending <= 1;
                            print_c <= 0;
                            if (print_r == target_m - 1) begin
                                // Op2 Done, go to Confirm state
                                sel_step <= 6'd20;
                            end else begin
                                print_r <= print_r + 1;
                                sel_step <= 6'd34; 
                            end
                        end
                    end

                    // --- Print Scalar ---
                    6'd39: begin 
                        if (!tx_busy && !tx_pending) begin
                            tx_data <= scalar_val + "0";
                            tx_start <= 1;
                            tx_pending <= 1;
                            sel_step <= 6'd40;
                        end
                    end
                    
                    6'd40: begin
                        if (!tx_busy && !tx_pending) begin
                            tx_data <= 8'h0D;
                            tx_start <= 1;
                            tx_pending <= 1;
                            sel_step <= 6'd41;
                        end
                    end
                    
                    6'd41: begin
                        if (!tx_busy && !tx_pending) begin
                            tx_data <= 8'h0A;
                            tx_start <= 1;
                            tx_pending <= 1;
                            sel_step <= 6'd20;
                        end
                    end

                    // ==========================================
                    // NEW: Wait for RX Done to Clear (Debounce)
                    // ==========================================
                    // 6'd42: begin // Wait for !rx_done before Op2
                    //     if (!rx_done) sel_step <= 6'd16;
                    // end

                    6'd43: begin // Wait for !rx_done before Scalar
                        if (!rx_done) sel_step <= 6'd19;
                    end

                    // ==========================================
                    // Convolution: Select 3x3 Kernel
                    // ==========================================
                    7'd70: begin // Wait for rx_done to clear before listing kernels
                        if (!rx_done) sel_step <= 7'd90;
                    end
                    
                    7'd90: begin // Init: List all 3x3 matrices
                        target_m <= 5'd3;
                        target_n <= 5'd3;
                        scan_slot <= 0;
                        match_idx <= 1;
                        sel_step <= 7'd91;
                    end
                    
                    7'd91: begin // Query slot for 3x3 kernel
                        query_slot <= scan_slot[3:0];
                        sel_step <= 7'd92;
                    end
                    
                    7'd92: begin // Check if 3x3 and print
                        if (query_valid && query_m == 5'd3 && query_n == 5'd3) begin
                            print_addr <= query_addr;
                            print_r <= 0;
                            print_c <= 0;
                            sel_step <= 7'd93; // Print index
                        end else begin
                            if (scan_slot == 15) sel_step <= 7'd95; // Done listing, wait selection
                            else begin
                                scan_slot <= scan_slot + 1;
                                sel_step <= 7'd91;
                            end
                        end
                    end
                    
                    7'd93: begin // Print kernel index
                        if (!tx_busy && !tx_pending) begin
                            tx_data <= match_idx + "0"; 
                            tx_start <= 1;
                            tx_pending <= 1;
                            sel_step <= 7'd94;
                        end
                    end
                    
                    7'd94: begin // Send CR after kernel index
                        if (!tx_busy && !tx_pending) begin
                            tx_data <= 8'h0D;
                            tx_start <= 1;
                            tx_pending <= 1;
                            sel_step <= 7'd71;
                        end
                    end
                    
                    7'd71: begin // Send LF, then print kernel content
                        if (!tx_busy && !tx_pending) begin
                            tx_data <= 8'h0A;
                            tx_start <= 1;
                            tx_pending <= 1;
                            print_r <= 0;
                            print_c <= 0;
                            sel_step <= 7'd72; // Go to print kernel content
                        end
                    end
                    
                    7'd72: begin // Read kernel element
                        internal_rd_en <= 1;
                        internal_rd_addr <= print_addr + (print_r * 3) + print_c;
                        sel_step <= 7'd73;
                    end
                    
                    7'd73: begin // Wait read
                        sel_step <= 7'd74;
                        print_step <= 0;
                    end
                    
                    7'd74: begin // Send kernel element
                        if (!tx_busy && !tx_pending) begin
                            if (mem_rd_data >= 100) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 100) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 1; end
                                    1: begin tx_data <= ((mem_rd_data % 100) / 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 2; end
                                    2: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 0; sel_step <= 7'd75; end
                                endcase
                            end else if (mem_rd_data >= 10) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 1; end
                                    1: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 0; sel_step <= 7'd75; end
                                endcase
                            end else begin
                                tx_data <= mem_rd_data + "0";
                                tx_start <= 1;
                                tx_pending <= 1;
                                sel_step <= 7'd75;
                            end
                        end
                    end
                    
                    7'd75: begin // Check kernel row end
                        if (print_c == 2) begin // 3x3 kernel, col 0,1,2
                            if (!tx_busy && !tx_pending) begin
                                tx_data <= 8'h0D; // CR
                                tx_start <= 1;
                                tx_pending <= 1;
                                sel_step <= 7'd76;
                            end
                        end else begin
                            if (!tx_busy && !tx_pending) begin
                                tx_data <= " "; // Space
                                tx_start <= 1;
                                tx_pending <= 1;
                                print_c <= print_c + 1;
                                sel_step <= 7'd72;
                            end
                        end
                    end
                    
                    7'd76: begin // Send LF after kernel row
                        if (!tx_busy && !tx_pending) begin
                            tx_data <= 8'h0A; // LF
                            tx_start <= 1;
                            tx_pending <= 1;
                            print_c <= 0;
                            if (print_r == 2) begin // Done printing this kernel
                                match_idx <= match_idx + 1;
                                if (scan_slot == 15) sel_step <= 7'd95; // Done listing all
                                else begin
                                    scan_slot <= scan_slot + 1;
                                    sel_step <= 7'd91; // Next kernel
                                end
                            end else begin
                                print_r <= print_r + 1;
                                sel_step <= 7'd72;
                            end
                        end
                    end
                    
                    7'd95: begin // Wait for kernel selection
                        if (rx_done) begin
                            if (rx_data >= "0" && rx_data <= "9") begin
                                user_sel_idx <= rx_data - "0";
                                scan_slot <= 0;
                                match_idx <= 1;
                                sel_step <= 7'd96;
                                error_code <= `ERR_NONE;
                            end else begin
                                error_code <= `ERR_VALUE_RANGE;
                                if (!tx_busy) begin tx_data <= "!"; tx_start <= 1'b1; end
                            end
                        end
                    end
                    
                    7'd96: begin // Find kernel slot
                        query_slot <= scan_slot[3:0];
                        sel_step <= 7'd97;
                    end
                    
                    7'd97: begin // Match kernel
                        if (query_valid && query_m == 5'd3 && query_n == 5'd3) begin
                            if (match_idx == user_sel_idx) begin
                                op2_slot <= scan_slot[3:0];
                                // Restore image dimensions for result
                                target_m <= op1_m;
                                target_n <= op1_n;
                                // Kernel already printed during listing, go directly to confirm
                                sel_step <= 6'd20;
                            end else begin
                                match_idx <= match_idx + 1;
                                if (scan_slot == 15) begin
                                    scan_slot <= 0;
                                    sel_step <= 7'd95;
                                end else begin
                                    scan_slot <= scan_slot + 1;
                                    sel_step <= 7'd96;
                                end
                            end
                        end else begin
                            if (scan_slot == 15) begin
                                scan_slot <= 0;
                                sel_step <= 7'd95;
                            end else begin
                                scan_slot <= scan_slot + 1;
                                sel_step <= 7'd96;
                            end
                        end
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
                        end else if (selected_op_type == OP_CONV) begin
                            alloc_m <= conv_out_m;
                            alloc_n <= conv_out_n;
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
                        end else if (selected_op_type == OP_MUL) begin
                            commit_m <= op1_m;
                            commit_n <= target_n;
                        end else if (selected_op_type == OP_CONV) begin
                            commit_m <= conv_out_m;
                            commit_n <= conv_out_n;
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
                        end else if (selected_op_type == OP_MUL) begin
                            iter_m <= op1_m;
                            iter_n <= target_n;
                        end else if (selected_op_type == OP_CONV) begin
                            iter_m <= conv_out_m;
                            iter_n <= conv_out_n;
                        end else begin
                            iter_m <= target_m;
                            iter_n <= target_n;
                        end
                        
                        res_send_idx <= 0;
                        sub_state <= SEND_RESULT;
                    end
                    default: exec_state <= 0;
                endcase
            end

            SEND_RESULT: begin
                case (res_send_idx)
                    0: begin // Send Result Slot
                        if (!tx_busy && !tx_pending) begin
                            tx_data <= res_slot + "0"; 
                            tx_start <= 1;
                            tx_pending <= 1;
                            res_send_idx <= 1;
                        end
                    end
                    1: begin // Send CR
                         if (!tx_busy && !tx_pending) begin
                            tx_data <= 8'h0D; 
                            tx_start <= 1;
                            tx_pending <= 1;
                            res_send_idx <= 7;
                        end
                    end
                    7: begin // Send LF
                         if (!tx_busy && !tx_pending) begin
                            tx_data <= 8'h0A; 
                            tx_start <= 1;
                            tx_pending <= 1;
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
                        if (!tx_busy && !tx_pending) begin
                            if (mem_rd_data >= 100) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 100) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 1; end
                                    1: begin tx_data <= ((mem_rd_data % 100) / 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 2; end
                                    2: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 0; res_send_idx <= 6; end
                                endcase
                            end else if (mem_rd_data >= 10) begin
                                case (print_step)
                                    0: begin tx_data <= (mem_rd_data / 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 1; end
                                    1: begin tx_data <= (mem_rd_data % 10) + "0"; tx_start <= 1; tx_pending <= 1; print_step <= 0; res_send_idx <= 6; end
                                endcase
                            end else begin
                                tx_data <= mem_rd_data + "0";
                                tx_start <= 1;
                                tx_pending <= 1;
                                res_send_idx <= 6;
                            end
                        end
                    end
                    6: begin // Check Row End
                        if (print_c == iter_n - 1) begin
                            if (!tx_busy && !tx_pending) begin
                                tx_data <= 8'h0D; // CR
                                tx_start <= 1;
                                tx_pending <= 1;
                                res_send_idx <= 8;
                            end
                        end else begin
                            if (!tx_busy && !tx_pending) begin
                                tx_data <= " "; // Space
                                tx_start <= 1;
                                tx_pending <= 1;
                                print_c <= print_c + 1;
                                res_send_idx <= 2; 
                            end
                        end
                    end
                    8: begin // Send LF
                        if (!tx_busy && !tx_pending) begin
                            tx_data <= 8'h0A; // LF
                            tx_start <= 1;
                            tx_pending <= 1;
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
                    default: res_send_idx <= 0;
                endcase
            end

            DONE: begin
                 if (btn_posedge) sub_state <= IDLE;
            end

            default: sub_state <= IDLE;
            endcase
        end
    end else begin
        sub_state <= IDLE;
        btn_prev <= btn_confirm;
    end
end

endmodule