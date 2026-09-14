/* oled.c — OLED 128x64 de la placa (conector J4) como pantallita de estado del MSXimus.
 *
 * HARDWARE (esquematico ZYNQ_MINI pag. 10): modulo OLED de 30 pines con SSD1306 y bomba
 * de carga interna (C1P/C1N/C2P/C2N + VBAT). De sus pines el fabricante solo cablea CUATRO
 * a la FPGA, y son justo los del SPI de 4 hilos:
 *      OLED_D0  = E18  ->  D0  (pin 18) = SCLK
 *      OLED_D1  = E19  ->  D1  (pin 19) = SDIN
 *      OLED_DC  = F16  ->  D/C (pin 15)
 *      OLED_RST = F17  ->  RST (pin 14)
 * BS0/BS1/BS2 (seleccion de interfaz) y CS van puenteados en la placa. D2..D7 sin conectar,
 * que es lo que descarta el I2C (alli habria que unir D1 con D2 para el SDA bidireccional).
 *
 * POR QUE POR GPIO DEL PS Y NO EN LA FPGA: los 4 pines salen del PS por GPIO EMIO (banco 2,
 * bits 0..3 = GPIO 54..57) y el protocolo se hace a mano aqui. Asi el ARM, que ya tiene todos
 * los datos del OSD, pinta directamente; y si el puenteado de la placa resultara ser I2C en
 * vez de SPI, se cambia ESTE fichero sin volver a compilar la FPGA (25 min de Vivado).
 *
 * El bit-bang no necesita esperas: cada escritura al GPIO cruza el AXI GP del PS y tarda del
 * orden de 100 ns, o sea un reloj SPI de ~5 MHz, por debajo de los 10 MHz que admite el chip.
 * Un refresco entero son 1024 bytes = ~16k escrituras = unos pocos ms, y va a 1 Hz. */
#include "xil_types.h"
#include "sleep.h"
#include "log.h"
#include "oled.h"
#include "font8x8.h"

#define REG(a)          (*(volatile u32 *)(a))
#define MBOX            0x1FF00000u
#define SDBOX           0x1FF00100u
#define APER_CLK_CTRL   REG(0xF800012Cu)
#define SLCR_LOCK       REG(0xF8000004u)
#define SLCR_UNLOCK     REG(0xF8000008u)

/* GPIO del PS: banco 2 = las 32 primeras EMIO (GPIO 54..85) */
#define GPIO_BASE       0xE000A000u
#define GPIO_DATA_2     REG(GPIO_BASE + 0x048u)
#define GPIO_DIRM_2     REG(GPIO_BASE + 0x284u)
#define GPIO_OEN_2      REG(GPIO_BASE + 0x288u)

#define PIN_SCLK        (1u << 0)                      /* EMIO 0 -> E18 */
#define PIN_SDIN        (1u << 1)                      /* EMIO 1 -> E19 */
#define PIN_DC          (1u << 2)                      /* EMIO 2 -> F16 */
#define PIN_RSTN        (1u << 3)                      /* EMIO 3 -> F17 */

extern u64 gt_now(void);
extern u32 usb_stats_mount, usb_n_kbd, usb_n_mouse, usb_n_pad;
extern s32 osd_temp_dc;                                 /* osd.c: temperatura del die en decimas de C */

#define COLS 128
#define PAGES 8
static u8  fb[PAGES][COLS];
static u32 shadow;
static int ready;
static u64 t0;

/* ---------------- capa fisica: SPI de 4 hilos a mano ---------------- */
static void gp(void) { GPIO_DATA_2 = shadow; }

static void wr8(u8 b)
{
    for (int i = 0; i < 8; i++) {                       /* MSB primero */
        shadow = (shadow & ~(PIN_SCLK | PIN_SDIN)) | ((b & 0x80u) ? PIN_SDIN : 0u);
        gp();                                           /* dato puesto, reloj bajo */
        shadow |= PIN_SCLK;
        gp();                                           /* flanco de subida: el SSD1306 muestrea */
        b = (u8)(b << 1);
    }
}
static void cmd(u8 c) { shadow &= ~PIN_DC; gp(); wr8(c); }
static void dat(u8 d) { shadow |=  PIN_DC; gp(); wr8(d); }

/* ---------------- marco de texto ---------------- */
static void oled_clear(void)
{
    for (int p = 0; p < PAGES; p++)
        for (int x = 0; x < COLS; x++) fb[p][x] = 0u;
}
/* fila 0..7 (8 px), columna 0..15 (8 px). Recorta lo que no cabe. */
static void oled_text(int row, int col, const char *s)
{
    if (row < 0 || row >= PAGES) return;
    for (int x = col * 8; *s && x <= COLS - 8; s++, x += 8) {
        u8 c = (u8)*s;
        if (c < FONT8X8_FIRST || c >= (u8)(FONT8X8_FIRST + FONT8X8_COUNT)) c = ' ';
        for (int i = 0; i < 8; i++) fb[row][x + i] = FONT8X8[c - FONT8X8_FIRST][i];
    }
}
static void oled_flush(void)
{
    cmd(0x21u); cmd(0u); cmd(COLS - 1u);                /* rango de columnas */
    cmd(0x22u); cmd(0u); cmd(PAGES - 1u);               /* rango de paginas */
    for (int p = 0; p < PAGES; p++)
        for (int x = 0; x < COLS; x++) dat(fb[p][x]);
}

