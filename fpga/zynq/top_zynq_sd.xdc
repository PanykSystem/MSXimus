# top_zynq_sd.xdc — microSD del MSXimus en el header (se anade desde build.tcl
# salvo ZYNQ_NO_SD=1, variante de biseccion con los sd_* en tie-off).
# ---- microSD del MSXimus (sd_reader, modo SD 1 bit) en el header CAM1 ----
# NO hay microSD en el PL (TF1/TF2 = SD0/SD1 del PS por MIO). Breakout pasivo
# 3V3 en CAM1 pines 31..36 (GND 37/38, 3V3 39/40). Ver PLAN.md D.
set_property PACKAGE_PIN N18      [get_ports sd_sclk]
set_property PACKAGE_PIN T20      [get_ports sd_cmd]
set_property PACKAGE_PIN P20      [get_ports sd_dat0]
set_property PACKAGE_PIN N20      [get_ports sd_dat1]
set_property PACKAGE_PIN U20      [get_ports sd_dat2]
set_property PACKAGE_PIN P18      [get_ports sd_dat3]
set_property IOSTANDARD  LVCMOS33 [get_ports {sd_sclk sd_cmd sd_dat0 sd_dat1 sd_dat2 sd_dat3}]
set_property PULLUP      TRUE      [get_ports {sd_cmd sd_dat0 sd_dat1 sd_dat2 sd_dat3}]

