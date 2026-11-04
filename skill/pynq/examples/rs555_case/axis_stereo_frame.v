`timescale 1ns/1ps
module axis_stereo_frame #(
    parameter integer FRAME_SAMPLES = 4096
)(
    input  wire clk,
    input  wire resetn,
    input  wire signed [15:0] pcm_a,
    input  wire signed [15:0] pcm_b,
    input  wire pcm_valid,
    output reg [31:0] m_axis_tdata,
    output wire [3:0] m_axis_tkeep,
    output reg m_axis_tvalid,
    input  wire m_axis_tready,
    output reg m_axis_tlast
);
    reg [15:0] frame_count;
    wire transfer = m_axis_tvalid && m_axis_tready;
    wire slot_available = !m_axis_tvalid || m_axis_tready;
    wire [15:0] count_after_transfer = transfer ?
        (m_axis_tlast ? 16'd0 : frame_count + 1'b1) : frame_count;

    assign m_axis_tkeep = 4'b1111;

    always @(posedge clk) begin
        if (!resetn) begin
            m_axis_tdata <= 0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
            frame_count <= 0;
        end else begin
            if (transfer)
                frame_count <= count_after_transfer;

            // Permit a new PCM word on the same cycle the previous AXI beat is
            // accepted. Only load a fresh word when TREADY is high: while DMA
            // is idle, this prevents a stale valid word from starting a packet
            // at an arbitrary position. TLAST is counted on accepted transfers.
            if (slot_available) begin
                if (pcm_valid && m_axis_tready) begin
                    m_axis_tdata <= {pcm_b, pcm_a};
                    m_axis_tvalid <= 1'b1;
                    m_axis_tlast <= (count_after_transfer == FRAME_SAMPLES-1);
                end else begin
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast <= 1'b0;
                end
            end
        end
    end
endmodule
