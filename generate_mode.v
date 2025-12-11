// ========================================
// Matrix Generation Mode (RESTRUCTURED)
// Purpose: Generate random matrices per user specification
// Added: Formatted UART output (space between digits, newline per row)
// ========================================

`timescale 1ns / 1ps
`include "matrix_pkg.vh"

module generate_mode #(
    parameter ELEMENT_WIDTH = `ELEMENT_WIDTH,
    parameter ADDR_WIDTH = `BRAM_ADDR_WIDTH,
    parameter TIMEOUT_CNT_MAX = 16'd65535  // 内存分配超时计数器（可选，增强健壮性）
)(
    input wire clk,
    input wire rst_n,
    input wire mode_active,
    
    // Configuration parameters
    input wire [3:0] config_max_dim,
    input wire [3:0] config_max_value,
    input wire [3:0] random_value,
    
    // UART receive interface
    input wire [7:0] rx_data,
    input wire rx_done,
    output reg clear_rx_buffer,
    
    // UART transmit interface
    output reg [7:0] tx_data,
    output reg tx_start,
    input wire tx_busy,
    
    // Matrix manager interface
    output reg alloc_req,
    input wire [3:0] alloc_slot,
    input wire [ADDR_WIDTH-1:0] alloc_addr,
    input wire alloc_valid,
    output reg commit_req,
    output reg [3:0] commit_slot,
    output reg [3:0] commit_m,
    output reg [3:0] commit_n,
    output reg [ADDR_WIDTH-1:0] commit_addr,
    
    // Memory write interface
    output reg mem_wr_en,
    output reg [ADDR_WIDTH-1:0] mem_wr_addr,
    output reg [ELEMENT_WIDTH-1:0] mem_wr_data,
    
    // Error and state output
    output reg [3:0] error_code,
    output reg [3:0] sub_state
);

// 扩展状态定义：新增输出矩阵的状态
localparam IDLE = 4'd0, 
           WAIT_M = 4'd1, 
           WAIT_N = 4'd2, 
           ALLOC = 4'd3, 
           GEN_DATA = 4'd4, 
           COMMIT = 4'd5,
           DISPLAY_MATRIX = 4'd6,  // 新增：格式化输出矩阵
           DONE = 4'd7;

// Internal state
reg [3:0] gen_m, gen_n;
reg [7:0] gen_count;          // 生成数据的计数器
reg [ADDR_WIDTH-1:0] gen_addr;// 分配的BRAM起始地址
reg [3:0] gen_slot;           // 分配的矩阵槽位

