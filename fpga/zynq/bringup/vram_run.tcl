# vram_run.tcl — XSDB: ps7_init + post_config, programa el PL, espera la
# tabla del vram_test en VRAM_BASE+0x3F0000 (0x103F0000) y la imprime.
# Uso:  xsdb.bat vram_run.tcl <FCLK_MHZ>     (hw_server.bat arrancado aparte)
# Hace TODO desde xsdb en el orden canonico: parar los A9 (con el BOOT switch en
# QSPI estan ejecutando la demo de fabrica y tocando la DDR) -> ps7_init ->
# programar el PL -> ps7_post_config.
set here [file dirname [file normalize [info script]]]
set mhz  [expr {$argc > 0 ? [lindex $argv 0] : 150}]

connect -url tcp:127.0.0.1:3121
after 1000
# 1) parar los dos Cortex-A9 donde esten
targets -set -filter {name =~ "ARM*#0"}
catch {stop}
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
after 200
# 2) inicializar el PS (relojes, MIO, DDR)
targets -set -filter {name =~ "APU*"}
source $here/ps7_init_$mhz.tcl
ps7_init
# 2b) borrar el magic de un run anterior (la tabla la escribe el PL al final)
mwr 0x103F0000 0
# 3) programar el PL
targets -set -filter {name =~ "xc7z020"}
fpga -f $here/vram_test_$mhz.bit
# 4) level shifters + soltar FCLK_RESET
targets -set -filter {name =~ "APU*"}
ps7_post_config

# esperar el magic (el test tarda ~1 s; watchdog 7 x 0.45 s)
set magic 0
for {set i 0} {$i < 30} {incr i} {
    after 500
    set magic [lindex [mrd -value 0x103F0000 1] 0]
    if {$magic == 0xB0B0CAFE} break
}
if {$magic != 0xB0B0CAFE} {
    puts "SIN TABLA: magic=[format 0x%08X $magic] tras [expr {$i*0.5}] s. LEDs = benchmark colgado."
    exit 1
}
set fclk [lindex [mrd -value 0x103F0004 1] 0]
set ns_per_cyc [expr {1000.0 / $fclk}]
puts ""
puts "==== v9968_axi_backend @ $fclk MHz  (cliente sintetico wv2, 64 KB de VRAM) ===="
puts ""
set names {
    "FILL   escrituras de palabra (fire&forget)"
    "SEQ_A  lecturas 16b secuenciales (hits)"
    "RND_A  lecturas 16b aleatorias (fallos)"
    "SEQ_B  lecturas 16b secuenciales por B"
    "COMBO  A+B misma linea a la vez"
    "MASKED escritura de 1 byte + 2 lecturas"
    "WR_RD  escritura + lectura inmediata"
}
puts [format "%-44s %9s %6s %7s %8s %8s %8s" "fase" "ciclos" "ops" "errores" "ns/op" "min ns" "max ns"]
puts [string repeat - 96]
set total_err 0
for {set f 0} {$f < 7} {incr f} {
    set base [expr {0x103F0008 + 16*$f}]
    set v [mrd -value $base 4]
    lassign $v cyc ops err mm
    set nm [lindex $names $f]
    set wd [expr {($err & 0x80000000) != 0}]
    set errn [expr {$err & 0x7FFFFFFF}]
    set total_err [expr {$total_err + $errn + $wd}]
    set nsop [expr {$ops > 0 ? $cyc * $ns_per_cyc / $ops : 0}]
    set mn [expr {($mm & 0xFFFF) * $ns_per_cyc}]
    set mx [expr {(($mm >> 16) & 0xFFFF) * $ns_per_cyc}]
    puts [format "%-44s %9d %6d %7d %8.1f %8.1f %8.1f %s" $nm $cyc $ops $errn $nsop $mn $mx [expr {$wd ? "TIMEOUT" : ""}]]
}
puts ""
puts [expr {$total_err == 0 ? "RESULTADO: 0 errores en todas las fases" : "RESULTADO: $total_err errores/timeouts"}]
exit
