`timescale 1ns/1ps
// Motor control ported from the user-verified standalone dianji/motor_pwm.v.
// BTN0: -5%, BTN1: +5%, BTN2: STOP, BTN3: START.
// BTN inputs are ACTIVE LOW exactly as in the verified standalone project.
// Changes required for the integrated design:
//   * PS FCLK0 is 100 MHz (standalone sysclk was 125 MHz).
//   * PWM period and 20-ms key sampling scale with CLK_HZ.
//   * Reset, two-flop input synchronizers, optional software ESTOP.
//   * Duty/motor-on outputs feed the existing LCD and status logic.
module motor_pwm #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer PWM_HZ = 25_000
)(
    input  wire       clk,
    input  wire       resetn,
    input  wire       btn0,
    input  wire       btn1,
    input  wire       btn2,
    input  wire       btn3,
    input  wire       estop,
    output wire       rpwm,
    output wire       lpwm,
    output wire       en_out,
    output wire [7:0] duty_percent
);
    // The standalone project used 5000 ticks and 250 ticks per step at
    // 125 MHz. At 100 MHz this becomes 4000 ticks and 200 ticks per step,
    // preserving 25 kHz PWM and exact 5% steps.
    localparam integer PWM_PERIOD = CLK_HZ / PWM_HZ;
    localparam integer PWM_STEP = PWM_PERIOD / 20;
    localparam integer DEBOUNCE_MAX = CLK_HZ / 50; // 20 ms

    reg [31:0] pwm_counter;
    reg [31:0] debounce_counter;
    reg [4:0]  duty_steps; // 0..20, initially 10 (50%)
    reg        motor_enable;
    reg [3:0]  btn_meta;
    reg [3:0]  btn_sync;
    reg [3:0]  key_state;
    reg [3:0]  key_state_d;

    wire [3:0] key_input = ~btn_sync;
    wire [3:0] key_press = key_state & ~key_state_d;
    wire [31:0] high_ticks = duty_steps * PWM_STEP;

    // Original default: 50% duty but STOPPED until BTN3 is pressed.
    always @(posedge clk) begin
        if (!resetn) begin
            pwm_counter      <= 32'd0;
            debounce_counter <= 32'd0;
            duty_steps       <= 5'd10;
            motor_enable     <= 1'b0;
            btn_meta         <= 4'hF;
            btn_sync         <= 4'hF;
            key_state        <= 4'd0;
            key_state_d      <= 4'd0;
        end else begin
            // Two-flop synchronization of the asynchronous pushbuttons.
            btn_meta <= {btn3, btn2, btn1, btn0};
            btn_sync <= btn_meta;

            // Original standalone design samples buttons every ~20 ms.
            if (debounce_counter < DEBOUNCE_MAX - 1) begin
                debounce_counter <= debounce_counter + 1'b1;
            end else begin
                debounce_counter <= 32'd0;
                key_state <= key_input;
            end
            key_state_d <= key_state;

            if (key_press[0] && duty_steps != 0)
                duty_steps <= duty_steps - 1'b1; // BTN0: -5%
            if (key_press[1] && duty_steps < 20)
                duty_steps <= duty_steps + 1'b1; // BTN1: +5%

            // Software ESTOP also clears the latched START state. Releasing
            // ESTOP never starts the motor without a fresh BTN3 press.
            if (estop || key_press[2])
                motor_enable <= 1'b0;            // BTN2: STOP
            else if (key_press[3])
                motor_enable <= 1'b1;            // BTN3: START

            if (pwm_counter >= PWM_PERIOD - 1)
                pwm_counter <= 32'd0;
            else
                pwm_counter <= pwm_counter + 1'b1;
        end
    end

    assign rpwm = resetn && !estop && motor_enable &&
                  (pwm_counter < high_ticks);
    assign lpwm = 1'b0; // Driver LPWM is physically tied to GND.
    assign en_out = resetn && !estop && motor_enable;
    assign duty_percent = duty_steps * 8'd5;
endmodule
