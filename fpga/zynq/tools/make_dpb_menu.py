#!/usr/bin/env python3
"""
make_dpb_menu.py — genera zynq/gowin_dpb_menu.v (RAM de doble puerto INFERIBLE,
mismos puertos que la IP DPB de Gowin) a partir de src/iosys/gowin_dpb_menu.v,
conservando el contenido inicial (INIT_RAM_00..3F = los textos del overlay).
Geometria: 2048 x 8, READ_MODE=0 (bypass: dato al ciclo siguiente),
WRITE_MODE=00 (normal), RESET_MODE=SYNC. Bytes little-endian dentro de cada
INIT_RAM de 256 bits (byte 0 = bits [7:0]).
"""
import re, os
HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.normpath(os.path.join(HERE, "..", "..", "src", "iosys", "gowin_dpb_menu.v"))
DST  = os.path.normpath(os.path.join(HERE, "..", "gowin_dpb_menu.v"))

s = open(SRC, encoding="utf-8", errors="ignore").read()
init = {}
for m in re.finditer(r"INIT_RAM_([0-9A-F]{2})\s*=\s*256'h([0-9A-Fa-f]{64})", s):
    init[int(m.group(1), 16)] = m.group(2)
assert len(init) == 64, f"esperaba 64 INIT_RAM, hay {len(init)}"
mem = []
for k in range(64):
    h = init[k]
    for b in range(32):                       # byte 0 = los 2 hex de la derecha
        mem.append(int(h[62 - 2*b:64 - 2*b], 16))
assert len(mem) == 2048
nonzero = sum(1 for x in mem if x)

out = []
out.append("// gowin_dpb_menu.v — GENERADO por zynq/tools/make_dpb_menu.py a partir de")
out.append("// src/iosys/gowin_dpb_menu.v (IP DPB de Gowin). RAM de doble puerto 2048x8")
out.append("// inferible en Xilinx, mismos puertos y mismo contenido inicial (%d bytes != 0)." % nonzero)
out.append("// Puerto A: lectura/escritura (textdisp escribe). Puerto B: solo lectura.")
out.append("// READ_MODE=0 de Gowin = dato en el ciclo siguiente (sin registro de salida: oce sin uso).")
out.append("module gowin_dpb_menu (douta, doutb, clka, ocea, cea, reseta, wrea, clkb, oceb, ceb, resetb, wreb, ada, dina, adb, dinb);")
out.append("    output reg [7:0] douta;")
out.append("    output reg [7:0] doutb;")
out.append("    input clka, ocea, cea, reseta, wrea;")
out.append("    input clkb, oceb, ceb, resetb, wreb;")
out.append("    input [10:0] ada, adb;")
out.append("    input [7:0]  dina, dinb;")
out.append("")
out.append("    (* ram_style = \"block\" *) reg [7:0] mem [0:2047];")
out.append("    integer i;")
out.append("    initial begin")
out.append("        for (i = 0; i < 2048; i = i + 1) mem[i] = 8'h00;")
for a, v in enumerate(mem):
    if v:
        c = chr(v) if 32 <= v < 127 else "."
        out.append("        mem[%4d] = 8'h%02X;  // '%s'" % (a, v, c))
out.append("    end")
out.append("")
out.append("    always @(posedge clka) begin")
out.append("        if (cea) begin")
out.append("            if (wrea) mem[ada] <= dina;")
out.append("            if (reseta) douta <= 8'h00; else douta <= mem[ada];")
out.append("        end")
out.append("    end")
out.append("    always @(posedge clkb) begin")
out.append("        if (ceb) begin")
out.append("            if (wreb) mem[adb] <= dinb;")
out.append("            if (resetb) doutb <= 8'h00; else doutb <= mem[adb];")
out.append("        end")
out.append("    end")
out.append("endmodule")
open(DST, "w", encoding="utf-8").write("\n".join(out) + "\n")
txt = "".join(chr(x) if 32 <= x < 127 else "." for x in mem)
print(DST, "-", nonzero, "bytes con contenido")
print("texto visible:", re.sub(r"\.{3,}", " | ", txt).strip(" |"))
