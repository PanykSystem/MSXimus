# psreset.tcl — reset completo del PS por JTAG (equivale a apagar y encender el
# PS sin tocar el cable): limpia un HP atascado por una transaccion a medias
# (reprogramacion en caliente del PL con los level shifters abiertos, 14/09).
# Con el BOOT en QSPI el PS rearranca la demo de fabrica; boot.tcl la para.
# Uso: xsdb.bat tools/psreset.tcl   (luego tools/boot.tcl como siempre)
connect -url tcp:127.0.0.1:3121
after 500
targets -set -filter {name =~ "APU*"}
puts "PS: rst -system ..."
rst -system
after 3000
targets -set -filter {name =~ "ARM*#0"}
catch {stop}
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
puts "PS_RESET_OK"
exit
