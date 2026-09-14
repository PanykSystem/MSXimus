# Detecta la ZYNQ MINI por JTAG. Solo lectura, no programa nada.
# Uso: vivado -mode batch -source detect.tcl
open_hw_manager
if {[catch {connect_hw_server -allow_non_jtag} err]} {
    puts "ERROR: no arranca hw_server: $err"
    exit 1
}
set targets [get_hw_targets]
if {[llength $targets] == 0} {
    puts "SIN_TARGET: no se ve ningun cable JTAG. Comprobar USB-C 'JTAG&Power', BOOT=00, y que no haya otro programador conectado."
    exit 2
}
puts "TARGETS: $targets"
open_hw_target [lindex $targets 0]
set devs [get_hw_devices]
puts "DEVICES: $devs"
foreach d $devs {
    puts "  $d  IDCODE=[get_property IDCODE $d]  PART=[get_property PART $d]"
}
close_hw_target
exit 0
