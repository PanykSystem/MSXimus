# proxy_run.tcl — carga y arranca el proxy de SD del ARM (arm/sdproxy/sdproxy.elf)
# en el core 0 (el core 1 se deja parado: por el lee memoria el depurador).
# Requiere ps7_init hecho (DDR viva). Uso: xsdb.bat tools/proxy_run.tcl [elf]
set here [file dirname [file normalize [info script]]]
set elf [expr {$argc > 0 ? [lindex $argv 0] : "$here/../arm/companion/companion.elf"}]
if {![file exists $elf]} { puts "ERROR: no existe $elf"; exit 1 }
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#0"}
catch {stop}
dow $elf
con
after 300
# esperar a que ponga MODE=1 (lectura por el core 1, parado)
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
set ok 0
for {set i 0} {$i < 40} {incr i} {
    if {[expr {[mrd -value 0x1FF00100] & 1}]} { set ok 1; break }
    after 100
}
puts [expr {$ok ? "PROXY_OK: MODE=1 (el ARM sirve la SD)" : "PROXY_TIMEOUT: el ARM no ha puesto MODE=1"}]
exit
