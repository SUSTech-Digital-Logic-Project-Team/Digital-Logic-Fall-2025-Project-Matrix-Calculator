// ========================================
// RESTRUCTURED: Matrix Calculator Top Module
// Optimized for BRAM usage on EGO1 board
// ========================================

`timescale 1ns / 1ps
`include "matrix_pkg.vh"

module matrix_calculator_top_optimized (
    input wire clk,
    input wire rst_n,
    input wire [2:0] dip_sw,
    input wire btn_confirm,  // 
    input wire btn_back,     // ��������
    input wire uart_rx,
    output wire uart_tx,
    output wire [6:0] seg_display, // ע�⣺display_ctrl �ڲ���������?1?7??? wire ����
    output wire [3:0] led_status,
    output wire [1:0] seg_select
);

    // ========================================
    // 1. �������� (Debouncing) - �����޸�
    // ========================================
    // �������ź�
    (* DONT_TOUCH = "true" *) wire btn_confirm_pulse; 
    (* DONT_TOUCH = "true" *) wire btn_back_pulse;

    // ����ģ�飺ֱ�Ӵ���ԭʼ�����ź�
    button_debounce db_confirm (
        .clk(clk), .rst_n(rst_n), 
        .btn_in(btn_confirm),  // ԭʼ�����źţ�������������ʱΪ0��
        .btn_pulse(btn_confirm_pulse) // �����������
    );
    button_debounce db_back (
        .clk(clk), .rst_n(rst_n), 
        .btn_in(btn_back),     // ԭʼ�����ź�
        .btn_pulse(btn_back_pulse) // �����������
    );

    // ========================================
    // Main State Machine
    // ========================================
    reg [2:0] main_state, main_state_next;
    wire [3:0] op_type_from_compute;
    
    // Mode active signals
    wire input_mode_active = (main_state == `MODE_INPUT);
    wire generate_mode_active = (main_state == `MODE_GENERATE);
    wire display_mode_active = (main_state == `MODE_DISPLAY);
    wire compute_mode_active = (main_state == `MODE_COMPUTE);
    wire setting_mode_active = (main_state == `MODE_SETTING);

// ========================================
// Configuration Parameters
// ========================================
wire [3:0] config_max_dim_from_setting, config_max_value_from_setting, config_matrices_per_size_from_setting;

// Use setting values when in SETTING mode, otherwise use defaults
reg [3:0] config_max_dim, config_max_value, config_matrices_per_size;

always @(*) begin
    if (setting_mode_active) begin
        config_max_dim = config_max_dim_from_setting;
        config_max_value = config_max_value_from_setting;
        config_matrices_per_size = config_matrices_per_size_from_setting;
    end else begin
        config_max_dim = `DEFAULT_MAX_DIM;
        config_max_value = `DEFAULT_MAX_VALUE;
        config_matrices_per_size = `DEFAULT_MATRICES_PER_SIZE;
    end
end

// ========================================
// UART Interface Signals
// ========================================
wire [7:0] rx_data;
wire rx_done;

wire [7:0] tx_data_mux;
wire tx_start_mux;
wire tx_busy, rx_busy;

// ========================================
// BRAM Memory Interface Signals
// ========================================
wire mem_a_en, mem_a_we, mem_b_en;
wire [`BRAM_ADDR_WIDTH-1:0] mem_a_addr, mem_b_addr;
wire [`ELEMENT_WIDTH-1:0] mem_a_din, mem_a_dout, mem_b_dout;

// ========================================
// Matrix Manager Interface Signals
// ========================================
wire alloc_req_mux, commit_req_mux;
wire [3:0] alloc_m_mux, alloc_n_mux;
wire [3:0] alloc_slot, commit_slot_mux;
wire [`BRAM_ADDR_WIDTH-1:0] alloc_addr, commit_addr_mux;
wire alloc_valid;
wire [3:0] commit_m_mux, commit_n_mux;

wire [3:0] query_slot_mux;
wire query_valid;
wire [3:0] query_m, query_n;
wire [`BRAM_ADDR_WIDTH-1:0] query_addr;
wire [7:0] query_element_count;
wire [7:0] total_matrix_count;

// ========================================
// Random Number Generator
// ========================================
wire [3:0] random_value;

// ========================================
// Error Signals
// ========================================
wire [3:0] error_code_input, error_code_generate, error_code_display;
wire [3:0] error_code_compute, error_code_setting;
reg [3:0] error_code;
reg error_led;
reg [25:0] error_timer;

// ========================================
// Sub-state Signals
// ========================================
wire [3:0] sub_state_input, sub_state_generate, sub_state_display;
wire [3:0] sub_state_compute, sub_state_setting;
reg [3:0] sub_state;

// ========================================
// UART TX Multiplexing
// ========================================
wire [7:0] tx_data_input, tx_data_generate, tx_data_display, tx_data_compute, tx_data_setting;
wire tx_start_input, tx_start_generate, tx_start_display, tx_start_compute, tx_start_setting;
wire clear_rx_input, clear_rx_generate, clear_rx_display, clear_rx_compute, clear_rx_setting;

assign tx_data_mux = input_mode_active ? tx_data_input :
                     generate_mode_active ? tx_data_generate :
                     display_mode_active ? tx_data_display :
                     compute_mode_active ? tx_data_compute :
                     setting_mode_active ? tx_data_setting : 8'd0;

assign tx_start_mux = input_mode_active ? tx_start_input :
                      generate_mode_active ? tx_start_generate :
                      display_mode_active ? tx_start_display :
                      compute_mode_active ? tx_start_compute :
                      setting_mode_active ? tx_start_setting : 1'b0;

// ========================================
// BRAM Memory Write Multiplexing
// ========================================
wire mem_wr_en_input, mem_wr_en_generate;
wire [`BRAM_ADDR_WIDTH-1:0] mem_wr_addr_input, mem_wr_addr_generate;
wire [`ELEMENT_WIDTH-1:0] mem_wr_data_input, mem_wr_data_generate;

assign mem_a_en = mem_wr_en_input | mem_wr_en_generate | mem_rd_en_display | mem_rd_en_compute;
assign mem_a_we = mem_wr_en_input | mem_wr_en_generate;
assign mem_a_addr = mem_wr_en_input ? mem_wr_addr_input :
                    mem_wr_en_generate ? mem_wr_addr_generate :
                    mem_rd_en_display ? mem_rd_addr_display :
                    mem_rd_addr_compute;
assign mem_a_din = mem_wr_en_input ? mem_wr_data_input : mem_wr_data_generate;

// ========================================
// BRAM Memory Read Multiplexing
// ========================================
wire mem_rd_en_display, mem_rd_en_compute;
wire [`BRAM_ADDR_WIDTH-1:0] mem_rd_addr_display, mem_rd_addr_compute;

// Connect read data from BRAM port A
wire [`ELEMENT_WIDTH-1:0] mem_rd_data = mem_a_dout;

// ========================================
// Matrix Manager Allocation Multiplexing
// ========================================
wire alloc_req_input, alloc_req_generate;
wire [3:0] alloc_m_input, alloc_n_input, alloc_m_generate, alloc_n_generate;
wire commit_req_input, commit_req_generate;
wire [3:0] commit_slot_input, commit_slot_generate;
wire [3:0] commit_m_input, commit_n_input, commit_m_generate, commit_n_generate;
wire [`BRAM_ADDR_WIDTH-1:0] commit_addr_input, commit_addr_generate;

assign alloc_req_mux = alloc_req_input | alloc_req_generate;
assign alloc_m_mux = input_mode_active ? alloc_m_input : alloc_m_generate;
assign alloc_n_mux = input_mode_active ? alloc_n_input : alloc_n_generate;
assign commit_req_mux = commit_req_input | commit_req_generate;
assign commit_slot_mux = input_mode_active ? commit_slot_input : commit_slot_generate;
assign commit_m_mux = input_mode_active ? commit_m_input : commit_m_generate;
assign commit_n_mux = input_mode_active ? commit_n_input : commit_n_generate;
assign commit_addr_mux = input_mode_active ? commit_addr_input : commit_addr_generate;

wire [3:0] query_slot_display, query_slot_compute;
assign query_slot_mux = display_mode_active ? query_slot_display : query_slot_compute;

// ========================================
    // State Machine Logic (Updated with Debounced Buttons)
    // ========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            main_state <= `MAIN_MENU;
        end else begin
            main_state <= main_state_next;
        end
    end

    always @(*) begin
        main_state_next = main_state;
        case (main_state)
            `MAIN_MENU: begin
                if (btn_confirm_pulse) begin
                    case (dip_sw)
                        3'd1: main_state_next = `MODE_INPUT;
                        3'd2: main_state_next = `MODE_GENERATE;
                        3'd3: main_state_next = `MODE_DISPLAY;
                        3'd4: main_state_next = `MODE_COMPUTE;
                        3'd5: main_state_next = `MODE_SETTING;
                        default: main_state_next = `MAIN_MENU; 
                    endcase
                end
            end
            
            default: begin 
                if (btn_back_pulse) begin
                    main_state_next = `MAIN_MENU;
                end
            end
        endcase
    end

// ========================================
// Sub-state and Error Multiplexing
// ========================================
always @(*) begin
    case (main_state)
        `MODE_INPUT: sub_state = sub_state_input;
        `MODE_GENERATE: sub_state = sub_state_generate;
        `MODE_DISPLAY: sub_state = sub_state_display;
        `MODE_COMPUTE: sub_state = sub_state_compute;
        `MODE_SETTING: sub_state = sub_state_setting;
        default: sub_state = 4'd0;
    endcase
end

always @(*) begin
    case (main_state)
        `MODE_INPUT: error_code = error_code_input;
        `MODE_GENERATE: error_code = error_code_generate;
        `MODE_DISPLAY: error_code = error_code_display;
        `MODE_COMPUTE: error_code = error_code_compute;
        `MODE_SETTING: error_code = error_code_setting;
        default: error_code = `ERR_NONE;
    endcase
end

// ========================================
// Error Handling with Timer
// ========================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        error_led <= 1'b0;
        error_timer <= 26'd0;
    end else begin
        if (error_code != `ERR_NONE) begin
            if (error_timer < 26'd50_000_000) begin
                error_timer <= error_timer + 1'b1;
                error_led <= 1'b1;
            end else begin
                error_timer <= 26'd0;
                error_led <= 1'b0;
            end
        end else begin
            error_timer <= 26'd0;
            error_led <= 1'b0;
        end
    end
end

// ========================================
// Module Instantiation
// ========================================

// UART Module
uart_module #(
    .CLK_FREQ(`CLK_FREQ),
    .BAUD_RATE(`BAUD_RATE)
) uart_inst (
    .clk(clk),
    .rst_n(rst_n),
    .uart_rx(uart_rx),
    .uart_tx(uart_tx),
    .rx_data(rx_data),
    .rx_done(rx_done),
    .tx_data(tx_data_mux),
    .tx_start(tx_start_mux),
    .tx_busy(tx_busy)
);

// BRAM Memory Pool (using optimized module)
bram_memory_pool #(
    .DATA_WIDTH(`ELEMENT_WIDTH),
    .ADDR_WIDTH(`BRAM_ADDR_WIDTH),
    .DEPTH(`MAX_ELEMENTS)
) bram_mem_inst (
    .clk(clk),
    .rst_n(rst_n),
    .a_en(mem_a_en),
    .a_we(mem_a_we),
    .a_addr(mem_a_addr),
    .a_din(mem_a_din),
    .a_dout(mem_a_dout),
    .b_en(mem_b_en),
    .b_addr(mem_b_addr),
    .b_dout(mem_b_dout)
);

// Matrix Manager (optimized version)
matrix_manager_optimized #(
    .MAX_STORAGE_MATRICES(`MAX_STORAGE_MATRICES),
    .MAX_ELEMENTS(`MAX_ELEMENTS),
    .ELEMENT_WIDTH(`ELEMENT_WIDTH)
) matrix_mgr_inst (
    .clk(clk),
    .rst_n(rst_n),
    .alloc_req(alloc_req_mux),
    .alloc_m(alloc_m_mux),
    .alloc_n(alloc_n_mux),
    .alloc_slot(alloc_slot),
    .alloc_addr(alloc_addr),
    .alloc_valid(alloc_valid),
    .commit_req(commit_req_mux),
    .commit_slot(commit_slot_mux),
    .commit_m(commit_m_mux),
    .commit_n(commit_n_mux),
    .commit_addr(commit_addr_mux),
    .query_slot(query_slot_mux),
    .query_valid(query_valid),
    .query_m(query_m),
    .query_n(query_n),
    .query_addr(query_addr),
    .query_element_count(query_element_count),
    .total_matrix_count(total_matrix_count)
);

