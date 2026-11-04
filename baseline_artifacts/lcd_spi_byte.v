`timescale 1ns/1ps
module lcd_spi_byte #(
    parameter integer CLK_HZ=100_000_000,
    parameter integer SPI_HZ=2_000_000
)(
    input wire clk,
    input wire resetn,
    input wire start,
    input wire [7:0] data,
    output reg sclk,
    output reg mosi,
    output reg busy,
    output reg done
);
    localparam integer DIV = CLK_HZ/(2*SPI_HZ);
    reg [31:0] divcnt;
    reg [2:0] bitidx;
    reg phase;
    reg finish_pending;
    always @(posedge clk) begin
      done<=1'b0;
      if(!resetn) begin sclk<=0;mosi<=0;busy<=0;divcnt<=0;bitidx<=7;phase<=0;finish_pending<=0; end
      else begin
        if(finish_pending) begin finish_pending<=0;done<=1; end
        if(!busy && start) begin
          busy<=1;divcnt<=0;bitidx<=7;phase<=0;sclk<=0;mosi<=data[7];
        end else if(busy) begin
          if(divcnt>=DIV-1) begin
            divcnt<=0;
            if(!phase) begin sclk<=1;phase<=1; end
            else begin
              sclk<=0;phase<=0;
              if(bitidx==0) begin busy<=0;finish_pending<=1; end
              else begin bitidx<=bitidx-1'b1;mosi<=data[bitidx-1'b1]; end
            end
          end else divcnt<=divcnt+1'b1;
        end
      end
    end
endmodule
