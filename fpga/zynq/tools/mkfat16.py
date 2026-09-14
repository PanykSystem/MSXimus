#!/usr/bin/env python3
"""
mkfat16.py — imagen de "SD" de prueba para el MSXimus en la ZYNQ MINI (sd_axi_proxy,
modo imagen): MBR con una particion FAT16 (tipo 0x0E, LBA 2048, como la imagen de
SymbOS que ya arranca en el MSXimus) y los ficheros que se le pasen en la raiz.

Uso: python mkfat16.py salida.img [--mb 32] fichero1 [fichero2 ...]
     (los ficheros van a la raiz con su nombre 8.3 en mayusculas)
"""
import os, struct, sys, time

BPS = 512

def name83(path):
    base = os.path.basename(path).upper()
    stem, _, ext = base.partition(".")
    if len(stem) > 8 or len(ext) > 3:
        raise SystemExit(f"nombre no 8.3: {base}")
    return stem.ljust(8).encode("ascii") + ext.ljust(3).encode("ascii")

def dos_datetime(t=None):
    lt = time.localtime(t)
    d = ((lt.tm_year - 1980) << 9) | (lt.tm_mon << 5) | lt.tm_mday
    tm = (lt.tm_hour << 11) | (lt.tm_min << 5) | (lt.tm_sec // 2)
    return tm, d

def build(out, mb, files):
    part_lba = 2048
    spc = 8                                   # 4 KB por cluster
    root_entries = 512
    # sectores de la particion: multiplo de spc, < 65536 para que quepa en el campo de 16 bits
    part_sectors = min(mb * 2048, 65535) - part_lba
    part_sectors -= part_sectors % spc
    root_sectors = root_entries * 32 // BPS
    # FAT16: clusters = (part - reservados - fats - raiz) / spc; fat_sz iterado
    fat_sz = 1
    while True:
        data_sectors = part_sectors - 1 - 2 * fat_sz - root_sectors
        clusters = data_sectors // spc
        need = ((clusters + 2) * 2 + BPS - 1) // BPS
        if need <= fat_sz: break
        fat_sz = need
    if clusters < 4085: raise SystemExit(f"demasiado pequena para FAT16: {clusters} clusters")
    first_data = 1 + 2 * fat_sz + root_sectors

    img = bytearray((part_lba + part_sectors) * BPS)
    # ---- MBR ----
    mbr = img[0:BPS]
    e = 0x1BE
    struct.pack_into("<BBBBBBBBII", mbr, e, 0x00, 0xFE, 0xFF, 0xFF, 0x0E, 0xFE, 0xFF, 0xFF, part_lba, part_sectors)
    mbr[0x1FE:0x200] = b"\x55\xAA"
    img[0:BPS] = mbr
    # ---- sector de arranque (BPB) ----
    bs = bytearray(BPS)
    bs[0:3] = b"\xEB\x3C\x90"; bs[3:11] = b"MSXIMUS "
    struct.pack_into("<HBHBHHBHHHII", bs, 11, BPS, spc, 1, 2, root_entries, part_sectors, 0xF8, fat_sz, 32, 8, part_lba, 0)
    struct.pack_into("<BBBI", bs, 36, 0x80, 0, 0x29, 0x20260914)
    bs[43:54] = b"MSXIMUS DDR"; bs[54:62] = b"FAT16   "
    bs[0x1FE:0x200] = b"\x55\xAA"
    p = part_lba * BPS
    img[p:p + BPS] = bs
    # ---- FAT (x2) y raiz ----
    fat = bytearray(fat_sz * BPS)
    fat[0:4] = b"\xF8\xFF\xFF\xFF"
    root = bytearray(root_sectors * BPS)
    tm, d = dos_datetime()
    root[0:11] = b"MSXIMUS DDR"; root[11] = 0x08; struct.pack_into("<HH", root, 22, tm, d)
    next_cluster = 2
    for i, f in enumerate(files, start=1):
        data = open(f, "rb").read()
        n = max(1, (len(data) + spc * BPS - 1) // (spc * BPS))
        first = next_cluster
        for c in range(first, first + n):
            nxt = 0xFFFF if c == first + n - 1 else c + 1
            struct.pack_into("<H", fat, c * 2, nxt)
        off = (part_lba + first_data + (first - 2) * spc) * BPS
        img[off:off + len(data)] = data
        ent = i * 32
        root[ent:ent + 11] = name83(f); root[ent + 11] = 0x20
        struct.pack_into("<HHHHI", root, ent + 22, tm, d, first, 0, len(data)) if False else None
        struct.pack_into("<HH", root, ent + 22, tm, d)           # hora/fecha de modificacion
        struct.pack_into("<H", root, ent + 26, first)            # primer cluster
        struct.pack_into("<I", root, ent + 28, len(data))        # tamano
        next_cluster += n
        print(f"  {os.path.basename(f):14s} {len(data):8d} B  clusters {first}..{first + n - 1}")
    img[p + BPS:p + BPS + len(fat)] = fat
    img[p + BPS + len(fat):p + BPS + 2 * len(fat)] = fat
    r = p + (1 + 2 * fat_sz) * BPS
    img[r:r + len(root)] = root
    open(out, "wb").write(img)
    print(f"{out}: {len(img) // 1048576} MB, particion FAT16 de {part_sectors} sectores, {clusters} clusters, FAT {fat_sz} sect.")

if __name__ == "__main__":
    args = sys.argv[1:]
    if len(args) < 2: raise SystemExit(__doc__)
    out = args[0]; mb = 32; files = []
    i = 1
    while i < len(args):
        if args[i] == "--mb": mb = int(args[i + 1]); i += 2
        else: files.append(args[i]); i += 1
    build(out, mb, files)
