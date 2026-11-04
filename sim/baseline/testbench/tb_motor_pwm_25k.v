`timescale 1ns/1ps
// RS555 PWM frequency/duty datapath test at the actual 100 MHz / 25 kHz parameters.
// Internal motor_enable and duty_steps are forced only to bypass the 20-ms
// button sampling delay. This test does NOT verify buttons or debounce.
module tb_motor_pwm_25k;
    reg clk = 1'b0;
    reg resetn = 1'b0;
    reg btn0 = 1'b1, btn1 = 1'b1, btn2 = 1'b1, btn3 = 1'b1;
    reg estop = 1'b0;
    wire rpwm, lpwm, en_out;
    wire [7:0] duty_percent;
    always #5 clk = ~clk; // 100 MHz

    motor_pwm #(.CLK_HZ(100_000_000), .PWM_HZ(25_000)) dut (
        .clk(clk), .resetn(resetn), .btn0(btn0), .btn1(btn1),
        .btn2(btn2), .btn3(btn3), .estop(estop),
        .rpwm(rpwm), .lpwm(lpwm), .en_out(en_out),
        .duty_percent(duty_percent)
    );

    time rise1, rise2, fall1;
    task measure_pwm;
        input integer expected_duty;
        input integer expected_high_ns;
        begin
            @(posedge rpwm);
            rise1 = $time;
            @(negedge rpwm);
            fall1 = $time;
            @(posedge rpwm);
            rise2 = $time;
            $display("DUTY=%0d%% PERIOD=%0d ns HIGH=%0d ns FREQ=%.1f Hz",
                duty_percent, rise2-rise1, fall1-rise1,
                1.0e9 / (rise2-rise1));
            if ((rise2-rise1) != 40000)
                $fatal(1, "PWM period mismatch");
            if ((fall1-rise1) != expected_high_ns)
                $fatal(1, "PWM high time mismatch");
            if (duty_percent !== expected_duty || en_out !== 1'b1 || lpwm !== 1'b0)
                $fatal(1, "PWM output/status mismatch");
        end
    endtask

    initial begin
        // Reset and check default stopped state.
        repeat (5) @(negedge clk);
        resetn = 1'b1;
        repeat (3) @(negedge clk);
        if (en_out !== 1'b0 || duty_percent !== 8'd50 || rpwm !== 1'b0)
            $fatal(1, "Reset/default-stop mismatch");

        // Force only internal control state to test actual PWM timing quickly.
        force dut.motor_enable = 1'b1;
        force dut.duty_steps = 5'd10;
        measure_pwm(50, 20000);

        // Move to 55% at a period boundary; ignore one transition cycle.
        @(negedge rpwm);
        force dut.duty_steps = 5'd11;
        measure_pwm(55, 22000);

        // Emergency stop must immediately suppress both PWM and enable.
        estop = 1'b1;
        #1;
        if (rpwm !== 1'b0 || en_out !== 1'b0)
            $fatal(1, "ESTOP output not suppressed");
        $display("MOTOR_PWM_25K_TEST_PASS");
        release dut.duty_steps;
        release dut.motor_enable;
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "25-kHz PWM test timeout");
    end
endmodule
