`timescale 1ns/1ps
module tb_fir31_pipeline;
  reg clk = 1'b0;
  always #5 clk = ~clk;
  reg resetn = 1'b0;
  reg in_valid = 1'b0;
  reg signed [15:0] din = 0;
  wire signed [15:0] dout;
  wire out_valid;
  fir31 dut (.clk(clk), .resetn(resetn), .in_valid(in_valid), .din(din),
             .dout(dout), .out_valid(out_valid));

  integer coeff[0:30];
  integer history[0:30];
  reg signed [63:0] acc, scaled;
  reg signed [15:0] expected;
  reg signed [15:0] expected_pipe[0:5];
  reg valid_pipe[0:5];
  reg signed [15:0] held_output;
  integer i, n_checked, stimulus_index, random_seed, rng;

  initial begin
    coeff[ 0]=-39;   coeff[ 1]= 67; coeff[ 2]=-68; coeff[ 3]=0;
    coeff[ 4]=156;   coeff[ 5]=-324;coeff[ 6]=326; coeff[ 7]=0;
    coeff[ 8]=-620;  coeff[ 9]=1187;coeff[10]=-1137;coeff[11]=0;
    coeff[12]=2244;  coeff[13]=-5011;coeff[14]=7306;coeff[15]=24593;
    coeff[16]=7306;  coeff[17]=-5011;coeff[18]=2244;coeff[19]=0;
    coeff[20]=-1137; coeff[21]=1187;coeff[22]=-620;coeff[23]=0;
    coeff[24]=326;   coeff[25]=-324;coeff[26]=156;coeff[27]=0;
    coeff[28]=-68;   coeff[29]=67;coeff[30]=-39;
    for (i=0;i<31;i=i+1) history[i]=0;
    for (i=0;i<6;i=i+1) begin expected_pipe[i]=0; valid_pipe[i]=0; end
    held_output=0; n_checked=0; stimulus_index=0; random_seed=32'h13579bdf;
  end

  task apply_reset;
    integer j;
    begin
      @(negedge clk); resetn=0; in_valid=0; din=0;
      @(posedge clk); #1;
      if (out_valid !== 1'b0 || dout !== 16'sd0)
        $fatal(1,"RESET_FAIL valid=%b dout=%0d",out_valid,dout);
      for (j=0;j<31;j=j+1) history[j]=0;
      for (j=0;j<6;j=j+1) begin expected_pipe[j]=0; valid_pipe[j]=0; end
      held_output=0;
      @(negedge clk); resetn=1;
    end
  endtask

  task send_sample;
    input integer x;
    input integer v;
    integer j;
    begin
      @(negedge clk); din=x; in_valid=(v!=0);
      expected=0;
      if (v!=0) begin
        for(j=30;j>0;j=j-1) history[j]=history[j-1];
        history[0]=x;
        acc=0;
        for(j=0;j<31;j=j+1)
          acc=acc + $signed(history[j]) * $signed(coeff[j]);
        scaled=acc >>> 15;
        if (scaled > 32767) expected=16'sh7fff;
        else if (scaled < -32768) expected=-16'sd32768;
        else expected=scaled[15:0];
      end
      @(posedge clk); #1;
      // The current input at E0 must appear at output at E6.
      if (out_valid !== valid_pipe[5])
        $fatal(1,"VALID_FAIL idx=%0d got=%b expected=%b",stimulus_index,out_valid,valid_pipe[5]);
      if (valid_pipe[5]) held_output=expected_pipe[5];
      if (dout !== held_output)
        $fatal(1,"DATA_FAIL idx=%0d dout=%0d expected=%0d",stimulus_index,dout,held_output);
      if (valid_pipe[5]) n_checked=n_checked+1;
      for(j=5;j>0;j=j-1) begin
        valid_pipe[j]=valid_pipe[j-1];
        expected_pipe[j]=expected_pipe[j-1];
      end
      valid_pipe[0]=(v!=0);
      expected_pipe[0]=expected;
      stimulus_index=stimulus_index+1;
    end
  endtask

  integer t;
  initial begin
    apply_reset();
    send_sample(20000,1);
    for(t=0;t<45;t=t+1) send_sample(0,1);
    $display("FIR_IMPULSE_PASS");
    for(t=0;t<10;t=t+1) send_sample(1234,0);
    $display("FIR_IDLE_PASS");
    apply_reset();
    send_sample(-20000,1);
    for(t=0;t<45;t=t+1) send_sample(0,1);
    $display("FIR_NEGATIVE_IMPULSE_PASS");
    apply_reset();
    for(t=0;t<60;t=t+1) send_sample(12000,1);
    for(t=0;t<64;t=t+1) send_sample((t%2)?-16000:16000,1);
    for(t=0;t<50;t=t+1) send_sample((t%3)?32767:-32768,1);
    for(t=0;t<128;t=t+1) begin
      rng=$random(random_seed);
      send_sample(rng >>> 16, ((t%7)!=0));
    end
    // Empty the last 6 pipeline positions and verify output hold.
    for(t=0;t<12;t=t+1) send_sample(0,0);
    $display("FIR31_PIPELINE_TEST_PASS checked=%0d latency_cycles=6",n_checked);
    $finish;
  end
  initial begin
    #100000;
    $fatal(1,"FIR_TIMEOUT");
  end
endmodule
