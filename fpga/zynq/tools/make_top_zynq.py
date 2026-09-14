#!/usr/bin/env python3
"""
make_top_zynq.py — genera fpga/zynq/top_zynq.v a partir de fpga/top.v (Tang).

Cirugia MINIMA y reproducible (anclas de texto, no numeros de linea):
  1. defines: +ZYNQ +ENABLE_V9968_VDP +ENABLE_VRAM_AXI; -WAVE_DDR3/LOADER/OPL4_WAVE;
     -ADPCM_SDRAM (queda el fallback BSRAM).
  2. cabecera del modulo: puertos de la ZYNQ MINI; los del Tang que desaparecen
     pasan a wires internos con tie-off (la logica de pegamento NO se toca).
  3. relojes: Gowin_PLL/pll_27/pll_74/pll_86/pll_12 -> MMCM/PLLE2 (PLAN.md A).
  4. fan_ctrl + ro_osc fuera.
  5. memory_ctrl -> memory_axi (HP1 @ clk_54m).
  6. v9968_ddr3_backend -> v9968_axi_backend (HP0 @ FCLK0).
  7. cargador de flash: STATE_RESET -> STATE_IDLE (el pack lo carga el PS).
  8. /WAIT: el termino ram_busy de las lecturas tambien sin turbo.
  9. PS7 wrapper + sincronizadores de reset al final del modulo.
Uso: python make_top_zynq.py   (desde cualquier sitio; escribe ../top_zynq.v)
"""
import re, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.normpath(os.path.join(HERE, "..", "..", "top.v"))
DST  = os.path.normpath(os.path.join(HERE, "..", "top_zynq.v"))
# ZYNQ_NO_MAILBOX=1: variante de biseccion SIN el buzon de depuracion (HP2) ni
# la OR del teclado = la configuracion que arranco el 13/09 (N_HP 2 en build.tcl).
NO_MB = os.environ.get("ZYNQ_NO_MAILBOX") == "1"
# ZYNQ_NO_SD=1: sin puertos sd_* (tie-off como el 13/09). ZYNQ_MB_IDLE=1: buzon
# instanciado pero sin trafico AXI (ENABLE=0). Ambos solo para bisecar en placa.
NO_SD   = os.environ.get("ZYNQ_NO_SD") == "1"
MB_IDLE = os.environ.get("ZYNQ_MB_IDLE") == "1"

s = open(SRC, encoding="utf-8", errors="surrogateescape").read()
n_edits = 0

def rep(old, new, count=1, label=""):
    global s, n_edits
    c = s.count(old)
    assert c == count, f"[{label}] esperaba {count} ocurrencia(s) de {old[:60]!r}, hay {c}"
    s = s.replace(old, new)
    n_edits += 1

def rep_span(start_anchor, end_regex, new, label=""):
    """Sustituye desde start_anchor (inclusive) hasta la primera linea que casa
    end_regex (inclusive) por new."""
    global s, n_edits
    i = s.find(start_anchor)
    assert i >= 0 and s.count(start_anchor) == 1, f"[{label}] ancla {start_anchor[:50]!r}: {s.count(start_anchor)}"
    m = re.compile(end_regex, re.M).search(s, i + len(start_anchor))
    assert m, f"[{label}] no encuentro el fin {end_regex!r}"
    s = s[:i] + new + s[m.end():]
    n_edits += 1

# ---------------------------------------------------------------- 1. defines
rep("`define ENABLE_V9958\n",
    "// ======================================================================\n"
    "//  top_zynq.v — GENERADO por zynq/tools/make_top_zynq.py a partir de top.v\n"
    "//  NO EDITAR A MANO: los cambios van al script (o a top.v si son comunes).\n"
    "// ======================================================================\n"
    "`define ZYNQ                 // ZYNQ MINI (XC7Z020): ver zynq/PLAN.md\n"
    "`define ENABLE_V9958\n", label="cabecera")
rep("`define ENABLE_WAVE_DDR3 ", "//`define ENABLE_WAVE_DDR3 ", label="wave_ddr3")
rep("`define ENABLE_WAVE_LOADER ", "//`define ENABLE_WAVE_LOADER ", label="wave_loader")
rep("`define ENABLE_OPL4_WAVE ", "//`define ENABLE_OPL4_WAVE ", label="opl4_wave")
rep("//`define ENABLE_V9968_VDP ", "`define ENABLE_V9968_VDP ", label="v9968")
rep("//`define ENABLE_VRAM_DDR3 ", "`define ENABLE_VRAM_AXI   // Zynq: v9968_axi_backend (HP0). Era ENABLE_VRAM_DDR3 ", label="vram_axi")
# el define anidado de ADPCM_SDRAM (bajo VRAM_DDR3) NO debe activarse: queda el fallback BSRAM
rep("  `ifdef ENABLE_VRAM_DDR3\n   `define ENABLE_ADPCM_SDRAM\n  `endif\n",
    "  `ifdef ENABLE_VRAM_DDR3\n   //`define ENABLE_ADPCM_SDRAM   // Zynq: ADPCM en BRAM (FALLBACK_BSRAM=1)\n  `endif\n", label="adpcm")
# renombrar el resto de usos de ENABLE_VRAM_DDR3 -> ENABLE_VRAM_AXI, SALVO los dos
# `ifndef que dejan los pines ddr_* del SOM en reposo (aqui son wires internos y
# asi quedan conducidos)
keep = "`ifndef ENABLE_VRAM_DDR3\n    // pines DDR3 del SOM en reposo seguro"
keep2 = "`ifndef ENABLE_VRAM_DDR3\n    // DDR3 en reposo seguro"
assert s.count(keep) == 1 and s.count(keep2) == 1
s = s.replace(keep, "@@KEEP1@@").replace(keep2, "@@KEEP2@@")
s = s.replace("ENABLE_VRAM_DDR3", "ENABLE_VRAM_AXI")
s = s.replace("@@KEEP1@@", keep).replace("@@KEEP2@@", keep2)
n_edits += 1

