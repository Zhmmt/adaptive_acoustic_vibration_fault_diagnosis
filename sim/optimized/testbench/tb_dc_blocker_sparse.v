`timescale 1ns/1ps
// Sparse-valid bit-exact functional test for pipelined DC blocker.
module tb_dc_blocker_sparse;
    reg clk=0;
    always #5 clk=~clk;
    reg resetn=0, in_valid=0;
    reg signed [15:0] din=0;
    wire signed [15:0] dout;
    wire out_valid;
    localparam signed [15:0] ALPHA_Q15=16'sd32604;
    dc_blocker #(.ALPHA_Q15(ALPHA_Q15)) dut(
        .clk(clk), .resetn(resetn), .in_valid(in_valid), .din(din),
        .dout(dout), .out_valid(out_valid));

    reg signed [15:0] ref_x=0;
    reg signed [31:0] ref_y=0;
    reg signed [47:0] ref_product;
    reg signed [31:0] ref_next;
    reg signed [15:0] ref_out;
    integer checked=0, i;

    function signed [15:0] clip16;
        input signed [31:0] v;
        begin
            if (v > 32767)       clip16=16'sh7fff;
            else if (v < -32768) clip16=-16'sd32768;
            else                 clip16=v[15:0];
        end
    endfunction

    task reset_design;
        begin
            @(negedge clk); resetn=0; in_valid=0; din=0;
            ref_x=0; ref_y=0;
            repeat(4) @(posedge clk);
            #1;
            if (dout !== 0 || out_valid !== 0) $fatal(1,"DC_RESET_FAIL");
            @(negedge clk); resetn=1;
        end
    endtask

    task check_sample;
        input signed [15:0] v;
        begin
            @(negedge clk);
            in_valid=1; din=v;
            ref_product=$signed(ref_y)*$signed(ALPHA_Q15);
            ref_next=$signed(v)-$signed(ref_x)+(ref_product >>> 15);
            ref_x=v;
            ref_y=ref_next;
            ref_out=clip16(ref_next);
            @(posedge clk); #1;
            if (out_valid !== 0) $fatal(1,"DC_EARLY_VALID sample=%0d at launch",checked);
            @(negedge clk); in_valid=0;
            repeat (2) begin
                @(posedge clk); #1;
                if (out_valid !== 0) $fatal(1,"DC_EARLY_VALID sample=%0d",checked);
            end
            @(posedge clk); #1;
            if (out_valid !== 1 || dout !== ref_out)
                $fatal(1,"DC_MISMATCH sample=%0d in=%0d got=%0d exp=%0d valid=%b", 
                       checked,$signed(v),$signed(dout),$signed(ref_out),out_valid);
            @(posedge clk); #1;
            if (out_valid !== 0 || dout !== ref_out)
                $fatal(1,"DC_HOLD_FAIL sample=%0d",checked);
            checked=checked+1;
        end
    endtask

    initial begin
        reset_design();
        check_sample(10000);
        for (i=0;i<300;i=i+1) check_sample(10000);
        for (i=0;i<200;i=i+1) begin
            case (i%8)
              0:check_sample(32767);
              1:check_sample(-32768);
              2:check_sample(0);
              3:check_sample(-25000);
              4:check_sample(25000);
              5:check_sample(8000);
              6:check_sample(-8000);
              7:check_sample(1);
            endcase
        end
        reset_design();
        check_sample(-5000);
        if (dout !== -16'sd5000) $fatal(1,"DC_RESET_HISTORY_FAIL");
        $display("DC_BLOCKER_SPARSE_TEST_PASS checked=%0d output_latency=3_clocks",checked);
        $finish;
    end
    initial begin #1000000; $fatal(1,"DC_SPARSE_TEST_TIMEOUT"); end
endmodule
