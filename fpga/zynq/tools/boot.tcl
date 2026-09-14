# boot.tcl — arranque del MSXimus en la ZYNQ MINI desde XSDB (sin FSBL, sin SDK):
#   1) parar los dos Cortex-A9 (con el BOOT switch en QSPI corren la demo de fabrica)
#   2) ps7_init: relojes, MIO, entrenamiento de la DDR3
#   3) cargar el pack de BIOS en la DDR donde el cargador de flash del Tang lo
#      dejaba: RAM_START_ADDRESS+1 = 0x700000 de la ventana de memory_axi
#      (RAM_BASE 0x10800000) -> 0x10F00000. 512 KB + 6 (firma AB + config).
#   4) programar el PL   5) ps7_post_config (level shifters + FCLK_RESET0_N)
# Uso:  xsdb.bat tools/boot.tcl [pack.bin] [bitstream.bit]   (hw_server.bat aparte)
set here [file dirname [file normalize [info script]]]
set pack [expr {$argc > 0 ? [lindex $argv 0] : "$here/../../../files/20260906/pack_bios_msximus_v35d_nextor214.bin"}]
set bit  [expr {$argc > 1 ? [lindex $argv 1] : "$here/../msximus_zynq.bit"}]
set RAM_BASE  0x10800000
set PACK_OFF  0x700000
set packaddr  [expr {$RAM_BASE + $PACK_OFF}]

if {![file exists $pack]} { puts "ERROR: no existe el pack $pack"; exit 1 }
if {![file exists $bit]}  { puts "ERROR: no existe el bitstream $bit"; exit 1 }
puts "pack: $pack ([file size $pack] bytes) -> [format 0x%08X $packaddr]"
puts "bit : $bit"

connect -url tcp:127.0.0.1:3121
after 1000
targets -set -filter {name =~ "ARM*#0"}
catch {stop}
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
after 200
targets -set -filter {name =~ "APU*"}

# 1b) 🚨 PARAR EL PL ANTES DE TOCAR EL PS. 14/09: reprogramar en caliente dejaba
#     HP0/HP1 muertos (memory_axi.dbg_state: AR aceptado y r_cnt=0, en 4 bitstreams
#     distintos y con cualquier combinacion de reset previo / level shifters; solo
#     lo limpiaba un reset del PS: tools/psreset.tcl). Causa: ps7_init RESETEA Y
#     REENTRENA EL DDRC mientras la imagen anterior sigue leyendo la DDR por HP
#     (V9968 a 150 MHz, memory_axi, buzon) -> transaccion a medias en el puerto
#     del DDRC. Desde la imagen de fabrica (sin masters AXI) nunca fallaba. Con
#     FCLK_RESET0..3_N bajos los backends del PL entran en reset (VALID=0,
#     READY=1: drenan) y ps7_init trabaja con el HP en silencio. Los level
#     shifters se dejan solo PS->PL (0xA) hasta ps7_post_config, como el FSBL.
#     Experimentos: BOOT_QUIESCE=0/1, BOOT_LVL=keep|0xF|0xA|0x0.
set QUIESCE [expr {[info exists ::env(BOOT_QUIESCE)] ? $::env(BOOT_QUIESCE) : 1}]
set LVL     [expr {[info exists ::env(BOOT_LVL)] ? $::env(BOOT_LVL) : "0xA"}]
puts "pre-init: quiesce=$QUIESCE lvl_shftr=$LVL"
mwr -force 0xF8000008 0x0000DF0D                                ;# SLCR unlock
if {$QUIESCE} { mwr -force 0xF8000240 0x0000000F; after 150 }   ;# masters del PL en reset y drenando
if {$LVL ne "keep"} { mwr -force 0xF8000900 [expr {$LVL}] }      ;# 0xA = solo PS->PL
mwr -force 0xF8000004 0x0000767B                                ;# SLCR lock

# 2) ps7_init: relojes, MIO, entrenamiento de la DDR3 (con el PL parado)
source $here/../ps7_init.tcl
ps7_init

# 3) pack a la DDR y comprobacion de las dos puntas
#    (xsdb: mwr -bin -file <fichero> <direccion> <num_palabras>; 524294 B -> 131074 palabras)
mwr -bin -file $pack $packaddr [expr {([file size $pack] + 3) / 4}]
set head [mrd -value $packaddr 2]
set tail [mrd -value [expr {$packaddr + 0x80000 - 4}] 3]
puts "DDR: cabeza [format %08X [lindex $head 0]] [format %08X [lindex $head 1]]  cola+firma [format %08X [lindex $tail 1]] [format %08X [lindex $tail 2]]"