# ---------------------------------------------------------------- 2. cabecera
rep_span("module top\n", r"^\);[ \t]*\n", '''module top_zynq
#(
    parameter SD_SLOT = 3             // (como el Tang: slot de la microSD)
)(
    // ---- ZYNQ MINI: pines dedicados ----
    input  wire        clk50,          // K17, 50 MHz (el "ex_clk_27m" del Tang)
    input  wire        key_s1_n,       // M19 (K2)
    input  wire        key_s2_n,       // M20 (K3)
    output wire [3:0]  led_z,          // W13 V12 U12 T12 (activos a 1)

    // HDMI (mismos nombres que el Tang: data_p/n, clk_p/n; H16/D19/C20/B19)
    output wire [2:0]  data_p,
    output wire [2:0]  data_n,
    output wire        clk_p,
    output wire        clk_n,
    output wire        hdmi_out_en,    // H18

    // microSD del MSXimus (sd_reader del PL, modo SD 1 bit). La placa NO tiene
    // microSD en el PL (TF1/TF2 son SD0/SD1 del PS por MIO): breakout pasivo 3V3
    // en el header CAM1, pines 31..36 (GND en 37/38, 3V3 en 39/40). PLAN.md D.
    output wire        sd_sclk,        // N18 (CAM1-34)
    inout  wire        sd_cmd,         // T20 (CAM1-33)
    inout  wire        sd_dat0,        // P20 (CAM1-35)
    output wire        sd_dat1,        // N20 (CAM1-36)
    output wire        sd_dat2,        // U20 (CAM1-31)
    output wire        sd_dat3,        // P18 (CAM1-32)

    // ---- PS7: DDR3 + MIO (pines fijos del PS, sin .xdc) ----
    inout  wire [14:0] DDR_addr,
    inout  wire [2:0]  DDR_ba,
    inout  wire        DDR_cas_n,
    inout  wire        DDR_ck_n,
    inout  wire        DDR_ck_p,
    inout  wire        DDR_cke,
    inout  wire        DDR_cs_n,
    inout  wire [1:0]  DDR_dm,
    inout  wire [15:0] DDR_dq,
    inout  wire [1:0]  DDR_dqs_n,
    inout  wire [1:0]  DDR_dqs_p,
    inout  wire        DDR_odt,
    inout  wire        DDR_ras_n,
    inout  wire        DDR_reset_n,
    inout  wire        DDR_we_n,
    inout  wire        FIXED_IO_ddr_vrn,
    inout  wire        FIXED_IO_ddr_vrp,
    inout  wire [53:0] FIXED_IO_mio,
    inout  wire        FIXED_IO_ps_clk,
    inout  wire        FIXED_IO_ps_porb,
    inout  wire        FIXED_IO_ps_srstb
);
    // ================================================================
    //  ZYNQ: los puertos del Tang que aqui no existen pasan a wires
    //  internos con tie-off. La logica que los consume NO se toca:
    //  Vivado la poda. Cuando un subsistema se conecte de verdad
    //  (USB al header, SD1, ESP32, UART del PS por EMIO) su wire se
    //  sustituye por el puerto real y su .xdc.
    // ================================================================
    wire ex_clk_27m = clk50;          // nombre historico (lleva 50 MHz tambien en el Tang)
    wire s1 = key_s1_n;
    wire s2 = key_s2_n;
    assign hdmi_out_en = 1'b1;

    // BL616 (SPI companion + UART iosys + JTAG select): no existe en la Zynq
    wire spi_sclk = 1'b0, spi_csn = 1'b1, spi_dat = 1'b0;
    wire spi_dir, spi_irqn;
    wire bl616_jtagsel;               // = RX de la UART del iosys <- UART0 del PS (EMIO): el ARM hace de BL616
    wire jtagseln, iosys_uart_tx;     // iosys_uart_tx -> UART0_RX del PS
    // ESP32-C6 (WiFi): pendiente de 3 pines del header (PLAN.md D)
    wire esp_rx_i = 1'b1;
    wire esp_tx_o, esp_turbo_o;
    // LEDs del Tang (6, activos a 0) -> 4 de la placa (activos a 1)
    wire [5:0] led;
    assign led_z = ~led[3:0];
    wire ws2812_led;
    wire [4:0] dbg_pmod1, dbg_pmod0;  // (el ILA sustituye a los PMOD)
    wire uart_pmod_rx = 1'b1;
    // Flash SPI del Tang: el pack lo carga el PS en la DDR (cargador a IDLE)
    wire mspi_cs, mspi_sclk, mspi_wp, mspi_hold;
    wire mspi_miso, mspi_mosi;
    // (microSD: puertos reales sd_* en el header, ver cabecera)
    wire usb_uart_tx;
    // USB-A x2 (soft-host en el PL): pendiente de 4 pines del header
    wire usb1_dp, usb1_dn, usb2_dp, usb2_dn;
    // SDRAM y DDR3 del Tang: no existen (memory_axi / v9968_axi_backend)
    wire O_sdram_clk, O_sdram_cke, O_sdram_cs_n, O_sdram_cas_n, O_sdram_ras_n, O_sdram_wen_n;
    wire [15:0] IO_sdram_dq;
    wire [12:0] O_sdram_addr;
    wire [1:0]  O_sdram_ba, O_sdram_dqm;
    wire [14:0] ddr_addr;
    wire [2:0]  ddr_bank;
    wire ddr_cs, ddr_ras, ddr_cas, ddr_we, ddr_ck, ddr_ck_n, ddr_cke, ddr_odt, ddr_reset_n;
    wire [1:0]  ddr_dm;
    wire [15:0] ddr_dq;
    wire [1:0]  ddr_dqs, ddr_dqs_n;
    wire fan_en_o;

    // ---- PS7: relojes/reset y los dos puertos HP (instancia al final) ----
    wire        fclk0;                // 150 MHz: aclk de la VRAM
    wire        frst0_n;              // FCLK_RESET0_N (lo suelta ps7_post_config)
    wire [5:0]  hp0_awid;   wire [31:0] hp0_awaddr;  wire [3:0] hp0_awlen;   wire [2:0] hp0_awsize;
    wire [1:0]  hp0_awburst, hp0_awlock; wire [3:0] hp0_awcache; wire [2:0] hp0_awprot; wire [3:0] hp0_awqos;
    wire        hp0_awvalid, hp0_awready;
    wire [5:0]  hp0_wid;    wire [63:0] hp0_wdata;   wire [7:0] hp0_wstrb;  wire hp0_wlast, hp0_wvalid, hp0_wready;
    wire [5:0]  hp0_bid;    wire [1:0]  hp0_bresp;   wire hp0_bvalid, hp0_bready;
    wire [5:0]  hp0_arid;   wire [31:0] hp0_araddr;  wire [3:0] hp0_arlen;   wire [2:0] hp0_arsize;
    wire [1:0]  hp0_arburst, hp0_arlock; wire [3:0] hp0_arcache; wire [2:0] hp0_arprot; wire [3:0] hp0_arqos;
    wire        hp0_arvalid, hp0_arready;
    wire [5:0]  hp0_rid;    wire [63:0] hp0_rdata;   wire [1:0] hp0_rresp;  wire hp0_rlast, hp0_rvalid, hp0_rready;
    wire [5:0]  hp1_awid;   wire [31:0] hp1_awaddr;  wire [3:0] hp1_awlen;   wire [2:0] hp1_awsize;
    wire [1:0]  hp1_awburst, hp1_awlock; wire [3:0] hp1_awcache; wire [2:0] hp1_awprot; wire [3:0] hp1_awqos;
    wire        hp1_awvalid, hp1_awready;
    wire [5:0]  hp1_wid;    wire [63:0] hp1_wdata;   wire [7:0] hp1_wstrb;  wire hp1_wlast, hp1_wvalid, hp1_wready;
    wire [5:0]  hp1_bid;    wire [1:0]  hp1_bresp;   wire hp1_bvalid, hp1_bready;
    wire [5:0]  hp1_arid;   wire [31:0] hp1_araddr;  wire [3:0] hp1_arlen;   wire [2:0] hp1_arsize;
    wire [1:0]  hp1_arburst, hp1_arlock; wire [3:0] hp1_arcache; wire [2:0] hp1_arprot; wire [3:0] hp1_arqos;
    wire        hp1_arvalid, hp1_arready;
    wire [5:0]  hp1_rid;    wire [63:0] hp1_rdata;   wire [1:0] hp1_rresp;  wire hp1_rlast, hp1_rvalid, hp1_rready;
    // HP2 = buzon de depuracion (zynq/dbg_mailbox_axi.v): teclado desde xsdb + telemetria
    wire [5:0]  hp2_awid;   wire [31:0] hp2_awaddr;  wire [3:0] hp2_awlen;   wire [2:0] hp2_awsize;
    wire [1:0]  hp2_awburst, hp2_awlock; wire [3:0] hp2_awcache; wire [2:0] hp2_awprot; wire [3:0] hp2_awqos;
    wire        hp2_awvalid, hp2_awready;
    wire [5:0]  hp2_wid;    wire [63:0] hp2_wdata;   wire [7:0] hp2_wstrb;  wire hp2_wlast, hp2_wvalid, hp2_wready;
    wire [5:0]  hp2_bid;    wire [1:0]  hp2_bresp;   wire hp2_bvalid, hp2_bready;
    wire [5:0]  hp2_arid;   wire [31:0] hp2_araddr;  wire [3:0] hp2_arlen;   wire [2:0] hp2_arsize;
    wire [1:0]  hp2_arburst, hp2_arlock; wire [3:0] hp2_arcache; wire [2:0] hp2_arprot; wire [3:0] hp2_arqos;
    wire        hp2_arvalid, hp2_arready;
    wire [5:0]  hp2_rid;    wire [63:0] hp2_rdata;   wire [1:0] hp2_rresp;  wire hp2_rlast, hp2_rvalid, hp2_rready;
    wire [127:0] kbd_mbox;            // bitmap HID leido del buzon (dominio clk_54m)
    wire [15:0] joy1_mbox, joy2_mbox; // joysticks USB del companion (formato SNES del BL616), clk_54m
    wire [7:0]  mb_mouse_btn, mb_mouse_dx, mb_mouse_dy;   // raton USB del companion: delta por informe
    wire        mb_mouse_rep;         // pulso clk_54m: nuevo informe de raton
    // HP3 = proxy de sectores "SD" (zynq/sd_axi_proxy.v) a clk_27m
    wire [5:0]  hp3_awid;   wire [31:0] hp3_awaddr;  wire [3:0] hp3_awlen;   wire [2:0] hp3_awsize;
    wire [1:0]  hp3_awburst, hp3_awlock; wire [3:0] hp3_awcache; wire [2:0] hp3_awprot; wire [3:0] hp3_awqos;
    wire        hp3_awvalid, hp3_awready;
    wire [5:0]  hp3_wid;    wire [63:0] hp3_wdata;   wire [7:0] hp3_wstrb;  wire hp3_wlast, hp3_wvalid, hp3_wready;
    wire [5:0]  hp3_bid;    wire [1:0]  hp3_bresp;   wire hp3_bvalid, hp3_bready;
    wire [5:0]  hp3_arid;   wire [31:0] hp3_araddr;  wire [3:0] hp3_arlen;   wire [2:0] hp3_arsize;
    wire [1:0]  hp3_arburst, hp3_arlock; wire [3:0] hp3_arcache; wire [2:0] hp3_arprot; wire [3:0] hp3_arqos;
    wire        hp3_arvalid, hp3_arready;
    wire [5:0]  hp3_rid;    wire [63:0] hp3_rdata;   wire [1:0] hp3_rresp;  wire hp3_rlast, hp3_rvalid, hp3_rready;
''', label="cabecera del modulo")

