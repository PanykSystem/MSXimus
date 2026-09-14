# top_zynq_esp.xdc — ESP32 (WiFi UNAPI por UART + aviso de turbo) en el header CAM1.
# Mismo cableado de 3 hilos que el J10 de la Tang (esp_rx_i <- TX del ESP, esp_tx_o -> RX
# del ESP, esp_turbo_o -> GPIO del ESP), asi el C6 o el S3 se pinchan sin tocar el PL.
# CAM1: 26 W16 = esp_rx_i, 28 R18 = esp_tx_o, 30 P19 = esp_turbo_o; GND 37/38, 5 V pin 2
# (VIN del modulo) o 3V3 39/40. Todo 3V3 (el header es LVCMOS33 estricto). Ver PLAN.md D.
# El PULLUP de esp_rx_i deja la UART en reposo (alto) sin modulo pinchado.
set_property PACKAGE_PIN W16      [get_ports esp_rx_i]
set_property PACKAGE_PIN R18      [get_ports esp_tx_o]
set_property PACKAGE_PIN P19      [get_ports esp_turbo_o]
set_property IOSTANDARD  LVCMOS33 [get_ports {esp_rx_i esp_tx_o esp_turbo_o}]
set_property PULLUP      TRUE      [get_ports esp_rx_i]
