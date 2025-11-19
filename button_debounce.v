`timescale 1ns / 1ps

module button_debounce(
    input wire clk,
    input wire rst_n,
    input wire btn_in,
    output reg btn_out
);
    // 20ms 消抖 @ 100MHz (2,000,000 cycles)
    parameter CNT_MAX = 21'd2_000_000; 
    
    reg [20:0] cnt;
    reg btn_sync_0, btn_sync_1; // 同步寄存器，防止亚稳态
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_sync_0 <= 1'b0;
            btn_sync_1 <= 1'b0;
        end else begin
            btn_sync_0 <= btn_in;
            btn_sync_1 <= btn_sync_0;
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 21'd0;
            btn_out <= 1'b0;
        end else begin
            if (btn_sync_1 == btn_out) begin
                cnt <= 21'd0;
            end else begin
                cnt <= cnt + 1'b1;
                if (cnt == CNT_MAX) begin
                    btn_out <= btn_sync_1;
                end
            end
        end
    end
endmodule