# ---------------------------------------------------------------- 3. relojes
rep_span("    Gowin_PLL pll_main (", r"^    \);[ \t]*\n", '''    // ---- ZYNQ MMCM_A: 50 x 27 = VCO 1350 (el mismo VCO que el PLLA del Tang) ----
    wire mA_fb, mA_fb_b, mA_108, mA_54, mA_27, mA_135, mA_375;
    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"), .CLKIN1_PERIOD(20.000), .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(27.000), .CLKFBOUT_PHASE(0.0),
        .CLKOUT0_DIVIDE_F(12.500), .CLKOUT0_DUTY_CYCLE(0.5), .CLKOUT0_PHASE(0.0),   // 108
        .CLKOUT1_DIVIDE(25),       .CLKOUT1_DUTY_CYCLE(0.5), .CLKOUT1_PHASE(0.0),   //  54
        .CLKOUT2_DIVIDE(50),       .CLKOUT2_DUTY_CYCLE(0.5), .CLKOUT2_PHASE(0.0),   //  27
        .CLKOUT3_DIVIDE(10),       .CLKOUT3_DUTY_CYCLE(0.5), .CLKOUT3_PHASE(0.0),   // 135
        .CLKOUT4_DIVIDE(36),       .CLKOUT4_DUTY_CYCLE(0.5), .CLKOUT4_PHASE(0.0),   //  37.5
        .REF_JITTER1(0.010), .STARTUP_WAIT("FALSE")
    ) pll_main (
        .CLKIN1(ex_clk_27m), .CLKFBIN(mA_fb_b), .CLKFBOUT(mA_fb), .CLKFBOUTB(),
        .CLKOUT0(mA_108), .CLKOUT0B(), .CLKOUT1(mA_54), .CLKOUT1B(),
        .CLKOUT2(mA_27),  .CLKOUT2B(), .CLKOUT3(mA_135), .CLKOUT3B(),
        .CLKOUT4(mA_375), .CLKOUT5(), .CLKOUT6(),
        .LOCKED(clock_locked), .PWRDWN(1'b0), .RST(1'b0)
    );
    BUFG bA_fb  (.I(mA_fb),  .O(mA_fb_b));
    BUFG bA_108 (.I(mA_108), .O(clk_108m));
    BUFG bA_54  (.I(mA_54),  .O(clk_54m));
    BUFG bA_27  (.I(mA_27),  .O(clk_27m));
    BUFG bA_135 (.I(mA_135), .O(clk_135));
    BUFG bA_375 (.I(mA_375), .O(clk_wave375));
''', label="pll_main")
rep_span("    pll_27 pll27_video (", r"^    \);[ \t]*\n", '''    // ---- ZYNQ: clk27_video = el 27 de MMCM_A (el Tang usaba un PLL aparte) ----
    assign clk27_video = clk_27m;
    assign pll27_lock  = clock_locked;
''', label="pll_27")
rep_span("    pll_74 pll74_video (", r"^    \);[ \t]*\n", '''    // ---- ZYNQ MMCM_C: 27 x 27.5 = VCO 742.5 -> /10 = 74.25 ; /2 = 371.25 (validado en bringup/hdmi720) ----
    wire mC_fb, mC_fb_b, mC_74, mC_371, mC_lock;
    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"), .CLKIN1_PERIOD(37.037), .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(27.500), .CLKFBOUT_PHASE(0.0),
        .CLKOUT0_DIVIDE_F(2.000), .CLKOUT0_DUTY_CYCLE(0.5), .CLKOUT0_PHASE(0.0),   // 371.25
        .CLKOUT1_DIVIDE(10),      .CLKOUT1_DUTY_CYCLE(0.5), .CLKOUT1_PHASE(0.0),   //  74.25
        .REF_JITTER1(0.010), .STARTUP_WAIT("FALSE")
    ) pll74_video (
        .CLKIN1(clk27_video), .CLKFBIN(mC_fb_b), .CLKFBOUT(mC_fb), .CLKFBOUTB(),
        .CLKOUT0(mC_371), .CLKOUT0B(), .CLKOUT1(mC_74), .CLKOUT1B(),
        .CLKOUT2(), .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .LOCKED(mC_lock), .PWRDWN(1'b0), .RST(~clock_locked)
    );
    BUFG bC_fb  (.I(mC_fb),  .O(mC_fb_b));
    BUFG bC_74  (.I(mC_74),  .O(clk_hdmi));
    BUFG bC_371 (.I(mC_371), .O(clk_hdmi5));
''', label="pll_74")
rep("    pll_86 pll86_vdp ( .clkout0(clk_86), .lock(pll86_lock), .clkin(clk27_video) );\n",
'''    // ---- ZYNQ PLLE2_D: 27 x 35 = VCO 945 -> /11 = 85.909 (V9968) ----
    wire pD_fb, pD_fb_b, pD_86;
    PLLE2_BASE #(
        .BANDWIDTH("OPTIMIZED"), .CLKIN1_PERIOD(37.037), .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT(35), .CLKFBOUT_PHASE(0.0),
        .CLKOUT0_DIVIDE(11), .CLKOUT0_DUTY_CYCLE(0.5), .CLKOUT0_PHASE(0.0),
        .REF_JITTER1(0.010), .STARTUP_WAIT("FALSE")
    ) pll86_vdp (
        .CLKIN1(clk27_video), .CLKFBIN(pD_fb_b), .CLKFBOUT(pD_fb),
        .CLKOUT0(pD_86), .CLKOUT1(), .CLKOUT2(), .CLKOUT3(), .CLKOUT4(), .CLKOUT5(),
        .LOCKED(pll86_lock), .PWRDWN(1'b0), .RST(~clock_locked)
    );
    BUFG bD_fb (.I(pD_fb), .O(pD_fb_b));
    BUFG bD_86 (.I(pD_86), .O(clk_86));
''', label="pll_86")
rep_span("    pll_12 pll12_usb (", r"^    \);[ \t]*\n", '''    // ---- ZYNQ PLLE2_E: 50 x 24 = VCO 1200 -> /100 = 12 (usb_hid_host) ----
    wire pE_fb, pE_fb_b, pE_12;
    PLLE2_BASE #(
        .BANDWIDTH("OPTIMIZED"), .CLKIN1_PERIOD(20.000), .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT(24), .CLKFBOUT_PHASE(0.0),
        .CLKOUT0_DIVIDE(100), .CLKOUT0_DUTY_CYCLE(0.5), .CLKOUT0_PHASE(0.0),
        .REF_JITTER1(0.010), .STARTUP_WAIT("FALSE")
    ) pll12_usb (
        .CLKIN1(ex_clk_27m), .CLKFBIN(pE_fb_b), .CLKFBOUT(pE_fb),
        .CLKOUT0(pE_12), .CLKOUT1(), .CLKOUT2(), .CLKOUT3(), .CLKOUT4(), .CLKOUT5(),
        .LOCKED(pll12_lock), .PWRDWN(1'b0), .RST(1'b0)
    );
    BUFG bE_fb (.I(pE_fb), .O(pE_fb_b));
    BUFG bE_12 (.I(pE_12), .O(clk_usb12));
''', label="pll_12")

