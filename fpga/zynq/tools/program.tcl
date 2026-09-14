# Programa el PL de la ZYNQ MINI por JTAG (volatil: se pierde al apagar).
# Uso: vivado -mode batch -source program.tcl [-tclargs fichero.bit]
set here [file dirname [file normalize [info script]]]
set bit [expr {$argc > 0 ? [lindex $argv 0] : "$here/led_stream.bit"}]
if {![file exists $bit]} { puts "ERROR: no existe $bit"; exit 1 }

open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7z020*] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
refresh_hw_device $dev
puts "PROGRAMADO: $bit"
close_hw_target
exit 0
