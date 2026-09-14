# memory_axi + cliente sintetico del puerto Z80. HP0 a clk_54m.
# Uso:  vivado -mode batch -source build_ram.tcl
# Salida: ram_test.bit y ps7_init.tcl en esta carpeta.
set here [file dirname [file normalize [info script]]]
cd $here
set ::FCLK_MHZ 100
set ::N_HP 1

create_project -force ram_test ./vivado_prj_ram -part xc7z020clg400-2
source ../bd_ps7.tcl
set bd [get_files ps7_bd.bd]
generate_target all $bd
make_wrapper -files $bd -top
add_files ./vivado_prj_ram/ram_test.srcs/sources_1/bd/ps7_bd/hdl/ps7_bd_wrapper.v

add_files ../memory_axi.v
add_files ./ram_test.v
add_files ./ram_test_top.v
add_files -fileset constrs_1 ./ram_test.xdc
set_property top ram_test_top [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { puts "ERROR: sintesis fallida"; exit 1 }

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} { puts "ERROR: implementacion fallida"; exit 1 }

file copy -force ./vivado_prj_ram/ram_test.runs/impl_1/ram_test_top.bit ./ram_test.bit
file copy -force [glob ./vivado_prj_ram/ram_test.srcs/sources_1/bd/ps7_bd/ip/ps7_bd_processing_system7_0_0/ps7_init.tcl] ./ps7_init.tcl
open_run impl_1
report_timing_summary -file ./timing_ram.rpt
report_utilization    -file ./util_ram.rpt

puts "=================================================="
puts "OK: [file normalize ./ram_test.bit]"
puts "=================================================="
exit 0