# ---------------------------------------------------------------- 4. fan + ro_osc
rep_span("    fan_ctrl #(.WIN_CYC(32'd262144)", r"^    \);[ \t]*\n",
         "    // ZYNQ: sin ventilador (fan_ctrl + ro_osc fuera)\n    assign fan_en_ctrl = 1'b0;\n    assign fan_dbg_cnt = 20'd0;\n    assign fan_ro_en = 1'b0; assign fan_ro_rst = 1'b0;\n", label="fan_ctrl")
rep_span("    ro_osc u_roosc (", r"^    \);[ \t]*\n", "    assign fan_ro_cnt = 20'd0;\n", label="ro_osc")

# ---------------------------------------------------------------- 5. memory_ctrl -> memory_axi
rep_span("memory_ctrl #(.SDCLK_INVERT(1'b1)) mem1 (", r"^\);[ \t]*\n", '''// ==== ZYNQ: la RAM del Z80 en la DDR del PS (zynq/memory_axi.v, HP1 @ clk_54m) ====
// Mismo contrato ram_* que memory_ctrl. vram_*/wv*/rfsh no existen aqui (V9968 con
// VRAM en AXI; ADPCM en BRAM; sin wave; el refresco lo hace el DDRC).
wire [31:0] mem_dbg_hits, mem_dbg_miss, mem_dbg_state;
reg  [1:0]  rst54_s = 2'b00;
always @(posedge clk_54m) rst54_s <= {rst54_s[0], frst0_n};
wire        rst54_n = rst54_s[1];
memory_axi #(.RAM_BASE(32'h1080_0000), .LINES_LOG(12)) mem1 (
    .clk_54m(clk_54m), .bus_reset_n(bus_reset_n),
    .video_dhclk(VideoDHClk), .video_dlclk(VideoDLClk), .cpu_run(cpu_run_r),
    .ram_din(ram_din), .ram_req(ram_req), .ram_write(ram_write), .ram_addr(ram_addr),
    .ram_dout(ram_dout), .ram_busy(ram_busy),
    .dbg_hits(mem_dbg_hits), .dbg_miss(mem_dbg_miss), .dbg_state(mem_dbg_state), .ready(),
    .aresetn(rst54_n),
    .M_AWID(hp1_awid), .M_AWADDR(hp1_awaddr), .M_AWLEN(hp1_awlen), .M_AWSIZE(hp1_awsize),
    .M_AWBURST(hp1_awburst), .M_AWLOCK(hp1_awlock), .M_AWCACHE(hp1_awcache), .M_AWPROT(hp1_awprot),
    .M_AWQOS(hp1_awqos), .M_AWVALID(hp1_awvalid), .M_AWREADY(hp1_awready),
    .M_WID(hp1_wid), .M_WDATA(hp1_wdata), .M_WSTRB(hp1_wstrb), .M_WLAST(hp1_wlast),
    .M_WVALID(hp1_wvalid), .M_WREADY(hp1_wready),
    .M_BID(hp1_bid), .M_BRESP(hp1_bresp), .M_BVALID(hp1_bvalid), .M_BREADY(hp1_bready),
    .M_ARID(hp1_arid), .M_ARADDR(hp1_araddr), .M_ARLEN(hp1_arlen), .M_ARSIZE(hp1_arsize),
    .M_ARBURST(hp1_arburst), .M_ARLOCK(hp1_arlock), .M_ARCACHE(hp1_arcache), .M_ARPROT(hp1_arprot),
    .M_ARQOS(hp1_arqos), .M_ARVALID(hp1_arvalid), .M_ARREADY(hp1_arready),
    .M_RID(hp1_rid), .M_RDATA(hp1_rdata), .M_RRESP(hp1_rresp), .M_RLAST(hp1_rlast),
    .M_RVALID(hp1_rvalid), .M_RREADY(hp1_rready)
);
// puertos de memory_ctrl que aqui no existen: en reposo
assign VrmDbi2 = 16'd0;
assign wv_dout = 16'd0;  assign wv_done = 1'b0;
assign wv2_dout = 16'd0; assign wv2_done = 1'b0;
assign wv3_dout = 16'd0; assign wv3_done = 1'b0;
assign O_sdram_clk = 1'b0; assign O_sdram_cke = 1'b0; assign O_sdram_cs_n = 1'b1;
assign O_sdram_cas_n = 1'b1; assign O_sdram_ras_n = 1'b1; assign O_sdram_wen_n = 1'b1;
assign O_sdram_addr = 13'd0; assign O_sdram_ba = 2'd0; assign O_sdram_dqm = 2'b11;
''', label="memory_ctrl")

# ---------------------------------------------------------------- 6. v9968_ddr3_backend -> axi
rep_span("    v9968_ddr3_backend u_vddr3 (", r"^    \);[ \t]*\n", '''    // ==== ZYNQ: la VRAM del V9968 en la DDR del PS (zynq/v9968_axi_backend.v, HP0 @ FCLK0) ====
    // Misma interfaz que v9968_ddr3_backend; los bridges se conectan tal cual.
    reg [1:0] rst150_s = 2'b00;
    always @(posedge fclk0) rst150_s <= {rst150_s[0], frst0_n};
    v9968_axi_backend #(.VRAM_BASE(32'h1000_0000)) u_vddr3 (
        .a_req(vddr_a_req), .a_we(vddr_a_we), .a_addr(vddr_a_addr),
        .a_wdata(vddr_a_wdata), .a_wmask(vddr_a_wmask),
        .a_dout(vddr_a_dout), .a_done(vddr_a_done),
        .b_req(vddr_b_req), .b_addr(vddr_b_addr),
        .b_dout(vddr_b_dout), .b_done(vddr_b_done),
        .clk_x1_out(vddr_clk_x1), .ready(vddr_ready), .diag(vddr_diag),
        .dbg_ops(vddr_ops),
        .recal_req(1'b0),
        .aclk(fclk0), .aresetn(rst150_s[1]),
        .M_AWID(hp0_awid), .M_AWADDR(hp0_awaddr), .M_AWLEN(hp0_awlen), .M_AWSIZE(hp0_awsize),
        .M_AWBURST(hp0_awburst), .M_AWLOCK(hp0_awlock), .M_AWCACHE(hp0_awcache), .M_AWPROT(hp0_awprot),
        .M_AWQOS(hp0_awqos), .M_AWVALID(hp0_awvalid), .M_AWREADY(hp0_awready),
        .M_WID(hp0_wid), .M_WDATA(hp0_wdata), .M_WSTRB(hp0_wstrb), .M_WLAST(hp0_wlast),
        .M_WVALID(hp0_wvalid), .M_WREADY(hp0_wready),
        .M_BID(hp0_bid), .M_BRESP(hp0_bresp), .M_BVALID(hp0_bvalid), .M_BREADY(hp0_bready),
        .M_ARID(hp0_arid), .M_ARADDR(hp0_araddr), .M_ARLEN(hp0_arlen), .M_ARSIZE(hp0_arsize),
        .M_ARBURST(hp0_arburst), .M_ARLOCK(hp0_arlock), .M_ARCACHE(hp0_arcache), .M_ARPROT(hp0_arprot),
        .M_ARQOS(hp0_arqos), .M_ARVALID(hp0_arvalid), .M_ARREADY(hp0_arready),
        .M_RID(hp0_rid), .M_RDATA(hp0_rdata), .M_RRESP(hp0_rresp), .M_RLAST(hp0_rlast),
        .M_RVALID(hp0_rvalid), .M_RREADY(hp0_rready)
    );
''', label="v9968_ddr3_backend")

