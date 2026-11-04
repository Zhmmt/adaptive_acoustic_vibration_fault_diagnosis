`timescale 1ns/1ps
// DC blocker timing experiment for the RS555 stereo audio path.
// IMPORTANT: This implementation needs >= 4 clock cycles between accepted
// input-valid pulses. The production DMIC/CIC path supplies widely spaced
// samples; this is NOT a generic 1-sample-per-clock drop-in replacement.
// Equation (bit-accurate modulo 2^32 to the original RTL):
// y[n] = x[n] - x[n-1] + ((y[n-1] * ALPHA_Q15) >>> 15)
module dc_blocker #(
    parameter signed [15:0] ALPHA_Q15 = 16'sd32604
)(
    input  wire clk,
    input  wire resetn,
    input  wire in_valid,
    input  wire signed [15:0] din,
    output reg signed [15:0] dout,
    output reg out_valid
);
    localparam [1:0] S_IDLE=2'd0, S_COMBINE=2'd1,
                     S_ADD=2'd2, S_OUTPUT=2'd3;
    reg [1:0] state;
    reg signed [15:0] x_prev;
    reg signed [31:0] y_prev;
    reg signed [15:0] input_hold, x_prev_hold;

    // 32x16 multiplication decomposed into two registered partial products.
    // The lower 16 bits of y_prev must be treated as UNSIGNED.
    reg signed [32:0] prod_low;
    reg signed [31:0] prod_high;

    reg signed [32:0] alpha_scaled;
    reg signed [17:0] delta_x;
    reg signed [31:0] y_pending;

    function signed [15:0] sat16;
        input signed [31:0] v;
        begin
            if (v > 32767)       sat16 = 16'sh7fff;
            else if (v < -32768) sat16 = -16'sd32768;
            else                 sat16 = v[15:0];
        end
    endfunction

    always @(posedge clk) begin
        out_valid <= 1'b0;
        if (!resetn) begin
            state <= S_IDLE;
            x_prev <= 16'sd0;
            y_prev <= 32'sd0;
            input_hold <= 16'sd0;
            x_prev_hold <= 16'sd0;
            prod_low <= 33'sd0;
            prod_high <= 32'sd0;
            alpha_scaled <= 33'sd0;
            delta_x <= 18'sd0;
            y_pending <= 32'sd0;
            dout <= 16'sd0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (in_valid) begin
                        input_hold <= din;
                        x_prev_hold <= x_prev;
                        x_prev <= din;
                        // 17-bit positive low limb * signed 16-bit coeff.
                        prod_low <= $signed({1'b0, y_prev[15:0]}) *
                                    $signed(ALPHA_Q15);
                        prod_high <= $signed(y_prev[31:16]) *
                                     $signed(ALPHA_Q15);
                        state <= S_COMBINE;
                    end
                end
                S_COMBINE: begin
                    // floor((hi*2^16 + lo)*alpha / 2^15)
                    // = 2*hi*alpha + floor(lo*alpha / 2^15).
                    // Exact for positive and negative values.
                    alpha_scaled <= $signed({prod_high, 1'b0}) +
                                    ($signed(prod_low) >>> 15);
                    delta_x <= $signed({{2{input_hold[15]}}, input_hold}) -
                               $signed({{2{x_prev_hold[15]}}, x_prev_hold});
                    state <= S_ADD;
                end
                S_ADD: begin
                    // Deliberate 32-bit truncation matches original y_now.
                    y_pending <= alpha_scaled +
                                 $signed({{15{delta_x[17]}}, delta_x});
                    state <= S_OUTPUT;
                end
                S_OUTPUT: begin
                    y_prev <= y_pending;
                    dout <= sat16(y_pending);
                    out_valid <= 1'b1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
