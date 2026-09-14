# vram.tcl — vuelca un trozo CRUDO de la VRAM del V9968, que en la Zynq vive en la DDR
# del PS de forma lineal: direccion de VRAM N -> DDR 0x10280000 + N.
# Sirve para distinguir "nunca escrito" (basura de la DDR, bytes sin patron) de
# "escrito y luego corrompido" (estructura reconocible).
# Uso: xsdb.bat tools/vram.tcl [addr_vram_hex] [n_bytes]      por defecto 0x0000, 512 B
set base 0x10280000
set off  [expr {$argc > 0 ? [lindex $argv 0] : 0}]
set n    [expr {$argc > 1 ? [lindex $argv 1] : 512}]
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
set addr [expr {$base + $off}]
set words [expr {($n + 3) / 4}]
set v [mrd -value $addr $words]
puts [format "VRAM +0x%05X  (DDR 0x%08X), %d bytes" $off $addr $n]
# histograma rapido: cuantos valores distintos de byte hay (ruido = muchos, grafico = pocos)
array set hist {}
set line ""
set i 0
foreach w $v {
    for {set b 0} {$b < 4} {incr b} {
        set byte [expr {($w >> ($b*8)) & 0xFF}]
        incr hist($byte)
        append line [format "%02X" $byte]
        incr i
        if {$i % 32 == 0} { puts [format "  +%05X  %s" [expr {$off + $i - 32}] $line]; set line "" }
    }
}
if {$line ne ""} { puts "  $line" }
puts [format "distintos=%d de %d bytes  (mucha variedad = DDR sin inicializar; poca = grafico real)" \
      [llength [array names hist]] $i]
exit
