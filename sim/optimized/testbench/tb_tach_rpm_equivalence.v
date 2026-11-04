`timescale 1ns/1ps
module tb_tach_rpm_equivalence;
  reg clk=0;
  always #5 clk=~clk;
  reg resetn=0, tach_in=0;
  wire [15:0] rpm_new, rpm_ref;
  wire seen_new, seen_ref;
  integer cycle_count=0;
  integer phase=0;
  integer period=120;
  integer high_width=30;

  tach_rpm #(.CLK_HZ(1000),.PULSES_PER_REV(20)) uut(
    .clk(clk),.resetn(resetn),.tach_in(tach_in),
    .rpm(rpm_new),.pulse_seen(seen_new));
  tach_rpm_reference #(.CLK_HZ(1000),.PULSES_PER_REV(20)) refdut(
    .clk(clk),.resetn(resetn),.tach_in(tach_in),
    .rpm(rpm_ref),.pulse_seen(seen_ref));

  always @(negedge clk) begin
    if (!resetn) begin
      tach_in=0;
      phase=0;
    end else begin
      cycle_count=cycle_count+1;
      if (cycle_count==2000) period=57;
      if (cycle_count==4000) period=31;
      if (cycle_count==6000) period=0; // stop
      if (cycle_count==8500) begin period=100; high_width=3; end // glitch filtering
      if (cycle_count==11000) begin period=43; high_width=20; end
      if (period==0) begin tach_in=0;phase=0; end
      else begin
        tach_in=(phase < high_width);
        phase=(phase + 1)%period;
      end
    end
    #1;
    if (rpm_new !== rpm_ref || seen_new !== seen_ref) begin
      $display("TACH_EQ_FAIL cycle=%0d new=%0d ref=%0d seen_new=%b seen_ref=%b",
        cycle_count,rpm_new,rpm_ref,seen_new,seen_ref);
      $fatal(1,"TACH_EQ_MISMATCH");
    end
  end

  initial begin
    repeat (7) @(posedge clk);
    #1 resetn=1;
    repeat (14000) @(posedge clk);
    $display("TACH_EQ_PASS checked_cycles=%0d",cycle_count);
    $finish;
  end
endmodule
