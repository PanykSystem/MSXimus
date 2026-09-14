# bd_ps7.tcl — Block design del PS7 de la ZYNQ MINI para el MSXimus.
#   DDR3 (config del fabricante, incluidas longitudes de pista), UART1 (MIO 48-49),
#   FCLK0 = ::FCLK_MHZ, y ::N_HP puertos S_AXI_HPn de 64 bits expuestos al PL,
#   cada uno con su reloj como ENTRADA del bd (HPn_ACLK): el top decide si es
#   FCLK0 (VRAM a 150) o clk_54m (RAM del Z80, sin CDC).
#   Sin M_AXI_GP ni perifericos (QSPI/SD/ETH/USB se anaden con el PS).
# Se llama desde build.tcl con el proyecto ya creado. Requiere ::FCLK_MHZ y ::N_HP.

create_bd_design "ps7_bd"
set ps7 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0]

set_property -dict [list \
    CONFIG.PCW_PACKAGE_NAME {clg400} \
    CONFIG.PCW_PRESET_BANK0_VOLTAGE {LVCMOS 3.3V} \
    CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
    CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ {33.333333} \
    CONFIG.PCW_APU_PERIPHERAL_FREQMHZ {666.666666} \
    \
    CONFIG.PCW_UIPARAM_DDR_ENABLE {1} \
    CONFIG.PCW_UIPARAM_DDR_MEMORY_TYPE {DDR 3} \
    CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41J256M16 RE-125} \
    CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {16 Bit} \
    CONFIG.PCW_UIPARAM_DDR_DRAM_WIDTH {16 Bits} \
    CONFIG.PCW_UIPARAM_DDR_DEVICE_CAPACITY {4096 MBits} \
    CONFIG.PCW_UIPARAM_DDR_SPEED_BIN {DDR3_1066F} \
    CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ {533.333333} \
    CONFIG.PCW_UIPARAM_DDR_ECC {Disabled} \
    CONFIG.PCW_UIPARAM_DDR_BANK_ADDR_COUNT {3} \
    CONFIG.PCW_UIPARAM_DDR_ROW_ADDR_COUNT {15} \
    CONFIG.PCW_UIPARAM_DDR_COL_ADDR_COUNT {10} \
    CONFIG.PCW_UIPARAM_DDR_BL {8} \
    CONFIG.PCW_UIPARAM_DDR_CL {7} \
    CONFIG.PCW_UIPARAM_DDR_CWL {6} \
    CONFIG.PCW_UIPARAM_DDR_T_RCD {7} \
    CONFIG.PCW_UIPARAM_DDR_T_RP {7} \
    CONFIG.PCW_UIPARAM_DDR_T_RC {48.91} \
    CONFIG.PCW_UIPARAM_DDR_T_RAS_MIN {35.0} \
    CONFIG.PCW_UIPARAM_DDR_T_FAW {40.0} \
    CONFIG.PCW_UIPARAM_DDR_HIGH_TEMP {Normal (0-85)} \
    CONFIG.PCW_UIPARAM_DDR_USE_INTERNAL_VREF {0} \
    CONFIG.PCW_UIPARAM_DDR_TRAIN_WRITE_LEVEL {1} \
    CONFIG.PCW_UIPARAM_DDR_TRAIN_READ_GATE {1} \
    CONFIG.PCW_UIPARAM_DDR_TRAIN_DATA_EYE {1} \
    CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY0 {0.25} \
    CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY1 {0.25} \
    CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY2 {0.25} \
    CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY3 {0.25} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_0_PACKAGE_LENGTH {54.563} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_1_PACKAGE_LENGTH {54.563} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_2_PACKAGE_LENGTH {54.563} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_3_PACKAGE_LENGTH {54.563} \
    CONFIG.PCW_UIPARAM_DDR_DQS_0_PACKAGE_LENGTH {101.239} \
    CONFIG.PCW_UIPARAM_DDR_DQS_1_PACKAGE_LENGTH {79.5025} \
    CONFIG.PCW_UIPARAM_DDR_DQS_2_PACKAGE_LENGTH {60.536} \
    CONFIG.PCW_UIPARAM_DDR_DQS_3_PACKAGE_LENGTH {71.7715} \
    CONFIG.PCW_UIPARAM_DDR_DQ_0_PACKAGE_LENGTH {104.5365} \
    CONFIG.PCW_UIPARAM_DDR_DQ_1_PACKAGE_LENGTH {70.676} \
    CONFIG.PCW_UIPARAM_DDR_DQ_2_PACKAGE_LENGTH {59.1615} \
    CONFIG.PCW_UIPARAM_DDR_DQ_3_PACKAGE_LENGTH {81.319} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_0_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_1_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_2_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_3_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_DQS_0_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_DQS_1_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_DQS_2_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_DQS_3_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_DQ_0_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_DQ_1_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_DQ_2_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_DQ_3_PROPOGATION_DELAY {160} \
    \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49} \
    CONFIG.PCW_UART1_BAUD_RATE {115200} \
    CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART0_UART0_IO {EMIO} \
    CONFIG.PCW_UART0_BAUD_RATE {115200} \
    CONFIG.PCW_QSPI_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_SD0_SD0_IO {MIO 40 .. 45} \
    CONFIG.PCW_SD0_GRP_CD_ENABLE {0} \
    CONFIG.PCW_SD0_GRP_WP_ENABLE {0} \
    CONFIG.PCW_SD0_GRP_POW_ENABLE {0} \
    CONFIG.PCW_SD1_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_SD1_SD1_IO {MIO 10 .. 15} \
    CONFIG.PCW_SD1_GRP_CD_ENABLE {0} \
    CONFIG.PCW_SD1_GRP_WP_ENABLE {0} \
    CONFIG.PCW_SD1_GRP_POW_ENABLE {0} \
    CONFIG.PCW_SDIO_PERIPHERAL_FREQMHZ {50} \
    CONFIG.PCW_MIO_10_PULLUP {enabled} CONFIG.PCW_MIO_11_PULLUP {enabled} CONFIG.PCW_MIO_12_PULLUP {enabled} \
    CONFIG.PCW_MIO_13_PULLUP {enabled} CONFIG.PCW_MIO_14_PULLUP {enabled} CONFIG.PCW_MIO_15_PULLUP {enabled} \
    CONFIG.PCW_MIO_40_PULLUP {enabled} CONFIG.PCW_MIO_41_PULLUP {enabled} CONFIG.PCW_MIO_42_PULLUP {enabled} \
    CONFIG.PCW_MIO_43_PULLUP {enabled} CONFIG.PCW_MIO_44_PULLUP {enabled} CONFIG.PCW_MIO_45_PULLUP {enabled} \
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_USB0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_USB0_USB0_IO {MIO 28 .. 39} \
    CONFIG.PCW_USB0_RESET_ENABLE {1} \
    CONFIG.PCW_USB0_RESET_IO {MIO 46} \
    CONFIG.PCW_I2C0_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_TTC0_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_GPIO_MIO_GPIO_ENABLE {0} \
    \
    CONFIG.PCW_USE_S_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_GP1 {1} \
    CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {1} \
    CONFIG.PCW_GPIO_EMIO_GPIO_IO {4} \
    CONFIG.PCW_USE_M_AXI_GP0 {0} \
    CONFIG.PCW_USE_M_AXI_GP1 {0} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {64} \
    CONFIG.PCW_USE_S_AXI_HP1 [expr {$::N_HP >= 2 ? 1 : 0}] \
    CONFIG.PCW_S_AXI_HP1_DATA_WIDTH {64} \
    CONFIG.PCW_USE_S_AXI_HP2 [expr {$::N_HP >= 3 ? 1 : 0}] \
    CONFIG.PCW_S_AXI_HP2_DATA_WIDTH {64} \
    CONFIG.PCW_USE_S_AXI_HP3 [expr {$::N_HP >= 4 ? 1 : 0}] \
    CONFIG.PCW_S_AXI_HP3_DATA_WIDTH {64} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $::FCLK_MHZ \
    CONFIG.PCW_EN_CLK1_PORT {0} \
    CONFIG.PCW_EN_CLK2_PORT {0} \
    CONFIG.PCW_EN_CLK3_PORT {0} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
] $ps7

