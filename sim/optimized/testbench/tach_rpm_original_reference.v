`timescale 1ns/1ps
module tach_rpm_reference #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer PULSES_PER_REV = 20
)(
    input  wire        clk,
    input  wire        resetn,
    input  wire        tach_in,
    output reg [15:0]  rpm,
    output reg         pulse_seen
);
    reg [2:0] sync;
    reg [3:0] stable_cnt;
    reg       tach_filtered;
    reg       tach_prev;
    reg [31:0] gate_cnt;
    reg [15:0] pulse_cnt;

    wire rising = tach_filtered & ~tach_prev;

    always @(posedge clk) begin
        if (!resetn) begin
            sync <= 3'b000;
            stable_cnt <= 0;
            tach_filtered <= 0;
            tach_prev <= 0;
            gate_cnt <= 0;
            pulse_cnt <= 0;
            rpm <= 0;
            pulse_seen <= 0;
        end else begin
            sync <= {sync[1:0], tach_in};
            tach_prev <= tach_filtered;
            // simple 8-cycle glitch filter
            if (sync[2] == tach_filtered) begin
                stable_cnt <= 0;
            end else begin
                if (stable_cnt == 4'd7) begin
                    tach_filtered <= sync[2];
                    stable_cnt <= 0;
                end else begin
                    stable_cnt <= stable_cnt + 1'b1;
                end
            end

            if (rising) begin
                pulse_cnt <= pulse_cnt + 1'b1;
                pulse_seen <= 1'b1;
            end

            if (gate_cnt >= CLK_HZ-1) begin
                gate_cnt <= 0;
                rpm <= (pulse_cnt * 60) / PULSES_PER_REV;
                pulse_cnt <= 0;
            end else begin
                gate_cnt <= gate_cnt + 1'b1;
            end
        end
    end
endmodule
