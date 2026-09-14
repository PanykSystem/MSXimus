/* log.h — log en anillo en la DDR, legible desde xsdb (tools/armlog.tcl).
 *   LOG_BASE+0: 'ALOG'   +4: indice de escritura (bytes escritos, sin limite)
 *   +8 .. +8+LOG_SIZE-1: caracteres (anillo)                                  */
#ifndef LOG_H
#define LOG_H
#include "xil_types.h"
#define LOG_BASE 0x1FF00800U
#define LOG_SIZE 0x700U
void log_init(void);
void log_char(char c);
void log_str(const char *s);
void log_hex(u32 v);
void log_dec(u32 v);
int  log_printf(const char *fmt, ...);      /* printf al anillo (TinyUSB con CFG_TUSB_DEBUG) */
#endif
