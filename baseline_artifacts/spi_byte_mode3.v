`timescale 1ns/1ps
module spi_byte_mode3 #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer SPI_HZ = 1_000_000
)(
    input  wire       clk,
    input  wire       resetn,
    input  wire       start,
    input  wire [7:0] tx_data,
    input  wire       miso,
    output reg        mosi,
    output reg        sclk,
    output reg [7:0]  rx_data,
    output reg        busy,
    output reg        done
);
    localparam integer DIV = CLK_HZ/(2*SPI_HZ);
    reg [31:0] div_cnt;
    reg [2:0] bit_idx;
    reg phase;
    reg finish_pending;

    always @(posedge clk) begin
        done <= 1'b0;
        if (!resetn) begin
            mosi <= 1'b0;
            sclk <= 1'b1; // mode 3 idle high
            rx_data <= 8'd0;
            busy <= 1'b0;
            div_cnt <= 0;
            bit_idx <= 3'd7;
            phase <= 1'b0;
            finish_pending <= 1'b0;
        end else begin
            if (finish_pending) begin
                finish_pending <= 1'b0;
                done <= 1'b1;
            end

            if (!busy && start) begin
                busy <= 1'b1;
                div_cnt <= 0;
                bit_idx <= 3'd7;
                phase <= 1'b0;
                sclk <= 1'b1;
                mosi <= tx_data[7];
                rx_data <= 0;
            end else if (busy) begin
                if (div_cnt >= DIV-1) begin
                    div_cnt <= 0;
                    if (!phase) begin
                        // SPI mode 3: falling edge is the data-change edge.
                        // The first bit was prepared when start was accepted;
                        // later bits are prepared here before the next rising edge.
                        sclk <= 1'b0;
                        mosi <= tx_data[bit_idx];
                        phase <= 1'b1;
                    end else begin
                        // Rising edge: sample MISO while MOSI remains stable.
                        sclk <= 1'b1;
                        rx_data[bit_idx] <= miso;
                        if (bit_idx == 0) begin
                            busy <= 1'b0;
                            finish_pending <= 1'b1;
                            phase <= 1'b0;
                        end else begin
                            bit_idx <= bit_idx - 1'b1;
                            phase <= 1'b0;
                        end
                    end
                end else begin
                    div_cnt <= div_cnt + 1'b1;
                end
            end
        end
    end
endmodule
