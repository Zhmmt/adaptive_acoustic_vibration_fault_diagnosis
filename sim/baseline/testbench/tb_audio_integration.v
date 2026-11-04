`timescale 1ns/1ps
module tb_audio_integration;
    reg clk=0, resetn=0, m_axis_tready=1;
    always #5 clk=~clk;

    wire dmic_mclk;
    wire dmic_mdat = dmic_mclk ? 1'b0 : 1'b1;
    wire signed [15:0] pcm_a, pcm_b;
    wire pcm_valid;
    wire [31:0] m_axis_tdata;
    wire [3:0] m_axis_tkeep;
    wire m_axis_tvalid, m_axis_tlast;

    // Reduced rate only for efficient functional simulation.
    // Production defaults remain HALF_DIV=25, DECIM_R=125, CIC_SHIFT=6.
    dmic_audio #(.HALF_DIV(2),.DECIM_R(8),.CIC_SHIFT(0)) audio (
        .clk(clk), .resetn(resetn), .dmic_mdat(dmic_mdat),
        .dmic_mclk(dmic_mclk), .pcm_a(pcm_a), .pcm_b(pcm_b),
        .pcm_valid(pcm_valid)
    );
    axis_stereo_frame #(.FRAME_SAMPLES(4)) axis (
        .clk(clk), .resetn(resetn), .pcm_a(pcm_a),.pcm_b(pcm_b),
        .pcm_valid(pcm_valid),.m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),.m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),.m_axis_tlast(m_axis_tlast)
    );

    reg [31:0] expected [0:255];
    integer rd=0, wr=0;
    integer transfers=0, pcm_count=0, stall_checks=0;
    integer distinct_count=0;
    reg [31:0] held_data;
    reg held_last;
    reg prev_stall=0;
    reg first_mclk_seen=0;
    reg last_mclk;

    always @(posedge clk) begin
        if (!resetn) begin
            rd=0; wr=0; transfers=0; pcm_count=0;
            stall_checks=0; distinct_count=0;
            prev_stall=0; first_mclk_seen=0; last_mclk=0;
        end else begin
            if (first_mclk_seen && dmic_mclk !== last_mclk) begin
                // MCLK transitions are expected; the input is phase-dependent.
            end
            last_mclk=dmic_mclk;
            first_mclk_seen=1;
            if (m_axis_tkeep !== 4'b1111)
                $fatal(1,"AXIS_KEEP_FAIL got=%b",m_axis_tkeep);
            if (prev_stall) begin
                if (m_axis_tvalid !== 1'b1 || m_axis_tdata !== held_data || m_axis_tlast !== held_last)
                    $fatal(1,"AXIS_STALL_STABILITY_FAIL");
                stall_checks=stall_checks+1;
            end
            // Current AXIS output represents an earlier PCM sample.
            if (m_axis_tvalid && m_axis_tready) begin
                if (rd>=wr) $fatal(1,"AXIS_UNEXPECTED_BEAT");
                if (m_axis_tdata !== expected[rd])
                    $fatal(1,"AXIS_DATA_FAIL beat=%0d expected=%h got=%h",transfers,expected[rd],m_axis_tdata);
                if (m_axis_tlast !== ((transfers%4)==3))
                    $fatal(1,"AXIS_LAST_FAIL beat=%0d last=%b",transfers,m_axis_tlast);
                rd=rd+1;
                transfers=transfers+1;
                if ((transfers%4)==0)
                    $display("AXIS_FRAME_PASS frame=%0d beats=4",transfers/4);
            end
            if (pcm_valid) begin
                pcm_count=pcm_count+1;
                if (pcm_a !== pcm_b) distinct_count=distinct_count+1;
                // This design accepts PCM only when AXIS can load it.
                if (m_axis_tready) begin
                    if (wr>=256) $fatal(1,"TESTBENCH_QUEUE_OVERFLOW");
                    expected[wr]={pcm_b,pcm_a};
                    wr=wr+1;
                end
            end
            prev_stall=m_axis_tvalid && !m_axis_tready;
            if (prev_stall) begin
                held_data=m_axis_tdata;
                held_last=m_axis_tlast;
            end
            if (transfers>=16) begin
                if (pcm_count<16 || distinct_count==0)
                    $fatal(1,"STEREO_OUTPUT_FAIL pcm=%0d distinct=%0d",pcm_count,distinct_count);
                if (stall_checks==0) $fatal(1,"NO_BACKPRESSURE_EXERCISED");
                $display("AUDIO_INTEGRATION_TEST_PASS pcm=%0d axis_beats=%0d frames=4 stall_cycles=%0d",pcm_count,transfers,stall_checks);
                $finish;
            end
        end
    end

    initial begin
        repeat(7) @(negedge clk);
        resetn=1;
        // Apply backpressure to the first pending AXI word.
        wait(m_axis_tvalid===1'b1);
        @(negedge clk) m_axis_tready=0;
        repeat(8) @(negedge clk);
        m_axis_tready=1;
    end
    initial begin
        #1000000;
        $fatal(1,"AUDIO_INTEGRATION_TIMEOUT transfers=%0d pcm=%0d",transfers,pcm_count);
    end
endmodule
