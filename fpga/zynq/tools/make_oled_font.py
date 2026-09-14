#!/usr/bin/env python3
"""
make_oled_font.py — convierte la fuente 8x8 del OSD (src/iosys/font.vh, la misma que
pinta textdisp en el HDMI) a la orientacion que quiere el SSD1306 del OLED de la placa,
y la escribe como cabecera C para el companion del ARM.

font.vh: FONT[c][fila] = 8 bytes, un byte por FILA, bit0 = columna de la IZQUIERDA.
SSD1306 (direccionamiento por paginas): cada byte escrito es una COLUMNA de 8 pixeles
verticales, bit0 = fila de ARRIBA. O sea, la traspuesta.

Salida: arm/companion/font8x8.h con los 96 caracteres imprimibles (0x20..0x7F).
Uso: python make_oled_font.py
"""
import os, re

HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.normpath(os.path.join(HERE, "..", "..", "src", "iosys", "font.vh"))
DST  = os.path.normpath(os.path.join(HERE, "..", "arm", "companion", "font8x8.h"))

rows = []
for line in open(SRC, encoding="utf-8"):
    m = re.findall(r"8'h([0-9A-Fa-f]{2})", line)
    if len(m) == 8:
        rows.append([int(x, 16) for x in m])
assert len(rows) >= 128, f"esperaba >=128 glifos en {SRC}, hay {len(rows)}"

FIRST, LAST = 0x20, 0x7F
out = []
for c in range(FIRST, LAST + 1):
    g = rows[c]
    cols = []
    for x in range(8):                       # columna x del glifo
        b = 0
        for y in range(8):                   # fila y -> bit y del byte
            if (g[y] >> x) & 1:
                b |= 1 << y
        cols.append(b)
    out.append((c, cols))

with open(DST, "w", encoding="utf-8", newline="\n") as f:
    f.write("/* font8x8.h — GENERADO por zynq/tools/make_oled_font.py desde src/iosys/font.vh.\n")
    f.write(" * NO EDITAR A MANO. Fuente 8x8 del OSD, traspuesta a columnas para el SSD1306:\n")
    f.write(" * cada byte = una columna de 8 pixeles verticales (bit0 = arriba).\n")
    f.write(f" * Caracteres 0x{FIRST:02X}..0x{LAST:02X}; FONT8X8[c - 0x{FIRST:02X}][columna]. */\n")
    f.write("#ifndef FONT8X8_H_\n#define FONT8X8_H_\n\n")
    f.write(f"#define FONT8X8_FIRST 0x{FIRST:02X}\n")
    f.write(f"#define FONT8X8_COUNT {len(out)}\n\n")
    f.write("static const unsigned char FONT8X8[FONT8X8_COUNT][8] = {\n")
    for c, cols in out:
        ch = chr(c) if 0x20 < c < 0x7F else " "
        body = ", ".join(f"0x{b:02X}" for b in cols)
        f.write(f"    {{ {body} }},   /* 0x{c:02X} {ch} */\n")
    f.write("};\n\n#endif\n")

print(f"{DST}: {len(out)} glifos (0x{FIRST:02X}..0x{LAST:02X})")
