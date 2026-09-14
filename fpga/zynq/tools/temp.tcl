# temp.tcl — temperatura del die del Zynq y tensiones internas por el XADC, a
# traves del interfaz PS-XADC (devcfg, 0xF8007100..), sin tocar el PL.
#   temp = codigo * 503.975 / 65536 - 273.15   (reg 0x00; maximo desde el arranque: 0x20)
#   VCCINT = codigo * 3 / 65536 (reg 0x01), VCCAUX (0x02), VCCBRAM (0x06)
# Uso: xsdb.bat tools/temp.tcl
set CFG  0xF8007100
set MSTS 0xF800710C
set CMDF 0xF8007110
set RDF  0xF8007114
set MCTL 0xF8007118
connect -url tcp:127.0.0.1:3121
if {[catch { targets -set -filter {name =~ "ARM*#1"}; catch {stop}; mrd -value $CFG }]} { targets -set -filter {name =~ "APU*"} }
mwr -force $MCTL 0x10          ;# reset del interfaz
mwr -force $MCTL 0x00
mwr -force $CFG  0x80001114    ;# enable, TCKRATE /4, IGAP 20
proc xadc_rd {addr} {
    mwr -force $::CMDF [expr {(1 << 26) | ($addr << 16)}]   ;# DRP read
    mrd -force -value $::RDF                                 ;# respuesta del comando anterior
    mwr -force $::CMDF 0                                     ;# NOP para empujar la respuesta
    return [expr {[mrd -force -value $::RDF] & 0xFFFF}]
}
set t   [xadc_rd 0x00]
set tmx [xadc_rd 0x20]
set vi  [xadc_rd 0x01]
set va  [xadc_rd 0x02]
set vb  [xadc_rd 0x06]
puts [format "Zynq XADC: temperatura del die = %.1f C (maximo desde el arranque %.1f C)" \
    [expr {$t * 503.975 / 65536.0 - 273.15}] [expr {$tmx * 503.975 / 65536.0 - 273.15}]]
puts [format "           VCCINT = %.3f V  VCCAUX = %.3f V  VCCBRAM = %.3f V" \
    [expr {$vi * 3.0 / 65536.0}] [expr {$va * 3.0 / 65536.0}] [expr {$vb * 3.0 / 65536.0}]]
exit
