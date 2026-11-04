# Vivado 2026.1 - pure PL first-run build
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set build_dir [file join $root build pure_pl]
catch {close_project}
file mkdir $build_dir
create_project -force rs555_pure_pl $build_dir -part xc7z020clg400-1

set rtl_dir [file join $root rtl]
add_files [glob -nocomplain [file join $rtl_dir *.v]]
add_files -fileset constrs_1 [file join $root constraints pure_pl.xdc]
set_property top rs555_pure_pl_top [current_fileset]
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
# Do not query BITSTREAM.FILE on the run object; locate the generated file.
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
  error "Implementation completed but ${top_name}.bit was not found under $build_dir"
}
puts "\nSUCCESS - pure PL bitstream:\n$bitfile\n"
