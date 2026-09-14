# vramfill.tcl — rellena un trozo de la VRAM del V9968 (que en la Zynq es DDR lineal desde
# 0x10280000) con un valor. Diagnostico: la DDR arranca con basura/FF y el V9968 la muestra
# tal cual, asi que una zona "que nadie escribe" se ve BLANCA (FF = dos pixeles color 15 en
# SCREEN 5) en vez de negra como en el Tang. Poniendola a 0 se ve si la banda rara de la
# pantalla sale de ahi.
# Uso: xsdb.bat tools/vramfill.tcl [addr_vram_hex] [n_bytes] [valor_byte]
set base 0x10280000
set off  [expr {$argc > 0 ? [lindex $argv 0] : 0x6A00}]
set n    [expr {$argc > 1 ? [lindex $argv 1] : 0x1600}]
set val  [expr {$argc > 2 ? [lindex $argv 2] : 0}]
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
set words [expr {($n + 3) / 4}]
set w [expr {($val & 0xFF) | (($val & 0xFF) << 8) | (($val & 0xFF) << 16) | (($val & 0xFF) << 24)}]
mwr -force [expr {$base + $off}] [lrepeat $words $w] $words
puts [format "VRAM +0x%05X .. +0x%05X = 0x%02X  (%d palabras)" $off [expr {$off + $n - 1}] $val $words]
exit
