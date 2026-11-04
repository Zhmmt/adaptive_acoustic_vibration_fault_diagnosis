`timescale 1ns/1ps
module rs555_system_core #(
    parameter integer CLK_HZ=100_000_000,
    parameter integer PDM_HALF_DIV=25,
    parameter integer PDM_DECIM=125,
    parameter integer TACH_PPR=20,
    parameter integer FRAME_SAMPLES=4096
)(
    input wire clk,
    input wire resetn,
    input wire [15:0] control,
    // PYNQ-Z2 board buttons, same active-low wiring as standalone dianji.
    input wire btn0,
    input wire btn1,
    input wire btn2,
    input wire btn3,

    // attachment-board DMIC / LCD
    input  wire dmic_mdat,
    output wire dmic_mclk,
    output wire lcd_sck,
    output wire lcd_sdat,
    output wire lcd_dc,
    output wire lcd_cs_n,
    output wire lcd_rst_n,
    output wire lcd_bklt,

    // PMOD-B external modules
    output wire motor_rpwm,
    output wire motor_lpwm,
    output wire motor_en,
    input  wire tach_in,
    // ADXL345 is accessed by PS over AXI IIC; software reports the result.
    input  wire [31:0] adxl_sw,

    // status buses to PS
    output wire [31:0] status0,
    output wire [31:0] status1,
    output wire [31:0] status2,
    // AXI GPIO status2 channel-2: actual PWM/enable/ESTOP/fault
    output wire [15:0] motor_status,

    // stereo PCM AXI stream
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA" *)
    output wire [31:0] m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TKEEP" *)
    output wire [3:0] m_axis_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *)
    output wire m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *)
    input  wire m_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXIS, TDATA_NUM_BYTES 4, HAS_TKEEP 1, HAS_TLAST 1, HAS_TREADY 1, FREQ_HZ 100000000" *)
    output wire m_axis_tlast
);
    // The verified standalone motor code uses four physical buttons.
    // AXI control[7:0] and [8] no longer drive motor duty/enable.
    // AXI control[9] remains a software ESTOP, [10:11] control fault display.
    wire [7:0] duty;
    wire estop = control[9];
    wire fault_override_valid = control[10];
    wire fault_override = control[11];

    motor_pwm #(.CLK_HZ(CLK_HZ),.PWM_HZ(25000)) motor0(
      .clk(clk),.resetn(resetn),
      .btn0(btn0),.btn1(btn1),.btn2(btn2),.btn3(btn3),.estop(estop),
      .duty_percent(duty),.rpwm(motor_rpwm),.lpwm(motor_lpwm),.en_out(motor_en));

    wire [15:0] rpm;
    wire tach_seen;
    tach_rpm #(.CLK_HZ(CLK_HZ),.PULSES_PER_REV(TACH_PPR)) tach0(
      .clk(clk),.resetn(resetn),.tach_in(tach_in),.rpm(rpm),.pulse_seen(tach_seen));

    // SW status provided by Vitis via AXI GPIO (do not drive SDA/SCL from this core).
    // adxl_sw[15:0] vibration, [23:16] DEVID, [24] valid/ready.
    wire [15:0] vib = adxl_sw[15:0];
    wire [7:0] adxl_id = adxl_sw[23:16];
    wire adxl_ready = adxl_sw[24];

    wire signed [15:0] pcm_a,pcm_b;
    wire pcm_valid;
    dmic_audio #(.HALF_DIV(PDM_HALF_DIV),.DECIM_R(PDM_DECIM),.CIC_SHIFT(6)) audio0(
      .clk(clk),.resetn(resetn),.dmic_mdat(dmic_mdat),.dmic_mclk(dmic_mclk),
      .pcm_a(pcm_a),.pcm_b(pcm_b),.pcm_valid(pcm_valid));

    reg [15:0] sound_a,sound_b;
    reg [31:0] pcm_count;
    reg dmic_alive;
    wire [15:0] abs_a = pcm_a[15] ? (~pcm_a + 1'b1) : pcm_a;
    wire [15:0] abs_b = pcm_b[15] ? (~pcm_b + 1'b1) : pcm_b;
    always @(posedge clk) begin
      if(!resetn) begin sound_a<=0;sound_b<=0;pcm_count<=0;dmic_alive<=0;end
      else if(pcm_valid) begin
        pcm_count<=pcm_count+1'b1;dmic_alive<=1;
        if(abs_a>sound_a) sound_a<=abs_a; else sound_a<=sound_a-((sound_a>>7) == 0 ? 16'd1 : (sound_a>>7));
        if(abs_b>sound_b) sound_b<=abs_b; else sound_b<=sound_b-((sound_b>>7) == 0 ? 16'd1 : (sound_b>>7));
      end
    end

    axis_stereo_frame #(.FRAME_SAMPLES(FRAME_SAMPLES)) axis0(
      .clk(clk),.resetn(resetn),.pcm_a(pcm_a),.pcm_b(pcm_b),.pcm_valid(pcm_valid),
      .m_axis_tdata(m_axis_tdata),.m_axis_tkeep(m_axis_tkeep),.m_axis_tvalid(m_axis_tvalid),.m_axis_tready(m_axis_tready),.m_axis_tlast(m_axis_tlast));

    // Conservative local fallback only; normal/fault classification is preferably supplied by Python after baseline calibration.
    wire local_fault = motor_en && ((vib > 16'd1200) || (sound_a > 16'd24000) || (sound_b > 16'd24000));
    wire display_fault = fault_override_valid ? fault_override : local_fault;

    // Read-only PL->PS status. This does not alter BTN0..BTN3 controls.
    // [7:0]  duty percent 0..100 (retained when STOPPED)
    // [8]    motor_en (physical START state and !software ESTOP)
    // [9]    software ESTOP bit
    // [10]   actual LCD fault flag
    // [15:11] reserved zero
    assign motor_status = {5'd0, display_fault, estop, motor_en, duty};

    wire lcd_frame_pulse;
    reg lcd_frame_seen;
    always @(posedge clk) begin
      if (!resetn) lcd_frame_seen <= 1'b0;
      else if (lcd_frame_pulse) lcd_frame_seen <= 1'b1;
    end

    st7789p3_dashboard #(.CLK_HZ(CLK_HZ),.SPI_HZ(2_000_000)) lcd0(
      .clk(clk),.resetn(resetn),.enable(1'b1),.rpm(rpm),.vibration(vib),.sound_a(sound_a),.sound_b(sound_b),
      .duty(duty),.motor_on(motor_en),.fault(display_fault),
      .lcd_sck(lcd_sck),.lcd_sdat(lcd_sdat),.lcd_dc(lcd_dc),.lcd_cs_n(lcd_cs_n),.lcd_rst_n(lcd_rst_n),.lcd_bklt(lcd_bklt),.frame_done(lcd_frame_pulse));

    wire [7:0] flags = {2'b00,dmic_alive,lcd_frame_seen,display_fault,motor_en,tach_seen,adxl_ready};
    assign status0 = {rpm,vib};
    assign status1 = {sound_a,sound_b};
    assign status2 = {pcm_count[15:0],adxl_id,flags};
endmodule
