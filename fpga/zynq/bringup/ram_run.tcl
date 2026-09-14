# ram_run.tcl — XSDB: para los A9, ps7_init, PRE-CARGA 16 KB en la ventana de
# RAM (como hara el PS con los packs), programa el PL, post_config, y lee la
# tabla que el cliente escribe a traves de memory_axi.
# Uso:  xsdb.bat ram_run.tcl      (hw_server.bat arrancado aparte)
set here [file dirname [file normalize [info script]]]
set RAM_BASE 0x10800000
set PS_OFF   0x100000
set RES_OFF  0x7F0000

connect -url tcp:127.0.0.1:3121
after 1000
targets -set -filter {name =~ "ARM*#0"}
catch {stop}
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
after 200
targets -set -filter {name =~ "APU*"}
source $here/ps7_init.tcl
ps7_init

# --- pre-carga: b(a) = a[7:0] ^ a[15:8] ^ 0xC3 con a = PS_OFF + i (16 KB) ---
set base [expr {$RAM_BASE + $PS_OFF}]
for {set chunk 0} {$chunk < 16384} {incr chunk 1024} {
    set words {}
    for {set i $chunk} {$i < $chunk + 1024} {incr i 4} {
        set w 0
        for {set b 0} {$b < 4} {incr b} {
            set a [expr {$PS_OFF + $i + $b}]
            set v [expr {(($a & 0xFF) ^ (($a >> 8) & 0xFF) ^ 0xC3) & 0xFF}]
            set w [expr {$w | ($v << (8*$b))}]
        }
        lappend words $w
    }
    mwr [expr {$base + $chunk}] $words
}
puts "pre-carga: 16 KB en [format 0x%08X $base]  (primeras: [mrd -value $base 2])"
mwr [expr {$RAM_BASE + $RES_OFF}] 0

targets -set -filter {name =~ "xc7z020"}
fpga -f $here/ram_test.bit
targets -set -filter {name =~ "APU*"}
ps7_post_config

set magic 0
for {set i 0} {$i < 40} {incr i} {
    after 500
    set magic [lindex [mrd -value [expr {$RAM_BASE + $RES_OFF}] 1] 0]
    if {$magic == 0xB0B0CAFE} break
}
if {$magic != 0xB0B0CAFE} {
    puts "SIN TABLA: magic=[format 0x%08X $magic] tras [expr {$i*0.5}] s. LEDs = fase colgada."
    exit 1
}
set fclk [lindex [mrd -value [expr {$RAM_BASE + $RES_OFF + 4}] 1] 0]
set ns [expr {1000.0 / $fclk}]
puts ""
puts "==== memory_axi (cache 64 KB, HP0 @ $fclk MHz)  cliente Z80 sintetico ===="
puts ""
set names {
    "PS_LOAD 16 KB cargados por xsdb (fallos)"
    "FILL    64 KB escritos byte a byte"
    "SEQ     64 KB leidos en orden"
    "RND     8192 lecturas aleatorias"
    "WR_RD   escribe byte + lee inmediato"
    "SEQ2    64 KB otra vez (todo en cache)"
    "INVAL   cpu_run=0 + 64 KB otra vez"
}
puts [format "%-42s %9s %6s %7s %8s %8s %8s" "fase" "ciclos" "ops" "errores" "ns/op" "min ns" "max ns"]
puts [string repeat - 94]
set terr 0
for {set f 0} {$f < 7} {incr f} {
    set v [mrd -value [expr {$RAM_BASE + $RES_OFF + 8 + 16*$f}] 4]
    lassign $v cyc ops err mm
    set wd [expr {($err & 0x80000000) != 0}]
    set errn [expr {$err & 0x7FFFFFFF}]
    set terr [expr {$terr + $errn + $wd}]
    set nsop [expr {$ops > 0 ? $cyc * $ns / $ops : 0}]
    puts [format "%-42s %9d %6d %7d %8.1f %8.1f %8.1f %s" [lindex $names $f] $cyc $ops $errn $nsop \
          [expr {($mm & 0xFFFF) * $ns}] [expr {(($mm >> 16) & 0xFFFF) * $ns}] [expr {$wd ? "TIMEOUT" : ""}]]
}
set hm [mrd -value [expr {$RAM_BASE + $RES_OFF + 8 + 16*7}] 2]
lassign $hm hits miss
puts ""
puts [format "cache: %d hits, %d fallos  (%.1f %% hits)" $hits $miss [expr {($hits+$miss) > 0 ? 100.0*$hits/($hits+$miss) : 0}]]
puts [expr {$terr == 0 ? "RESULTADO: 0 errores en todas las fases" : "RESULTADO: $terr errores/timeouts"}]
exit
