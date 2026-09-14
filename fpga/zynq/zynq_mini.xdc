# =============================================================================
# ZYNQ MINI (OMDAZZ) - XC7Z020-CLG400-2
# Pinout base consolidado a partir de los 14 .xdc de ejemplo del fabricante.
#
# AVISO: los .xdc originales del fabricante mezclan pines de OTRA placa de
# encapsulado mayor (AH26, AJ27, AK28, AE29...). Esos NO existen en el CLG400
# y estan descartados aqui. Solo se conserva lo verificado en >=2 ficheros
# o lo unico coherente con el CLG400.
#
# PENDIENTE de confirmar contra el esquematico o la placa en mano:
#   - SD1 (PL)            -> conector microSD del lado PL
#   - OLED (PL)
#   - header de 34 IOs single-ended 3V3 (PL)
#   - tercer boton (K1, segun el diagrama es del PS)
#
# CONFIRMADO en placa (13/09): hay PHY USB3320C (U19) junto al USB-C P3 ->
# USB0 del PS por ULPI en MIO 28..39. Ningun ejemplo del fabricante lo
# habilita: activar USB0 a mano en el asistente del PS7.
# VALIDADO en placa (13/09): clk K17 = 50 MHz, LEDs W13/V12/U12/T12, boton M19.
# =============================================================================

# -----------------------------------------------------------------------------
# Reloj de sistema del PL: 50 MHz
# -----------------------------------------------------------------------------
set_property PACKAGE_PIN K17      [get_ports clk]
set_property IOSTANDARD  LVCMOS33 [get_ports clk]
create_clock -period 20.000 -name sys_clk [get_ports clk]

# -----------------------------------------------------------------------------
# Botones de usuario (PL). Activo bajo.
# El fabricante usa M19 y M20 indistintamente como "reset" segun el ejemplo.
# -----------------------------------------------------------------------------
set_property PACKAGE_PIN M19      [get_ports rst_n]
set_property IOSTANDARD  LVCMOS33 [get_ports rst_n]

#set_property PACKAGE_PIN M20      [get_ports key2_n]
#set_property IOSTANDARD  LVCMOS33 [get_ports key2_n]

# -----------------------------------------------------------------------------
# LEDs de usuario (PL) x4
# -----------------------------------------------------------------------------
set_property PACKAGE_PIN W13      [get_ports {led[0]}]
set_property PACKAGE_PIN V12      [get_ports {led[1]}]
set_property PACKAGE_PIN U12      [get_ports {led[2]}]
set_property PACKAGE_PIN T12      [get_ports {led[3]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {led[*]}]

# -----------------------------------------------------------------------------
# HDMI / TMDS (PL). Los pares N los resuelve Vivado solo a partir del P.
# HDMI_OUT_EN habilita el buffer de salida: hay que ponerlo a 1.
# -----------------------------------------------------------------------------
set_property PACKAGE_PIN H16      [get_ports tmds_clk_p]
set_property PACKAGE_PIN D19      [get_ports {tmds_data_p[0]}]
set_property PACKAGE_PIN C20      [get_ports {tmds_data_p[1]}]
set_property PACKAGE_PIN B19      [get_ports {tmds_data_p[2]}]
set_property IOSTANDARD  TMDS_33  [get_ports tmds_clk_p]
set_property IOSTANDARD  TMDS_33  [get_ports {tmds_data_p[*]}]

set_property PACKAGE_PIN H18      [get_ports hdmi_out_en]
set_property IOSTANDARD  LVCMOS33 [get_ports hdmi_out_en]

# -----------------------------------------------------------------------------
# EEPROM I2C (PL)
# -----------------------------------------------------------------------------
#set_property PACKAGE_PIN F19      [get_ports eeprom_scl]
#set_property PACKAGE_PIN F20      [get_ports eeprom_sda]
#set_property IOSTANDARD  LVCMOS33 [get_ports {eeprom_scl eeprom_sda}]

# -----------------------------------------------------------------------------
# UART del PL (independiente de la UART1 del PS, que va por MIO 48..49)
# -----------------------------------------------------------------------------
#set_property PACKAGE_PIN P15      [get_ports uart_rx]
#set_property PACKAGE_PIN U15      [get_ports uart_tx]
#set_property IOSTANDARD  LVCMOS33 [get_ports {uart_rx uart_tx}]

# -----------------------------------------------------------------------------
# Ethernet Gigabit del PL (RGMII). El MSXimus no lo necesita; queda por si
# algun dia sustituye al ESP32 para las descargas del File-Hunter.
# -----------------------------------------------------------------------------
#set_property PACKAGE_PIN G17      [get_ports phy_rst_n]
#set_property PACKAGE_PIN G18      [get_ports phy_mdc]
#set_property PACKAGE_PIN G19      [get_ports phy_mdio]
#set_property PACKAGE_PIN J14      [get_ports phy_txc]
#set_property PACKAGE_PIN K14      [get_ports phy_tx_ctrl]
#set_property PACKAGE_PIN N16      [get_ports {phy_txd[0]}]
#set_property PACKAGE_PIN J19      [get_ports {phy_txd[1]}]
#set_property PACKAGE_PIN H20      [get_ports {phy_txd[2]}]
#set_property PACKAGE_PIN N15      [get_ports {phy_txd[3]}]
#set_property PACKAGE_PIN L16      [get_ports phy_rxc]
#set_property PACKAGE_PIN L17      [get_ports phy_rx_ctrl]
#set_property PACKAGE_PIN L20      [get_ports {phy_rxd[0]}]
#set_property PACKAGE_PIN K19      [get_ports {phy_rxd[1]}]
#set_property PACKAGE_PIN J18      [get_ports {phy_rxd[2]}]
#set_property PACKAGE_PIN J20      [get_ports {phy_rxd[3]}]

# =============================================================================
# Datos del PS (no van en el .xdc: se meten en el asistente del PS7)
#
#   DDR3          MT41J256M16 RE-125, 16 bit, 533,333 MHz, 512 MB, sin ECC
#   Cristal PS    33,333333 MHz
#   APU           766 MHz  (los ejemplos ARM usan 666,67; PetaLinux usa 766)
#   Bank0 / Bank1 LVCMOS 3.3V / LVCMOS 1.8V   <-- ojo, un ejemplo pone 3.3/3.3
#
#   MIO:
#     QSPI Flash (128 Mbit, single SS, 200 MHz) .... MIO 1 .. 6
#     SD1 ......................................... MIO 10 .. 15
#     ETH0 Gigabit ................................ MIO 16 .. 27
#     USB0 (PHY USB3320C, ULPI) ................... MIO 28 .. 39  <- activar a mano
#     SD0 ......................................... MIO 40 .. 45
#     UART1 (USB-C) ............................... MIO 48 .. 49
#     ETH0 MDIO ................................... MIO 52 .. 53
#
#   AXI: los 4 puertos S_AXI_HP son de 64 bits. Para el MSXimus, la VRAM del
#   V9968 y la RAM del MSX salen por aqui en vez de por SDRAM/DDR3 en el PL.
# =============================================================================
