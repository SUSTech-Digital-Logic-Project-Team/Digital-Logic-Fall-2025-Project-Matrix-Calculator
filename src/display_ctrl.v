`timescale 1ns / 1ps
`include "matrix_pkg.vh"

module display_ctrl (
    input wire clk,
    input wire rst_n,
    input wire [2:0] main_state,
    input wire [3:0] sub_state,
    input wire [3:0] op_type,
    input wire [3:0] error_code,
    input wire [4:0] countdown_val, // 倒计时数值输入 (5-bit for 5-15 seconds)
    output reg [6:0] seg_display,
    output reg [6:0] seg_countdown, // New port for countdown display
    output reg [1:0] count_down_select, // 2-bit one-hot code for countdown digit selection
    output reg [3:0] led_status,
    output reg [1:0] seg_select // 改为 output，直接由内部逻辑控制扫描
);

    // Segments: GFEDCBA
    localparam SEG_0 = 7'b1000000; // EGO1 很多是共阳极(0亮1灭)或共阴极。
    // 假设你的约束文件对应的是：1亮0灭（共阴）。如果上板发现是反的，请对以下所有值取反。
    // 基于你原本的代码，假设 1 = 亮 (Common Cathode)
    localparam S_0 = 7'b0111111;
    localparam S_1 = 7'b0000110;
    localparam S_2 = 7'b1011011;
    localparam S_3 = 7'b1001111;
    localparam S_4 = 7'b1100110;
    localparam S_5 = 7'b1101101;
    localparam S_6 = 7'b1111101;
    localparam S_7 = 7'b0000111;
    localparam S_8 = 7'b1111111;
    localparam S_9 = 7'b1101111;
    localparam S_OFF = 7'b0000000;
    
    // 特殊字符定义 (依据 PDF)
    // T (Transpose): E,F,A,B -> 像 't' (0000111) 容易混淆，通常用 F,E,D,G (0111000) -> 't' 或 E,F,A (1110000) -> '7'?
    // 建议：
    localparam CHAR_T = 7'b1111000; // Display 'T'
    localparam CHAR_A = 7'b1110111; // Display 'A'
    localparam CHAR_S = 7'b1101101; // Display 'S'
    localparam CHAR_M = 7'b0110111; // Display 'M'
    localparam CHAR_C = 7'b0111001; // Display 'C'

    reg [6:0] disp_data_mode;
    reg [6:0] disp_data_op;
    
    // 扫描计数器 (提前声明以供倒计时逻辑使用)
    // 使用 1kHz 扫描, scan_cnt[16] 翻转周期约为 1.3ms (100MHz时)
    reg [16:0] scan_cnt;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) scan_cnt <= 0;
        else scan_cnt <= scan_cnt + 1;
    end

    // 1. 解码主模式 (Digit 1 - 左侧)
    always @(*) begin
        case (main_state)
            3'd0: disp_data_mode = S_0; // Menu
            3'd1: disp_data_mode = S_1; // Input
            3'd2: disp_data_mode = S_2; // Generate
            3'd3: disp_data_mode = S_3; // Display
            3'd4: disp_data_mode = S_4; // Compute
            3'd5: disp_data_mode = S_5; // Setting
            default: disp_data_mode = S_OFF;
        endcase
    end

    // 2. 解码操作类型 (Digit 0 - 右侧)
    // 仅在 Compute 模式下有效
    always @(*) begin
        if (main_state == 3'd4) begin // Compute Mode
            case (op_type)
                3'd1: disp_data_op = CHAR_T; // Transpose
                3'd2: disp_data_op = CHAR_A; // Add
                3'd3: disp_data_op = CHAR_S; // b (Scalar)
                3'd4: disp_data_op = CHAR_M; // Mult
                3'd5: disp_data_op = CHAR_C; // Conv 
                default: disp_data_op = S_OFF;
            endcase
        end else if (error_code != 0) begin
            // 如果有错误，右侧显示 'E'
            disp_data_op = 7'b1111001; 
        end else begin
            disp_data_op = S_OFF;
        end
    end

    // 3. 倒计时显示逻辑 (两位数显示，使用独热码扫描)
    // 分离十位和个位
    wire [3:0] countdown_tens = countdown_val / 10;  // 十位 (0 or 1)
    wire [3:0] countdown_ones = countdown_val % 10;  // 个位 (0-9)
    
    // 七段数码管编码函数
    function [6:0] digit_to_seg;
        input [3:0] digit;
        begin
            case (digit)
                4'd0: digit_to_seg = S_0;
                4'd1: digit_to_seg = S_1;
                4'd2: digit_to_seg = S_2;
                4'd3: digit_to_seg = S_3;
                4'd4: digit_to_seg = S_4;
                4'd5: digit_to_seg = S_5;
                4'd6: digit_to_seg = S_6;
                4'd7: digit_to_seg = S_7;
                4'd8: digit_to_seg = S_8;
                4'd9: digit_to_seg = S_9;
                default: digit_to_seg = S_OFF;
            endcase
        end
    endfunction
    
    // 倒计时显示扫描逻辑 (使用scan_cnt[16]进行高频切换)
    always @(*) begin
        if (error_code != 0) begin
            // 使用与主显示相同的扫描时钟进行切换
            if (scan_cnt[16] == 1'b0) begin
                // 显示十位 (左侧数码管)
                count_down_select = 2'b10;
                if (countdown_tens == 0)
                    seg_countdown = S_OFF; // 十位为0时不显示
                else
                    seg_countdown = digit_to_seg(countdown_tens);
            end else begin
                // 显示个位 (右侧数码管)
                count_down_select = 2'b01;
                seg_countdown = digit_to_seg(countdown_ones);
            end
        end else begin
            seg_countdown = S_OFF; // 无错误时不显示
            count_down_select = 2'b00; // 关闭倒计时数码管
        end
    end

    // 4. 主显示扫描逻辑
    always @(*) begin
        // scan_cnt[16] 翻转周期约为 1.3ms (100MHz时)
        case (scan_cnt[16])
            1'b0: begin
                seg_select = 2'b10; // 选通左边的数码管 (Mode)
                seg_display = disp_data_mode;
            end
            1'b1: begin
                seg_select = 2'b01; // 选通右边的数码管 (Op / Error)
                seg_display = disp_data_op;
            end
        endcase
    end

    // LED 状态
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) led_status <= 4'b0000;
        else begin
            led_status[0] <= (error_code != 0); // 错误灯
            led_status[1] <= (main_state == 3'd4); // 计算模式指示灯
            led_status[2] <= (sub_state != 0);  // 忙碌/非空闲
            led_status[3] <= scan_cnt[16];      // 心跳包
        end
    end

endmodule