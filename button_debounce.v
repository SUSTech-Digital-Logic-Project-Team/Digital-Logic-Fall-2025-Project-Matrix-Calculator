`timescale 1ns / 1ps

module button_debounce(
    input wire clk,
    input wire rst_n,
    input wire btn_in,
    output reg btn_out
);
    // 优化�?20ms 有点长，按快了可能会丢�?�建议改�? 10ms �? 15ms�?
    // 10ms @ 100MHz = 1,000,000
    parameter CNT_MAX = 21'd100; 
    
    reg [20:0] cnt;
    reg btn_sync_0, btn_sync_1; 
    
    // 第一段：信号同步（保持不变，这是对的�?
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_sync_0 <= 1'b0;
            btn_sync_1 <= 1'b0;
        end else begin
            btn_sync_0 <= btn_in;
            btn_sync_1 <= btn_sync_0;
        end
    end
    
    // 第二段：消抖计数（核心修复）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 21'd0;
            btn_out <= 1'b0; // <=== 修复：复位必须是 0 (假设按键平时�?0)
        end else begin
            // 如果同步后的输入信号 等于 当前输出信号
            if (btn_sync_1 == btn_out) begin
                cnt <= 21'd0; // 计数器清零，等待下一次变�?
            end else begin
                // 状�?�不�?致，�?始计�?
                cnt <= cnt + 1'b1;
                if (cnt == CNT_MAX) begin
                    btn_out <= btn_sync_1; // 只有维持�? CNT_MAX 这么久，才更新输�?
                end
            end
        end
    end
endmodule