# ---------------------------------------------------------------- 6b. contadores con asignacion mixta
# Idioma OCM: `cnt = cnt + 1` (bloqueante, el casex ve cnt+1) y `cnt <= 0` (no
# bloqueante) en las ramas. Gowin lo sintetiza como se pretende; Vivado avisa
# (Synth 8-6090 "entire logic could be removed"). Forma EQUIVALENTE sin mezcla:
# cnt_n = cnt+1 para el casex, `cnt <= cnt_n` por defecto, y los `cnt <= 0` de
# las ramas (posteriores) siguen ganando. Valor final identico en ambos casos.
rep("""            counter_demux = counter_demux + 4'd1;
            casex ({state_demux, counter_demux})""",
"""            counter_demux_n = counter_demux + 4'd1;   // ZYNQ: sin asignacion mixta
            counter_demux <= counter_demux_n;
            casex ({state_demux, counter_demux_n})""", label="counter_demux")
rep("""            counter_iso = counter_iso + 3'd1;
            casex ({state_iso, counter_iso})""",
"""            counter_iso_n = counter_iso + 3'd1;       // ZYNQ: sin asignacion mixta
            counter_iso <= counter_iso_n;
            casex ({state_iso, counter_iso_n})""", label="counter_iso")
# declaraciones de los *_n junto a las de los contadores
rep("reg [3:0] counter_demux", "reg [3:0] counter_demux_n;\n    reg [3:0] counter_demux", label="decl counter_demux")
rep("reg [2:0] counter_iso", "reg [2:0] counter_iso_n;\n    reg [2:0] counter_iso", label="decl counter_iso")

# ---------------------------------------------------------------- 7. flash: cargador a IDLE
rep("""            STATE_RESET: begin   // reset
                ff_flash_state <= STATE_READ_START;
                ff_flash_rd <= 0;
                ff_rom_wr <= 0;""",
"""            STATE_RESET: begin   // reset
`ifdef ZYNQ
                ff_flash_state <= STATE_IDLE;    // ZYNQ: el pack lo carga el PS en la DDR
`else
                ff_flash_state <= STATE_READ_START;
`endif
                ff_flash_rd <= 0;
                ff_rom_wr <= 0;""", label="flash reset (cargador de arranque)")

# ---------------------------------------------------------------- 8. /WAIT con ram_busy sin turbo
rep("""                    if ( ram_write == 1 || (turbo_eff == 1 && bus_mreq_n == 0 && bus_rd_n == 0 && ram_busy == 1) || (ex_bus_iorq_n == 0)&& (bus_rd_n == 0 || bus_wr_n == 0) ) begin  // P2: sin Compatible Mode (= v1.9 nano)""",
"""`ifdef ZYNQ
                    // ZYNQ: un fallo de cache de memory_axi tarda mas que un T-state
                    // tambien a 3,58: el termino ram_busy de las lecturas SIEMPRE
                    if ( ram_write == 1 || (bus_mreq_n == 0 && bus_rd_n == 0 && ram_busy == 1) || (ex_bus_iorq_n == 0)&& (bus_rd_n == 0 || bus_wr_n == 0) ) begin
`else
                    if ( ram_write == 1 || (turbo_eff == 1 && bus_mreq_n == 0 && bus_rd_n == 0 && ram_busy == 1) || (ex_bus_iorq_n == 0)&& (bus_rd_n == 0 || bus_wr_n == 0) ) begin  // P2: sin Compatible Mode (= v1.9 nano)
`endif""", label="wait idle")
rep("""                    if ( (turbo_eff ? clk_falling_5m4_54 : clk_falling_3m6_54) == 1 && (turbo_eff == 0 || ram_busy == 0) ) begin
`endif
                        wait_io_ff <= 1;""",
"""                    if ( (turbo_eff ? clk_falling_5m4_54 : clk_falling_3m6_54) == 1 && (
`ifdef ZYNQ
                         ram_busy == 0
`else
                         turbo_eff == 0 || ram_busy == 0
`endif
                         ) ) begin
`endif
                        wait_io_ff <= 1;""", label="wait state2")

# ---------------------------------------------------------------- 8a. sd_reader -> proxy de sectores (HP3)
# La placa no tiene microSD en el PL (TF1/TF2 cuelgan del PS). sd_axi_proxy clona
# la interfaz de sd_reader: MODE 0 = imagen de disco en la DDR (xsdb), MODE 1 =
# el ARM sirve la tarjeta real (peticion en SDBOX + IRQ_F2P). Ver el .v.
rep_span("    sd_reader #(\n        .CLK_DIV(3'd2),", r"^    \);[ \t]*\n", '''    // ==== ZYNQ: proxy de sectores (zynq/sd_axi_proxy.v, HP3 @ clk_27m) en lugar de sd_reader ====
    // Misma interfaz de cliente. MODE 0: imagen de disco en la DDR cargada por xsdb
    // (tools/boot.tcl <pack> <bit> <img>). MODE 1: el ARM sirve la tarjeta real
    // (TF1/TF2) por el buzon SDBOX + IRQ_F2P. Los pines sd_* del header quedan en
    // reposo hasta que haya un breakout (entonces, sd_reader de nuevo).
    assign sd_sclk = 1'b1;
    reg  [1:0] rst27_s = 2'b00;
    always @(posedge clk_27m) rst27_s <= {rst27_s[0], frst0_n};
    wire [15:0] sd_ram_blocks;
    wire        sd_irq, sd_mode;
    sd_axi_proxy #(.DISK_BASE(32'h1100_0000), .DISK_MB(32'd224),
                   .SDBOX(32'h1FF0_0100), .SDBUF(32'h1FF1_0000)) sd1 (
        .rstn(bus_reset_n), .clk(clk_27m),
        .card_stat(sd_card_stat_w), .card_type(sd_card_type_w),
        .rstart(ff_sd_rstart), .rsector(ff_sd_sector), .rbusy(sd_busy_w), .rdone(sd_done_w),
        .outen(sd_outen_w), .outaddr(sd_outaddr_w), .outbyte(sd_outbyte_w),
        .wstart(ff_sd_wstart), .inbyte(sd_inbyte_w),
        .c_size(sd_c_size_w), .c_size_mult(sd_c_size_mult_w), .read_bl_len(sd_read_bl_len_w),
        .mid(sd_mid_w), .oid(sd_oid_w), .pnm(sd_pnm_w), .psn(sd_psn_w),
        .crc_error(sd_crc_error_w), .rcrc_error(sd_rcrc_error_w), .timeout_error(sd_timeout_error_w),
        .init(ff_sd_init), .rcount(sdio_count), .buf_ack(sdio_ack | dma_ack), .blk_rdy(sd_blk_rdy_w),
        .req_irq(sd_irq), .mode(sd_mode), .dbg_blocks(sd_ram_blocks),
        .aresetn(rst27_s[1]),
        .M_AWID(hp3_awid), .M_AWADDR(hp3_awaddr), .M_AWLEN(hp3_awlen), .M_AWSIZE(hp3_awsize),
        .M_AWBURST(hp3_awburst), .M_AWLOCK(hp3_awlock), .M_AWCACHE(hp3_awcache), .M_AWPROT(hp3_awprot),
        .M_AWQOS(hp3_awqos), .M_AWVALID(hp3_awvalid), .M_AWREADY(hp3_awready),
        .M_WID(hp3_wid), .M_WDATA(hp3_wdata), .M_WSTRB(hp3_wstrb), .M_WLAST(hp3_wlast),
        .M_WVALID(hp3_wvalid), .M_WREADY(hp3_wready),
        .M_BID(hp3_bid), .M_BRESP(hp3_bresp), .M_BVALID(hp3_bvalid), .M_BREADY(hp3_bready),
        .M_ARID(hp3_arid), .M_ARADDR(hp3_araddr), .M_ARLEN(hp3_arlen), .M_ARSIZE(hp3_arsize),
        .M_ARBURST(hp3_arburst), .M_ARLOCK(hp3_arlock), .M_ARCACHE(hp3_arcache), .M_ARPROT(hp3_arprot),
        .M_ARQOS(hp3_arqos), .M_ARVALID(hp3_arvalid), .M_ARREADY(hp3_arready),
        .M_RID(hp3_rid), .M_RDATA(hp3_rdata), .M_RRESP(hp3_rresp), .M_RLAST(hp3_rlast),
        .M_RVALID(hp3_rvalid), .M_RREADY(hp3_rready)
    );
''', label="sd_reader -> sd_axi_proxy")

