# build.tcl — MSXimus para la ZYNQ MINI (XC7Z020), Vivado 2019.2 en batch.
#
#   vivado -mode batch -source build.tcl -tclargs elab   -> solo elaboracion RTL (paso 1)
#   vivado -mode batch -source build.tcl -tclargs synth  -> + sintesis y utilizacion (paso 2)
#   vivado -mode batch -source build.tcl [-tclargs bit]  -> + implementacion y bitstream (paso 3)
#
# Comparte fpga/src, v9968, video720, jtopl, opl3, G80A... con el Tang (ver PLAN.md).
# Lista de ficheros = la linea V9968 de fpga/build.tcl SIN lo especifico de Gowin
# (gowin_pll*, pll_27/74/86/12, clockdiv, memory.v, fan_ctrl, ro_osc, wave_sdram,
# ddr3/*, v9968_ddr3_backend) y CON zynq/memory_axi.v, zynq/v9968_axi_backend.v.

set here [file dirname [file normalize [info script]]]
set fpga [file normalize "$here/.."]
cd $here
set mode [expr {$argc > 0 ? [lindex $argv 0] : "bit"}]
set ::FCLK_MHZ 150
# HP0 VRAM, HP1 RAM Z80, HP2 buzon xsdb, HP3 "SD en DDR" (con ZYNQ_NO_MAILBOX=1 el HP2 queda en reposo)
set ::N_HP 4
puts "N_HP = $::N_HP"

create_project -force msximus_zynq ./vivado_prj -part xc7z020clg400-2
set_property target_language Verilog [current_project]

# ---- PS7 ----
source $here/bd_ps7.tcl
set bd [get_files ps7_bd.bd]
generate_target all $bd
make_wrapper -files $bd -top
add_files ./vivado_prj/msximus_zynq.srcs/sources_1/bd/ps7_bd/hdl/ps7_bd_wrapper.v

