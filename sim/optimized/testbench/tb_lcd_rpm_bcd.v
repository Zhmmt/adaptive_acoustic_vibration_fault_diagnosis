`timescale 1ns/1ps
module tb_lcd_rpm_bcd;
  reg clk=0;
  always #5 clk = ~clk;
  reg resetn=0, enable=1;
  reg [15:0] rpm=0;
  wire lcd_sck, lcd_sdat, lcd_dc, lcd_cs_n, lcd_rst_n, lcd_bklt, frame_done;
  st7789p3_dashboard #(.CLK_HZ(1000), .SPI_HZ(100), .WIDTH(2), .HEIGHT(2)) dut (
    .clk(clk), .resetn(resetn), .enable(enable), .rpm(rpm),
    .vibration(16'd0), .sound_a(16'd0), .sound_b(16'd0),
    .duty(8'd0), .motor_on(1'b0), .fault(1'b0),
    .lcd_sck(lcd_sck), .lcd_sdat(lcd_sdat), .lcd_dc(lcd_dc),
    .lcd_cs_n(lcd_cs_n), .lcd_rst_n(lcd_rst_n),
    .lcd_bklt(lcd_bklt), .frame_done(frame_done)
  );
  function [15:0] expected_bcd4;
    input integer x;
    reg [3:0] th, hu, te, on;
    begin
      th=(x/1000)%10;
      hu=(x/100)%10;
      te=(x/10)%10;
      on=x%10;
      expected_bcd4={th,hu,te,on};
    end
  endfunction
  reg [15:0] samples [0:7];
  integer i;
  initial begin
    samples[0]=16'd0; samples[1]=16'd1;
    samples[2]=16'd9; samples[3]=16'd10;
    samples[4]=16'd1234; samples[5]=16'd9999;
    samples[6]=16'd10000; samples[7]=16'd65535;
    rpm=samples[0];
    repeat (3) @(negedge clk);
    resetn=1;
    for (i=0; i<8; i=i+1) begin
      @(posedge frame_done);
      #1;
      if (dut.rpm_bcd_busy !== 1'b0)
        $fatal(1, "BCD_NOT_READY idx=%0d", i);
      if (dut.rpm_bcd[15:0] !== expected_bcd4(samples[i]))
        $fatal(1,"RPM_BCD_FAIL idx=%0d rpm=%0d got=%h expected=%h", i, samples[i], dut.rpm_bcd[15:0], expected_bcd4(samples[i]));
      $display("RPM_BCD_PASS idx=%0d rpm=%0d bcd=%h",i,samples[i],dut.rpm_bcd[15:0]);
      if (i < 7) rpm=samples[i+1];
      @(negedge frame_done);
    end
    $display("LCD_RPM_BCD_TEST_PASS checks=8");
    $finish;
  end
  initial begin
    #5000000;
    $fatal(1,"LCD_RPM_BCD_TIMEOUT");
  end
endmodule
