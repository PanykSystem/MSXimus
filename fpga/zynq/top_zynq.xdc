# top_zynq.xdc — MSXimus en la ZYNQ MINI (XC7Z020-CLG400-2)
# Pines validados en placa (13/09): reloj K17, LEDs, botones, HDMI.
# Los del PS (DDR/MIO) los fija la IP; los HP y FCLK0 los constriñe la IP.
# PENDIENTE (PLAN.md D): USB x2, SD1 del PL, ESP32-C6 en el header de 34 IOs.

# ---- reloj del PL: 50 MHz ----
set_property PACKAGE_PIN K17      [get_ports clk50]
set_property IOSTANDARD  LVCMOS33 [get_ports clk50]
create_clock -period 20.000 -name clk50 [get_ports clk50]

# ---- botones (activos a 0) ----
set_property PACKAGE_PIN M19      [get_ports key_s1_n]
set_property PACKAGE_PIN M20      [get_ports key_s2_n]
set_property IOSTANDARD  LVCMOS33 [get_ports {key_s1_n key_s2_n}]

# ---- LEDs del PL (activos a 1) ----
set_property PACKAGE_PIN W13      [get_ports {led_z[0]}]
set_property PACKAGE_PIN V12      [get_ports {led_z[1]}]
set_property PACKAGE_PIN U12      [get_ports {led_z[2]}]
set_property PACKAGE_PIN T12      [get_ports {led_z[3]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {led_z[*]}]

# ---- HDMI (TMDS; el lado N lo coloca Vivado en la pareja del pad) ----
set_property PACKAGE_PIN H16      [get_ports clk_p]
set_property PACKAGE_PIN D19      [get_ports {data_p[0]}]
set_property PACKAGE_PIN C20      [get_ports {data_p[1]}]
set_property PACKAGE_PIN B19      [get_ports {data_p[2]}]
set_property IOSTANDARD  TMDS_33  [get_ports {clk_p clk_n data_p[*] data_n[*]}]
set_property PACKAGE_PIN H18      [get_ports hdmi_out_en]
set_property IOSTANDARD  LVCMOS33 [get_ports hdmi_out_en]

# (microSD del MSXimus: top_zynq_sd.xdc, lo anade build.tcl)

# ---- dominios de reloj asincronos entre si (los cruces van por CDC explicitos) ----
# Traduccion del set_clock_groups del SDC del Tang (fpga/build.tcl): nucleo MSX
# {pad 50, 108, 54, 27, 135, 37.5} · video HDMI {74.25, 371.25} · V9968 {85.909}
# · USB {12} · PS {FCLK0 150}. Nombres = los que Vivado deriva de los MMCM/PLL
# (report_clocks tras sintesis). mA_27 alimenta a MMCM_C/PLLE2_D, pero el Tang
# ya trataba video y VDP como asincronos del nucleo (toggles en los bridges).
set_clock_groups -asynchronous \
    -group [get_clocks {clk50 mA_108 mA_54 mA_27 mA_135 mA_375}] \
    -group [get_clocks {mC_74 mC_371}] \
    -group [get_clocks {pD_86}] \
    -group [get_clocks {pE_12}] \
    -group [get_clocks {clk_fpga_0}]

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
