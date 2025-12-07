`timescale 1ns / 1ps

module button_debounce(
    input wire clk,
    input wire rst_n,
    input wire btn_in,
    output reg btn_pulse
);

    // Parameter for debounce delay
    // 100MHz clock -> 10ms debounce = 1,000,000 cycles
    parameter DEBOUNCE_TIME = 1_000_000;
    
    reg [19:0] counter;
    reg btn_stable;
    reg btn_sync_0, btn_sync_1;
    reg btn_stable_prev;

    // Synchronize input to clock domain to avoid metastability
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_sync_0 <= 1'b0;
            btn_sync_1 <= 1'b0;
        end else begin
            btn_sync_0 <= btn_in;
            btn_sync_1 <= btn_sync_0;
        end
    end

    // Debounce logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 0;
            btn_stable <= 1'b0;
            btn_pulse <= 1'b0;
            btn_stable_prev <= 1'b0;
        end else begin
            // If input changes, reset counter
            if (btn_sync_1 != btn_stable) begin
                if (counter < DEBOUNCE_TIME) begin
                    counter <= counter + 1;
                end else begin
                    // Stable for enough time, update state
                    btn_stable <= btn_sync_1;
                    counter <= 0;
                end
            end else begin
                counter <= 0;
            end
            
            // Edge detection on the STABLE signal
            // Detect Rising Edge (Press) or Falling Edge (Release)
            // Based on previous logic, it seemed to trigger on Release (Falling Edge)
            // Let's stick to Falling Edge (Release) to match previous behavior
            // Or Rising Edge (Press) if that feels more natural.
            // The previous code was ~sync0 & sync1 (Falling Edge).
            
            btn_stable_prev <= btn_stable;
            
            // Generate 1-cycle pulse on Falling Edge (1->0 transition)
            if (btn_stable_prev == 1'b1 && btn_stable == 1'b0)
                btn_pulse <= 1'b1;
            else
                btn_pulse <= 1'b0;
        end
    end

endmodule
