`timescale 1ns/1ps
module fir31(
    input wire clk,
    input wire resetn,
    input wire in_valid,
    input wire signed [15:0] din,
    output reg signed [15:0] dout,
    output reg out_valid
);
    reg signed [15:0] d[0:29];
    integer i;
    reg signed [47:0] sum;

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

    always @(posedge clk) begin
      out_valid <= 1'b0;
      if (!resetn) begin
        for (i=0;i<30;i=i+1) d[i] <= 0;
        dout <= 0;
      end else if (in_valid) begin
        sum = $signed(din) * $signed(coef(0));
        for (i=1;i<31;i=i+1)
          sum = sum + $signed(d[i-1]) * $signed(coef(i));
        for (i=29;i>0;i=i-1) d[i] <= d[i-1];
        d[0] <= din;
        dout <= sat16(sum);
        out_valid <= 1'b1;
      end
    end
endmodule
