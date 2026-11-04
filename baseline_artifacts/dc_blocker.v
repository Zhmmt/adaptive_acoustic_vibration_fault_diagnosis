`timescale 1ns/1ps
module dc_blocker #(
    parameter signed [15:0] ALPHA_Q15 = 16'sd32604 // ~0.995
)(
    input wire clk,
    input wire resetn,
    input wire in_valid,
    input wire signed [15:0] din,
    output reg signed [15:0] dout,
    output reg out_valid
);
    reg signed [15:0] x_prev;
    reg signed [31:0] y_prev;
    reg signed [47:0] mult;
    reg signed [31:0] y_now;

    function signed [15:0] sat16;
        input signed [31:0] v;
        begin
            if (v > 32767) sat16 = 16'sh7fff;
            else if (v < -32768) sat16 = -16'sd32768;
            else sat16 = v[15:0];
        end
    endfunction

    always @(posedge clk) begin
        out_valid <= 1'b0;
        if (!resetn) begin
            x_prev<=0; y_prev<=0; dout<=0;
        end else if (in_valid) begin
            mult = y_prev * ALPHA_Q15;
            y_now = $signed(din) - $signed(x_prev) + (mult >>> 15);
            x_prev <= din;
            y_prev <= y_now;
            dout <= sat16(y_now);
            out_valid <= 1'b1;
        end
    end
endmodule
