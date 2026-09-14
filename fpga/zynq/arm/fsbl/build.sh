#!/bin/bash
# build.sh — FSBL del MSXimus para la ZYNQ MINI SIN SDK: el zynq_fsbl de Xilinx tal cual
# (fuentes en data/embeddedsw de Vivado 2019.2) + la BSP standalone de esas mismas fuentes +
# drivers qspips/sdps/xilffs de ahi + el driver devcfg (PCAP), que Vivado no trae y esta
# bajado de github.com/Xilinx/embeddedsw (xilinx-v2019.2) en devcfg/ + ps7_init.c/h del bd.
# Consola por la UART1 (P1, 115200) con FSBL_DEBUG_INFO. Sale fsbl.elf (para bootgen).
set -e
cd "$(dirname "$0")"
TC="/c/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/14.2 rel1/bin"
export PATH="$TC:$PATH"
E=/d/Xilinx/Vivado/2019.2/data/embeddedsw
STD=$E/lib/bsp/standalone_v7_1/src
FSBL=$E/lib/sw_apps/zynq_fsbl/src
QSPI=$E/XilinxProcessorIPLib/drivers/qspips_v3_6/src
SDPS=$E/XilinxProcessorIPLib/drivers/sdps_v3_8/src
UART=$E/XilinxProcessorIPLib/drivers/uartps_v3_8/src
WDT=$E/XilinxProcessorIPLib/drivers/wdtps_v3_2/src
FFS=$E/lib/sw_services/xilffs_v4_2/src
# ps7_init del block design (se regenera con cada build de Vivado)
BD=../../vivado_prj/msximus_zynq.srcs/sources_1/bd/ps7_bd/ip/ps7_bd_processing_system7_0_0
if [ -f "$BD/ps7_init.c" ]; then cp "$BD/ps7_init.c" "$BD/ps7_init.h" ps7/; fi
CFLAGS="-mcpu=cortex-a9 -marm -mfpu=vfpv3 -mfloat-abi=soft -O2 -ffreestanding -fno-builtin -nostdlib -Wall
        -Wno-unused-function -Wno-unused-variable -Wno-unused-but-set-variable -DFSBL_DEBUG_INFO
        -Ibsp -Ips7 -Idevcfg -I$FSBL -I$STD/common -I$STD/arm/cortexa9 -I$STD/arm/common
        -I$STD/arm/common/gcc -I$QSPI -I$SDPS -I$UART -I$WDT -I$FFS/include"
SRCS="$FSBL/main.c $FSBL/image_mover.c $FSBL/md5.c $FSBL/pcap.c $FSBL/qspi.c $FSBL/sd.c
      $FSBL/nand.c $FSBL/nor.c $FSBL/rsa.c $FSBL/fsbl_hooks.c $FSBL/fsbl_handoff.S ps7/ps7_init.c
      bsp/outbyte.c bsp/xdevcfg_g.c bsp/xqspips_g.c bsp/xsdps_g.c
      devcfg/xdevcfg.c devcfg/xdevcfg_hw.c devcfg/xdevcfg_sinit.c devcfg/xdevcfg_intr.c
      $QSPI/xqspips.c $QSPI/xqspips_hw.c $QSPI/xqspips_options.c $QSPI/xqspips_sinit.c
      $SDPS/xsdps.c $SDPS/xsdps_options.c $SDPS/xsdps_sinit.c
      $FFS/ff.c $FFS/diskio.c $FFS/ffsystem.c $FFS/ffunicode.c
      $STD/common/xil_assert.c $STD/common/xil_printf.c $STD/common/xil_io.c $STD/common/xil_mem.c
      $STD/common/xplatform_info.c
      $STD/arm/common/vectors.c $STD/arm/common/xil_exception.c
      $STD/arm/cortexa9/xil_cache.c $STD/arm/cortexa9/xil_mmu.c $STD/arm/cortexa9/xtime_l.c
      $STD/arm/cortexa9/xil_misc_psreset_api.c bsp/stubs.c
      $STD/arm/cortexa9/gcc/asm_vectors.S $STD/arm/cortexa9/gcc/boot.S $STD/arm/cortexa9/gcc/cpu_init.S
      $STD/arm/cortexa9/gcc/translation_table.S $STD/arm/cortexa9/gcc/xil-crt0.S
      $STD/arm/common/gcc/_exit.c $STD/arm/common/gcc/_sbrk.c $STD/arm/common/gcc/close.c $STD/arm/common/gcc/lseek.c
      $STD/arm/common/gcc/read.c $STD/arm/common/gcc/write.c $STD/arm/common/gcc/fstat.c $STD/arm/common/gcc/isatty.c
      $STD/arm/common/gcc/getpid.c $STD/arm/common/gcc/kill.c $STD/arm/common/gcc/open.c"
mkdir -p build
objs=""
for src in $SRCS; do
    o=build/$(basename "${src%.*}").o
    arm-none-eabi-gcc $CFLAGS -c "$src" -o "$o"
    objs="$objs $o"
done
arm-none-eabi-gcc $CFLAGS -T "$FSBL/lscript.ld" -Wl,-Map=build/fsbl.map -Wl,--no-warn-rwx-segments -o fsbl.elf $objs -lc -lgcc
arm-none-eabi-size fsbl.elf
echo "BUILD_OK: $(pwd)/fsbl.elf"
