## External ports produced by rs555_overlay block design
## Teacher Attach Board
set_property -dict {PACKAGE_PIN Y16 IOSTANDARD LVCMOS33} [get_ports dmic_mdat]
set_property -dict {PACKAGE_PIN Y17 IOSTANDARD LVCMOS33} [get_ports dmic_mclk]
set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33} [get_ports lcd_sdat]
set_property -dict {PACKAGE_PIN V6  IOSTANDARD LVCMOS33} [get_ports lcd_rst_n]
set_property -dict {PACKAGE_PIN Y6  IOSTANDARD LVCMOS33} [get_ports lcd_sck]
set_property -dict {PACKAGE_PIN U7  IOSTANDARD LVCMOS33} [get_ports lcd_dc]
set_property -dict {PACKAGE_PIN C20 IOSTANDARD LVCMOS33} [get_ports lcd_cs_n]
set_property -dict {PACKAGE_PIN V7  IOSTANDARD LVCMOS33} [get_ports lcd_bklt]

## Onboard pushbuttons (same pins as verified dianji/motor_pwm.xdc)
## BTN0=-5%, BTN1=+5%, BTN2=STOP, BTN3=START; active-low in RTL.
set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33} [get_ports btn0]
set_property -dict {PACKAGE_PIN D20 IOSTANDARD LVCMOS33} [get_ports btn1]
set_property -dict {PACKAGE_PIN L20 IOSTANDARD LVCMOS33} [get_ports btn2]
set_property -dict {PACKAGE_PIN L19 IOSTANDARD LVCMOS33} [get_ports btn3]

## PMOD JB / B
## User wiring: motor RPWM=JB1, motor R_EN/L_EN tied to 3.3V,
## motor LPWM tied to GND; ADXL345 I2C SCL=JB2 and SDA=JB3.
## HC-020K tach moved to JB7 to avoid the SDA conflict.
set_property -dict {PACKAGE_PIN W14 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports motor_rpwm]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33 PULLUP true} [get_ports tach_in]
set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVCMOS33 PULLUP true} [get_ports IIC_0_scl_io]
set_property -dict {PACKAGE_PIN T11 IOSTANDARD LVCMOS33 PULLUP true} [get_ports IIC_0_sda_io]
