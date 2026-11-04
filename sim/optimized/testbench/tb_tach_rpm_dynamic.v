`timescale 1ns/1ps
// RS555 HC-020K tachometer dynamic verification
// DUT is the user's unmodified tach_rpm.v.
// This test accelerates the 1-second gate: 100000 cycles at a 10 ns simulation clock.
module tb_tach_rpm_dynamic;
  localparam integer CLK_HZ_SIM = 100000;
  localparam integer PPR = 20;
  reg clk = 0;
  always #5 clk = ~clk;
  reg resetn = 0;
  reg tach_in = 0;
  wire [15:0] rpm;
  wire pulse_seen;

  integer period_cycles = 0;
  integer high_cycles = 40;
  integer phase = 0;
  integer measured;
  integer low_bound;
  integer high_bound;

  tach_rpm #(.CLK_HZ(CLK_HZ_SIM), .PULSES_PER_REV(PPR)) dut (
    .clk(clk), .resetn(resetn), .tach_in(tach_in),
    .rpm(rpm), .pulse_seen(pulse_seen)
  );

  // All stimuli change on falling edges; registers sample on rising edges.
  always @(negedge clk) begin
    if (!resetn || period_cycles == 0) begin
      phase = 0;
      tach_in = 0;
    end else begin
      tach_in = (phase < high_cycles);
      if (phase >= period_cycles - 1) phase = 0;
      else phase = phase + 1;
    end
  end

  // Start a new input condition away from the falling-edge stimulus process.
  task configure_input;
    input integer hz;
    input integer pulse_high;
    begin
      @(posedge clk); #1;
      if (hz == 0) period_cycles = 0;
      else period_cycles = CLK_HZ_SIM / hz;
      high_cycles = pulse_high;
      phase = 0;
    end
  endtask

  task check_report;
    input [127:0] label;
    input integer expected;
    begin
      // Wait two complete counting gates, avoiding mixed old/new windows.
      repeat (2*CLK_HZ_SIM + 30) @(posedge clk);
      #1;
      measured = rpm;
      low_bound = expected - 3;
      if (low_bound < 0) low_bound = 0;
      high_bound = expected + 3;
      if (measured < low_bound || measured > high_bound) begin
        $display("DYNAMIC_FAIL %0s expected=%0d measured=%0d",label,expected,measured);
        $fatal(1,"RPM_OUT_OF_RANGE");
      end
      $display("DYNAMIC_PASS %0s expected=%0d measured=%0d",label,expected,measured);
    end
  endtask

  task do_reset;
    begin
      @(posedge clk); #1;
      resetn = 0;
      period_cycles = 0;
      repeat (5) @(posedge clk);
      #1;
      if (rpm !== 16'd0 || pulse_seen !== 1'b0)
        $fatal(1,"RESET_STATE_FAIL");
      resetn = 1;
      $display("DYNAMIC_PASS reset_output");
    end
  endtask

  initial begin
    repeat (5) @(posedge clk);
    #1; resetn = 1;

    configure_input(100,40);
    check_report("startup_100hz",300);
    if (pulse_seen !== 1'b1) $fatal(1,"PULSE_SEEN_NOT_SET");

    configure_input(500,40);
    check_report("acceleration_100_to_500hz",1500);

    configure_input(200,40);
    check_report("deceleration_500_to_200hz",600);

    configure_input(0,40);
    check_report("stop_to_zero",0);
    // pulse_seen is a sticky flag in the actual RTL; it should remain 1 until reset.
    if (pulse_seen !== 1'b1) $fatal(1,"STICKY_PULSE_SEEN_CHANGED");
    $display("DYNAMIC_PASS pulse_seen_sticky_by_design");

    // Clear history; 3-clock-wide pulses are shorter than the DUT 8-cycle filter.
    do_reset();
    configure_input(100,3);
    check_report("three_cycle_glitches_filtered",0);
    if (pulse_seen !== 1'b0) $fatal(1,"GLITCH_FALSE_PULSE_SEEN");
    $display("DYNAMIC_PASS glitch_did_not_set_pulse_seen");

    // Return to real, 40-cycle-wide pulse stimulation after glitches.
    configure_input(100,40);
    check_report("valid_pulses_after_glitches",300);
    if (pulse_seen !== 1'b1) $fatal(1,"VALID_PULSES_NOT_SEEN");

    do_reset();
    configure_input(300,40);
    check_report("restart_after_reset_300hz",900);
    $display("TACH_DYNAMIC_TEST_PASS");
    $finish;
  end

  initial begin
    #20000000;
    $fatal(1,"TACH_DYNAMIC_TIMEOUT");
  end
endmodule
