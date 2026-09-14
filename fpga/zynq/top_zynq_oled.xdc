# top_zynq_oled.xdc — OLED 128x64 (SSD1306) del conector J4 de la ZYNQ MINI.
# El fabricante cablea SOLO 4 senales del modulo a la FPGA, las del SPI de 4 hilos
# (esquematico pag. 10; D2..D7 sin conectar, que es lo que descarta el I2C):
#   J4 pin 18 D0  = SCLK -> E18   ·   J4 pin 19 D1 = SDIN -> E19
#   J4 pin 15 D/C        -> F16   ·   J4 pin 14 RST        -> F17
# BS0/BS1/BS2 (seleccion de interfaz) y CS van puenteados en la placa.
# Las conduce el ARM por GPIO EMIO del PS (banco 2, bits 0..3 = GPIO 54..57), asi el
# protocolo se cambia en arm/companion/oled.c sin recompilar la FPGA. Banco 35, 3V3.
set_property PACKAGE_PIN E18      [get_ports oled_sclk]
set_property PACKAGE_PIN E19      [get_ports oled_sdin]
set_property PACKAGE_PIN F16      [get_ports oled_dc]
set_property PACKAGE_PIN F17      [get_ports oled_rst_n]
set_property IOSTANDARD  LVCMOS33 [get_ports {oled_sclk oled_sdin oled_dc oled_rst_n}]
