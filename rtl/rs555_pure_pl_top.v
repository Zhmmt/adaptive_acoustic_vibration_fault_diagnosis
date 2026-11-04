`timescale 1ns/1ps
module rs555_pure_pl_top(
    input wire sysclk,
    input wire [1:0] sw,
    input wire btn0,
    input wire btn1,
    input wire btn2,
    input wire btn3,
    output wire [3:0] led,
    input wire dmic_mdat,
    output wire dmic_mclk,
    output wire lcd_sck,lcd_sdat,lcd_dc,lcd_cs_n,lcd_rst_n,lcd_bklt,
    output wire motor_rpwm,
    input wire tach_in,
    inout wire adxl_scl,adxl_sda
);
    reg [7:0] rstcnt=0;
    wire resetn = &rstcnt;
    always @(posedge sysclk) if(!resetn) rstcnt<=rstcnt+1'b1;

    // Motor duty/enable are controlled ONLY by BTN0..BTN3.
    // SW0 is a separate software-style ESTOP for this legacy pure-PL build.
    wire [15:0] control = {6'd0,sw[0],9'd0};
    wire [31:0] s0,s1,s2;
    wire [31:0] axis_data;
    wire [3:0] axis_keep;
    wire axis_valid,axis_last;

    rs555_system_core #(.CLK_HZ(125_000_000),.PDM_HALF_DIV(31),.PDM_DECIM(126),.TACH_PPR(20)) core(
      .clk(sysclk),.resetn(resetn),.control(control),
      .btn0(btn0),.btn1(btn1),.btn2(btn2),.btn3(btn3),
      .dmic_mdat(dmic_mdat),.dmic_mclk(dmic_mclk),
      .lcd_sck(lcd_sck),.lcd_sdat(lcd_sdat),.lcd_dc(lcd_dc),.lcd_cs_n(lcd_cs_n),.lcd_rst_n(lcd_rst_n),.lcd_bklt(lcd_bklt),
      .motor_rpwm(motor_rpwm),.motor_lpwm(),.motor_en(),.tach_in(tach_in),
      .adxl_sw(32'd0), // Pure PL does not contain AXI IIC or a Vitis ADXL publisher.
      .status0(s0),.status1(s1),.status2(s2),
      .m_axis_tdata(axis_data),.m_axis_tkeep(axis_keep),.m_axis_tvalid(axis_valid),.m_axis_tready(1'b1),.m_axis_tlast(axis_last));

    // Keep unused legacy ADXL pins high-impedance; I2C requires the overlay.
    assign adxl_scl = 1'bz;
    assign adxl_sda = 1'bz;
    assign led[0]=resetn;
    assign led[1]=s2[1]; // tach seen
    assign led[2]=s2[0]; // ADXL345 ready (DEVID=0xE5)
    assign led[3]=s2[2]; // motor running flag from core status
endmodule
