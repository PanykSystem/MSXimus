# alive.tcl — pruebas de vida del MSX por xsdb sin tocar el PL:
#   JIFFY (FC9Eh) en DDR 0x10803C9E: si sube, la BIOS corre y hay VBLANK.
#   VRAM (0x10280000): si hay bytes != 0, el VDP recibio el logo.  (VRAM del V9968 = DDR 0x10280000, medido 14/09)
connect -url tcp:127.0.0.1:3121
after 500
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
set j1 [lindex [mrd -value 0x10803C9C 1] 0]
after 500
set j2 [lindex [mrd -value 0x10803C9C 1] 0]
puts [format "JIFFY: %04X -> %04X  (%s)" [expr {($j1>>16)&0xFFFF}] [expr {($j2>>16)&0xFFFF}] [expr {$j1 != $j2 ? "CAMBIA: el Z80 corre y hay VBLANK" : "quieto"}]]
set nz 0
foreach off {0x0 0x1000 0x2000 0x4000 0x8000 0x10000 0x20000} {
    set v [mrd -value [expr {0x10280000 + $off}] 16]
    foreach w $v { if {$w != 0} { incr nz } }
}
puts "VRAM: $nz palabras != 0 de 112 muestreadas"
puts "pack en DDR (cabeza 16 B): [mrd -value 0x10F00000 4]"
puts "RAM pag.3 (F380..): [mrd -value 0x10803380 4]"
exit