# ---------------------------------------------------------------- 8b. teclado inyectado desde xsdb
# La matriz `keyboard` (bitmap HID, pulsado=1) es la OR de los dos USB; aqui se le
# suma el buzon de la DDR (dbg_mailbox_axi, clk_54m) con el mismo cruce 2FF a 27M.
if not NO_MB: rep("    assign keyboard = kbd_usb_s2;\n",
"""    // ZYNQ: + teclado inyectado desde xsdb (zynq/dbg_mailbox_axi.v, tools/key.tcl)
    reg [127:0] kbd_mbox_s1 = 128'd0, kbd_mbox_s2 = 128'd0;
    always @(posedge clk_27m) begin
        kbd_mbox_s1 <= kbd_mbox;
        kbd_mbox_s2 <= kbd_mbox_s1;
    end
    assign keyboard = kbd_usb_s2 | kbd_mbox_s2;
""", label="teclado buzon")

# ---------------------------------------------------------------- 8c. joysticks y raton USB del companion
# El ARM (arm/companion, TinyUSB host en el USB-C P3) deja en el buzon los mandos en
# el mismo formato SNES que el BL616 (MBOX+0x10) y el raton como acumulados
# (MBOX+0x14/+0x18); el buzon saca joy1/joy2 y pulso+delta de raton (clk_54m).
# Los mandos se OR-ean con los del BL616 (cruce 2FF a clk_27m, son cuasi-estaticos);
# el raton entra en msx_mouse (ya en clk_54m) multiplexado con el de usb_hid_host.
if not NO_MB:
    rep("    wire [15:0] mcu_hid1, mcu_hid2;\n",
"""    wire [15:0] mcu_hid1_u, mcu_hid2_u;                 // del BL616 (iosys)
    reg  [15:0] joy1_mb_s1 = 16'd0, joy1_mb_s2 = 16'd0;  // ZYNQ: del companion (buzon, clk_54m -> clk_27m)
    reg  [15:0] joy2_mb_s1 = 16'd0, joy2_mb_s2 = 16'd0;
    always @(posedge clk_27m) begin
        joy1_mb_s1 <= joy1_mbox; joy1_mb_s2 <= joy1_mb_s1;
        joy2_mb_s1 <= joy2_mbox; joy2_mb_s2 <= joy2_mb_s1;
    end
    wire [15:0] mcu_hid1 = mcu_hid1_u | joy1_mb_s2;
    wire [15:0] mcu_hid2 = mcu_hid2_u | joy2_mb_s2;
""", label="joy buzon: wires")
    rep("        .hid1           (mcu_hid1),\n        .hid2           (mcu_hid2),\n",
        "        .hid1           (mcu_hid1_u),\n        .hid2           (mcu_hid2_u),\n", label="joy buzon: iosys")
    rep("    assign msx_mouse_present = mo_seen_s1;\n",
"""    // ZYNQ: raton del companion (buzon). Mismo dominio (clk_54m) que msx_mouse.
    reg       mb_mouse_seen = 1'b0;
    reg [7:0] mb_rep_cnt = 8'd0;                      // telemetria: informes recibidos del buzon
    reg [1:0] mb_btn_q = 2'b00;                       // botones: NIVEL (msx_mouse los saca por combinacional)
    always @(posedge clk_54m) if (mb_mouse_rep) begin
        mb_mouse_seen <= 1'b1; mb_rep_cnt <= mb_rep_cnt + 8'd1; mb_btn_q <= mb_mouse_btn[1:0];
    end
    wire [11:0] mm_cur_x;                             // telemetria: interior de msx_mouse
    wire [7:0]  mm_rel_x;
    reg  [3:0]  mm_strobe_cnt = 4'd0;                 // flancos del strobe (pin 8 del puerto 2) vistos a clk_54m
    reg         mm_strobe_d = 1'b1;
    always @(posedge clk_54m) begin
        mm_strobe_d <= psgPB[5];
        if (psgPB[5] != mm_strobe_d) mm_strobe_cnt <= mm_strobe_cnt + 4'd1;
    end
    // telemetria: ultimos 3 valores escritos en el registro 15 del PSG + cuenta (quien toca el strobe)
    wire        r15_wr = (bus_addr[7:0] == 8'hA1 && bus_iorq_n == 1'b0 && bus_wr_n == 1'b0 && bus_m1_n == 1'b1
                          && psg_addr_latch == 4'd15);
    reg         r15_wr_d = 1'b0;
    reg  [23:0] r15_hist = 24'd0;
    reg  [7:0]  r15_cnt = 8'd0;
    always @(posedge clk_54m) begin
        r15_wr_d <= r15_wr;
        if (r15_wr && !r15_wr_d) begin r15_hist <= {r15_hist[15:0], cpu_dout}; r15_cnt <= r15_cnt + 8'd1; end
    end
    assign msx_mouse_present = mo_seen_s1 | mb_mouse_seen;
""", label="raton buzon: present")
    rep("""        .rep_pulse (mo_rep_54),
        .dx        (mo_dx_q),
        .dy        (mo_dy_q),
        .btn       ({mo_btn_q[1], mo_btn_q[0]}),   // {derecho, izquierdo}
""",
"""        .rep_pulse (mo_rep_54 | mb_mouse_rep),                              // ZYNQ: + raton del companion
        .dx        (mb_mouse_rep ? mb_mouse_dx : mo_dx_q),
        .dy        (mb_mouse_rep ? mb_mouse_dy : mo_dy_q),
        .btn       ({mo_btn_q[1] | mb_btn_q[1], mo_btn_q[0] | mb_btn_q[0]}),   // {derecho, izquierdo}: nivel, OR de los dos ratones
        .dbg_cur_x (mm_cur_x),
        .dbg_rel_x (mm_rel_x),
""", label="raton buzon: msx_mouse")

