/* main.c — proxy de SD del MSXimus en la ZYNQ MINI (Cortex-A9 core 0, bare-metal).
 *
 * Sirve la tarjeta REAL de TF2 (SD1, MIO 10..15) al modulo sd_axi_proxy del PL
 * a traves del buzon SDBOX en la DDR (ver fpga/zynq/sd_axi_proxy.v):
 *   W0 +0x00: [0] MODE (1 = proxy)  [32] tarjeta presente  [63:48] tamano (MB)
 *   W1 +0x08: [31:0] REQ_SEQ  [39:32] op (1 lee, 2 escribe)  [47:40] bloques
 *   W2 +0x10: [31:0] sector
 *   W3 +0x18: [31:0] ACK_SEQ  [63:32] estado (0 = OK)
 *   +0x20..: estadisticas del ARM (lecturas, escrituras, errores, reinits, vueltas)
 * Datos en SDBUF (+n*512). Sin MMU ni caches (start.S): coherente sin mas.
 *
 * Bucle de bajo consumo (v2): el core duerme en WFI y lo despiertan
 *   - IRQ_F2P[0] (ID 61 del GIC): req_irq del proxy del PL, nivel alto hasta el acuse;
 *   - el timer privado del core (ID 29) cada 10 ms, para la vigilancia de la tarjeta.
 * Las interrupciones quedan enmascaradas en CPSR (no hay manejadores): WFI se
 * despierta con una IRQ pendiente aunque este enmascarada, y el GIC solo tiene
 * que reenviarlas (distribuidor + interfaz de CPU habilitados).
 * Cambio en caliente: un acceso que falla reinicializa la tarjeta (y reintenta);
 * sin tarjeta, init cada 0,5 s; con tarjeta, SEND_STATUS (ACMD13) cada 2 s.    */
#include "xil_types.h"
#include "xstatus.h"
#include "xparameters.h"
#include "xsdps.h"
#include "log.h"
#include "sleep.h"

#define SDBOX     0x1FF00100U
#define SDBUF     0x1FF10000U
#define SD_DEVICE 1U                 /* 1 = TF2 (SD1); 0 = TF1 (SD0) */

enum { W_MODE = 0, W_CARD = 1, W_REQ_SEQ = 2, W_REQ_OPC = 3, W_REQ_SEC = 4,
       W_ACK_SEQ = 6, W_ACK_ST = 7, W_N_RD = 8, W_N_WR = 9, W_N_ERR = 10, W_N_INIT = 11, W_N_LOOP = 12 };

/* GIC (distribuidor 0xF8F01000, interfaz de CPU 0xF8F00100) y timer privado (0xF8F00600) */
#define REG(a)      (*(volatile u32 *)(a))
#define ICDDCR      REG(0xF8F01000U)
#define ICDISER(n)  REG(0xF8F01100U + 4U * (n))
#define ICDIPR(id)  (*(volatile u8 *)(0xF8F01400U + (id)))
#define ICDIPTR(id) (*(volatile u8 *)(0xF8F01800U + (id)))
#define ICDICFR(n)  REG(0xF8F01C00U + 4U * (n))
#define ICCICR      REG(0xF8F00100U)
#define ICCPMR      REG(0xF8F00104U)
#define PTIM_LOAD   REG(0xF8F00600U)
#define PTIM_CTRL   REG(0xF8F00608U)
#define PTIM_ISR    REG(0xF8F0060CU)
#define ID_PTIMER   29U
#define ID_F2P0     61U              /* IRQ_F2P[0] */

static volatile u32 * const box = (volatile u32 *)SDBOX;
static XSdPs sd;
static int   present;
static u32   card_mb;
extern u64   gt_now(void);
extern void  l2_disable(void);
extern int   usb_host_init(void);
extern void  usb_host_poll(void);
extern void  osd_init(void);                          /* osd.c: pagina de informacion por la UART0 -> iosys */
extern void  osd_poll(void);
extern u32   usb_stats_mount, usb_stats_reports;

static void wake_setup(void)
{
    ICDDCR = 0U;
    for (u32 n = 0; n < 3U; n++) {                                     /* la demo de fabrica deja IRQs
        REG(0xF8F01180U + 4U * n) = 0xFFFFFFFFU;                        * habilitadas/pendientes que nadie
        REG(0xF8F01280U + 4U * n) = 0xFFFFFFFFU;                        * acusa: WFI no dormiria nunca */
    }
    ICDIPR(ID_PTIMER) = 0xA0U;  ICDIPR(ID_F2P0) = 0xA0U;
    ICDIPTR(ID_F2P0) = 0x01U;                                         /* -> CPU0 */
    ICDICFR(ID_F2P0 / 16U) = (ICDICFR(ID_F2P0 / 16U) & ~(3U << ((ID_F2P0 % 16U) * 2U)))
                             | (1U << ((ID_F2P0 % 16U) * 2U));         /* nivel alto, 1-N */
    ICDISER(ID_PTIMER / 32U) = 1U << (ID_PTIMER % 32U);
    ICDISER(ID_F2P0 / 32U)   = 1U << (ID_F2P0 % 32U);
    ICCPMR = 0xFFU;
    ICCICR = 0x01U;
    ICDDCR = 0x01U;
    PTIM_CTRL = 0U;
    PTIM_ISR  = 1U;
    PTIM_LOAD = COUNTS_PER_SECOND / 100U;                              /* 10 ms (CPU/2) */
    PTIM_CTRL = 0x07U;                                                 /* enable, auto-reload, IRQ */
}

