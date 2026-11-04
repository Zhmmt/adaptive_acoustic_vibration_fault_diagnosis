# Vivado 2026.1 - PYNQ-Z2 overlay with control/status AXI GPIO + audio AXI DMA
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set build_dir [file join $root build overlay]
catch {close_project}
file mkdir $build_dir
create_project -force rs555_overlay_proj $build_dir -part xc7z020clg400-1
catch {set_property board_part tul.com.tw:pynq-z2:part0:1.0 [current_project]}

set rtl_dir [file join $root rtl]
add_files [glob -nocomplain [file join $rtl_dir *.v]]
add_files -fileset constrs_1 [file join $root constraints overlay.xdc]
update_compile_order -fileset sources_1

create_bd_design rs555_overlay

# Zynq PS
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} [get_bd_cells ps7]
set_property -dict [list \
  CONFIG.PCW_USE_M_AXI_GP0 {1} \
  CONFIG.PCW_USE_S_AXI_HP0 {1} \
  CONFIG.PCW_EN_CLK0_PORT {1} \
  CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100.000000}] [get_bd_cells ps7]

# AXI GPIO control: [7:0] and bit8 are RESERVED (motor controlled by BTN0..BTN3),
# bit9 software ESTOP, bit10 fault override-valid, bit11 fault override.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_ctrl
set_property -dict [list CONFIG.C_GPIO_WIDTH {16} CONFIG.C_ALL_OUTPUTS {1}] [get_bd_cells axi_gpio_ctrl]

# status0={rpm[15:0],vibration[15:0]}
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_status0
set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_ALL_INPUTS {1}] [get_bd_cells axi_gpio_status0]

# status1={soundA[15:0],soundB[15:0]}
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_status1
set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_ALL_INPUTS {1}] [get_bd_cells axi_gpio_status1]

# status2 channel 1={pcm_count[15:0],ADXL_DEVID[7:0],flags[7:0]}
# status2 channel 2={5'd0,fault,estop,motor_en,pwm_duty[7:0]}
# Reuse the existing AXI-Lite base address; second channel data is offset 0x08.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_status2
set_property -dict [list \
  CONFIG.C_GPIO_WIDTH {32} CONFIG.C_ALL_INPUTS {1} \
  CONFIG.C_IS_DUAL {1} CONFIG.C_GPIO2_WIDTH {16} \
  CONFIG.C_ALL_INPUTS_2 {1}] [get_bd_cells axi_gpio_status2]

# Software-fed ADXL345 status: bit[15:0]=vibration, [23:16]=DEVID, [24]=ready.
# Keeps the LCD/local fault/status bus synchronized with Vitis measurements.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_adxl_sw
set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_ALL_OUTPUTS {1}] [get_bd_cells axi_gpio_adxl_sw]

# Restore the working Xilinx AXI IIC path from the previously validated xin1 app.
# This is the ONLY block driving the external sensor I2C pins.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_iic:2.1 axi_iic_adxl
# make_bd_intf_pins_external returns a success status, NOT the created port
# object in Vivado.  Query the new interface port explicitly before renaming.
set iic_pin [get_bd_intf_pins -quiet axi_iic_adxl/IIC]
if {[llength $iic_pin] != 1} {
  error "AXI IIC interface axi_iic_adxl/IIC not found: check IP configuration"
}
# Vivado BD interface handles commonly use the absolute object name /IIC_0.
# Do NOT compare the object string /IIC_0 directly to the displayed name IIC_0.
# This is a fresh BD, so the first externalized IIC port should auto-name IIC_0.
set iic_ports_before [get_bd_intf_ports -quiet *]
make_bd_intf_pins_external $iic_pin
set iic_created {}
foreach iic_candidate [get_bd_intf_ports -quiet *] {
  if {[lsearch -exact $iic_ports_before $iic_candidate] < 0} {
    lappend iic_created $iic_candidate
  }
}
if {[llength $iic_created] != 1} {
  error "Expected exactly one new AXI IIC external bus; found '[join $iic_created {, }]'"
}
set iic_external [lindex $iic_created 0]
# /IIC_0 is an object path, and its actual port name is IIC_0.
set iic_external_name [string trimleft $iic_external /]
if {$iic_external_name ne "IIC_0"} {
  # Never rename an existing IIC_0 to itself, which would become IIC_1.
  # Fail explicitly rather than silently creating a mismatched XDC constraint.
  error "AXI IIC external bus is $iic_external (name '$iic_external_name'), expected /IIC_0. Check block-design port creation."
}
if {[llength [get_bd_intf_ports -quiet IIC_0]] != 1} {
  error "AXI IIC IIC_0 bus lookup failed; cannot apply constraints for IIC_0_scl_io and IIC_0_sda_io"
}
puts "AXI IIC /IIC_0 verified; constraints refer to IIC_0_scl_io (Y14), IIC_0_sda_io (T11)" 

