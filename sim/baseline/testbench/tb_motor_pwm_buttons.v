`timescale 1ns/1ps
// RS555 motor_pwm RTL functional regression: active-low buttons and limits.
// Accelerated parameters: CLK_HZ=10000, PWM_HZ=100; button debounce=200 clocks.
// The separate 100 MHz / 25 kHz testbench verifies production PWM timing.
module tb_motor_pwm_buttons;
  reg clk = 0;
  reg resetn = 0;
  reg btn0 = 1, btn1 = 1, btn2 = 1, btn3 = 1;
  reg estop = 0;
  wire rpwm, lpwm, en_out;
  wire [7:0] duty_percent;

  always #5 clk = ~clk;

  motor_pwm #(.CLK_HZ(10000), .PWM_HZ(100)) dut (
    .clk(clk), .resetn(resetn),
    .btn0(btn0), .btn1(btn1), .btn2(btn2), .btn3(btn3),
    .estop(estop), .rpwm(rpwm), .lpwm(lpwm),
    .en_out(en_out), .duty_percent(duty_percent)
  );

  task check_duty;
    input integer expected;
    begin
      if (duty_percent !== expected)
        $fatal(1, "DUTY_MISMATCH expected=%0d observed=%0d at=%0t", expected, duty_percent, $time);
      if (lpwm !== 1'b0)
        $fatal(1, "LPWM_NOT_LOW at=%0t", $time);
    end
  endtask

  // A press and release each span >2 debounce sampling windows.
  task press_button;
    input integer index;
    begin
      @(negedge clk);
      case (index)
        0: btn0 = 0;
        1: btn1 = 0;
        2: btn2 = 0;
        3: btn3 = 0;
        default: $fatal(1, "BAD_BUTTON_INDEX");
      endcase
      repeat (450) @(negedge clk);
      case (index)
        0: btn0 = 1;
        1: btn1 = 1;
        2: btn2 = 1;
        3: btn3 = 1;
      endcase
      repeat (450) @(negedge clk);
    end
  endtask

  integer i;
  initial begin
    repeat (5) @(negedge clk);
    resetn = 1;
    repeat (10) @(negedge clk);
    check_duty(50);
    if (en_out !== 1'b0 || rpwm !== 1'b0)
      $fatal(1, "RESET_STOP_FAILED");
    $display("RESET_STOP_PASS duty=50%%");

    press_button(3);
    if (en_out !== 1'b1) $fatal(1, "BTN3_START_FAILED");
    $display("BTN3_START_PASS");

    press_button(0);
    check_duty(45);
    $display("BTN0_MINUS_5_PASS duty=45%%");

    press_button(2);
    if (en_out !== 1'b0 || rpwm !== 1'b0)
      $fatal(1, "BTN2_STOP_FAILED");
    $display("BTN2_STOP_PASS");

    press_button(3);
    if (en_out !== 1'b1) $fatal(1, "RESTART_FAILED");
    $display("RESTART_PASS");

    // 45 -> 0: 9 presses, then one extra press checks lower saturation.
    for (i=0; i<9; i=i+1) begin
      press_button(0);
      check_duty(40 - i*5);
    end
    check_duty(0);
    if (rpwm !== 1'b0) $fatal(1, "ZERO_DUTY_PWM_NOT_LOW");
    press_button(0);
    check_duty(0);
    $display("LOWER_BOUND_PASS duty=0%%");

    // 0 -> 100: 20 presses, then one extra press checks upper saturation.
    for (i=1; i<=20; i=i+1) begin
      press_button(1);
      check_duty(i*5);
    end
    press_button(1);
    check_duty(100);
    if (en_out !== 1'b1 || rpwm !== 1'b1)
      $fatal(1, "FULL_DUTY_PWM_NOT_HIGH");
    $display("UPPER_BOUND_PASS duty=100%%");

    @(negedge clk); estop = 1;
    #1;
    if (en_out !== 1'b0 || rpwm !== 1'b0)
      $fatal(1, "ESTOP_FAILED");
    @(negedge clk); estop = 0;
    repeat (8) @(negedge clk);
    if (en_out !== 1'b0 || rpwm !== 1'b0)
      $fatal(1, "ESTOP_AUTO_RESTART_FAILED");
    press_button(3);
    if (en_out !== 1'b1) $fatal(1, "POST_ESTOP_RESTART_FAILED");
    $display("ESTOP_AND_RESTART_PASS");
    $display("MOTOR_PWM_BUTTONS_TEST_PASS");
    $finish;
  end

  initial begin
    #1000000;
    $fatal(1, "TIMEOUT");
  end
endmodule
