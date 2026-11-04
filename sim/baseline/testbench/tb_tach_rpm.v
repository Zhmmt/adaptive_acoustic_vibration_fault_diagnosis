`timescale 1ns/1ps
// Functional verification of the actual RS555 tach_rpm.v.
// CLK_HZ is reduced to 100000 to speed up simulation; the one-second
// window in DUT therefore lasts 100000 simulated clock cycles.
module tb_tach_rpm;
  localparam integer CLK_HZ_SIM = 100000;
  localparam integer PPR = 20;
  reg clk = 0;
  always #5 clk = ~clk;
  reg resetn = 0;
  reg tach_in = 0;
  wire [15:0] rpm;
  wire pulse_seen;
  integer period_cycles = 0;
  integer phase = 0;
  integer i;
  integer low_bound, high_bound;
  integer measured_rpm;

  tach_rpm #(.CLK_HZ(CLK_HZ_SIM), .PULSES_PER_REV(PPR)) dut (
    .clk(clk), .resetn(resetn), .tach_in(tach_in),
    .rpm(rpm), .pulse_seen(pulse_seen));

  // Generate pulses synchronous to the simulation clock. High width = 40 cycles.
  always @(negedge clk) begin
    if (!resetn || period_cycles == 0) begin
      phase = 0;
      tach_in = 0;
    end else begin
      tach_in = (phase < 40);
      if (phase >= period_cycles-1) phase = 0;
      else phase = phase + 1;
    end
  end

  task check_speed;
    input integer hz;
    input integer expected_rpm;
    begin
      @(negedge clk);
      if (hz == 0) period_cycles = 0;
      else period_cycles = CLK_HZ_SIM / hz;
      phase = 0;
      // Wait through two full windows so that the reported value does
      // not mix pulse frequencies from old and new operating conditions.
      repeat (2*CLK_HZ_SIM+20) @(posedge clk);
      // One-count quantization at 20 pulses/rev means 3 RPM per pulse.
      low_bound  = expected_rpm - 3;
      if (low_bound < 0) low_bound = 0;
      high_bound = expected_rpm + 3;
      measured_rpm = rpm;
      if (measured_rpm < low_bound || measured_rpm > high_bound) begin
        $display("TACH_FAIL input=%0dHz expected=%0d actual=%0d", hz, expected_rpm, rpm);
        $fatal(1, "TACH_RPM_MISMATCH");
      end
      $display("TACH_PASS input=%0dHz expected=%0d actual=%0d", hz, expected_rpm, rpm);
    end
  endtask

  initial begin
    repeat (6) @(negedge clk);
    resetn = 1;
    check_speed(100, 300);
    if (pulse_seen !== 1'b1) $fatal(1, "PULSE_SEEN_NOT_SET");
    check_speed(200, 600);
    check_speed(300, 900);
    check_speed(400, 1200);
    check_speed(500, 1500);
    check_speed(0, 0);
    // Check reset clears both output flags.
    @(negedge clk); resetn = 0;
    repeat (4) @(posedge clk);
    if (rpm !== 0 || pulse_seen !== 0) $fatal(1, "RESET_OUTPUT_FAIL");
    $display("RESET_OUTPUT_PASS");
    $display("TACH_RPM_TEST_PASS");
    $finish;
  end

  initial begin
    #15000000;
    $fatal(1, "TACH_TEST_TIMEOUT");
  end
endmodule
