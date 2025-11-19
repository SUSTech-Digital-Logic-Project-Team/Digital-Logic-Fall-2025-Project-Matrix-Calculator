// ========================================
// Display control module
// Purpose: Control 7-segment display and LED status indicators
// ========================================

`timescale 1ns / 1ps

module display_ctrl (
    input wire clk,
    input wire rst_n,
    
    // State information
    input wire [2:0] main_state,
    input wire [3:0] sub_state,
    input wire [3:0] op_type,
    input wire [3:0] error_code,
    input wire [5:0] error_timer,
    
    // Display outputs
    output reg [6:0] seg_display,
    output reg [3:0] led_status,
    output reg [6:0] seg_display_subtype // 新增：显示计算模式子类型的七段数码管
);

// 7-segment display encoding (common cathode)
// Segments: GFEDCBA (bit 6 to 0)
localparam SEG_0 = 7'b0111111;
localparam SEG_1 = 7'b0000110;
localparam SEG_2 = 7'b1011011;
localparam SEG_3 = 7'b1001111;
localparam SEG_4 = 7'b1100110;
localparam SEG_5 = 7'b1101101;
localparam SEG_6 = 7'b1111101;
localparam SEG_7 = 7'b0000111;
localparam SEG_8 = 7'b1111111;
localparam SEG_9 = 7'b1101111;
localparam SEG_A = 7'b1110111;
localparam SEG_B = 7'b1111100;
localparam SEG_C = 7'b0111001;
localparam SEG_D = 7'b1011110;
localparam SEG_E = 7'b1111001;
localparam SEG_F = 7'b1110001;
localparam SEG_OFF = 7'b0000000;

// Display main state on 7-segment
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        seg_display <= SEG_0;
    end else begin
        case (main_state)
            3'd0: seg_display <= SEG_0;  // MAIN_MENU
            3'd1: seg_display <= SEG_1;  // MODE_INPUT
            3'd2: seg_display <= SEG_2;  // MODE_GENERATE
            3'd3: seg_display <= SEG_3;  // MODE_DISPLAY
            3'd4: seg_display <= SEG_4;  // MODE_COMPUTE
            3'd5: seg_display <= SEG_5;  // MODE_SETTING
            default: seg_display <= SEG_OFF;
        endcase
    end
end

// Display sub state on 7-segment
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        seg_display <= SEG_0;
    end else begin
        case (main_state)
            3'd0: seg_display <= SEG_0;  // mode1
            3'd1: seg_display <= SEG_1;  // mode2
            3'd2: seg_display <= SEG_2;  // mode3
            3'd3: seg_display <= SEG_3;  // mode4
            3'd4: seg_display <= SEG_4;  // mode5
            3'd5: seg_display <= SEG_5;  // mode6
            default: seg_display <= SEG_OFF; // No signal
        endcase
    end
end

// LED status indicators
// LED[0]: Error indicator
// LED[1]: Active mode indicator
// LED[2]: Operation type indicator
// LED[3]: Heartbeat
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        led_status <= 4'b0000;
    end else begin
        // LED[0]: Error indicator (blinks when error_code != 0)
        led_status[0] <= (error_code != 4'd0) ? error_timer[5] : 1'b0;
        
        // LED[1]: Active mode indicator (on when not in main menu)
        led_status[1] <= (main_state != 3'd0);
        
        // LED[2]: Sub-state indicator
        led_status[2] <= (sub_state != 4'd0);
        
        // LED[3]: Heartbeat (toggles periodically)
        led_status[3] <= error_timer[4];
    end
end

endmodule
