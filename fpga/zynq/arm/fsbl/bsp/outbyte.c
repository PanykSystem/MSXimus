/* outbyte.c — consola del FSBL por la UART1 del PS (0xE0001000, MIO 48/49 -> CH340 del P1,
 * 115200 8N1 que deja ps7_init). xil_printf llama a outbyte(). */
#include "xil_types.h"

#define UART1_SR   (*(volatile u32 *)0xE000102Cu)
#define UART1_FIFO (*(volatile u32 *)0xE0001030u)

void outbyte(char c)
{
    while (UART1_SR & 0x10u) ;                 /* TXFULL */
    UART1_FIFO = (u32)(u8)c;
}

char inbyte(void)
{
    while (UART1_SR & 0x02u) ;                 /* RXEMPTY */
    return (char)UART1_FIFO;
}