# audio DMA: S2MM only
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_audio
set_property -dict [list \
  CONFIG.c_include_sg {0} \
  CONFIG.c_include_mm2s {0} \
  CONFIG.c_include_s2mm {1} \
  CONFIG.c_s_axis_s2mm_tdata_width {32} \
  CONFIG.c_sg_length_width {16} \
  CONFIG.c_prmry_is_aclk_async {0}] [get_bd_cells axi_dma_audio]

# Custom module reference
create_bd_cell -type module -reference rs555_system_core core
set_property -dict [list CONFIG.CLK_HZ {100000000} CONFIG.PDM_HALF_DIV {25} CONFIG.PDM_DECIM {125} CONFIG.TACH_PPR {20} CONFIG.FRAME_SAMPLES {4096}] [get_bd_cells core]

# Core clock/reset from PS FCLK0
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins core/clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins core/resetn]

# GPIO buses
connect_bd_net [get_bd_pins axi_gpio_ctrl/gpio_io_o] [get_bd_pins core/control]
connect_bd_net [get_bd_pins core/status0] [get_bd_pins axi_gpio_status0/gpio_io_i]
connect_bd_net [get_bd_pins core/status1] [get_bd_pins axi_gpio_status1/gpio_io_i]
connect_bd_net [get_bd_pins core/status2] [get_bd_pins axi_gpio_status2/gpio_io_i]
connect_bd_net [get_bd_pins core/motor_status] [get_bd_pins axi_gpio_status2/gpio2_io_i]
connect_bd_net [get_bd_pins axi_gpio_adxl_sw/gpio_io_o] [get_bd_pins core/adxl_sw]

# Audio stream to DMA. AXI DMA v7.1 clocks the S_AXIS_S2MM stream from
# m_axi_s2mm_aclk in synchronous/simple-DMA mode; there is no s_axis_s2mm_aclk pin.
foreach pin {m_axi_s2mm_aclk s_axi_lite_aclk axi_resetn} {
  if {[llength [get_bd_pins -quiet axi_dma_audio/$pin]] != 1} {
    error "AXI DMA expected pin axi_dma_audio/$pin was not generated; check AXI DMA IP configuration."
  }
}
connect_bd_intf_net [get_bd_intf_pins core/M_AXIS] [get_bd_intf_pins axi_dma_audio/S_AXIS_S2MM]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_dma_audio/m_axi_s2mm_aclk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_dma_audio/s_axi_lite_aclk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins axi_dma_audio/axi_resetn]

# AXI-Lite peripherals -> GP0. Automation also creates interconnect/reset where needed.
foreach p {axi_gpio_ctrl axi_gpio_status0 axi_gpio_status1 axi_gpio_status2 axi_gpio_adxl_sw} {
  apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/ps7/M_AXI_GP0" Clk "Auto"} [get_bd_intf_pins $p/S_AXI]
}
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/ps7/M_AXI_GP0" Clk "Auto"} [get_bd_intf_pins axi_dma_audio/S_AXI_LITE]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/ps7/M_AXI_GP0" Clk "Auto"} [get_bd_intf_pins axi_iic_adxl/S_AXI]

# DMA high-performance DDR path -> HP0
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/axi_dma_audio/M_AXI_S2MM" Slave "/ps7/S_AXI_HP0" Clk "Auto"} [get_bd_intf_pins ps7/S_AXI_HP0]

