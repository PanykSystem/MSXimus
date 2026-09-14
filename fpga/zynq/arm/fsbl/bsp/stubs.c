/* stubs.c — lo que la BSP generada por el SDK aportaria y aqui va a mano:
 * usleep/sleep con el timer global (xtime_l) y _init/_fini vacios (crti/crtn no se enlazan). */
#include "xparameters.h"
#include "xil_types.h"
#include "xtime_l.h"

void usleep(unsigned long useconds)
{
    XTime t0, t;
    u64 n = (u64)useconds * (u64)(COUNTS_PER_SECOND / 1000000U);
    XTime_GetTime(&t0);
    do { XTime_GetTime(&t); } while ((u64)(t - t0) < n);
}

void sleep(unsigned int seconds)
{
    while (seconds--) usleep(1000000UL);
}

void _init(void) { }
void _fini(void) { }
