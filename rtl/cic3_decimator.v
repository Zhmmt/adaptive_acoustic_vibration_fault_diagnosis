`timescale 1ns/1ps
module cic3_decimator #(
    parameter integer R = 125,
    parameter integer W = 40
)(
    input  wire clk,
    input  wire resetn,
    input  wire sample_valid,
    input  wire pdm_bit,
    output reg signed [W-1:0] dout,
    output reg out_valid
);
    reg signed [W-1:0] i1, i2, i3;
    reg signed [W-1:0] d1, d2, d3;
    reg [15:0] decim_cnt;

    wire signed [W-1:0] xin = pdm_bit ? {{(W-1){1'b0}},1'b1} : {W{1'b1}};
    // Explicit next-state arithmetic matches the validated Stage 6 CIC3 core:
    // the comb uses the integrator value including the current valid input.
    wire signed [W-1:0] i1_next = i1 + xin;
    wire signed [W-1:0] i2_next = i2 + i1_next;
    wire signed [W-1:0] i3_next = i3 + i2_next;
    wire signed [W-1:0] c1_next = i3_next - d1;
    wire signed [W-1:0] c2_next = c1_next - d2;
    wire signed [W-1:0] c3_next = c2_next - d3;

    always @(posedge clk) begin
        out_valid <= 1'b0;
        if (!resetn) begin
            i1 <= 0; i2 <= 0; i3 <= 0;
            d1 <= 0; d2 <= 0; d3 <= 0;
            decim_cnt <= 0;
            dout <= 0;
        end else if (sample_valid) begin
            i1 <= i1_next;
            i2 <= i2_next;
            i3 <= i3_next;
            if (decim_cnt >= R-1) begin
                decim_cnt <= 0;
                d1 <= i3_next;
                d2 <= c1_next;
                d3 <= c2_next;
                dout <= c3_next;
                out_valid <= 1'b1;
            end else begin
                decim_cnt <= decim_cnt + 1'b1;
            end
        end
    end
endmodule