/* ---------------- formato (local: oled.c no depende de osd.c) ---------------- */
static char *put_str(char *d, const char *s) { while (*s) *d++ = *s++; return d; }
static char *put_u(char *d, u32 v)
{
    char t[11]; int n = 0;
    do { t[n++] = (char)('0' + v % 10u); v /= 10u; } while (v);
    while (n) *d++ = t[--n];
    return d;
}
static char *put_fix1(char *d, s32 v)                   /* v en decimas */
{
    if (v < 0) { *d++ = '-'; v = -v; }
    d = put_u(d, (u32)v / 10u); *d++ = '.'; *d++ = (char)('0' + (u32)v % 10u);
    return d;
}
static char *put_2(char *d, u32 v) { *d++ = (char)('0' + (v / 10u) % 10u); *d++ = (char)('0' + v % 10u); return d; }

/* ---------------- API ---------------- */
void oled_init(void)
{
    static const u8 seq[] = {
        0xAE,                   /* apagado mientras se configura */
        0xD5, 0x80,             /* divisor de reloj / frecuencia del oscilador */
        0xA8, 0x3F,             /* multiplex 1/64 */
        0xD3, 0x00,             /* sin desplazamiento vertical */
        0x40,                   /* linea de inicio = 0 */
        0x8D, 0x14,             /* bomba de carga ON (el modulo no trae 12 V) */
        0x20, 0x00,             /* direccionamiento HORIZONTAL: el volcado es un chorro de 1024 B */
        0xA1,                   /* columnas invertidas (el modulo va girado) */
        0xC8,                   /* filas invertidas */
        0xDA, 0x12,             /* configuracion de los COM: 128x64 alterno */
        0x81, 0xCF,             /* contraste */
        0xD9, 0xF1,             /* precarga */
        0xDB, 0x40,             /* nivel de VCOMH */
        0xA4,                   /* mostrar la RAM (no "todo encendido") */
        0xA6,                   /* video normal */
        0xAF                    /* encendido */
    };
    SLCR_UNLOCK = 0xDF0Du;
    APER_CLK_CTRL |= 1u << 22;                          /* reloj AMBA del GPIO */
    SLCR_LOCK = 0x767Bu;
    GPIO_DIRM_2 |= 0x0Fu;                               /* los 4 como salida */
    GPIO_OEN_2  |= 0x0Fu;
    shadow = 0u; gp();                                  /* RST abajo */
    usleep(20000);
    shadow = PIN_RSTN; gp();                            /* RST arriba */
    usleep(20000);
    for (u32 i = 0; i < sizeof(seq); i++) cmd(seq[i]);
    oled_clear();
    oled_flush();
    t0 = gt_now();
    ready = 1;
    log_str("OLED: SSD1306 128x64 por GPIO EMIO (SPI 4 hilos)\n");
}

void oled_tick(void)
{
    volatile u32 *sb  = (volatile u32 *)SDBOX;
    volatile u32 *tel = (volatile u32 *)(MBOX + 0x40);
    char l[20], *p;
    u32 hits, miss, pct10, up;

    if (!ready) return;
    hits = tel[2]; miss = tel[3];
    pct10 = (hits + miss) ? (u32)((u64)hits * 1000u / (hits + miss)) : 0u;
    up = (u32)((gt_now() - t0) / (u64)COUNTS_PER_SECOND);

    oled_clear();
    oled_text(0, 0, "MSXimus  ZYNQ");

    p = put_str(l, "die "); p = put_fix1(p, osd_temp_dc); p = put_str(p, " C"); *p = 0;
    oled_text(1, 0, l);

    p = put_str(l, "SD ");
    if (sb[1] & 1u) { p = put_u(p, sb[1] >> 16); p = put_str(p, "MB"); } else p = put_str(p, "--");
    *p = 0;
    oled_text(2, 0, l);

    p = put_str(l, "USB t"); p = put_u(p, usb_n_kbd);
    p = put_str(p, " r");    p = put_u(p, usb_n_mouse);
    p = put_str(p, " m");    p = put_u(p, usb_n_pad); *p = 0;
    oled_text(3, 0, l);

    /* +0x60 = {lat_max del AXI de ondas, lecturas, escrituras, r15}: el OPL4 en la DDR */
    p = put_str(l, "OPL4 "); p = put_u(p, ((tel[8] >> 24) & 0xFFu) * 80u / 3u); p = put_str(p, "ns"); *p = 0;
    oled_text(4, 0, l);

    p = put_str(l, "cache "); p = put_fix1(p, (s32)pct10); *p++ = '%'; *p = 0;
    oled_text(5, 0, l);

    p = put_str(l, "up "); p = put_2(p, up / 3600u); *p++ = ':';
    p = put_2(p, (up / 60u) % 60u); *p++ = ':'; p = put_2(p, up % 60u); *p = 0;
    oled_text(6, 0, l);

    /* +0x64 bit 25 = turbo_eff del core (F11 lo conmuta) */
    oled_text(7, 0, ((tel[9] >> 25) & 1u) ? "CPU 5.37MHz" : "CPU 3.58MHz");

    oled_flush();
}