static int sd_try_init(void)
{
    XSdPs_Config *cfg = XSdPs_LookupConfig(SD_DEVICE);
    box[W_N_INIT]++;
    if (cfg == NULL) return 0;
    if (XSdPs_CfgInitialize(&sd, cfg, cfg->BaseAddress) != XST_SUCCESS) return 0;
    if (XSdPs_CardInitialize(&sd) != XST_SUCCESS) return 0;
    card_mb = sd.SectorCount >> 11;                       /* sectores de 512 B -> MB */
    return 1;
}

static void publish_card(void)
{
    box[W_CARD] = (present ? 1U : 0U) | (card_mb << 16);
    dsb();
}

int main(void)
{
    u32 last, n_rd = 0, n_wr = 0, n_err = 0, n_loop = 0;
    u64 t_retry = 0;

    l2_disable();
    log_init();
    log_str("companion v3: SD de TF2 + USB host (TinyUSB)\n");
    box[W_N_RD] = 0; box[W_N_WR] = 0; box[W_N_ERR] = 0; box[W_N_INIT] = 0; box[W_N_LOOP] = 0;
    present = sd_try_init();
    if (!present) card_mb = 0;
    if (present) {
        log_str("tarjeta OK: "); log_dec(card_mb); log_str(" MB, tipo "); log_dec(sd.CardType);
        log_str(", HCS "); log_dec(sd.HCS); log_str(", bus "); log_dec(sd.BusWidth);
        log_str(" bits, "); log_dec(sd.BusSpeed); log_str(" Hz\n");
    } else {
        log_str("sin tarjeta (reintento cada 0,5 s)\n");
    }
    publish_card();
    last = box[W_REQ_SEQ];
    box[W_ACK_SEQ] = last;                                /* nada pendiente */
    dsb();
    box[W_MODE] = 1U;                                     /* proxy ON: el PL deja de usar la imagen */
    dsb();
    /* VRAM del V9968 a cero ANTES de soltar el MSX. Vive en la DDR (VRAM_BASE 0x10000000 +
     * 0x280000 del shim, 18 bits = 256 KB) y la DDR arranca con basura: cualquier zona que un
     * juego no escriba se veia como ruido blanco (Xevious, 14/09). En el Tang arranca limpia. */
    {
        volatile u32 *vram = (volatile u32 *)0x10280000U;
        for (u32 i = 0; i < 0x40000U / 4U; i++) vram[i] = 0U;
        dsb();
    }
    *(volatile u32 *)0x1FF0001CU = 1U;                    /* MSX_RUN: con BOOT.bin el MSX esperaba en reset */
    dsb();
    wake_setup();
    log_str("MODE=1, WFI\n");
    usb_host_init();
    osd_init();

    for (;;) {
        u32 seq;
        __asm__ volatile ("wfi" ::: "memory");
        PTIM_ISR = 1U;                                    /* si fue el timer, limpiar su evento */
        box[W_N_LOOP] = ++n_loop;
        usb_host_poll();                                  /* TinyUSB: interrupciones por sondeo + tarea */
        osd_poll();                                       /* OSD: F12 / MBOX+0x30; refresco 1 s */
        box[13] = usb_stats_mount; box[14] = usb_stats_reports;
        seq = box[W_REQ_SEQ];
        if (seq != last) {
            u32 opc, op, cnt, sec, st = 0;
            usleep(2);                                    /* la rafaga del PL (seq, op, sector) ya ha aterrizado */
            opc = box[W_REQ_OPC]; op = opc & 0xFFU; cnt = (opc >> 8) & 0xFFU; sec = box[W_REQ_SEC];
            if (cnt == 0U) cnt = 1U;
            for (int attempt = 0; attempt < 2; attempt++) {
                s32 r;
                if (!present) { st = 1U; break; }         /* sin tarjeta */
                if (op == 1U)      r = XSdPs_ReadPolled(&sd, sec, cnt, (u8 *)SDBUF);
                else if (op == 2U) r = XSdPs_WritePolled(&sd, sec, cnt, (const u8 *)SDBUF);
                else { st = 3U; break; }                  /* orden desconocida */
                if (r == XST_SUCCESS) { st = 0U; break; }
                st = 2U;                                  /* fallo: ¿se ha ido la tarjeta? reinit y un reintento */
                present = sd_try_init();
                publish_card();
            }
            if (st != 0U) n_err++; else if (op == 1U) n_rd++; else n_wr++;
            box[W_N_RD] = n_rd; box[W_N_WR] = n_wr; box[W_N_ERR] = n_err;
            box[W_ACK_ST] = st;
            dsb();
            box[W_ACK_SEQ] = seq;                         /* el PL espera este valor (y baja req_irq) */
            dsb();
            last = seq;
            if (st != 0U) {
                log_str("ERR op="); log_dec(op); log_str(" sec="); log_hex(sec);
                log_str(" n="); log_dec(cnt); log_str(" st="); log_dec(st); log_str("\n");
            }
        } else {
            u64 now = gt_now();
            if (!present) {
                if (now - t_retry > (u64)(COUNTS_PER_SECOND / 2U)) {     /* sin tarjeta: reintentar init */
                    t_retry = now;
                    present = sd_try_init();
                    if (present) { log_str("tarjeta insertada: "); log_dec(card_mb); log_str(" MB\n"); }
                    else card_mb = 0;
                    publish_card();
                }
            } else if (now - t_retry > (u64)(COUNTS_PER_SECOND * 2U)) {  /* con tarjeta: ¿sigue ahi? (ACMD13) */
                u8 sdstat[64];
                t_retry = now;
                if (XSdPs_Get_Status(&sd, sdstat) != XST_SUCCESS) {
                    present = 0; card_mb = 0;
                    publish_card();
                    log_str("tarjeta retirada\n");
                }
            }
            usleep(10);                                   /* con JTAG en halting-debug, WFI es un NOP en el A9:
                                                             espera con el timer (sin trafico en la DDR) */
        }
    }
    return 0;
}