# ---------------------------------------------------------------- 9. PS7 al final
assert s.rstrip().endswith("endmodule"), "top.v no termina en endmodule"
s = s.rstrip()[:-len("endmodule")]
n_edits += 1
s += '''
    // ================================================================
    //  ZYNQ: buzon de depuracion en la DDR (HP2 @ clk_54m). Desde xsdb:
    //  teclado (bitmap HID en MBOX+0) y telemetria (MBOX+0x40..0x5F).
    //  tools/key.tcl pulsa teclas; tools/tel.tcl lee la telemetria.
    // ================================================================
    dbg_mailbox_axi #(.MBOX(32'h1FF0_0000), .PERIOD(54000)) u_mbox (
        .clk(clk_54m), .aresetn(rst54_n),
        .kbd_mbox(kbd_mbox),
        .joy1(joy1_mbox), .joy2(joy2_mbox),
        .mouse_btn(mb_mouse_btn), .mouse_dx(mb_mouse_dx), .mouse_dy(mb_mouse_dy), .mouse_rep(mb_mouse_rep),
        .tel_hits(mem_dbg_hits), .tel_miss(mem_dbg_miss),
        .tel_status({vddr_ops[15:0], sd_mode, sd_irq, sd_busy_w, sd_blk_rdy_w, ff_sd_rstart, ff_sd_wstart,
                     clock_locked, vddr_ready, iosys_frz, cpu_run_r, sd_card_type_w, sd_card_stat_w}),
        .tel_dbg(mem_dbg_state),
        .tel_dbg2({sd_ram_blocks, sdio_count, sd_timeout_error_w, sd_crc_error_w, sd_rcrc_error_w, ff_sd_init, sd_card_stat_w}),
        // +0x60: raton y mandos (buzon HID): {present, port2, strobe, phase[2:0], 2'b0}, dx, dy, informes | data, joy0, joy1, 0
        .tel_dbg3({msx_mouse_present, psg_reg15_port2, psgPB[5], msx_mouse_phase, 2'b00, mb_mouse_dx, mb_mouse_dy, mb_rep_cnt}),
        .tel_dbg4({r15_hist, r15_cnt}),
        .M_AWID(hp2_awid), .M_AWADDR(hp2_awaddr), .M_AWLEN(hp2_awlen), .M_AWSIZE(hp2_awsize),
        .M_AWBURST(hp2_awburst), .M_AWLOCK(hp2_awlock), .M_AWCACHE(hp2_awcache), .M_AWPROT(hp2_awprot),
        .M_AWQOS(hp2_awqos), .M_AWVALID(hp2_awvalid), .M_AWREADY(hp2_awready),
        .M_WID(hp2_wid), .M_WDATA(hp2_wdata), .M_WSTRB(hp2_wstrb), .M_WLAST(hp2_wlast),
        .M_WVALID(hp2_wvalid), .M_WREADY(hp2_wready),
        .M_BID(hp2_bid), .M_BRESP(hp2_bresp), .M_BVALID(hp2_bvalid), .M_BREADY(hp2_bready),
        .M_ARID(hp2_arid), .M_ARADDR(hp2_araddr), .M_ARLEN(hp2_arlen), .M_ARSIZE(hp2_arsize),
        .M_ARBURST(hp2_arburst), .M_ARLOCK(hp2_arlock), .M_ARCACHE(hp2_arcache), .M_ARPROT(hp2_arprot),
        .M_ARQOS(hp2_arqos), .M_ARVALID(hp2_arvalid), .M_ARREADY(hp2_arready),
        .M_RID(hp2_rid), .M_RDATA(hp2_rdata), .M_RRESP(hp2_rresp), .M_RLAST(hp2_rlast),
        .M_RVALID(hp2_rvalid), .M_RREADY(hp2_rready)
    );

    // ================================================================
    //  ZYNQ: PS7 (DDR3 + MIO + FCLK0 + HP0..HP3). Block design: zynq/bd_ps7.tcl
    //  HP0 = VRAM (v9968_axi_backend) a FCLK0 = 150 MHz
    //  HP1 = RAM del Z80 (memory_axi) a clk_54m
    //  HP2 = buzon xsdb (dbg_mailbox_axi) a clk_54m
    //  HP3 = proxy de sectores "SD" (sd_axi_proxy) a clk_27m; su req_irq -> IRQ_F2P[0]
    // ================================================================
    ps7_bd_wrapper ps7 (
        .DDR_addr(DDR_addr), .DDR_ba(DDR_ba), .DDR_cas_n(DDR_cas_n), .DDR_ck_n(DDR_ck_n),
        .DDR_ck_p(DDR_ck_p), .DDR_cke(DDR_cke), .DDR_cs_n(DDR_cs_n), .DDR_dm(DDR_dm),
        .DDR_dq(DDR_dq), .DDR_dqs_n(DDR_dqs_n), .DDR_dqs_p(DDR_dqs_p), .DDR_odt(DDR_odt),
        .DDR_ras_n(DDR_ras_n), .DDR_reset_n(DDR_reset_n), .DDR_we_n(DDR_we_n),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn), .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio(FIXED_IO_mio), .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb), .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        .FCLK_CLK0(fclk0), .FCLK_RESET0_N(frst0_n), .IRQ_F2P(sd_irq),
        .UART0_TX(bl616_jtagsel), .UART0_RX(iosys_uart_tx),     // el ARM habla con iosys_bl616 (OSD)
        .HP0_ACLK(fclk0), .HP1_ACLK(clk_54m), .HP2_ACLK(clk_54m), .HP3_ACLK(clk_27m),
        .S_AXI_HP0_awid(hp0_awid), .S_AXI_HP0_awaddr(hp0_awaddr), .S_AXI_HP0_awlen(hp0_awlen),
        .S_AXI_HP0_awsize(hp0_awsize), .S_AXI_HP0_awburst(hp0_awburst), .S_AXI_HP0_awlock(hp0_awlock),
        .S_AXI_HP0_awcache(hp0_awcache), .S_AXI_HP0_awprot(hp0_awprot), .S_AXI_HP0_awqos(hp0_awqos),
        .S_AXI_HP0_awvalid(hp0_awvalid), .S_AXI_HP0_awready(hp0_awready),
        .S_AXI_HP0_wid(hp0_wid), .S_AXI_HP0_wdata(hp0_wdata), .S_AXI_HP0_wstrb(hp0_wstrb),
        .S_AXI_HP0_wlast(hp0_wlast), .S_AXI_HP0_wvalid(hp0_wvalid), .S_AXI_HP0_wready(hp0_wready),
        .S_AXI_HP0_bid(hp0_bid), .S_AXI_HP0_bresp(hp0_bresp), .S_AXI_HP0_bvalid(hp0_bvalid), .S_AXI_HP0_bready(hp0_bready),
        .S_AXI_HP0_arid(hp0_arid), .S_AXI_HP0_araddr(hp0_araddr), .S_AXI_HP0_arlen(hp0_arlen),
        .S_AXI_HP0_arsize(hp0_arsize), .S_AXI_HP0_arburst(hp0_arburst), .S_AXI_HP0_arlock(hp0_arlock),
        .S_AXI_HP0_arcache(hp0_arcache), .S_AXI_HP0_arprot(hp0_arprot), .S_AXI_HP0_arqos(hp0_arqos),
        .S_AXI_HP0_arvalid(hp0_arvalid), .S_AXI_HP0_arready(hp0_arready),
        .S_AXI_HP0_rid(hp0_rid), .S_AXI_HP0_rdata(hp0_rdata), .S_AXI_HP0_rresp(hp0_rresp),
        .S_AXI_HP0_rlast(hp0_rlast), .S_AXI_HP0_rvalid(hp0_rvalid), .S_AXI_HP0_rready(hp0_rready),
        .S_AXI_HP1_awid(hp1_awid), .S_AXI_HP1_awaddr(hp1_awaddr), .S_AXI_HP1_awlen(hp1_awlen),
        .S_AXI_HP1_awsize(hp1_awsize), .S_AXI_HP1_awburst(hp1_awburst), .S_AXI_HP1_awlock(hp1_awlock),
        .S_AXI_HP1_awcache(hp1_awcache), .S_AXI_HP1_awprot(hp1_awprot), .S_AXI_HP1_awqos(hp1_awqos),
        .S_AXI_HP1_awvalid(hp1_awvalid), .S_AXI_HP1_awready(hp1_awready),
        .S_AXI_HP1_wid(hp1_wid), .S_AXI_HP1_wdata(hp1_wdata), .S_AXI_HP1_wstrb(hp1_wstrb),
        .S_AXI_HP1_wlast(hp1_wlast), .S_AXI_HP1_wvalid(hp1_wvalid), .S_AXI_HP1_wready(hp1_wready),
        .S_AXI_HP1_bid(hp1_bid), .S_AXI_HP1_bresp(hp1_bresp), .S_AXI_HP1_bvalid(hp1_bvalid), .S_AXI_HP1_bready(hp1_bready),
        .S_AXI_HP1_arid(hp1_arid), .S_AXI_HP1_araddr(hp1_araddr), .S_AXI_HP1_arlen(hp1_arlen),
        .S_AXI_HP1_arsize(hp1_arsize), .S_AXI_HP1_arburst(hp1_arburst), .S_AXI_HP1_arlock(hp1_arlock),
        .S_AXI_HP1_arcache(hp1_arcache), .S_AXI_HP1_arprot(hp1_arprot), .S_AXI_HP1_arqos(hp1_arqos),
        .S_AXI_HP1_arvalid(hp1_arvalid), .S_AXI_HP1_arready(hp1_arready),
        .S_AXI_HP1_rid(hp1_rid), .S_AXI_HP1_rdata(hp1_rdata), .S_AXI_HP1_rresp(hp1_rresp),
        .S_AXI_HP1_rlast(hp1_rlast), .S_AXI_HP1_rvalid(hp1_rvalid), .S_AXI_HP1_rready(hp1_rready),
        .S_AXI_HP2_awid(hp2_awid), .S_AXI_HP2_awaddr(hp2_awaddr), .S_AXI_HP2_awlen(hp2_awlen),
        .S_AXI_HP2_awsize(hp2_awsize), .S_AXI_HP2_awburst(hp2_awburst), .S_AXI_HP2_awlock(hp2_awlock),
        .S_AXI_HP2_awcache(hp2_awcache), .S_AXI_HP2_awprot(hp2_awprot), .S_AXI_HP2_awqos(hp2_awqos),
        .S_AXI_HP2_awvalid(hp2_awvalid), .S_AXI_HP2_awready(hp2_awready),
        .S_AXI_HP2_wid(hp2_wid), .S_AXI_HP2_wdata(hp2_wdata), .S_AXI_HP2_wstrb(hp2_wstrb),
        .S_AXI_HP2_wlast(hp2_wlast), .S_AXI_HP2_wvalid(hp2_wvalid), .S_AXI_HP2_wready(hp2_wready),
        .S_AXI_HP2_bid(hp2_bid), .S_AXI_HP2_bresp(hp2_bresp), .S_AXI_HP2_bvalid(hp2_bvalid), .S_AXI_HP2_bready(hp2_bready),
        .S_AXI_HP2_arid(hp2_arid), .S_AXI_HP2_araddr(hp2_araddr), .S_AXI_HP2_arlen(hp2_arlen),
        .S_AXI_HP2_arsize(hp2_arsize), .S_AXI_HP2_arburst(hp2_arburst), .S_AXI_HP2_arlock(hp2_arlock),
        .S_AXI_HP2_arcache(hp2_arcache), .S_AXI_HP2_arprot(hp2_arprot), .S_AXI_HP2_arqos(hp2_arqos),
        .S_AXI_HP2_arvalid(hp2_arvalid), .S_AXI_HP2_arready(hp2_arready),
        .S_AXI_HP2_rid(hp2_rid), .S_AXI_HP2_rdata(hp2_rdata), .S_AXI_HP2_rresp(hp2_rresp),
        .S_AXI_HP2_rlast(hp2_rlast), .S_AXI_HP2_rvalid(hp2_rvalid), .S_AXI_HP2_rready(hp2_rready),
        .S_AXI_HP3_awid(hp3_awid), .S_AXI_HP3_awaddr(hp3_awaddr), .S_AXI_HP3_awlen(hp3_awlen),
        .S_AXI_HP3_awsize(hp3_awsize), .S_AXI_HP3_awburst(hp3_awburst), .S_AXI_HP3_awlock(hp3_awlock),
        .S_AXI_HP3_awcache(hp3_awcache), .S_AXI_HP3_awprot(hp3_awprot), .S_AXI_HP3_awqos(hp3_awqos),
        .S_AXI_HP3_awvalid(hp3_awvalid), .S_AXI_HP3_awready(hp3_awready),
        .S_AXI_HP3_wid(hp3_wid), .S_AXI_HP3_wdata(hp3_wdata), .S_AXI_HP3_wstrb(hp3_wstrb),
        .S_AXI_HP3_wlast(hp3_wlast), .S_AXI_HP3_wvalid(hp3_wvalid), .S_AXI_HP3_wready(hp3_wready),
        .S_AXI_HP3_bid(hp3_bid), .S_AXI_HP3_bresp(hp3_bresp), .S_AXI_HP3_bvalid(hp3_bvalid), .S_AXI_HP3_bready(hp3_bready),
        .S_AXI_HP3_arid(hp3_arid), .S_AXI_HP3_araddr(hp3_araddr), .S_AXI_HP3_arlen(hp3_arlen),
        .S_AXI_HP3_arsize(hp3_arsize), .S_AXI_HP3_arburst(hp3_arburst), .S_AXI_HP3_arlock(hp3_arlock),
        .S_AXI_HP3_arcache(hp3_arcache), .S_AXI_HP3_arprot(hp3_arprot), .S_AXI_HP3_arqos(hp3_arqos),
        .S_AXI_HP3_arvalid(hp3_arvalid), .S_AXI_HP3_arready(hp3_arready),
        .S_AXI_HP3_rid(hp3_rid), .S_AXI_HP3_rdata(hp3_rdata), .S_AXI_HP3_rresp(hp3_rresp),
        .S_AXI_HP3_rlast(hp3_rlast), .S_AXI_HP3_rvalid(hp3_rvalid), .S_AXI_HP3_rready(hp3_rready)
    );

endmodule
'''