// 格式化输出相关寄存器
reg [3:0] display_row;        // 当前输出的行
reg [3:0] display_col;        // 当前输出的列
reg [2:0] display_step;       // 输出步骤：0=换行, 1=输出元素, 2=输出空格, 3=结束
reg [ELEMENT_WIDTH-1:0] display_data; // 待输出的元素数据
reg [15:0] timeout_cnt;       // 内存分配超时计数器

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位所有寄存器
        sub_state <= IDLE;
        alloc_req <= 1'b0;
        commit_req <= 1'b0;
        mem_wr_en <= 1'b0;
        tx_start <= 1'b0;
        error_code <= `ERR_NONE;
        clear_rx_buffer <= 1'b0;
        gen_m <= 4'd0;
        gen_n <= 4'd0;
        gen_count <= 8'd0;
        gen_addr <= {ADDR_WIDTH{1'b0}};
        gen_slot <= 4'd0;
        mem_wr_addr <= {ADDR_WIDTH{1'b0}};
        mem_wr_data <= {ELEMENT_WIDTH{1'b0}};
        commit_slot <= 4'd0;
        commit_m <= 4'd0;
        commit_n <= 4'd0;
        commit_addr <= {ADDR_WIDTH{1'b0}};
        tx_data <= 8'd0;
        // 格式化输出寄存器复位
        display_row <= 4'd0;
        display_col <= 4'd0;
        display_step <= 3'd0;
        display_data <= {ELEMENT_WIDTH{1'b0}};
        timeout_cnt <= 16'd0;
    end else if (mode_active) begin
        // 默认值：清除单周期信号
        tx_start <= 1'b0;
        alloc_req <= 1'b0;
        commit_req <= 1'b0;
        mem_wr_en <= 1'b0;
        clear_rx_buffer <= 1'b0;

        case (sub_state)
            IDLE: begin
                // 复位格式化输出状态
                display_row <= 4'd0;
                display_col <= 4'd0;
                display_step <= 3'd0;
                error_code <= `ERR_NONE;
                timeout_cnt <= 16'd0;
                sub_state <= WAIT_M;
            end
            
            WAIT_M: begin
                // 【可选】替换为UART接收M的逻辑（原代码是固定3）
                // 示例：接收用户输入的M（ASCII数字转数值）
                if (rx_done) begin
                    clear_rx_buffer <= 1'b1; // 清除UART接收缓冲区
                    if (rx_data >= "0" && rx_data <= "9") begin
                        gen_m <= rx_data - "0"; // 转换为数值
                        // 校验M的范围
                        if (gen_m == 4'd0 || gen_m > config_max_dim) begin
                            error_code <= `ERR_DIM_RANGE;
                            sub_state <= IDLE; // 可替换为ERROR状态
                        end else begin
                            sub_state <= WAIT_N;
                        end
                    end
                end
                // 原固定值逻辑（保留可注释）：
                // gen_m <= 4'd3;
                // sub_state <= WAIT_N;
            end
            
            WAIT_N: begin
                // 【可选】替换为UART接收N的逻辑（原代码是固定3）
                if (rx_done) begin
                    clear_rx_buffer <= 1'b1;
                    if (rx_data >= "0" && rx_data <= "9") begin
                        gen_n <= rx_data - "0";
                        // 校验N的范围
                        if (gen_n == 4'd0 || gen_n > config_max_dim) begin
                            error_code <= `ERR_DIM_RANGE;
                            sub_state <= IDLE;
                        end else begin
                            alloc_req <= 1'b1; // 申请内存
                            sub_state <= ALLOC;
                        end
                    end
                end
                // 原固定值逻辑（保留可注释）：
                // gen_n <= 4'd3;
                // alloc_req <= 1'b1;
                // sub_state <= ALLOC;
            end
            
            ALLOC: begin
                alloc_req <= 1'b1; // 保持申请信号有效
                timeout_cnt <= timeout_cnt + 1'b1; // 超时计数
                
                if (alloc_valid) begin
                    // 内存分配成功
                    gen_addr <= alloc_addr;
                    gen_slot <= alloc_slot;
                    gen_count <= 8'd0;
                    timeout_cnt <= 16'd0;
                    sub_state <= GEN_DATA;
                end else if (timeout_cnt >= TIMEOUT_CNT_MAX) begin
                    // 内存分配超时
                    error_code <= `ERR_ALLOC_TIMEOUT;
                    sub_state <= IDLE;
                end
            end
            
            GEN_DATA: begin
                if (gen_count < ({4'd0, gen_m} * {4'd0, gen_n})) begin
                    // 生成随机数据并写入BRAM
                    mem_wr_en <= 1'b1;
                    mem_wr_addr <= gen_addr + gen_count;
                    // 限制随机值在配置范围内
                    mem_wr_data <= (random_value > config_max_value) ? config_max_value : random_value;
                    gen_count <= gen_count + 1'b1;
                end else begin
                    // 数据生成完成，进入提交状态
                    sub_state <= COMMIT;
                end
            end
            
            COMMIT: begin
                // 提交矩阵信息给管理器
                commit_req <= 1'b1;
                commit_slot <= gen_slot;
                commit_m <= gen_m;
                commit_n <= gen_n;
                commit_addr <= gen_addr;
                // 初始化输出状态，进入格式化输出
                display_row <= 4'd0;
                display_col <= 4'd0;
                display_step <= 3'd0;
                sub_state <= DISPLAY_MATRIX;
            end
            
            // 新增：格式化输出矩阵（核心逻辑）
            DISPLAY_MATRIX: begin
                commit_req <= 1'b0;
                case (display_step)
                    3'd0: begin // 步骤0：输出换行（行首）
                        if (!tx_busy && !tx_start) begin
                            // 先输出回车(\r)，再输出换行(\n)
                            tx_data <= 8'h0D; // Carriage Return (CR)
                            tx_start <= 1'b1;
                            display_step <= 3'd1;
                        end
                    end
                    
                    3'd1: begin // 步骤1：输出换行符
                        if (!tx_busy && !tx_start) begin
                            tx_data <= 8'h0A; // Line Feed (LF)
                            tx_start <= 1'b1;
                            display_step <= 3'd2;
                        end
                    end
                    
                    3'd2: begin // 步骤2：输出当前元素（转换为ASCII）
                        if (!tx_busy && !tx_start) begin
                            // 获取当前元素（gen_addr + 行*列数 + 列）
                            display_data <= random_value; // 直接用随机值（也可从BRAM读取）
                            // 转换为ASCII数字（0-9 -> "0"-"9"）
                            tx_data <= display_data[3:0] + "0";
                            tx_start <= 1'b1;
                            display_step <= 3'd3;
                        end
                    end
                    
                    3'd3: begin // 步骤3：输出空格或换行
                        if (!tx_busy && !tx_start) begin
                            if (display_col == gen_n - 1) begin
                                // 列结束：重置列，处理行
                                display_col <= 4'd0;
                                if (display_row == gen_m - 1) begin
                                    // 矩阵输出完成，进入结束步骤
                                    display_step <= 3'd4;
                                end else begin
                                    // 下一行：回到步骤0（换行）
                                    display_row <= display_row + 1'b1;
                                    display_step <= 3'd0;
                                end
                            end else begin
                                // 列未结束：输出空格，下一列
                                tx_data <= 8'h20; // Space (空格)
                                tx_start <= 1'b1;
                                display_col <= display_col + 1'b1;
                                display_step <= 3'd2; // 回到步骤2输出下一个元素
                            end
                        end
                    end
                    
                    3'd4: begin // 步骤4：矩阵输出完成（可选：输出最终换行）
                        if (!tx_busy && !tx_start) begin
                            tx_data <= 8'h0A; // 额外的换行符
                            tx_start <= 1'b1;
                            sub_state <= DONE;
                        end
                    end
                    
                    default: display_step <= 3'd0;
                endcase
            end
            
            DONE: begin
                // 输出完成，返回IDLE
                if (!tx_busy) begin
                    // 可选：输出完成标识（如"D"）
                    tx_data <= "D";
                    tx_start <= 1'b1;
                    sub_state <= IDLE;
                end
            end
            
            default: sub_state <= IDLE;
        endcase
    end else begin
        // 模式未激活，复位到IDLE
        sub_state <= IDLE;
        alloc_req <= 1'b0;
        commit_req <= 1'b0;
        mem_wr_en <= 1'b0;
    end
end

endmodule