# ---- RTL compartido (mismo orden que fpga/build.tcl) ----
set v {}
foreach f [glob $fpga/opl3/*.sv $fpga/opl3/*.v] { lappend v $f }
lappend v $fpga/src/opl4fm.v
lappend v $fpga/src/opl4_pcm.v
foreach f [glob $fpga/jtopl/*.v] { lappend v $f }
foreach f [glob $fpga/jt10/*.v] { lappend v $f }
lappend v $fpga/src/y8950_adpcm.v $fpga/src/adpcm_sdram.v $fpga/src/flash_rw.v
lappend v $fpga/src/megaram.v $fpga/src/gm2_slot1.v $fpga/src/sd_dma.sv
lappend v $fpga/src/scc_wave2_ghdl.v $fpga/src/scc_glue.v $fpga/src/scc_wave2v.v
lappend v $fpga/src/dbg_uart.v $fpga/src/ocm/kanji.v $fpga/src/ocm/rtc.v
lappend v $fpga/src/psg_filter.v $fpga/src/msx_mouse.v $fpga/src/ws2812.v
foreach f {crc16.v dpram.v pinfilter.v sd_reader.sv sdcmd_ctrl.sv sdc_ioport.sv} { lappend v $fpga/src/wondertang/$f }
foreach f [glob $fpga/tn_vdp_v3_v9958/src/hdmi/*.sv] { lappend v $f }
foreach f [glob $fpga/v9968/*.v] { lappend v $f }
lappend v $fpga/src/v9968_vram_shim.v $fpga/src/v9968_sdram_bridge.v $fpga/src/v9968_cpu_glue.v
lappend v $fpga/video720/msx2hdmi_v9968.sv
lappend v $fpga/src/msx_s1990.v
foreach f {iosys_bl616.v textdisp.v uart_fixed.v} { lappend v $fpga/src/iosys/$f }
lappend v $here/gowin_dpb_menu.v      ;# RAM del menu inferible (tools/make_dpb_menu.py), en vez de la IP DPB
foreach f {usb_hid_host.v usb_kbd_decode.v} { lappend v $fpga/src/usb_direct/$f }
# ---- Zynq ----
lappend v $here/gowin_prims.v $here/memory_axi.v $here/v9968_axi_backend.v $here/dbg_mailbox_axi.v
lappend v $here/sd_axi_proxy.v $here/top_zynq.v
add_files $v
# El build del Tang compila TODO como SystemVerilog (-verilog_std sysv2017) y hay
# .v con `int`, `logic`, `always_ff`... (dpram.v, ...). Misma semantica aqui.
set_property file_type SystemVerilog [get_files $v]
# usb_hid_host.v hace $readmemh("src/usb_direct/usb_hid_host_rom.hex") con ruta
# relativa al proyecto Gowin. Vivado la resuelve desde el DIRECTORIO DEL RUN de
# sintesis (anadir el .hex como fuente no basta si la ruta lleva carpetas), asi
# que un hook TCL.PRE recrea esa ruta dentro del run antes de synth_design.
set hook $here/tools/synth_pre.tcl
set fh [open $hook w]
puts $fh {# generado por build.tcl: $readmemh con ruta relativa al run de sintesis}
puts $fh "file mkdir src/usb_direct"
puts $fh "file copy -force {$fpga/src/usb_direct/usb_hid_host_rom.hex} src/usb_direct/usb_hid_host_rom.hex"
close $fh
set_property STEPS.SYNTH_DESIGN.TCL.PRE $hook [get_runs synth_1]

set vh {}
foreach f {T80s.vhd g80a.vhd t80.vhd t80_alu.vhd t80_mcode.vhd t80_pack.vhd t80_reg.vhd} { lappend vh $fpga/G80A/$f }
lappend vh $fpga/PSG_YM2149/YM2149.vhdl $fpga/denoise/denoise.vhd $fpga/monostable/monostable.vhd
foreach f {fifo.vhd lpf.vhd swioports.vhd uart_lite.vhd wifi_lite.vhd} { lappend vh $fpga/src/ocm/$f }
lappend vh $fpga/src/usb/usb_keyboard_msx.vhd $fpga/tn_vdp_v3_v9958/src/ram.vhd
# swioports.vhd hace "use work.vdp_package.all" (del VDP clasico). Gowin tolera
# el use sin el paquete si no se usa nada suyo; Vivado exige que exista.
lappend vh $fpga/tn_vdp_v3_v9958/src/vdp/vdp_package.vhd
add_files $vh

add_files -fileset constrs_1 $here/top_zynq.xdc
add_files -fileset constrs_1 $here/top_zynq_esp.xdc
# microSD en el header: sus pines van aparte; ZYNQ_NO_SD=1 (biseccion) deja los sd_* en tie-off
if {!([info exists ::env(ZYNQ_NO_SD)] && $::env(ZYNQ_NO_SD) eq "1")} {
    add_files -fileset constrs_1 $here/top_zynq_sd.xdc
} else { puts "ZYNQ_NO_SD: sin puertos sd_* (tie-off)" }
set_property top top_zynq [current_fileset]
update_compile_order -fileset sources_1

# ---------------------------------------------------------------- paso 1: elaboracion
if {$mode eq "elab"} {
    set t0 [clock seconds]
    synth_design -rtl -top top_zynq -part xc7z020clg400-2
    puts "ELAB_OK en [expr {[clock seconds]-$t0}] s"
    exit 0
}

# ---------------------------------------------------------------- paso 2: sintesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { puts "ERROR: sintesis fallida"; exit 1 }
open_run synth_1
report_utilization -file ./util_synth.rpt
report_utilization -hierarchical -hierarchical_depth 1 -file ./util_synth_hier.rpt
puts "SYNTH_OK"
if {$mode eq "synth"} { exit 0 }
close_design

# ---------------------------------------------------------------- paso 3: bitstream
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} { puts "ERROR: implementacion fallida"; exit 1 }
file copy -force ./vivado_prj/msximus_zynq.runs/impl_1/top_zynq.bit ./msximus_zynq.bit
file copy -force [glob ./vivado_prj/msximus_zynq.srcs/sources_1/bd/ps7_bd/ip/ps7_bd_processing_system7_0_0/ps7_init.tcl] ./ps7_init.tcl
open_run impl_1
report_utilization    -file ./util_impl.rpt
report_timing_summary -file ./timing.rpt
report_clocks         -file ./clocks.rpt
puts "=================================================="
puts "OK: [file normalize ./msximus_zynq.bit]"
puts "=================================================="
exit 0
