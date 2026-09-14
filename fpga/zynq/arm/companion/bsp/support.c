/* support.c — lo minimo de la BSP standalone que el driver xsdps necesita, sin
 * MMU ni caches (el programa arranca con SCTLR.M/C/I a cero en start.S, asi que
 * toda la memoria es strongly-ordered y coherente con el PL y con el DMA del SDIO):
 *   - usleep/sleep con el timer global del Cortex-A9 (CPU/2)
 *   - Xil_DCache*: no-op (cache desactivada)
 *   - outbyte: la salida de xil_printf va al log en anillo de la DDR (log.h)
 */
#include "xil_types.h"
#include "xparameters.h"
#include "log.h"

#define GT_LO   (*(volatile u32 *)(XPAR_GLOBAL_TMR_BASEADDR + 0x00U))
#define GT_HI   (*(volatile u32 *)(XPAR_GLOBAL_TMR_BASEADDR + 0x04U))
#define GT_CTRL (*(volatile u32 *)(XPAR_GLOBAL_TMR_BASEADDR + 0x08U))

u64 gt_now(void)
{
    u32 hi, lo, hi2;
    if ((GT_CTRL & 1U) == 0U) GT_CTRL = 1U;          /* arrancar el timer si nadie lo hizo */
    do { hi = GT_HI; lo = GT_LO; hi2 = GT_HI; } while (hi != hi2);
    return ((u64)hi << 32) | lo;
}

void usleep(unsigned long useconds)
{
    u64 end = gt_now() + (u64)useconds * (COUNTS_PER_SECOND / 1000000U);
    while (gt_now() < end) { }
}

void sleep(unsigned int seconds)
{
    usleep((unsigned long)seconds * 1000000UL);

}

void Xil_DCacheFlushRange(INTPTR adr, u32 len) { (void)adr; (void)len; }
void Xil_DCacheInvalidateRange(INTPTR adr, u32 len) { (void)adr; (void)len; }
void Xil_DCacheFlush(void) { }
void Xil_DCacheInvalidate(void) { }
void Xil_DCacheEnable(void) { }
void Xil_DCacheDisable(void) { }
void Xil_ICacheEnable(void) { }
void Xil_ICacheDisable(void) { }

void outbyte(char c) { log_char(c); }
/* syscalls minimos de newlib (los arrastra vsnprintf): nada de ficheros ni salida */
int  _close(int fd) { (void)fd; return -1; }
int  _lseek(int fd, int off, int whence) { (void)fd; (void)off; (void)whence; return -1; }
int  _read(int fd, char *b, int n) { (void)fd; (void)b; (void)n; return 0; }
int  _write(int fd, const char *b, int n) { (void)fd; for (int i = 0; i < n; i++) log_char(b[i]); return n; }
int  _fstat(int fd, void *st) { (void)fd; (void)st; return -1; }
int  _isatty(int fd) { (void)fd; return 1; }
int  _kill(int pid, int sig) { (void)pid; (void)sig; return -1; }
int  _getpid(void) { return 1; }
void _exit(int code) { (void)code; for (;;) ; }
/* heap estatico para newlib (vsnprintf de log_printf) */
static char heap_buf[16384];
static unsigned heap_used;
void *_sbrk(int incr)
{
    if (incr < 0 || heap_used + (unsigned)incr > sizeof heap_buf) return (void *)-1;
    void *p = heap_buf + heap_used; heap_used += (unsigned)incr; return p;
}
char inbyte(void) { return 0; }

/* L2 (PL310, 0xF8F02000): la demo de fabrica pudo dejarla activa. Sin MMU
 * nuestros accesos ya son no cacheables, pero el depurador (lecturas por el
 * core 1 parado) podria ver lineas rancias: limpiar+invalidar por way y apagar. */
#define L2_CTRL     (*(volatile u32 *)0xF8F02100U)
#define L2_CLINV_WAY (*(volatile u32 *)0xF8F027FCU)
#define L2_SYNC     (*(volatile u32 *)0xF8F02730U)
void l2_disable(void)
{
    if (L2_CTRL & 1U) {
        L2_CLINV_WAY = 0xFFFFU;
        while (L2_CLINV_WAY & 0xFFFFU) { }
        L2_SYNC = 0U;
        L2_CTRL = 0U;
    }
}

/* TinyUSB (CFG_TUSB_OS = OPT_OS_NONE) */
u32 tusb_time_millis_api(void) { return (u32)(gt_now() / (COUNTS_PER_SECOND / 1000U)); }
