`timescale 1ns/1ps
module st7789p3_dashboard #(
    parameter integer CLK_HZ=100_000_000,
    parameter integer SPI_HZ=2_000_000,
    parameter integer WIDTH=240,
    parameter integer HEIGHT=284
)(
    input wire clk,
    input wire resetn,
    input wire enable,
    input wire [15:0] rpm,
    input wire [15:0] vibration,
    input wire [15:0] sound_a,
    input wire [15:0] sound_b,
    input wire [7:0] duty,
    input wire motor_on,
    input wire fault,
    output wire lcd_sck,
    output wire lcd_sdat,
    output reg lcd_dc,
    output reg lcd_cs_n,
    output reg lcd_rst_n,
    output reg lcd_bklt,
    output reg frame_done
);
    wire tx_busy,tx_done;
    reg tx_start;
    reg [7:0] tx_data;
    lcd_spi_byte #(.CLK_HZ(CLK_HZ),.SPI_HZ(SPI_HZ)) tx(
      .clk(clk),.resetn(resetn),.start(tx_start),.data(tx_data),.sclk(lcd_sck),.mosi(lcd_sdat),.busy(tx_busy),.done(tx_done));

    localparam integer MS50=CLK_HZ/20;
    localparam integer MS120=(CLK_HZ/1000)*120;
    localparam integer MS150=(CLK_HZ/1000)*150;
    localparam integer MS20=CLK_HZ/50;
    localparam [4:0] ST_RST0=0,ST_RST1=1,ST_SW=2,ST_WSW=3,ST_SL=4,ST_WSL=5,
      ST_INIT=6,ST_DISP=7,ST_WDISP=8,ST_WIN=9,ST_PIX_H=10,ST_PIX_L=11,ST_GAP=12,ST_FRAMEWAIT=13;
    reg [4:0] state;
    reg [31:0] delaycnt;
    reg [7:0] init_idx;
    reg [8:0] iw; // {DC,data} temporary word used during LCD initialization
    reg [3:0] win_idx;
    reg [8:0] px;
    reg [8:0] py;
    reg [15:0] pix;
    reg [15:0] snap_rpm,snap_vib,snap_sa,snap_sb;
    reg [7:0] snap_duty;
    reg snap_motor,snap_fault;

    function [8:0] init_word;
      input [7:0] i;
      begin
        // {DC,data}; known-good ST7789P3 configuration, MADCTL=08, INVON=21
        case(i)
          0:init_word={1'b0,8'h3A}; 1:init_word={1'b1,8'h55};
          2:init_word={1'b0,8'h36}; 3:init_word={1'b1,8'h08};
          4:init_word={1'b0,8'hB2}; 5:init_word={1'b1,8'h0C}; 6:init_word={1'b1,8'h0C}; 7:init_word={1'b1,8'h00}; 8:init_word={1'b1,8'h33}; 9:init_word={1'b1,8'h33};
          10:init_word={1'b0,8'hB7}; 11:init_word={1'b1,8'h35};
          12:init_word={1'b0,8'hBB}; 13:init_word={1'b1,8'h19};
          14:init_word={1'b0,8'hC0}; 15:init_word={1'b1,8'h2C};
          16:init_word={1'b0,8'hC2}; 17:init_word={1'b1,8'h01};
          18:init_word={1'b0,8'hC3}; 19:init_word={1'b1,8'h12};
          20:init_word={1'b0,8'hC4}; 21:init_word={1'b1,8'h20};
          22:init_word={1'b0,8'hC6}; 23:init_word={1'b1,8'h0F};
          24:init_word={1'b0,8'hD0}; 25:init_word={1'b1,8'hA4}; 26:init_word={1'b1,8'hA1};
          27:init_word={1'b0,8'hE0}; 28:init_word={1'b1,8'hD0}; 29:init_word={1'b1,8'h04}; 30:init_word={1'b1,8'h0D}; 31:init_word={1'b1,8'h11}; 32:init_word={1'b1,8'h13}; 33:init_word={1'b1,8'h2B}; 34:init_word={1'b1,8'h3F}; 35:init_word={1'b1,8'h54}; 36:init_word={1'b1,8'h4C}; 37:init_word={1'b1,8'h18}; 38:init_word={1'b1,8'h0D}; 39:init_word={1'b1,8'h0B}; 40:init_word={1'b1,8'h1F}; 41:init_word={1'b1,8'h23};
          42:init_word={1'b0,8'hE1}; 43:init_word={1'b1,8'hD0}; 44:init_word={1'b1,8'h04}; 45:init_word={1'b1,8'h0C}; 46:init_word={1'b1,8'h11}; 47:init_word={1'b1,8'h13}; 48:init_word={1'b1,8'h2C}; 49:init_word={1'b1,8'h3F}; 50:init_word={1'b1,8'h44}; 51:init_word={1'b1,8'h51}; 52:init_word={1'b1,8'h2F}; 53:init_word={1'b1,8'h1F}; 54:init_word={1'b1,8'h1F}; 55:init_word={1'b1,8'h20}; 56:init_word={1'b1,8'h23};
          57:init_word={1'b0,8'h21};
          default:init_word={1'b0,8'h00};
        endcase
      end
    endfunction

    function [6:0] segmask;
      input [3:0] d;
      begin
        case(d)
          0:segmask=7'b1111110; 1:segmask=7'b0110000; 2:segmask=7'b1101101;
          3:segmask=7'b1111001; 4:segmask=7'b0110011; 5:segmask=7'b1011011;
          6:segmask=7'b1011111; 7:segmask=7'b1110000; 8:segmask=7'b1111111;
          9:segmask=7'b1111011; default:segmask=7'b0000001;
        endcase
      end
    endfunction

    function digit_pixel;
      input [3:0] d;
      input [7:0] lx;
      input [7:0] ly;
      reg [6:0] s;
      begin
        s=segmask(d);
        digit_pixel =
          (s[6] && ly<6 && lx>=6 && lx<30) ||
          (s[5] && lx>=30 && ly>=6 && ly<31) ||
          (s[4] && lx>=30 && ly>=33 && ly<58) ||
          (s[3] && ly>=58 && lx>=6 && lx<30) ||
          (s[2] && lx<6 && ly>=33 && ly<58) ||
          (s[1] && lx<6 && ly>=6 && ly<31) ||
          (s[0] && ly>=29 && ly<35 && lx>=6 && lx<30);
      end
    endfunction

    function [15:0] make_pixel;
      input [8:0] x0;
      input [8:0] y0;
      input [15:0] r0,v0,sa0,sb0;
      input [7:0] du0;
      input mo0,fa0;
      reg [3:0] d0,d1,d2,d3;
      reg [8:0] bw;
      reg hit;
      begin
        make_pixel=16'h0000;
        d0=(r0/1000)%10; d1=(r0/100)%10; d2=(r0/10)%10; d3=r0%10;
        hit=0;
        if(y0>=4 && y0<68) begin
          if(x0>=20 && x0<56) hit=digit_pixel(d0,x0-20,y0-4);
          else if(x0>=70 && x0<106) hit=digit_pixel(d1,x0-70,y0-4);
          else if(x0>=120 && x0<156) hit=digit_pixel(d2,x0-120,y0-4);
          else if(x0>=170 && x0<206) hit=digit_pixel(d3,x0-170,y0-4);
          if(hit) make_pixel=16'hFFFF;
        end
        if(y0>=82 && y0<102) begin
          bw=(sa0>>7); if(bw>220) bw=220;
          if(x0>=10 && x0<10+bw) make_pixel=16'h07E0; else if(x0>=10&&x0<230) make_pixel=16'h18E3;
        end
        if(y0>=112 && y0<132) begin
          bw=(sb0>>7); if(bw>220) bw=220;
          if(x0>=10 && x0<10+bw) make_pixel=16'h001F; else if(x0>=10&&x0<230) make_pixel=16'h18E3;
        end
        if(y0>=142 && y0<162) begin
          bw=(v0>>3); if(bw>220) bw=220;
          if(x0>=10 && x0<10+bw) make_pixel=16'hFFE0; else if(x0>=10&&x0<230) make_pixel=16'h18E3;
        end
        if(y0>=172 && y0<192) begin
          bw=du0*2; if(bw>220) bw=220;
          if(x0>=10 && x0<10+bw) make_pixel=16'h07FF; else if(x0>=10&&x0<230) make_pixel=16'h18E3;
        end
        if(y0>=214) begin
          if(!mo0) make_pixel=16'h4208;       // idle gray
          else if(fa0) make_pixel=16'hF800;   // fault red
          else make_pixel=16'h07E0;           // normal green
        end
      end
    endfunction

    task send_now;
      input dc;
      input [7:0] data;
      begin lcd_dc<=dc;tx_data<=data;tx_start<=1; end
    endtask

    always @(posedge clk) begin
      tx_start<=0; frame_done<=0;
      if(!resetn) begin
        state<=ST_RST0;delaycnt<=0;init_idx<=0;win_idx<=0;px<=0;py<=0;pix<=0;
        lcd_dc<=0;lcd_cs_n<=1;lcd_rst_n<=0;lcd_bklt<=0;
        snap_rpm<=0;snap_vib<=0;snap_sa<=0;snap_sb<=0;snap_duty<=0;snap_motor<=0;snap_fault<=0;
      end else if(!enable) begin
        state<=ST_RST0;delaycnt<=0;lcd_cs_n<=1;lcd_rst_n<=0;lcd_bklt<=0;
      end else begin
        case(state)
          ST_RST0: begin lcd_rst_n<=0;lcd_bklt<=0;lcd_cs_n<=1; if(delaycnt>=MS50-1) begin delaycnt<=0;state<=ST_RST1; end else delaycnt<=delaycnt+1; end
          ST_RST1: begin lcd_rst_n<=1;lcd_bklt<=1; if(delaycnt>=MS120-1) begin delaycnt<=0;lcd_cs_n<=0;send_now(0,8'h01);state<=ST_SW; end else delaycnt<=delaycnt+1; end
          ST_SW: if(tx_done) begin lcd_cs_n<=1;state<=ST_WSW;delaycnt<=0;end
          ST_WSW: if(delaycnt>=MS150-1) begin delaycnt<=0;lcd_cs_n<=0;send_now(0,8'h11);state<=ST_SL;end else delaycnt<=delaycnt+1;
          ST_SL: if(tx_done) begin lcd_cs_n<=1;state<=ST_WSL;delaycnt<=0;end
          ST_WSL: if(delaycnt>=MS120-1) begin delaycnt<=0;init_idx<=0;lcd_cs_n<=0;iw=init_word(0);send_now(iw[8],iw[7:0]);state<=ST_INIT;end else delaycnt<=delaycnt+1;
          ST_INIT: if(tx_done) begin
            if(init_idx==57) begin lcd_cs_n<=0;send_now(0,8'h29);state<=ST_DISP;end
            else begin init_idx<=init_idx+1'b1;iw=init_word(init_idx+1'b1);send_now(iw[8],iw[7:0]);end
          end
          ST_DISP: if(tx_done) begin lcd_cs_n<=1;delaycnt<=0;state<=ST_WDISP;end
          ST_WDISP: if(delaycnt>=MS20-1) begin delaycnt<=0;win_idx<=0;lcd_cs_n<=0;send_now(0,8'h2A);state<=ST_WIN;
            snap_rpm<=rpm;snap_vib<=vibration;snap_sa<=sound_a;snap_sb<=sound_b;snap_duty<=duty;snap_motor<=motor_on;snap_fault<=fault;
          end else delaycnt<=delaycnt+1;
          ST_WIN: if(tx_done) begin
            case(win_idx)
              0:begin win_idx<=1;send_now(1,8'h00);end
              1:begin win_idx<=2;send_now(1,8'h00);end
              2:begin win_idx<=3;send_now(1,8'h00);end
              3:begin win_idx<=4;send_now(1,8'hEF);end
              4:begin win_idx<=5;send_now(0,8'h2B);end
              5:begin win_idx<=6;send_now(1,8'h00);end
              6:begin win_idx<=7;send_now(1,8'h00);end
              7:begin win_idx<=8;send_now(1,8'h01);end
              8:begin win_idx<=9;send_now(1,8'h1B);end // 283
              default:begin px<=0;py<=0;pix<=make_pixel(0,0,snap_rpm,snap_vib,snap_sa,snap_sb,snap_duty,snap_motor,snap_fault);send_now(0,8'h2C);state<=ST_PIX_H;end
            endcase
          end
          ST_PIX_H: if(tx_done) begin send_now(1,pix[15:8]);state<=ST_PIX_L;end
          ST_PIX_L: if(tx_done) begin
            send_now(1,pix[7:0]);
            if(px==WIDTH-1 && py==HEIGHT-1) begin state<=ST_GAP;delaycnt<=0; end
            else begin
              if(px==WIDTH-1) begin px<=0;py<=py+1'b1;pix<=make_pixel(0,py+1'b1,snap_rpm,snap_vib,snap_sa,snap_sb,snap_duty,snap_motor,snap_fault);end
              else begin px<=px+1'b1;pix<=make_pixel(px+1'b1,py,snap_rpm,snap_vib,snap_sa,snap_sb,snap_duty,snap_motor,snap_fault);end
              state<=ST_PIX_H;
            end
          end
          ST_GAP: if(tx_done) begin lcd_cs_n<=1;delaycnt<=0;state<=ST_FRAMEWAIT;frame_done<=1;end
          ST_FRAMEWAIT: begin if(delaycnt>=CLK_HZ/20-1) begin delaycnt<=0;state<=ST_WDISP;end else delaycnt<=delaycnt+1;end
          default: state<=ST_RST0;
        endcase
      end
    end
endmodule
