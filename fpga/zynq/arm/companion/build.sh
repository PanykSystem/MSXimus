#!/bin/bash
# build.sh — compila companion.elf (Cortex-A9, bare-metal): proxy de SD (xsdps) +
# USB host (TinyUSB, ../tinyusb) con la toolchain ARM GNU 14.2 y los fuentes de
# Vivado 2019.2 (sin SDK).
set -e
cd "$(dirname "$0")"
TC="/c/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/14.2 rel1/bin"
export PATH="$TC:$PATH"
E=/d/Xilinx/Vivado/2019.2/data/embeddedsw
STD=$E/lib/bsp/standalone_v7_1/src
SDPS=$E/XilinxProcessorIPLib/drivers/sdps_v3_8/src
TU=$(cd ../tinyusb && pwd)/src
# -mno-unaligned-access: sin MMU toda la memoria es Strongly-Ordered y un acceso desalineado
# es DATA ABORT (gcc fusionaba strb en strh/str sobre char[] y osd_render abortaba).
CFLAGS="-mcpu=cortex-a9 -marm -mfloat-abi=soft -mno-unaligned-access -O2 -ffreestanding -fno-builtin -nostdlib -Wall -Wno-unused-function
        -DCI_HS_ZYNQ7000 -Ibsp -I. -Ixinput -I$TU -I$STD/common -I$STD/arm/cortexa9 -I$STD/arm/common -I$STD/arm/common/gcc -I$SDPS"
SRCS="start.S main.c log.c usb_host.c hid_pad.c osd.c xinput/xinput_host.c bsp/support.c bsp/xsdps_g.c
      $TU/tusb.c $TU/common/tusb_fifo.c $TU/host/usbh.c $TU/host/hub.c $TU/class/hid/hid_host.c
      $TU/portable/chipidea/ci_hs/hcd_ci_hs.c $TU/portable/ehci/ehci.c
      $SDPS/xsdps.c $SDPS/xsdps_options.c $SDPS/xsdps_sinit.c
      $STD/common/xil_assert.c $STD/common/xil_printf.c $STD/common/xplatform_info.c"
mkdir -p build
objs=""
for src in $SRCS; do
    o=build/$(basename "${src%.*}").o
    arm-none-eabi-gcc $CFLAGS -c "$src" -o "$o"
    objs="$objs $o"
done
arm-none-eabi-gcc $CFLAGS -T lscript.ld -Wl,-Map=build/companion.map -Wl,--no-warn-rwx-segments -o companion.elf $objs -lc -lgcc
arm-none-eabi-size companion.elf
echo "BUILD_OK: $(pwd)/companion.elf"
