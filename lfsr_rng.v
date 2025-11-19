// ========================================
// LFSR random number generator module
// Purpose: generate pseudo-random number sequence
// ========================================

`timescale 1ns / 1ps

module lfsr_rng #(
    parameter SEED = 16'hACE1
)(
    input wire clk,
    input wire rst_n,
    input wire [3:0] max_value,        // maximum value limit
    output wire [3:0] random_value     // random value output
);

reg [15:0] lfsr;

// LFSR feedback polynomial: x^16 + x^14 + x^13 + x^11 + 1
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        lfsr <= SEED;
    end else begin
        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    end
end

// Limit output range
assign random_value = (lfsr[3:0] <= max_value) ? lfsr[3:0] : (lfsr[3:0] % (max_value + 1));

endmodule
