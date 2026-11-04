`timescale 1ns/1ps
module tb_fir31;
  reg clk = 1'b0;
  always #5 clk = ~clk;
  reg resetn = 1'b0;
  reg in_valid = 1'b0;
  reg signed [15:0] din = 16'sd0;
  wire signed [15:0] dout;
  wire out_valid;
  fir31 dut (.clk(clk), .resetn(resetn), .in_valid(in_valid), .din(din),
             .dout(dout), .out_valid(out_valid));

  // Independent reference convolution: 31 Q15 taps, 64-bit accumulator.
  integer coeff[0:30];
  integer history[0:30];
  integer samples_checked = 0;
  integer valid_checked = 0;
  integer idle_checked = 0;
  integer reset_checked = 0;
  integer k;
  integer random_seed = 32'h13579bdf;
  reg signed [63:0] acc;
  reg signed [63:0] scaled;
  reg signed [15:0] expected;
  reg signed [15:0] last_expected = 0;
  integer stimulus_index = 0;

  initial begin
    coeff[ 0]=-39;   coeff[ 1]= 67;  coeff[ 2]=-68; coeff[ 3]= 0;
    coeff[ 4]=156;   coeff[ 5]=-324; coeff[ 6]=326; coeff[ 7]=0;
    coeff[ 8]=-620;  coeff[ 9]=1187; coeff[10]=-1137;coeff[11]=0;
    coeff[12]=2244;  coeff[13]=-5011;coeff[14]=7306; coeff[15]=24593;
    coeff[16]=7306;  coeff[17]=-5011;coeff[18]=2244; coeff[19]=0;
    coeff[20]=-1137; coeff[21]=1187; coeff[22]=-620; coeff[23]=0;
    coeff[24]=326;   coeff[25]=-324;coeff[26]=156;  coeff[27]=0;
    coeff[28]=-68;   coeff[29]=67;  coeff[30]=-39;
    for (k=0; k<31; k=k+1) history[k]=0;
  end

  task apply_reset;
    integer j;
    begin
      @(negedge clk);
      resetn=0; in_valid=0; din=0;
      @(posedge clk); #1;
      if (dout !== 16'sd0 || out_valid !== 1'b0)
        $fatal(1, "RESET_FAIL dout=%0d out_valid=%b", dout, out_valid);
      for (j=0; j<31; j=j+1) history[j]=0;
      last_expected=0;
      reset_checked=reset_checked+1;
      resetn=1;
      $display("FIR_RESET_PASS count=%0d", reset_checked);
    end
  endtask

  task send_sample;
    input integer x;
    input integer v;
    integer j;
    begin
      // Drive at falling edge; check outputs after next rising edge.
      @(negedge clk);
      din=x;
      in_valid=(v!=0);
      if (v!=0) begin
        for(j=30;j>0;j=j-1) history[j]=history[j-1];
        history[0]=x;
        acc=0;
        for(j=0;j<31;j=j+1)
          acc=acc + $signed(history[j]) * $signed(coeff[j]);
        scaled = acc >>> 15;
        if (scaled > 32767) expected=16'sh7fff;
        else if (scaled < -32768) expected=-16'sd32768;
        else expected=scaled[15:0];
      end else begin
        expected=last_expected;
      end
      @(posedge clk); #1;
      if (out_valid !== (v!=0))
        $fatal(1, "FIR_VALID_FAIL stimulus=%0d valid=%0d actual=%b",stimulus_index,v,out_valid);
      if (dout !== expected)
        $fatal(1, "FIR_DATA_FAIL stimulus=%0d din=%0d valid=%0d expected=%0d actual=%0d",stimulus_index,x,v,expected,dout);
      last_expected=expected;
      stimulus_index=stimulus_index+1;
      if(v!=0) samples_checked=samples_checked+1;
      else idle_checked=idle_checked+1;
      valid_checked=valid_checked+1;
    end
  endtask

  integer t;
  integer rng;
  initial begin
    $display("FIR31_TEST_BEGIN input_width=16 taps=31 q15_shift=15");
    apply_reset();
    // Single positive impulse: exercises each tap, including negative coefficients.
    send_sample(20000,1);
    for(t=0;t<35;t=t+1) send_sample(0,1);
    $display("FIR_IMPULSE_PASS");
    // Idle cycles must not advance the tap history or produce out_valid.
    for(t=0;t<8;t=t+1) send_sample(1234,0);
    $display("FIR_IDLE_PASS");
    // Negative impulse after reset.
    apply_reset();
    send_sample(-20000,1);
    for(t=0;t<35;t=t+1) send_sample(0,1);
    $display("FIR_NEGATIVE_IMPULSE_PASS");
    // DC response, alternating signs, and clipping extremes.
    apply_reset();
    for(t=0;t<50;t=t+1) send_sample(12000,1);
    $display("FIR_DC_PASS steady=%0d",dout);
    for(t=0;t<64;t=t+1) send_sample((t%2)?-16000:16000,1);
    $display("FIR_ALTERNATING_PASS");
    for(t=0;t<50;t=t+1) send_sample((t%3)?32767:-32768,1);
    $display("FIR_EXTREME_PASS");
    // Deterministic mixed values; interleaved gaps.
    for(t=0;t<128;t=t+1) begin
      rng = $random(random_seed);
      if ((t % 7)==0) send_sample(rng >>> 16,0);
      else send_sample(rng >>> 16,1);
    end
    $display("FIR_MIXED_PASS");
    // Reset mid-stream and verify history has been cleared.
    apply_reset();
    send_sample(0,1);
    if (dout !== 16'sd0) $fatal(1,"FIR_RESET_HISTORY_FAIL");
    $display("FIR_RESET_HISTORY_PASS");
    $display("FIR31_TEST_PASS checked_samples=%0d checked_idle=%0d checked_resets=%0d", samples_checked,idle_checked,reset_checked);
    $finish;
  end
  initial begin
    #100000;
    $fatal(1,"FIR_TIMEOUT");
  end
endmodule