# Pines dedicados del PS (DDR + MIO): puertos externos, no van en el .xdc
make_bd_intf_pins_external [get_bd_intf_pins $ps7/DDR] [get_bd_intf_pins $ps7/FIXED_IO]
set_property name DDR      [get_bd_intf_ports DDR_0]
set_property name FIXED_IO [get_bd_intf_ports FIXED_IO_0]

# HPn hacia el PL: puerto AXI3 externo + su ACLK como entrada del bd.
# ::HP_ACLK_HZ = frecuencia de cada ACLK (HP0 = VRAM a FCLK0, HP1 = RAM del Z80 a 54,
# HP2 = buzon de depuracion xsdb a 54, HP3 = "SD en DDR" a 27).
if {![info exists ::HP_ACLK_HZ]} { set ::HP_ACLK_HZ [list [expr {int($::FCLK_MHZ*1000000)}] 54000000 54000000 27000000] }
for {set n 0} {$n < $::N_HP} {incr n} {
    make_bd_intf_pins_external [get_bd_intf_pins $ps7/S_AXI_HP$n]
    set_property name S_AXI_HP$n [get_bd_intf_ports S_AXI_HP${n}_0]
    create_bd_port -dir I -type clk -freq_hz [lindex $::HP_ACLK_HZ $n] HP${n}_ACLK
    connect_bd_net [get_bd_ports HP${n}_ACLK] [get_bd_pins $ps7/S_AXI_HP${n}_ACLK]
    set_property CONFIG.ASSOCIATED_BUSIF S_AXI_HP$n [get_bd_ports HP${n}_ACLK]
}

