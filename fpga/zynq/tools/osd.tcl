# osd.tcl — enciende/apaga la pagina de informacion del sistema (OSD del iosys pintado
# por el companion del ARM: temperatura, tensiones, SD, USB, estado del MSX).
# Escribe MBOX+0x30 bit 0; el ARM lo sondea. Con el OSD encendido el Z80 esta congelado.
# Uso: xsdb.bat tools/osd.tcl on|off|show
set CTRL 0x1FF00030
set STAT 0x1FF00034
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
switch -- [lindex $argv 0] {
    on   { mwr $CTRL 1 }
    off  { mwr $CTRL 0 }
    show {}
    default { puts "uso: osd.tcl on|off|show"; exit 1 }
}
after 200
set s [mrd -value $STAT]
set t [expr {(($s >> 16) ^ 0x8000) - 0x8000}]
puts [format "OSD: %s | temperatura del die segun el ARM: %d.%d C" [expr {$s & 1 ? "ON" : "off"}] [expr {$t / 10}] [expr {abs($t) % 10}]]
exit
