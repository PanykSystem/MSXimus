# armlog.tcl — lee el log en anillo y las estadisticas del proxy de SD del ARM
# (arm/sdproxy: LOG_BASE 0x1FF00800, SDBOX 0x1FF00100). Se lee por el core 1
# (parado) o por el APU si los dos estan parados.
# Uso: xsdb.bat tools/armlog.tcl [n_chars=1500]
set n [expr {$argc > 0 ? [lindex $argv 0] : 1500}]
set LOG   0x1FF00800
set LOGSZ 0x700
set SDBOX 0x1FF00100
connect -url tcp:127.0.0.1:3121
if {[catch { targets -set -filter {name =~ "ARM*#1"}; mrd -value $LOG }]} { targets -set -filter {name =~ "APU*"} }
set h [mrd -value $LOG 2]
set magic [lindex $h 0]; set wr [lindex $h 1]
if {$magic != 0x474F4C41} { puts "sin log del ARM (magic [format %08X $magic])"; exit }
set start [expr {$wr > $n ? $wr - $n : 0}]
if {$wr > $LOGSZ && $start < $wr - $LOGSZ} { set start [expr {$wr - $LOGSZ}] }
set w [mrd -value [expr {$LOG + 8}] [expr {$LOGSZ / 4}]]
set txt ""
for {set i $start} {$i < $wr} {incr i} {
    set j [expr {$i % $LOGSZ}]
    set b [expr {([lindex $w [expr {$j / 4}]] >> (($j % 4) * 8)) & 255}]
    append txt [format %c $b]
}
puts "---- log del ARM ($wr bytes escritos) ----"
puts -nonewline $txt
puts "---- SDBOX ----"
set b [mrd -value $SDBOX 15]
puts [format "MODE=%d CARD: presente=%d MB=%d | REQ seq=%u op=%d n=%d sector=%u | ACK seq=%u st=%d | rd=%u wr=%u err=%u inits=%u" \
    [expr {[lindex $b 0] & 1}] [expr {[lindex $b 1] & 1}] [expr {[lindex $b 1] >> 16}] [lindex $b 2] \
    [expr {[lindex $b 3] & 255}] [expr {([lindex $b 3] >> 8) & 255}] [lindex $b 4] [lindex $b 6] [lindex $b 7] \
    [lindex $b 8] [lindex $b 9] [lindex $b 10] [lindex $b 11]]
puts [format "vueltas del bucle (wfi) = %u | USB: montajes=%u informes=%u" [lindex $b 12] [lindex $b 13] [lindex $b 14]]
# USB0 (companion): PORTSC1 0xE0002184 — [0] conectado, [1] cambio de conexion, [2] habilitado,
# [12] alimentacion, [27:26] velocidad (0 full, 1 low, 2 high), [31:30] PTS (2 = ULPI)
if {![catch { set p [mrd -value 0xE0002184] }]} {
    puts [format "USB0 PORTSC=%08X: conectado=%d habilitado=%d alim=%d velocidad=%s ulpi=%d" $p [expr {$p & 1}] [expr {($p >> 2) & 1}] \
        [expr {($p >> 12) & 1}] [lindex {full low high ?} [expr {($p >> 26) & 3}]] [expr {(($p >> 30) & 3) == 2}]]
}
# OSD (osd.c): MBOX+0x34 = [0] encendido, [31:16] temperatura del die en decimas de C
set s [mrd -value 0x1FF00034]
set t [expr {(($s >> 16) ^ 0x8000) - 0x8000}]
puts [format "OSD: %s | die %d.%d C (segun el ARM)" [expr {$s & 1 ? "ON" : "off"}] [expr {$t / 10}] [expr {abs($t) % 10}]]
# buzon HID del companion (MBOX+0x10..): joysticks y raton
set m [mrd -value 0x1FF00010 3]
puts [format "HID buzon: joy1=%04X joy2=%04X raton btn=%02X seq=%u ax=%d ay=%d" [expr {[lindex $m 0] & 0xFFFF}] [expr {[lindex $m 0] >> 16}] \
    [expr {[lindex $m 1] & 255}] [expr {([lindex $m 1] >> 8) & 255}] \
    [expr {(([lindex $m 2] & 0xFFFF) ^ 0x8000) - 0x8000}] [expr {(([lindex $m 2] >> 16) ^ 0x8000) - 0x8000}]]
exit
