/* osd.c — pagina de informacion del sistema en el OSD del MSXimus (textdisp 32x28 de
 * iosys_bl616) hablando el protocolo BL616<->FPGA por la UART0 del PS (EMIO):
 *   0xAA len[15:8] len[7:0] cmd params...   len = 1 + n_params
 *   cmd 4 x y = cursor; cmd 5 <texto> = imprimir desde el cursor; cmd 8 b = overlay on/off
 * Con el overlay encendido el top congela el Z80 (iosys_frz): es una pausa con datos.
 * Se enciende/apaga con F12 del teclado USB (usb_host.c) o con MBOX+0x30 bit 0
 * (tools/osd.tcl). Mientras esta apagado se reenvia "overlay off" cada segundo: el PL
 * puede cargarse DESPUES que este programa (boot.tcl) y su overlay nace encendido.
 * Temperatura y tensiones: XADC por el interfaz del PS (devcfg 0xF8007100..), como
 * tools/temp.tcl. Estado del PL: la telemetria que dbg_mailbox_axi deja en MBOX+0x40. */
#include "xil_types.h"
#include "sleep.h"
#include "log.h"
#include "oled.h"

#define REG(a)          (*(volatile u32 *)(a))
#define MBOX            0x1FF00000u
#define SDBOX           0x1FF00100u
#define OSD_CTRL        REG(MBOX + 0x30)             /* bit 0: OSD pedido desde xsdb */
#define OSD_STAT        REG(MBOX + 0x34)             /* [0] osd on, [31:16] temp en decimas de C */

#define UART0           0xE0000000u
#define UART_CR         REG(UART0 + 0x00)
#define UART_MR         REG(UART0 + 0x04)
#define UART_BAUDGEN    REG(UART0 + 0x18)
#define UART_SR         REG(UART0 + 0x2C)
#define UART_FIFO       REG(UART0 + 0x30)
#define UART_BAUDDIV    REG(UART0 + 0x34)
#define SLCR_LOCK       REG(0xF8000004u)
#define SLCR_UNLOCK     REG(0xF8000008u)
#define IO_PLL_CTRL     REG(0xF8000108u)
#define APER_CLK_CTRL   REG(0xF800012Cu)
#define UART_CLK_CTRL   REG(0xF8000154u)
#define PS_CLK_HZ       33333333u

#define XADC_CFG        REG(0xF8007100u)
#define XADC_CMDF       REG(0xF8007110u)
#define XADC_RDF        REG(0xF8007114u)
#define XADC_MCTL       REG(0xF8007118u)

extern u64 gt_now(void);
extern u32 usb_stats_mount, usb_stats_reports, usb_n_kbd, usb_n_mouse, usb_n_pad;
extern volatile u32 osd_hotkey;                       /* usb_host.c: pulsaciones de F12 */

s32         osd_temp_dc;                              /* die en decimas de C; lo lee tambien oled.c */
static int  osd_on;
static u32  hotkey_seen, ctrl_seen;
static u64  t_next, t_start;                          /* t_start: el timer global no se resetea al recargar el programa */

/* ---------------- UART0 -> iosys ---------------- */
static void uart_init(void)
{
    u32 fdiv = (IO_PLL_CTRL >> 12) & 0x7Fu;
    u32 div  = (UART_CLK_CTRL >> 8) & 0x3Fu;
    u32 ref  = (u32)((u64)PS_CLK_HZ * fdiv / (div ? div : 1u));   /* 100 MHz con IO PLL 1800/18 */
    u32 cd   = (ref + 5000000u) / 10000000u;                       /* 2 Mbps = ref / (cd * (4+1)) */
    SLCR_UNLOCK = 0xDF0Du;
    UART_CLK_CTRL |= 1u;                                            /* CLKACT0 */
    APER_CLK_CTRL |= 1u << 20;                                      /* reloj AMBA de UART0 */
    SLCR_LOCK = 0x767Bu;
    UART_CR = 0x28u | 0x03u;                                        /* TX/RX off + reset de FIFOs */
    while (UART_CR & 0x03u) ;
    UART_MR = 0x20u;                                                /* 8N1, reloj de referencia */
    UART_BAUDGEN = cd ? cd : 10u; UART_BAUDDIV = 4u;
    UART_CR = 0x14u | 0x40u;                                        /* RXEN TXEN RSTTO */
    log_str("OSD: UART0 ref "); log_dec(ref / 1000000u); log_str(" MHz, CD "); log_dec(cd); log_str("\n");
}
static void uart_putc(u8 c) { while (UART_SR & (1u << 4)) ; UART_FIFO = c; }          /* TXFULL */
static void uart_drain(void) { while (!(UART_SR & (1u << 1))) (void)UART_FIFO; }      /* RXEMPTY */

