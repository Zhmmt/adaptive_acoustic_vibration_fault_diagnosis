`timescale 1ns/1ps
module dmic_audio #(
    parameter integer HALF_DIV = 25,
    parameter integer DECIM_R = 125,
    parameter integer CIC_SHIFT = 6
)(
    input  wire clk,
    input  wire resetn,
    input  wire dmic_mdat,
    output reg  dmic_mclk,
    output wire signed [15:0] pcm_a,
    output wire signed [15:0] pcm_b,
    output wire pcm_valid
);
    reg [15:0] half_cnt;
    reg bit_from_rising_half;
    reg pair_valid;
    reg bit_a, bit_b;

    wire signed [39:0] cic_a, cic_b;
    wire cic_va, cic_vb;
    reg signed [15:0] cic16_a, cic16_b;
    reg cic16_valid;

    wire signed [15:0] dc_a, dc_b;
    wire dc_va, dc_vb;
    wire fir_va, fir_vb;

    function signed [15:0] sat_shift;
      input signed [39:0] v;
      reg signed [39:0] q;
      begin
        q = v >>> CIC_SHIFT;
        if (q > 32767) sat_shift = 16'sh7fff;
        else if (q < -32768) sat_shift = -16'sd32768;
        else sat_shift = q[15:0];
      end
    endfunction

    // The shared PDM line is sampled immediately BEFORE each MCLK transition.
    // This is the timing that was validated during Stage 6B on the real board.
    always @(posedge clk) begin
      pair_valid <= 1'b0;
      if (!resetn) begin
        half_cnt<=0; dmic_mclk<=0; bit_from_rising_half<=0; bit_a<=0; bit_b<=0;
      end else if (half_cnt == HALF_DIV-1) begin
        half_cnt <= 0;
        if (dmic_mclk) begin
          // about to fall: save bit driven during high half-cycle
          bit_from_rising_half <= dmic_mdat;
          dmic_mclk <= 1'b0;
        end else begin
          // about to rise: collect the other mic and process a stereo pair
          bit_a <= dmic_mdat;
          bit_b <= bit_from_rising_half;
          pair_valid <= 1'b1;
          dmic_mclk <= 1'b1;
        end
      end else half_cnt <= half_cnt + 1'b1;
    end

    cic3_decimator #(.R(DECIM_R),.W(40)) cic0(
      .clk(clk),.resetn(resetn),.sample_valid(pair_valid),.pdm_bit(bit_a),.dout(cic_a),.out_valid(cic_va));
    cic3_decimator #(.R(DECIM_R),.W(40)) cic1(
      .clk(clk),.resetn(resetn),.sample_valid(pair_valid),.pdm_bit(bit_b),.dout(cic_b),.out_valid(cic_vb));

    always @(posedge clk) begin
      cic16_valid <= 1'b0;
      if (!resetn) begin cic16_a<=0; cic16_b<=0; end
      else if (cic_va && cic_vb) begin
        cic16_a <= sat_shift(cic_a);
        cic16_b <= sat_shift(cic_b);
        cic16_valid <= 1'b1;
      end
    end

    dc_blocker dc0(.clk(clk),.resetn(resetn),.in_valid(cic16_valid),.din(cic16_a),.dout(dc_a),.out_valid(dc_va));
    dc_blocker dc1(.clk(clk),.resetn(resetn),.in_valid(cic16_valid),.din(cic16_b),.dout(dc_b),.out_valid(dc_vb));
    fir31 fir0(.clk(clk),.resetn(resetn),.in_valid(dc_va),.din(dc_a),.dout(pcm_a),.out_valid(fir_va));
    fir31 fir1(.clk(clk),.resetn(resetn),.in_valid(dc_vb),.din(dc_b),.dout(pcm_b),.out_valid(fir_vb));
    assign pcm_valid = fir_va & fir_vb;
endmodule
