`timescale 1ns/1ps
module tb_dc_blocker;
    reg clk = 0;
    always #5 clk = ~clk; // 100 MHz test clock
    reg resetn = 0;
    reg in_valid = 0;
    reg signed [15:0] din = 0;
    wire signed [15:0] dout;
    wire out_valid;
    localparam signed [15:0] ALPHA_Q15 = 16'sd32604;
    dc_blocker #(.ALPHA_Q15(ALPHA_Q15)) dut (
        .clk(clk), .resetn(resetn), .in_valid(in_valid), .din(din),
        .dout(dout), .out_valid(out_valid)
    );

    // Independent, fixed-width direct-equation reference. Only committed on input-valid.
    reg signed [15:0] ref_x = 0;
    reg signed [31:0] ref_y = 0;
    reg signed [15:0] ref_out = 0;
    reg ref_valid = 0;
    reg signed [63:0] product;
    reg signed [63:0] intermediate;
    reg signed [31:0] next_y;
    integer samples_checked = 0;
    integer cycles_checked = 0;
    integer initial_step = 0;
    integer final_dc = 0;

    function signed [15:0] clip16;
        input signed [31:0] v;
        begin
            if (v > 32767) clip16 = 16'sh7fff;
            else if (v < -32768) clip16 = -16'sd32768;
            else clip16 = v[15:0];
        end
    endfunction

    task tick;
        input reg rst_value;
        input reg valid_value;
        input signed [15:0] input_value;
        begin
            @(negedge clk);
            resetn = rst_value;
            in_valid = valid_value;
            din = input_value;
            if (!rst_value) begin
                ref_x = 0;
                ref_y = 0;
                ref_out = 0;
                ref_valid = 0;
            end else if (valid_value) begin
                product = $signed(ref_y) * $signed(ALPHA_Q15);
                intermediate = $signed(input_value) - $signed(ref_x) + (product >>> 15);
                next_y = intermediate[31:0];
                ref_x = input_value;
                ref_y = next_y;
                ref_out = clip16(next_y);
                ref_valid = 1;
            end else begin
                ref_valid = 0;
            end
            @(posedge clk);
            #1;
            cycles_checked = cycles_checked + 1;
            if (out_valid !== ref_valid || dout !== ref_out) begin
                $display("DC_FAIL cycle=%0d valid=%b expected_valid=%b input=%0d output=%0d expected=%0d ref_y=%0d", cycles_checked, out_valid, ref_valid, $signed(input_value), $signed(dout), $signed(ref_out), $signed(ref_y));
                $fatal(1, "DC_BLOCKER_REFERENCE_MISMATCH");
            end
            if (valid_value && rst_value) samples_checked = samples_checked + 1;
        end
    endtask

    integer i;
    reg signed [15:0] hold_before;
    initial begin
        $display("DC_BLOCKER_TEST_BEGIN alpha_q15=%0d", $signed(ALPHA_Q15));
        tick(0,0,0);
        tick(0,0,0);
        if (dout !== 0 || out_valid !== 0) $fatal(1,"RESET_FAIL");
        $display("DC_RESET_PASS");
        // First sample of a DC step is a positive high-pass transient.
        tick(1,1,10000);
        initial_step = $signed(dout);
        if (initial_step !== 10000) $fatal(1,"DC_STEP_FIRST_SAMPLE_FAIL");
        for (i=0;i<1000;i=i+1) tick(1,1,10000);
        final_dc = $signed(dout);
        if (final_dc < -200 || final_dc > 200) $fatal(1,"DC_STEADY_DECAY_FAIL");
        $display("DC_STEP_DECAY_PASS first=%0d after_1001_samples=%0d",initial_step,final_dc);
        // With valid low, reference and RTL must hold their last output.
        hold_before = dout;
        for (i=0;i<12;i=i+1) tick(1,0,-12000);
        if (dout !== hold_before) $fatal(1,"DC_PAUSE_HOLD_FAIL");
        $display("DC_PAUSE_PASS");
        // Signed and alternating signals, then full-scale swings for clipping behavior.
        for (i=0;i<90;i=i+1) begin
            if (i[0]) tick(1,1,-8000);
            else tick(1,1,8000);
        end
        for (i=0;i<70;i=i+1) begin
            case (i % 5)
                0: tick(1,1,32767);
                1: tick(1,1,-32768);
                2: tick(1,1,0);
                3: tick(1,1,25000);
                4: tick(1,1,-25000);
            endcase
        end
        $display("DC_SIGNED_AND_SATURATION_PASS");
        // Reset must clear history and next sample must behave as a fresh step.
        tick(0,0,0);
        tick(0,0,0);
        tick(1,1,-5000);
        if (dout !== -16'sd5000) $fatal(1,"DC_RESET_HISTORY_FAIL");
        $display("DC_RESET_HISTORY_PASS");
        $display("DC_BLOCKER_TEST_PASS checked_samples=%0d checked_cycles=%0d",samples_checked,cycles_checked);
        $finish;
    end
    initial begin #200000; $fatal(1,"DC_TEST_TIMEOUT"); end
endmodule