static void iosys_frame(u8 cmd, const u8 *p, u16 n)
{
    u16 len = (u16)(n + 1u);
    uart_putc(0xAA); uart_putc((u8)(len >> 8)); uart_putc((u8)len); uart_putc(cmd);
    for (u16 i = 0; i < n; i++) uart_putc(p[i]);
}
static void osd_overlay(int on) { u8 b = on ? 1u : 0u; iosys_frame(8, &b, 1); }
static void osd_line(u8 y, const char *s)                       /* fila completa (32 col, relleno) */
{
    u8 buf[32], xy[2] = { 0, y };
    u16 n = 0;
    while (n < 32u && s[n]) { buf[n] = (u8)s[n]; n++; }
    while (n < 32u) buf[n++] = ' ';
    iosys_frame(4, xy, 2);
    iosys_frame(5, buf, 32);
}

/* ---------------- XADC ---------------- */
static void xadc_init(void)
{
    XADC_MCTL = 0x10u; XADC_MCTL = 0u;
    XADC_CFG  = 0x80001114u;                                        /* enable, TCKRATE /4, IGAP 20 */
}
static u16 xadc_rd(u32 addr)
{
    XADC_CMDF = (1u << 26) | (addr << 16);                          /* lectura DRP */
    usleep(20); (void)XADC_RDF;                                     /* respuesta del comando anterior */
    XADC_CMDF = 0u;                                                 /* NOP: empuja la respuesta */
    usleep(20);
    return (u16)(XADC_RDF & 0xFFFFu);
}
/* T(C) = code * 503.975 / 65536 - 273.15  ->  decimas de C */
static s32 xadc_temp_dc(u16 code) { return (s32)((u64)code * 503975u / 6553600u) - 2731; }
static u32 xadc_mv(u16 code)      { return (u32)((u64)code * 3000u / 65536u); }

/* ---------------- formato ---------------- */
static char *put_str(char *d, const char *s) { while (*s) *d++ = *s++; return d; }
static char *put_u(char *d, u32 v)
{
    char t[11]; int n = 0;
    do { t[n++] = (char)('0' + v % 10u); v /= 10u; } while (v);
    while (n) *d++ = t[--n];
    return d;
}
static char *put_fix(char *d, s32 v, u32 dec)                    /* v en unidades 10^-dec */
{
    u32 p = 1; for (u32 i = 0; i < dec; i++) p *= 10u;
    if (v < 0) { *d++ = '-'; v = -v; }
    d = put_u(d, (u32)v / p);
    if (dec) { *d++ = '.'; u32 f = (u32)v % p; for (u32 q = p / 10u; q; q /= 10u) *d++ = (char)('0' + (f / q) % 10u); }
    return d;
}
static char *put_2(char *d, u32 v) { *d++ = (char)('0' + (v / 10u) % 10u); *d++ = (char)('0' + v % 10u); return d; }

/* ---------------- la pagina ---------------- */
/* Se escriben las 28 filas (las vacias tambien): la BSRAM de textdisp nace con el texto
 * de demostracion del bitstream y hay que taparlo. Lineas de <= 30 columnas: el borde
 * derecho del overlay queda fuera de la captura HDMI. */
