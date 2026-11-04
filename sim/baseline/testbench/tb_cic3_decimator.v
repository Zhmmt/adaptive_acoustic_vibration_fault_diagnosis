`timescale 1ns/1ps
module tb_cic3_decimator;
    localparam integer R = 8;
    localparam integer W = 40;
    localparam integer MAX_SAMPLES = 2048;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg resetn = 1'b0;
    reg sample_valid = 1'b0;
    reg pdm_bit = 1'b0;
    wire signed [W-1:0] dout;
    wire out_valid;

    cic3_decimator #(.R(R), .W(W)) dut (
        .clk(clk), .resetn(resetn), .sample_valid(sample_valid),
        .pdm_bit(pdm_bit), .dout(dout), .out_valid(out_valid)
    );

    // Independent golden model: CIC3 equals the convolution of three
    // length-R rectangular FIR windows evaluated at every Rth valid PDM bit.
    integer history [0:MAX_SAMPLES-1];
    integer nsamples = 0;
    integer outputs = 0;
    integer expected;
    integer a, b, c, index;
    integer seed = 32'h12345678;
    integer clock_edges = 0;
    reg was_valid;
    reg [W-1:0] previous_dout;

    task automatic reference_output;
        output integer value;
        integer x, y, z, idx;
        begin
            value = 0;
            for (x=0; x<R; x=x+1)
                for (y=0; y<R; y=y+1)
                    for (z=0; z<R; z=z+1) begin
                        idx = nsamples-1-x-y-z;
                        if (idx >= 0)
                            value = value + history[idx];
                    end
        end
    endtask

    // Check outputs AFTER the nonblocking assignments have settled.
    always @(posedge clk) begin
        clock_edges = clock_edges + 1;
        was_valid = sample_valid;
        previous_dout = dout;
        if (!resetn) begin
            nsamples = 0;
            #1;
            if (out_valid !== 1'b0 || dout !== {W{1'b0}})
                $fatal(1, "CIC_RESET_FAIL valid=%b dout=%0d", out_valid, $signed(dout));
        end else if (was_valid) begin
            if (nsamples >= MAX_SAMPLES)
                $fatal(1, "TESTBENCH_HISTORY_OVERFLOW");
            history[nsamples] = pdm_bit ? 1 : -1;
            nsamples = nsamples + 1;
            if ((nsamples % R) == 0)
                reference_output(expected);
            #1;
            if ((nsamples % R) == 0) begin
                if (out_valid !== 1'b1 || $signed(dout) !== expected)
                    $fatal(1, "CIC_MISMATCH sample=%0d expected=%0d actual=%0d out_valid=%b",
                           nsamples, expected, $signed(dout), out_valid);
                outputs = outputs + 1;
                if (outputs <= 5 || outputs % 10 == 0)
                    $display("CIC_PASS output=%0d sample=%0d value=%0d", outputs, nsamples, $signed(dout));
            end else if (out_valid !== 1'b0)
                $fatal(1, "CIC_UNEXPECTED_VALID sample=%0d", nsamples);
        end else begin
            #1;
            if (out_valid !== 1'b0)
                $fatal(1, "CIC_VALID_DURING_INPUT_GAP");
            if (dout !== previous_dout)
                $fatal(1, "CIC_OUTPUT_CHANGED_WITHOUT_VALID_INPUT");
        end
    end

    task automatic feed;
        input reg bit_value;
        input reg is_valid;
        begin
            @(negedge clk);
            pdm_bit = bit_value;
            sample_valid = is_valid;
        end
    endtask

    integer j;
    initial begin
        $display("CIC3_TEST_BEGIN R=%0d W=%0d", R, W);
        repeat (4) @(negedge clk);
        resetn = 1'b1;
        // Positive full scale, including startup transient and steady state.
        for (j=0; j<6*R; j=j+1) feed(1'b1, 1'b1);
        // Insert irregular sample_valid gaps; the filter must not advance.
        for (j=0; j<2*R; j=j+1) begin
            feed(1'b0, 1'b0);
            feed(1'b1, 1'b1);
        end
        // Negative full scale, alternating pattern, then deterministic PRBS.
        for (j=0; j<6*R; j=j+1) feed(1'b0, 1'b1);
        for (j=0; j<6*R; j=j+1) feed(j%2, 1'b1);
        for (j=0; j<6*R; j=j+1) begin
            seed = (seed * 1103515245 + 12345);
            feed(seed[16], 1'b1);
        end
        feed(1'b0, 1'b0);
        repeat (3) @(negedge clk);
        // Reset midstream and restart model from zero history.
        resetn = 1'b0;
        repeat (3) @(negedge clk);
        resetn = 1'b1;
        for (j=0; j<4*R; j=j+1) feed(j%3 != 0, 1'b1);
        feed(1'b0, 1'b0);
        repeat (3) @(negedge clk);
        if (outputs < 30)
            $fatal(1, "CIC_INSUFFICIENT_OUTPUTS %0d", outputs);
        $display("CIC3_DECIMATOR_TEST_PASS checked_outputs=%0d", outputs);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "CIC_TIMEOUT");
    end
endmodule