if NO_SD:
    i = s.index("    // microSD del MSXimus (sd_reader del PL, modo SD 1 bit).")
    j = s.index("    // ---- PS7: DDR3 + MIO (pines fijos del PS, sin .xdc) ----")
    s = s[:i] + s[j:]
    s = s.replace("    // (microSD: puertos reales sd_* en el header, ver cabecera)\n",
                  "    // [ZYNQ_NO_SD] microSD en tie-off (como el 13/09)\n"
                  "    wire sd_sclk, sd_cmd, sd_dat1, sd_dat2, sd_dat3;\n    wire sd_dat0 = 1'b1;\n")
    assert "output wire        sd_sclk" not in s and "wire sd_dat0 = 1'b1;" in s
    n_edits += 1
if MB_IDLE:
    s = s.replace("dbg_mailbox_axi #(.MBOX(32'h1FF0_0000), .PERIOD(54000)) u_mbox (",
                  "dbg_mailbox_axi #(.MBOX(32'h1FF0_0000), .PERIOD(54000), .ENABLE(0)) u_mbox (   // [ZYNQ_MB_IDLE]")
    assert ".ENABLE(0)" in s
    n_edits += 1
if NO_MB:
    # quitar la instancia del buzon (entre su cabecera y la del PS7); HP2 sigue en el
    # wrapper (N_HP fijo = 4), asi que sus cables se dejan en reposo.
    i = s.index("    // ================================================================\n    //  ZYNQ: buzon de depuracion")
    j = s.index("    // ================================================================\n    //  ZYNQ: PS7 (DDR3")
    s = s[:i] + '''    // [ZYNQ_NO_MAILBOX] HP2 en reposo
    assign hp2_awvalid = 1'b0; assign hp2_wvalid = 1'b0; assign hp2_arvalid = 1'b0;
    assign hp2_bready = 1'b1;  assign hp2_rready = 1'b1;
    assign hp2_awid = 6'd0; assign hp2_awaddr = 32'd0; assign hp2_awlen = 4'd0; assign hp2_awsize = 3'd0;
    assign hp2_awburst = 2'd0; assign hp2_awlock = 2'd0; assign hp2_awcache = 4'd0; assign hp2_awprot = 3'd0; assign hp2_awqos = 4'd0;
    assign hp2_wid = 6'd0; assign hp2_wdata = 64'd0; assign hp2_wstrb = 8'd0; assign hp2_wlast = 1'b0;
    assign hp2_arid = 6'd0; assign hp2_araddr = 32'd0; assign hp2_arlen = 4'd0; assign hp2_arsize = 3'd0;
    assign hp2_arburst = 2'd0; assign hp2_arlock = 2'd0; assign hp2_arcache = 4'd0; assign hp2_arprot = 3'd0; assign hp2_arqos = 4'd0;
    assign kbd_mbox = 128'd0;
    assign joy1_mbox = 16'd0; assign joy2_mbox = 16'd0;
    assign mb_mouse_btn = 8'd0; assign mb_mouse_dx = 8'd0; assign mb_mouse_dy = 8'd0; assign mb_mouse_rep = 1'b0;

''' + s[j:]
    assert "u_mbox" not in s
    n_edits += 1

open(DST, "w", encoding="utf-8", errors="surrogateescape").write(s)
print(f"{DST}: {n_edits} ediciones, {s.count(chr(10))} lineas"
      + (" [SIN BUZON]" if NO_MB else "") + (" [SIN SD]" if NO_SD else "") + (" [BUZON OCIOSO]" if MB_IDLE else ""))
