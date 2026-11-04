`timescale 1ns/1ps
// RS555 FIR31 timing fix: one product-register stage, five balanced adder
// stages (32 -> 16 -> 8 -> 4 -> 2 -> 1), then output saturation register.
// One sample can be accepted EVERY clock; output is delayed by SIX clocks.
// The tap history advances ONLY on in_valid. Output holds on invalid cycles.
module fir31(
    input  wire clk,
    input  wire resetn,
    input  wire in_valid,
    input  wire signed [15:0] din,
    output reg  signed [15:0] dout,
    output reg  out_valid
);
    reg signed [15:0] d[0:29];

    function signed [15:0] coef;
      input integer k;
      begin
        case(k)
          0:coef=-16'sd39; 1:coef=16'sd67; 2:coef=-16'sd68; 3:coef=16'sd0;
          4:coef=16'sd156; 5:coef=-16'sd324; 6:coef=16'sd326; 7:coef=16'sd0;
          8:coef=-16'sd620; 9:coef=16'sd1187; 10:coef=-16'sd1137; 11:coef=16'sd0;
          12:coef=16'sd2244; 13:coef=-16'sd5011; 14:coef=16'sd7306; 15:coef=16'sd24593;
          16:coef=16'sd7306; 17:coef=-16'sd5011; 18:coef=16'sd2244; 19:coef=16'sd0;
          20:coef=-16'sd1137; 21:coef=16'sd1187; 22:coef=-16'sd620; 23:coef=16'sd0;
          24:coef=16'sd326; 25:coef=-16'sd324; 26:coef=16'sd156; 27:coef=16'sd0;
          28:coef=-16'sd68; 29:coef=16'sd67; default:coef=-16'sd39;
        endcase
      end
    endfunction

    // Keep the SAME 48-bit accumulation / Q15 saturation semantics as original.
    function signed [15:0] sat16;
      input signed [47:0] v;
      reg signed [47:0] q;
      begin
        q = v >>> 15;
        if (q > 32767) sat16=16'sh7fff;
        else if (q < -32768) sat16=-16'sd32768;
        else sat16=q[15:0];
      end
    endfunction

    // Coefficient multiplication is mapped independently.  The register at
    // stage 0 breaks the original 31-term multiply/accumulate combinational path.
    wire signed [31:0] product[0:30];
    genvar g;
    generate
      for (g=0; g<31; g=g+1) begin: gen_product
        wire signed [15:0] tap;
        if (g == 0) begin: current_sample
          assign tap = din;
        end else begin: old_sample
          assign tap = d[g-1];
        end
        assign product[g] = tap * coef(g);
      end
    endgenerate

    reg signed [47:0] s0[0:31];
    reg signed [47:0] s1[0:15];
    reg signed [47:0] s2[0:7];
    reg signed [47:0] s3[0:3];
    reg signed [47:0] s4[0:1];
    reg signed [47:0] s5;
    // s0 at input edge; s1...s5 on following five edges;
    // dout/out_valid at input edge + 6 clocks.
    reg [5:0] valid_pipe;
    integer i;

    always @(posedge clk) begin
      if (!resetn) begin
        for (i=0; i<30; i=i+1) d[i] <= 16'sd0;
        for (i=0; i<32; i=i+1) s0[i] <= 48'sd0;
        for (i=0; i<16; i=i+1) s1[i] <= 48'sd0;
        for (i=0; i<8; i=i+1) s2[i] <= 48'sd0;
        for (i=0; i<4; i=i+1) s3[i] <= 48'sd0;
        for (i=0; i<2; i=i+1) s4[i] <= 48'sd0;
        s5 <= 48'sd0;
        valid_pipe <= 6'b0;
        dout <= 16'sd0;
        out_valid <= 1'b0;
      end else begin
        if (in_valid) begin
          for (i=29; i>0; i=i-1) d[i] <= d[i-1];
          d[0] <= din;
        end
        for (i=0; i<31; i=i+1)
          s0[i] <= in_valid ? {{16{product[i][31]}}, product[i]} : 48'sd0;
        s0[31] <= 48'sd0; // pad 31 taps to 32 leaves
        for (i=0; i<16; i=i+1) s1[i] <= s0[2*i] + s0[2*i+1];
        for (i=0; i<8; i=i+1)  s2[i] <= s1[2*i] + s1[2*i+1];
        for (i=0; i<4; i=i+1)  s3[i] <= s2[2*i] + s2[2*i+1];
        for (i=0; i<2; i=i+1)  s4[i] <= s3[2*i] + s3[2*i+1];
        s5 <= s4[0] + s4[1];
        valid_pipe <= {valid_pipe[4:0], in_valid};
        out_valid <= valid_pipe[5];
        if (valid_pipe[5]) dout <= sat16(s5);
      end
    end
endmodule