# S_AXI_GP0 (32 bits) hacia el PL: memoria de ondas del OPL4 (wave_axi) a 37,5 MHz
make_bd_intf_pins_external [get_bd_intf_pins $ps7/S_AXI_GP0]
set_property name S_AXI_GP0 [get_bd_intf_ports S_AXI_GP0_0]
create_bd_port -dir I -type clk -freq_hz 37500000 GP0_ACLK
connect_bd_net [get_bd_ports GP0_ACLK] [get_bd_pins $ps7/S_AXI_GP0_ACLK]
set_property CONFIG.ASSOCIATED_BUSIF S_AXI_GP0 [get_bd_ports GP0_ACLK]
# S_AXI_GP1 (32 bits): puerto de depuracion 34-37h de la memoria de ondas (2a wave_axi) a clk_54m
make_bd_intf_pins_external [get_bd_intf_pins $ps7/S_AXI_GP1]
set_property name S_AXI_GP1 [get_bd_intf_ports S_AXI_GP1_0]
create_bd_port -dir I -type clk -freq_hz 54000000 GP1_ACLK
connect_bd_net [get_bd_ports GP1_ACLK] [get_bd_pins $ps7/S_AXI_GP1_ACLK]
set_property CONFIG.ASSOCIATED_BUSIF S_AXI_GP1 [get_bd_ports GP1_ACLK]

# GPIO EMIO (4 bits) -> OLED 128x64 del conector J4 (SSD1306 por SPI de 4 hilos, bit-bang
# desde el ARM: arm/companion/oled.c). Banco 2 del GPIO del PS = EMIO, bits 0..3 = GPIO 54..57.
make_bd_intf_pins_external [get_bd_intf_pins $ps7/GPIO_0]
set_property name OLED_GPIO [get_bd_intf_ports GPIO_0_0]

# Reloj y reset del PL: puertos explicitos
create_bd_port -dir O -type clk FCLK_CLK0
connect_bd_net [get_bd_ports FCLK_CLK0] [get_bd_pins $ps7/FCLK_CLK0]
create_bd_port -dir O -type rst FCLK_RESET0_N
connect_bd_net [get_bd_ports FCLK_RESET0_N] [get_bd_pins $ps7/FCLK_RESET0_N]
# Interrupcion PL -> PS (IRQ_F2P[0] = peticion del proxy de SD al ARM)
create_bd_port -dir I -from 0 -to 0 -type intr IRQ_F2P
connect_bd_net [get_bd_ports IRQ_F2P] [get_bd_pins $ps7/IRQ_F2P]
# UART0 por EMIO: el ARM (companion) hace de BL616 con el protocolo de iosys_bl616
# (OSD de texto, mandos); el companion la programa a 2 Mbps (ref 100 MHz: CD 10, BDIV 4)
create_bd_port -dir O UART0_TX
connect_bd_net [get_bd_ports UART0_TX] [get_bd_pins $ps7/UART0_TX]
create_bd_port -dir I UART0_RX
connect_bd_net [get_bd_ports UART0_RX] [get_bd_pins $ps7/UART0_RX]

assign_bd_address
validate_bd_design
save_bd_design
