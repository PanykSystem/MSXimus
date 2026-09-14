# disk_save.tcl — vuelca a un fichero la imagen de disco que vive en la DDR
# (sd_axi_proxy en MODO IMAGEN escribe en ella lo que el MSX graba; al apagar se
# perderia). Uso: xsdb.bat tools/disk_save.tcl salida.img [MB]   (MB = tamano a
# volcar; por defecto 32). La imagen se lee de DISK_BASE 0x11000000.
set out [expr {$argc > 0 ? [lindex $argv 0] : "disk/msximus_saved.img"}]
set mb  [expr {$argc > 1 ? [lindex $argv 1] : 32}]
set DISK_BASE 0x11000000
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
puts "volcando $mb MB de [format 0x%08X $DISK_BASE] a $out ..."
mrd -bin -file $out $DISK_BASE [expr {$mb * 1048576 / 4}]
puts "DISK_SAVE_OK: $out ([file size $out] bytes)"
exit
