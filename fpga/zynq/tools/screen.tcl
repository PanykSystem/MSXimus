# screen.tcl — "ojos" sin captura: vuelca la pantalla de texto del MSX leyendo la
# tabla de nombres de la VRAM, que vive en la DDR del PS. Medido 14/09: la VRAM
# del V9968 empieza en DDR 0x10280000 (VRAM_BASE 0x10000000 + 0x280000; el
# glifo 'A' de la fuente esta en +0x208 = 0x41*8). Modo y tabla de nombres se
# leen de las variables del sistema del MSX (RAM pag.3 en DDR 0x10800000):
# SCRMOD (FCAF), NAMBAS (F922), LINL40 (F3AE).  SCREEN 0: LINL40 columnas;
# SCREEN 1: 32 columnas. Otros modos: no son de texto.
# Uso: xsdb.bat tools/screen.tcl [cols] [vram_base_ddr]
set VRAM 0x10280000
set RAM3 0x10800000
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
proc rb {a} { set w [mrd -value [expr {0x10800000 + (($a - 0xC000) & ~3)}]]; return [expr {($w >> ((($a - 0xC000) & 3) * 8)) & 255}] }
set scrmod [rb 0xFCAF]
set nambas [expr {[rb 0xF922] | [rb 0xF923] << 8}]
set linl40 [rb 0xF3AE]
set csry   [rb 0xF3DC]
set csrx   [rb 0xF3DD]
if {$argc > 1} { set VRAM [lindex $argv 1] }
if {$argc > 0} { set cols [lindex $argv 0] } elseif {$scrmod == 0} { set cols $linl40 } else { set cols 32 }
if {$scrmod > 1 && $argc == 0} { puts "SCREEN $scrmod: no es un modo de texto (NAMBAS=[format %04X $nambas])"; exit }
set base [expr {$VRAM + $nambas}]
set nwords [expr {($cols * 24 + 3) / 4}]
set w [mrd -value $base $nwords]
set bytes {}
foreach x $w { lappend bytes [expr {$x & 255}] [expr {($x >> 8) & 255}] [expr {($x >> 16) & 255}] [expr {($x >> 24) & 255}] }
puts "---- SCREEN $scrmod, ${cols}x24, NAMBAS [format %04X $nambas] (DDR [format 0x%08X $base]), cursor fila $csry col $csrx ----"
for {set r 0} {$r < 24} {incr r} {
    set line ""
    for {set c 0} {$c < $cols} {incr c} {
        set b [lindex $bytes [expr {$r * $cols + $c}]]
        append line [expr {$b >= 32 && $b < 127 ? [format %c $b] : ($b == 0 || $b == 32 ? " " : ".")}]
    }
    puts [format "%2d|%s|" [expr {$r + 1}] [string trimright $line]]
}
exit
