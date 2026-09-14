# armpc.tcl — ¿donde esta el core 0 del ARM? Lo para, imprime PC/LR/SP y la pila
# de llamadas (bt), y lo vuelve a arrancar (salvo -hold). Para saber en que
# funcion se ha quedado el companion: arm-none-eabi-addr2line -e companion.elf <pc>
# Uso: xsdb.bat tools/armpc.tcl [-hold]
set hold [expr {$argc > 0 && [lindex $argv 0] eq "-hold"}]
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#0"}
catch {stop}
catch { puts [rrd pc] }
catch { puts [rrd lr] }
catch { puts [rrd sp] }
catch { puts [bt] }
if {!$hold} { con }
exit