# 3a) memoria de ondas del OPL4 (zynq/wave_axi.v por S_AXI_GP0): la YRW801 (2 MB) en
#     WAVE_BASE 0x0F000000; los 2 MB siguientes son la RAM de muestras del MoonSound.
#     WAVE_ROM=fichero para otra ROM; WAVE_ROM=none para no cargarla.
set WAVE_BASE 0x0F000000
set wave [expr {[info exists ::env(WAVE_ROM)] ? $::env(WAVE_ROM) : "$here/../../../mi_release/3.1/yrw801.rom"}]
if {$wave ne "none"} {
    if {![file exists $wave]} { puts "ERROR: no existe la ROM de ondas $wave"; exit 1 }
    puts "wave: $wave ([file size $wave] bytes) -> [format 0x%08X $WAVE_BASE]"
    mwr -bin -file $wave $WAVE_BASE [expr {([file size $wave] + 3) / 4}]
    set wh [mrd -value $WAVE_BASE 1]
    puts [format "wave: cabeza %08X (YRW801 real: bytes 40 18 00 00 = 00001840 en little-endian)" [lindex $wh 0]]
}

# 3a2) VRAM del V9968 a cero (DDR 0x10280000, 256 KB): la DDR arranca con basura y toda zona
#      que un juego no escriba se veia como ruido blanco (Xevious, 14/09). En el Tang nace limpia.
#      (Con BOOT_PROXY=1 el companion lo hace tambien; aqui cubre el caso sin companion.)
set VRAM 0x10280000
mwr -force $VRAM [lrepeat 65536 0] 65536
puts "VRAM: 256 KB a cero en [format 0x%08X $VRAM]"

# 3b) buzon de depuracion (dbg_mailbox_axi, HP2) a cero ANTES de soltar el PL:
#     la DDR arranca con basura y el PL la leeria como teclas pulsadas.
set MBOX 0x1FF00000
mwr $MBOX {0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0} 24
mwr [expr {$MBOX + 0x1C}] 1      ;# MSX_RUN: el pack ya esta en la DDR, el MSX puede arrancar

# 3c) "SD" del MSXimus (sd_axi_proxy, HP3): buzon SDBOX en modo IMAGEN (MODE=0),
#     tarjeta presente, tamano = la ventana de la imagen (224 MB). Opcionalmente
#     se carga una imagen de disco (3er argumento) en DISK_BASE 0x11000000.
set SDBOX     0x1FF00100
set DISK_BASE 0x11000000
set DISK_MB   224
mwr $SDBOX [list 0 [expr {($DISK_MB << 16) | 1}] 0 0 0 0 0 0] 8   ;# W0 = {MB<<16|present, MODE=0}; REQ/ACK a cero
if {$argc > 2} {
    set img [lindex $argv 2]
    if {![file exists $img]} { puts "ERROR: no existe la imagen $img"; exit 1 }
    set mb [expr {([file size $img] + 1048575) / 1048576}]
    if {$mb > $DISK_MB} { puts "ERROR: imagen de $mb MB > ventana de $DISK_MB MB"; exit 1 }
    puts "disco: $img ($mb MB) -> [format 0x%08X $DISK_BASE]"
    mwr -bin -file $img $DISK_BASE [expr {([file size $img] + 3) / 4}]
    set s0 [mrd -value [expr {$DISK_BASE + 0x1FC}]]
    puts [format "disco: firma del sector 0 = %04X (55AA = MBR/boot valido)" [expr {($s0 >> 16) & 0xFFFF}]]
}

# 3d) BOOT_PROXY=1: el programa del ARM (arm/sdproxy) sirve la tarjeta REAL de TF2
#     al PL (MODE=1 en SDBOX). Se arranca en el core 0 ANTES de soltar el PL para
#     que el premontaje del menu ya vaya a la tarjeta. Desde aqui el core 0 corre:
#     la memoria y los registros se tocan por el core 1 (parado).
set memtgt "APU*"
if {[info exists ::env(BOOT_PROXY)] && $::env(BOOT_PROXY) eq "1"} {
    set elf [expr {[info exists ::env(BOOT_ELF)] ? $::env(BOOT_ELF) : "$here/../arm/companion/companion.elf"}]
    if {![file exists $elf]} { puts "ERROR: no existe $elf (arm/sdproxy/build.sh)"; exit 1 }
    targets -set -filter {name =~ "ARM*#0"}
    catch {stop}
    dow $elf
    con
    targets -set -filter {name =~ "ARM*#1"}
    catch {stop}
    set memtgt "ARM*#1"
    set ok 0
    for {set i 0} {$i < 50} {incr i} { if {[expr {[mrd -value $SDBOX] & 1}]} { set ok 1; break }; after 100 }
    set card [mrd -value [expr {$SDBOX + 4}]]
    puts [format "proxy ARM: %s | tarjeta presente=%d, %d MB" [expr {$ok ? "MODE=1" : "SIN RESPUESTA (MODE sigue 0)"}] [expr {$card & 1}] [expr {$card >> 16}]]
}

# 4) PL   5) suelta el PL (ps7_post_config: level shifters 0xF + FCLK_RESET altos)
targets -set -filter {name =~ "xc7z020"}
fpga -f $bit
targets -set -filter [format {name =~ "%s"} $memtgt]
ps7_post_config
puts "BOOT_OK: el MSX deberia arrancar ahora (logo/menu por HDMI)"
exit
