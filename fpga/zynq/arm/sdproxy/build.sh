#!/bin/bash
# build.sh — compila sdproxy.elf (Cortex-A9, bare-metal) con la toolchain ARM GNU
# 14.2 y los fuentes del driver xsdps / BSP standalone de Vivado 2019.2 (sin SDK).
set -e
cd "$(dirname "$0")"
TC="/c/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/14.2 rel1/bin"
export PATH="$TC:$PATH"
E=/d/Xilinx/Vivado/2019.2/data/embeddedsw
STD=$E/lib/bsp/standalone_v7_1/src
SDPS=$E/XilinxProcessorIPLib/drivers/sdps_v3_8/src
CFLAGS="-mcpu=cortex-a9 -marm -mfloat-abi=soft -O2 -ffreestanding -fno-builtin -nostdlib -Wall -Wno-unused-function
        -Ibsp -I. -I$STD/common -I$STD/arm/cortexa9 -I$STD/arm/common -I$STD/arm/common/gcc -I$SDPS"
mkdir -p build
objs=""
for src in start.S main.c log.c bsp/support.c bsp/xsdps_g.c $SDPS/xsdps.c $SDPS/xsdps_options.c $SDPS/xsdps_sinit.c \
           $STD/common/xil_assert.c $STD/common/xil_printf.c $STD/common/xplatform_info.c; do
    o=build/$(basename "${src%.*}").o
    arm-none-eabi-gcc $CFLAGS -c "$src" -o "$o"
    objs="$objs $o"
done
arm-none-eabi-gcc $CFLAGS -T lscript.ld -Wl,-Map=build/sdproxy.map -Wl,--no-warn-rwx-segments -o sdproxy.elf $objs -lc -lgcc
arm-none-eabi-size sdproxy.elf
echo "BUILD_OK: $(pwd)/sdproxy.elf"