#define ROWS 28
static void osd_render(void)
{
    static char pg[ROWS][34];
    char *p;
    volatile u32 *sb  = (volatile u32 *)SDBOX;
    volatile u32 *tel = (volatile u32 *)(MBOX + 0x40);
    volatile u8  *z80 = (volatile u8 *)0x10800000u;                /* pagina 3 del Z80: DDR + (A - 0xC000) */
    u16 tc = xadc_rd(0x00), tmax = xadc_rd(0x20);
    u16 vi = xadc_rd(0x01), va = xadc_rd(0x02), vb = xadc_rd(0x06);
    s32 t = xadc_temp_dc(tc);
    u32 up = (u32)((gt_now() - t_start) / (u64)COUNTS_PER_SECOND);
    u32 hits = tel[2], miss = tel[3];
    u32 pct10 = (hits + miss) ? (u32)((u64)hits * 1000u / (hits + miss)) : 0u;   /* % de aciertos x10 */

    for (int r = 0; r < ROWS; r++) pg[r][0] = 0;
    put_str(pg[0], "MSXimus / ZYNQ 7020  companion")[0] = 0;
    put_str(pg[1], "------------------------------")[0] = 0;
    p = put_str(pg[3], "Zynq die "); p = put_fix(p, t, 1); p = put_str(p, " C  max "); p = put_fix(p, xadc_temp_dc(tmax), 1); p = put_str(p, " C"); *p = 0;
    p = put_str(pg[4], "Vint "); p = put_fix(p, (s32)xadc_mv(vi) / 10, 2); p = put_str(p, " Vaux "); p = put_fix(p, (s32)xadc_mv(va) / 10, 2);
    p = put_str(p, " Vbram "); p = put_fix(p, (s32)xadc_mv(vb) / 10, 2); *p = 0;
    p = put_str(pg[6], "SD TF2  "); if (sb[1] & 1u) { p = put_u(p, sb[1] >> 16); p = put_str(p, " MB presente"); } else p = put_str(p, "sin tarjeta"); *p = 0;
    p = put_str(pg[7], " lect "); p = put_u(p, sb[8]); p = put_str(p, " escr "); p = put_u(p, sb[9]); p = put_str(p, " err "); p = put_u(p, sb[10]); *p = 0;
    p = put_str(pg[9], "USB  disp "); p = put_u(p, usb_stats_mount); p = put_str(p, " tec "); p = put_u(p, usb_n_kbd);
    p = put_str(p, " rat "); p = put_u(p, usb_n_mouse); p = put_str(p, " pad "); p = put_u(p, usb_n_pad); *p = 0;
    p = put_str(pg[10], " informes HID "); p = put_u(p, usb_stats_reports); *p = 0;
    p = put_str(pg[12], "MSX  SCREEN "); p = put_u(p, z80[0xFCAF - 0xC000]); p = put_str(p, "   (en pausa)"); *p = 0;
    p = put_str(pg[13], " RAM Z80 cache "); p = put_fix(p, (s32)pct10, 1); p = put_str(p, "% aciertos"); *p = 0;
    /* +0x60 (tel_dbg4): wave_axi (OPL4 en la DDR por GP0) = {lat_max AR->R en ciclos de 37,5 MHz
     * (x 26,67 ns), lecturas, escrituras; contadores de 8 bits} */
    p = put_str(pg[14], " OPL4 wave lat "); p = put_u(p, ((tel[8] >> 24) & 0xFFu) * 80u / 3u); p = put_str(p, "ns rd ");
    p = put_u(p, (tel[8] >> 16) & 0xFFu); p = put_str(p, " wr "); p = put_u(p, (tel[8] >> 8) & 0xFFu); *p = 0;
    /* +0x64 bit 25 = turbo_eff del core: el turbo WSX se conmuta con F11 */
    p = put_str(pg[16], "CPU "); p = put_str(p, (tel[9] >> 25) & 1u ? "5.37" : "3.58");
    p = put_str(p, " MHz   F11 turbo"); *p = 0;
    p = put_str(pg[15], "uptime "); p = put_2(p, up / 3600u); *p++ = ':'; p = put_2(p, (up / 60u) % 60u); *p++ = ':'; p = put_2(p, up % 60u);
    p = put_str(p, "  bucle "); p = put_u(p, sb[12] / 1000u); p = put_str(p, "k"); *p = 0;
    put_str(pg[27], "F12 o osd.tcl off: cerrar")[0] = 0;

    osd_temp_dc = t;
    OSD_STAT = 1u | ((u32)(t & 0xFFFF) << 16);
    osd_overlay(1);
    for (int r = 0; r < ROWS; r++) osd_line((u8)r, pg[r]);
}

/* ---------------- API ---------------- */
void osd_init(void)
{
    uart_init();
    xadc_init();
    oled_init();                                       /* OLED de la placa (J4): estado permanente */
    osd_on = 0; hotkey_seen = osd_hotkey; ctrl_seen = OSD_CTRL & 1u;
    OSD_STAT = 0u;
    osd_overlay(0);
    t_start = gt_now();
    t_next = t_start;
}

void osd_poll(void)
{
    u64 now = gt_now();
    u32 c = OSD_CTRL & 1u;
    int changed = 0;
    uart_drain();                                                   /* iosys manda los mandos cada 20 ms */
    if (osd_hotkey != hotkey_seen) { hotkey_seen = osd_hotkey; osd_on = !osd_on; changed = 1; }
    if (c != ctrl_seen)            { ctrl_seen = c; osd_on = (int)c; changed = 1; }
    if (changed) log_str(osd_on ? "OSD on\n" : "OSD off\n");
    if (!changed && now < t_next) return;
    t_next = now + (u64)COUNTS_PER_SECOND;
    if (osd_on) osd_render();
    else { osd_overlay(0); osd_temp_dc = xadc_temp_dc(xadc_rd(0x00)); OSD_STAT = (u32)(osd_temp_dc & 0xFFFF) << 16; }
    oled_tick();                                                    /* el OLED se refresca con el OSD encendido o apagado */
}