# External hardware ports, exact names match constraints/overlay.xdc
proc ext_in {name pin} {
  create_bd_port -dir I $name
  connect_bd_net [get_bd_ports $name] [get_bd_pins $pin]
}
proc ext_out {name pin} {
  create_bd_port -dir O $name
  connect_bd_net [get_bd_ports $name] [get_bd_pins $pin]
}
ext_in  dmic_mdat core/dmic_mdat
ext_out dmic_mclk core/dmic_mclk
ext_out lcd_sck core/lcd_sck
ext_out lcd_sdat core/lcd_sdat
ext_out lcd_dc core/lcd_dc
ext_out lcd_cs_n core/lcd_cs_n
ext_out lcd_rst_n core/lcd_rst_n
ext_out lcd_bklt core/lcd_bklt
ext_out motor_rpwm core/motor_rpwm
# Restore ALL four board pushbuttons from verified dianji standalone design.
ext_in  btn0 core/btn0
ext_in  btn1 core/btn1
ext_in  btn2 core/btn2
ext_in  btn3 core/btn3
# motor_lpwm is held low internally and wired to GND externally; motor_en is a software status only.
# Do not export either signal: REN/LEN are tied to 3.3 V and these unused ports would be unconstrained.
ext_in  tach_in core/tach_in
proc ext_io {name pin} {
  create_bd_port -dir IO $name
  connect_bd_net [get_bd_ports $name] [get_bd_pins $pin]
}
# ADXL345 port is now the AXI IIC IP external bus IIC_0 (auto-generated IOBUF).
# The wrapper ports are IIC_0_scl_io / IIC_0_sda_io.

assign_bd_address
validate_bd_design
save_bd_design

set wrapper_files [make_wrapper -files [get_files [file join $build_dir rs555_overlay_proj.srcs sources_1 bd rs555_overlay rs555_overlay.bd]] -top]
add_files -norecurse $wrapper_files
set_property top rs555_overlay_wrapper [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {![string match "*Complete*" [get_property STATUS [get_runs synth_1]]]} {
  error "Synthesis failed: [get_property STATUS [get_runs synth_1]]"
}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {![string match "*Complete*" [get_property STATUS [get_runs impl_1]]]} {
  error "Implementation failed: [get_property STATUS [get_runs impl_1]]"
}

# Search generated outputs by filename instead of BITSTREAM.FILE. In Vivado
# 2026.1 BITSTREAM.FILE is not a valid property on this run object, which can
# leave $bitfile empty and make file copy fail after a successful bitgen.
proc find_named {dir fname} {
  if {![file isdirectory $dir]} { return "" }
  foreach f [glob -nocomplain -directory $dir *] {
    if {[file isdirectory $f]} {
      set r [find_named $f $fname]
      if {$r ne ""} { return $r }
    } elseif {[file tail $f] eq $fname} {
      return [file normalize $f]
    }
  }
  return ""
}

set top_name [get_property TOP [current_fileset]]
set bitfile [find_named $build_dir "${top_name}.bit"]
if {$bitfile eq "" || ![file isfile $bitfile] || [file size $bitfile] == 0} {
  error "Bitstream generation reported complete, but ${top_name}.bit was not found under $build_dir"
}
set hwh [find_named $build_dir rs555_overlay.hwh]
if {$hwh eq "" || ![file isfile $hwh] || [file size $hwh] == 0} {
  # Keep the error explicit: PYNQ requires matching hardware handoff metadata.
  error "Bitstream exists, but rs555_overlay.hwh was not found under $build_dir; refusing to deploy an incomplete overlay"
}

set deploy [file join $root deploy]
file mkdir $deploy
set deploy_bit [file join $deploy rs555_final.bit]
set deploy_hwh [file join $deploy rs555_final.hwh]
file copy -force $bitfile $deploy_bit
file copy -force $hwh $deploy_hwh
if {![file isfile $deploy_bit] || [file size $deploy_bit] == 0 || ![file isfile $deploy_hwh] || [file size $deploy_hwh] == 0} {
  error "Overlay artifacts were not copied correctly to $deploy"
}
# Export matching XSA for Vitis. Export AFTER write_bitstream finishes.
set deploy_xsa [file join $deploy rs555_final.xsa]
write_hw_platform -fixed -include_bit -force -file $deploy_xsa
if {![file isfile $deploy_xsa] || [file size $deploy_xsa] == 0} {
  error "Hardware platform XSA was not generated: $deploy_xsa"
}
puts "Vitis XSA : $deploy_xsa"
puts "Bitstream: $bitfile"
puts "HWH      : $hwh"
puts "\nSUCCESS - matching overlay files copied to:\n  $deploy_bit\n  $deploy_hwh\n"