// ========================================
// LFSR Random Number Generator
// ========================================
lfsr_rng #(
    .SEED(16'hACE1)
) rng_inst (
    .clk(clk),
    .rst_n(rst_n),
    .max_value(config_max_value),
    .random_value(random_value)
);

// ========================================
// Input Mode Module
// ========================================

input_mode input_mode_inst (
    .clk(clk),
    .rst_n(rst_n),
    .mode_active(input_mode_active),
    .config_max_dim(config_max_dim),
    .config_max_value(config_max_value),
    .rx_data(rx_data),
    .rx_done(rx_done),
    .clear_rx_buffer(clear_rx_input),
    .tx_data(tx_data_input),
    .tx_start(tx_start_input),
    .tx_busy(tx_busy),
    .alloc_req(alloc_req_input),
    .alloc_m(alloc_m_input),
    .alloc_n(alloc_n_input),
    .alloc_slot(alloc_slot),
    .alloc_addr(alloc_addr),
    .alloc_valid(alloc_valid),
    .commit_req(commit_req_input),
    .commit_slot(commit_slot_input),
    .commit_m(commit_m_input),
    .commit_n(commit_n_input),
    .commit_addr(commit_addr_input),
    .mem_wr_en(mem_wr_en_input),
    .mem_wr_addr(mem_wr_addr_input),
    .mem_wr_data(mem_wr_data_input),
    .mem_rd_en(input_mode_active ? mem_b_en : 1'b0), // Enable only in input mode
    .mem_rd_addr(input_mode_active ? mem_b_addr : {`BRAM_ADDR_WIDTH{1'b0}}), 
    .mem_rd_data(input_mode_active ? mem_b_dout : {`ELEMENT_WIDTH{1'b0}}),
    .error_code(error_code_input),
    .sub_state(sub_state_input)
);

// ========================================
// Generate Mode Module
// ========================================
generate_mode generate_mode_inst (
    .clk(clk),
    .rst_n(rst_n),
    .mode_active(generate_mode_active),
    .config_max_dim(config_max_dim),
    .config_max_value(config_max_value),
    .random_value(random_value),
    .rx_data(rx_data),
    .rx_done(rx_done),
    .clear_rx_buffer(clear_rx_generate),
    .tx_data(tx_data_generate),
    .tx_start(tx_start_generate),
    .tx_busy(tx_busy),
    .alloc_req(alloc_req_generate),
    .alloc_slot(alloc_slot),
    .alloc_addr(alloc_addr),
    .alloc_valid(alloc_valid),
    .commit_req(commit_req_generate),
    .commit_slot(commit_slot_generate),
    .commit_m(commit_m_generate),
    .commit_n(commit_n_generate),
    .commit_addr(commit_addr_generate),
    .mem_wr_en(mem_wr_en_generate),
    .mem_wr_addr(mem_wr_addr_generate),
    .mem_wr_data(mem_wr_data_generate),
    .error_code(error_code_generate),
    .sub_state(sub_state_generate)
);

// ========================================
// Display Mode Module
// ========================================
display_mode display_mode_inst (
    .clk(clk),
    .rst_n(rst_n),
    .mode_active(display_mode_active),
    .rx_data(rx_data),
    .rx_done(rx_done),
    .clear_rx_buffer(clear_rx_display),
    .tx_data(tx_data_display),
    .tx_start(tx_start_display),
    .tx_busy(tx_busy),
    .total_matrix_count(total_matrix_count),
    .query_slot(query_slot_display),
    .query_valid(query_valid),
    .query_m(query_m),
    .query_n(query_n),
    .query_addr(query_addr),
    .query_element_count(query_element_count),
    .mem_rd_en(mem_rd_en_display),
    .mem_rd_addr(mem_rd_addr_display),
    .mem_rd_data(mem_rd_data), // Corrected connection
    .error_code(error_code_display),
    .sub_state(sub_state_display)
);

// ========================================
// Compute Mode Module
// ========================================
compute_mode compute_mode_inst (
        .clk(clk),
        .rst_n(rst_n),
        .mode_active(compute_mode_active),
        .config_max_dim(config_max_dim),
        
        // ����������������źţ�?1?7??1?7����ԭʼ������
        .dip_sw(dip_sw),               
        .btn_confirm(main_state == `MODE_COMPUTE ? btn_confirm_pulse : 1'b0), 
        .selected_op_type(op_type_from_compute), 
        
        .rx_data(rx_data),
        .rx_done(rx_done),
        .clear_rx_buffer(clear_rx_compute),
        .tx_data(tx_data_compute),
        .tx_start(tx_start_compute),
        .tx_busy(tx_busy),
        .total_matrix_count(total_matrix_count),
        .query_slot(query_slot_compute),
        .query_valid(query_valid),
        .query_m(query_m),
        .query_n(query_n),
        .query_addr(query_addr),
        .query_element_count(query_element_count),
        .mem_rd_en(mem_rd_en_compute),
        .mem_rd_addr(mem_rd_addr_compute),
        .mem_rd_data(mem_rd_data),
        .error_code(error_code_compute),
        .sub_state(sub_state_compute)
    );

// ========================================
// Setting Mode Module
// ========================================
setting_mode setting_mode_inst (
    .clk(clk),
    .rst_n(rst_n),
    .mode_active(setting_mode_active),
    .rx_data(rx_data),
    .rx_done(rx_done),
    .clear_rx_buffer(clear_rx_setting),
    .tx_data(tx_data_setting),
    .tx_start(tx_start_setting),
    .tx_busy(tx_busy),
    .config_max_dim(config_max_dim_from_setting),
    .config_max_value(config_max_value_from_setting),
    .config_matrices_per_size(config_matrices_per_size_from_setting),
    .error_code(error_code_setting),
    .sub_state(sub_state_setting)
);

wire [6:0] display_main;
wire [6:0] display_op;
// ========================================
// Display Control Module
// ========================================
display_ctrl disp_ctrl_inst (
        .clk(clk),
        .rst_n(rst_n),
        .main_state(main_state),
        .sub_state(sub_state),
        // ���?1?7??? Compute ģʽ����?1?7??? op_type������Ϊ 0
        .op_type(compute_mode_active ? op_type_from_compute : 4'd0),
        .error_code(error_code),
        .error_timer(error_timer[25:20]),
        .seg_display(seg_display), // ֱ������?1?7??? Output Port
        .led_status(led_status),
        .seg_select(seg_select)    // ֱ������?1?7??? Output Port
    );


endmodule
