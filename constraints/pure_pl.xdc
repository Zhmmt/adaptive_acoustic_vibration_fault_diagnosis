## PYNQ-Z2 125 MHz clock
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports sysclk]
create_clock -add -name sysclk -period 8.000 -waveform {0 4} [get_ports sysclk]

## switches / button / LEDs
set_property -dict {PACKAGE_PIN M20 IOSTANDARD LVCMOS33} [get_ports {sw[0]}]
set_property -dict {PACKAGE_PIN M19 IOSTANDARD LVCMOS33} [get_ports {sw[1]}]
set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33} [get_ports btn0]
set_property -dict {PACKAGE_PIN D20 IOSTANDARD LVCMOS33} [get_ports btn1]
set_property -dict {PACKAGE_PIN L20 IOSTANDARD LVCMOS33} [get_ports btn2]
set_property -dict {PACKAGE_PIN L19 IOSTANDARD LVCMOS33} [get_ports btn3]
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {led[3]}]

## Teacher Attach Board - hardware validated in prior bring-up
set_property -dict {PACKAGE_PIN Y16 IOSTANDARD LVCMOS33} [get_ports dmic_mdat]
set_property -dict {PACKAGE_PIN Y17 IOSTANDARD LVCMOS33} [get_ports dmic_mclk]
set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33} [get_ports lcd_sdat]
set_property -dict {PACKAGE_PIN V6  IOSTANDARD LVCMOS33} [get_ports lcd_rst_n]
set_property -dict {PACKAGE_PIN Y6  IOSTANDARD LVCMOS33} [get_ports lcd_sck]
set_property -dict {PACKAGE_PIN U7  IOSTANDARD LVCMOS33} [get_ports lcd_dc]
set_property -dict {PACKAGE_PIN C20 IOSTANDARD LVCMOS33} [get_ports lcd_cs_n]
set_property -dict {PACKAGE_PIN V7  IOSTANDARD LVCMOS33} [get_ports lcd_bklt]

## PMOD JB / B
## User wiring: motor RPWM=JB1; R_EN/L_EN=3.3V; LPWM=GND.
## ADXL345 I2C: SCL=JB2/Y14, SDA=JB3/T11. HC-020K OUT moved to JB7/V16.
set_property -dict {PACKAGE_PIN W14 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports motor_rpwm]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33 PULLUP true} [get_ports tach_in]
set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVCMOS33 PULLUP true} [get_ports adxl_scl]
set_property -dict {PACKAGE_PIN T11 IOSTANDARD LVCMOS33 PULLUP true} [get_ports adxl_sda]
