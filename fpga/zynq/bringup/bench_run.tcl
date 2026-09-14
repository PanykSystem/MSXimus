# bench_run.tcl — XSDB: ps7_init + post_config, espera la tabla del banco de
# pruebas en 0x1F000000 y la imprime en unidades utiles.
# Uso:  xsdb.bat bench_run.tcl <FCLK_MHZ>     (hw_server.bat arrancado aparte)
# Hace TODO desde xsdb en el orden canonico: parar los A9 (con el BOOT switch en
# QSPI estan ejecutando la demo de fabrica y tocando la DDR) -> ps7_init ->
# programar el PL -> ps7_post_config.
set here [file dirname [file normalize [info script]]]
set mhz  [expr {$argc > 0 ? [lindex $argv 0] : 100}]

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
# 3) programar el PL
targets -set -filter {name =~ "xc7z020"}
fpga -f $here/hp_bench_$mhz.bit
# 4) level shifters + soltar FCLK_RESET
targets -set -filter {name =~ "APU*"}
ps7_post_config

# esperar el magic (el bench tarda < 2 s; el watchdog como mucho 7 x 1.3 s)
set magic 0
for {set i 0} {$i < 30} {incr i} {
    after 500
    set magic [lindex [mrd -value 0x1F000000 1] 0]
    if {$magic == 0xB0B0CAFE} break
}
if {$magic != 0xB0B0CAFE} {
    puts "SIN TABLA: magic=[format 0x%08X $magic] tras [expr {$i*0.5}] s. LEDs = benchmark colgado."
    exit 1
}
set fclk [lindex [mrd -value 0x1F000004 1] 0]
set ns_per_cyc [expr {1000.0 / $fclk}]
puts ""
puts "==== S_AXI_HP0 @ $fclk MHz  (DDR3-1066 x16, MT41J256M16) ===="
puts ""

set names {
    "RD single secuencial, 1 en vuelo"
    "RD single ALEATORIO, 1 en vuelo"
    "WR single secuencial, 1 en vuelo"
    "RD rafaga16 secuencial, 1 en vuelo"
    "RD rafaga16 secuencial, 8 en vuelo"
    "WR rafaga16 secuencial, 4 en vuelo"
    "RD single ALEATORIO, 8 en vuelo"
}
set bytes_per_op {8 8 8 128 128 128 8}

puts [format "%-38s %9s %6s %9s %9s %9s %9s" "benchmark" "ciclos" "ops" "ns/op" "min ns" "max ns" "MB/s"]
puts [string repeat - 96]
for {set b 0} {$b < 7} {incr b} {
    set base [expr {0x1F000008 + 16*$b}]
    set v [mrd -value $base 4]
    lassign $v cyc ops lmin lmax
    set nm [lindex $names $b]
    set bpo [lindex $bytes_per_op $b]
    if {($lmax & 0xFFFF0000) == 0xDEAD0000} {
        set hs [expr {($lmin >> 24) & 0xFF}]
        set names_hs {awvalid awready wvalid wready bvalid arvalid arready rvalid}
        set act {}
        for {set k 0} {$k < 8} {incr k} { if {$hs & (0x80 >> $k)} { lappend act [lindex $names_hs $k] } }
        puts [format "%-38s %9d %6d   TIMEOUT foto=%08X issued=%d w_bursts=%d completed=%d  activos: %s"               $nm $cyc $ops $lmin [expr {($lmin>>16)&0xFF}] [expr {($lmin>>8)&0xFF}] [expr {$lmin&0xFF}] $act]
        continue
    }
    set nsop [expr {$ops > 0 ? $cyc * $ns_per_cyc / $ops : 0}]
    set mbs  [expr {$cyc > 0 ? ($ops * $bpo) / ($cyc * $ns_per_cyc / 1000.0) : 0}]
    if {$b == 0 || $b == 1 || $b == 2} {
        puts [format "%-38s %9d %6d %9.1f %9.1f %9.1f %9.1f" $nm $cyc $ops $nsop \
              [expr {$lmin * $ns_per_cyc}] [expr {$lmax * $ns_per_cyc}] $mbs]
    } else {
        puts [format "%-38s %9d %6d %9.1f %9s %9s %9.1f" $nm $cyc $ops $nsop "-" "-" $mbs]
    }
}
puts ""
puts "Referencia: la IP DDR3 de Gowin en el Tang servia ~1.3M lecturas/s (730 ns/op) a 32 bits."
exit
