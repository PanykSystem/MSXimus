# hid.tcl — escribe a mano el buzon HID del companion (MBOX+0x10..) para probar el lado
# PL (dbg_mailbox_axi -> mcu_hid1/2 y msx_mouse) sin USB: lo mismo que haria el ARM.
#   xsdb.bat tools/hid.tcl joy1 <hex16>            palabra SNES del jugador 1 (bit 4 UP, 5 DOWN,
#   xsdb.bat tools/hid.tcl joy2 <hex16>            10 LEFT, 11 RIGHT, 8 A, 0 B, 9 X, 1 Y, ...)
#   xsdb.bat tools/hid.tcl mouse <dx> <dy> [btn]   suma dx/dy a los acumulados (int16) y sube seq
#   xsdb.bat tools/hid.tcl show
set MBOX 0x1FF00000
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
set cmd [lindex $argv 0]
set w4 [mrd -value [expr {$MBOX + 0x10}]]
set w5 [mrd -value [expr {$MBOX + 0x14}]]
set w6 [mrd -value [expr {$MBOX + 0x18}]]
switch -- $cmd {
    joy1 { mwr [expr {$MBOX + 0x10}] [expr {($w4 & 0xFFFF0000) | ([lindex $argv 1] & 0xFFFF)}] }
    joy2 { mwr [expr {$MBOX + 0x10}] [expr {($w4 & 0x0000FFFF) | (([lindex $argv 1] & 0xFFFF) << 16)}] }
    mouse {
        set dx [lindex $argv 1]; set dy [lindex $argv 2]
        set btn [expr {$argc > 3 ? [lindex $argv 3] : ($w5 & 255)}]
        set ax [expr {(($w6 & 0xFFFF) + $dx) & 0xFFFF}]
        set ay [expr {(($w6 >> 16) + $dy) & 0xFFFF}]
        set seq [expr {(($w5 >> 8) + 1) & 255}]
        mwr [expr {$MBOX + 0x18}] [expr {$ax | ($ay << 16)}]
        mwr [expr {$MBOX + 0x14}] [expr {($btn & 255) | ($seq << 8)}]
    }
    move {                                        ;# solo los acumulados (un unico informe para el PL)
        set ax [expr {(($w6 & 0xFFFF) + [lindex $argv 1]) & 0xFFFF}]
        set ay [expr {(($w6 >> 16) + [lindex $argv 2]) & 0xFFFF}]
        mwr [expr {$MBOX + 0x18}] [expr {$ax | ($ay << 16)}]
    }
    show {}
    default { puts "uso: hid.tcl joy1|joy2 <hex16> | mouse <dx> <dy> [btn] | move <dx> <dy> | show"; exit 1 }
}
set m [mrd -value [expr {$MBOX + 0x10}] 3]
puts [format "HID buzon: joy1=%04X joy2=%04X raton btn=%02X seq=%u ax=%d ay=%d" [expr {[lindex $m 0] & 0xFFFF}] [expr {[lindex $m 0] >> 16}] \
    [expr {[lindex $m 1] & 255}] [expr {([lindex $m 1] >> 8) & 255}] \
    [expr {(([lindex $m 2] & 0xFFFF) ^ 0x8000) - 0x8000}] [expr {(([lindex $m 2] >> 16) ^ 0x8000) - 0x8000}]]
exit
