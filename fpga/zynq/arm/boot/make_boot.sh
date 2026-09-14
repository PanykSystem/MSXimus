#!/bin/bash
# make_boot.sh — BOOT.bin del MSXimus para la ZYNQ MINI (arranque autonomo desde la SD de
# TF1/SD0 o, mas adelante, desde la QSPI). Orden de carga del FSBL (= orden del .bif; el FSBL
# de Xilinx EXIGE el bitstream justo despues del bootloader, "Partition order invalid" si no):
#   1) fsbl.elf            (bootloader: ps7_init + DDR)
#   2) msximus_zynq.bit    (el PL arranca; MSX_RUN lo lee de la DDR: basura unos ms, luego 0)
#   3) companion.elf       (proxy de SD + USB + OSD; pone MSX_RUN cuando la tarjeta esta lista).
#                          TIENE que ser la PRIMERA particion PS: el FSBL toma la direccion de
#                          arranque de la primera que ve ("first PS partition", image_mover.c)
#   4) zeros.bin           -> DDR 0x1FF00000: buzon + SDBOX a cero (MSX_RUN = 0: el MSX espera)
#   5) pack.bin            -> DDR 0x10F00000: pack de BIOS (lo mismo que hace boot.tcl por JTAG)
#   6) yrw801.rom          -> DDR 0x0F000000: memoria de ondas del OPL4 (wave_axi, S_AXI_GP0)
#   (el FSBL carga TODAS las particiones y despues salta al companion)
# Uso: make_boot.sh [pack.bin] [yrw801.rom]   -> BOOT.bin en este directorio. Copiarlo a la
# raiz de una SD FAT32 y meterla en TF1 con el BOOT switch en SD.
set -e
cd "$(dirname "$0")"
PACK=${1:-../../../../files/20260906/pack_bios_msximus_v35d_nextor214.bin}
WAVE=${2:-../../../../mi_release/3.1/yrw801.rom}
BIT=../../msximus_zynq.bit
for f in ../fsbl/fsbl.elf ../companion/companion.elf "$BIT" "$PACK" "$WAVE"; do
    [ -f "$f" ] || { echo "ERROR: falta $f"; exit 1; }
done
python -c "open('zeros.bin','wb').write(bytes(65536))"
cp "$PACK" pack.bin
cp "$WAVE" yrw801.rom
cat > boot.bif <<EOF
the_ROM_image:
{
    [bootloader] ../fsbl/fsbl.elf
    $BIT
    ../companion/companion.elf
    [load=0x1FF00000] zeros.bin
    [load=0x10F00000] pack.bin
    [load=0x0F000000] yrw801.rom
}
EOF
"/d/Xilinx/Vivado/2019.2/bin/bootgen.bat" -arch zynq -image boot.bif -o BOOT.bin -w on
ls -la BOOT.bin
echo "BOOT_OK: $(pwd)/BOOT.bin (pack: $PACK, wave: $WAVE)"
