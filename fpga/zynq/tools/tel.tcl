# tel.tcl — telemetria del PL leida del buzon de la DDR (zynq/dbg_mailbox_axi.v, HP2).
# El PL escribe cada ~1 ms en MBOX+0x40:
#   +40 'MBOX' +44 seq | +48 hits(memory_axi) +4C miss | +50 kbd_echo[31:0] +54 status
#   status = {vddr_ops[15:0], 6'b0, mmcm_lock, vddr_ready, iosys_frz, cpu_run, sd_type[1:0], sd_stat[3:0]}
# Uso: xsdb.bat tools/tel.tcl [n_lecturas] [ms_entre_lecturas]
set MBOX 0x1FF00000
set n  [expr {$argc > 0 ? [lindex $argv 0] : 2}]
set ms [expr {$argc > 1 ? [lindex $argv 1] : 500}]
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
set kbd [mrd -value $MBOX 4]
puts "buzon teclado: [format %08X-%08X-%08X-%08X [lindex $kbd 3] [lindex $kbd 2] [lindex $kbd 1] [lindex $kbd 0]]"
for {set k 0} {$k < $n} {incr k} {
    set v [mrd -value [expr {$MBOX + 0x40}] 10]
    lassign $v magic seq hits miss echo st d2 d d4 d3
    # +0x64 d3 = {present[31], port2[30], strobe[29], phase[28:26], turbo_eff[25], dx[23:16], dy[15:8], informes[7:0]}
    # +0x60 d4 = {wave_axi: lat_max AR->R en ciclos de 37,5 MHz [31:24], lecturas[23:16], escrituras[15:8]; PSG r15 escrituras[7:0]}
    puts [format "   raton: present=%d port2=%d strobe=%d fase=%d dx=%d dy=%d informes=%d | PSG r15: escrituras=%d" \
        [expr {($d3>>31)&1}] [expr {($d3>>30)&1}] [expr {($d3>>29)&1}] [expr {($d3>>26)&7}] \
        [expr {((($d3>>16)&255)^128)-128}] [expr {((($d3>>8)&255)^128)-128}] [expr {$d3&255}] [expr {$d4&255}]]
    puts [format "   CPU: %s" [expr {(($d3>>25)&1) ? "5.37 MHz (turbo)" : "3.58 MHz"}]]
    puts [format "   opl4 wave (GP0): lat_max=%d ciclos (%.0f ns) lecturas=%d escrituras=%d (contadores de 8 bits)" \
        [expr {($d4>>24)&255}] [expr {(($d4>>24)&255)*1000.0/37.5}] [expr {($d4>>16)&255}] [expr {($d4>>8)&255}]]
    # d2 = {sd_ram_blocks[31:16], sdio_count[15:8], timeout[7], crc[6], rcrc[5], init[4], card_stat[3:0]}
    puts [format "   sdproxy: ordenes=%u rcount=%u timeout=%d crc=%d rcrc=%d init=%d stat=%d" \
        [expr {$d2>>16}] [expr {($d2>>8)&255}] [expr {($d2>>7)&1}] [expr {($d2>>6)&1}] [expr {($d2>>5)&1}] [expr {($d2>>4)&1}] [expr {$d2&15}]]
    set tag [format %c%c%c%c [expr {$magic>>24}] [expr {($magic>>16)&255}] [expr {($magic>>8)&255}] [expr {$magic&255}]]
    puts [format "%s seq=%u hits=%u miss=%u echo=%08X | vdp_ops=%u lock=%d vready=%d frz=%d cpu_run=%d sd_type=%d sd_stat=%d | sd: mode=%d irq=%d busy=%d blk_rdy=%d rstart=%d wstart=%d" \
        $tag $seq $hits $miss $echo [expr {$st>>16}] [expr {($st>>9)&1}] [expr {($st>>8)&1}] [expr {($st>>7)&1}] \
        [expr {($st>>6)&1}] [expr {($st>>4)&3}] [expr {$st&15}] \
        [expr {($st>>15)&1}] [expr {($st>>14)&1}] [expr {($st>>13)&1}] [expr {($st>>12)&1}] [expr {($st>>11)&1}] [expr {($st>>10)&1}]]
    # dbg_state: [2:0]seq [3]busy [4]miss_wait [5]filled [6]w_issued [7]inv_run [8]ar_seen [9]arvalid [13:10]wr_pend [19:14]last_rid [27:20]r_cnt [31:28]rd_tag
    puts [format "   memFSM: seq=%d busy=%d miss_wait=%d filled=%d w_issued=%d inv_run=%d ar_seen=%d arvalid=%d wr_pend=%d last_rid=%d r_cnt=%d rd_tag=%d" \
        [expr {$d&7}] [expr {($d>>3)&1}] [expr {($d>>4)&1}] [expr {($d>>5)&1}] [expr {($d>>6)&1}] [expr {($d>>7)&1}] \
        [expr {($d>>8)&1}] [expr {($d>>9)&1}] [expr {($d>>10)&15}] [expr {($d>>14)&63}] [expr {($d>>20)&255}] [expr {($d>>28)&15}]]
    if {$k < $n-1} { after $ms }
}
exit
