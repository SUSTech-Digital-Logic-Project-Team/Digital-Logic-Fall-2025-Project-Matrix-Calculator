module uart_rx #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD_RATE = 115200
)(
    input wire clk,
    input wire rst_n,
    input wire rx,             // 串口输入信号
    output reg [7:0] rx_data,  // 接收到的字节数据
    output reg rx_done         // 数据接收完成标志
);

    localparam BAUD_DIV = CLK_FREQ / BAUD_RATE;

    reg [15:0] baud_cnt;
    reg [3:0] bit_idx;
    reg [9:0] rx_shift;
    reg rx_busy;
    reg rx_d1, rx_d2;

    // 同步处理防止亚稳态
    always @(posedge clk) begin
        rx_d1 <= rx;
        rx_d2 <= rx_d1;
    end

    // UART接收状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt <= 0;
            bit_idx <= 0;
            rx_busy <= 0;
            rx_done <= 0;
            rx_data <= 8'b0;
        end else begin
            rx_done <= 0;
            if (!rx_busy) begin
                if (rx_d2 == 0) begin  // 检测到起始位
                    rx_busy <= 1;
                    baud_cnt <= BAUD_DIV / 2; // 对齐到数据中间
                    bit_idx <= 0;
                end
            end else begin
                if (baud_cnt == BAUD_DIV - 1) begin
                    baud_cnt <= 0;
                    bit_idx <= bit_idx + 1;
                    case (bit_idx)
                        0: ; // 起始位
                        1,2,3,4,5,6,7,8: rx_shift[bit_idx-1] <= rx_d2;
                        9: begin
                            rx_busy <= 0;
                            rx_data <= rx_shift[7:0];
                            rx_done <= 1;
                        end
                    endcase
                end else begin
                    baud_cnt <= baud_cnt + 1;
                end
            end
        end
    end
endmodule