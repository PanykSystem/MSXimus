#!/bin/bash
# make_boot.sh — BOOT.bin del MSXimus para la ZYNQ MINI (arranque autonomo desde la SD de
# TF1/SD0 o, mas adelante, desde la QSPI). Orden de carga del FSBL (= orden del .bif):
#   1) fsbl.elf            (bootloader: ps7_init + DDR)
#   2) zeros.bin           -> DDR 0x1FF00000: buzon + SDBOX a cero (MSX_RUN = 0: el MSX espera)
#   3) pack.bin            -> DDR 0x10F00000: pack de BIOS (lo mismo que hace boot.tcl por JTAG)
#   4) msximus_zynq.bit    (el PL arranca con el MSX en reset hasta MSX_RUN)
#   5) companion.elf       (proxy de SD + USB + OSD; pone MSX_RUN cuando la tarjeta esta lista)
# Uso: make_boot.sh [pack.bin]   -> BOOT.bin en este directorio. Copiarlo a la raiz de una SD
# FAT32 y meterla en TF1 con el BOOT switch en SD.
set -e
cd "$(dirname "$0")"
PACK=${1:-../../../../files/20260906/pack_bios_msximus_v35d_nextor214.bin}
BIT=../../msximus_zynq.bit
for f in ../fsbl/fsbl.elf ../companion/companion.elf "$BIT" "$PACK"; do
    [ -f "$f" ] || { echo "ERROR: falta $f"; exit 1; }
done
python -c "open('zeros.bin','wb').write(bytes(65536))"
cp "$PACK" pack.bin
cat > boot.bif <<EOF
the_ROM_image:
{
    [bootloader] ../fsbl/fsbl.elf
    [load=0x1FF00000] zeros.bin
    [load=0x10F00000] pack.bin
    $BIT
    ../companion/companion.elf
}
EOF
"/d/Xilinx/Vivado/2019.2/bin/bootgen.bat" -arch zynq -image boot.bif -o BOOT.bin -w on
ls -la BOOT.bin
echo "BOOT_OK: $(pwd)/BOOT.bin (pack: $PACK)"
