/* log.c — log en anillo en la DDR (ver log.h). Tambien memset/memcpy para el
 * driver (sin libc). */
#include "log.h"

static volatile u32  * const hdr = (volatile u32 *)LOG_BASE;
static volatile char * const buf = (volatile char *)(LOG_BASE + 8U);

void log_init(void) { hdr[0] = 0x474F4C41U; hdr[1] = 0U; }     /* "ALOG" */

void log_char(char c)
{
    u32 i = hdr[1];
    buf[i % LOG_SIZE] = c;
    hdr[1] = i + 1U;
}

void log_str(const char *s) { while (*s) log_char(*s++); }

void log_hex(u32 v)
{
    static const char h[] = "0123456789ABCDEF";
    for (int i = 28; i >= 0; i -= 4) log_char(h[(v >> i) & 0xFU]);
}

void log_dec(u32 v)
{
    char t[11]; int n = 0;
    do { t[n++] = (char)('0' + v % 10U); v /= 10U; } while (v);
    while (n) log_char(t[--n]);
}

void *memset(void *d, int c, unsigned int n) { unsigned char *p = d; while (n--) *p++ = (unsigned char)c; return d; }
void *memcpy(void *d, const void *s, unsigned int n) { unsigned char *p = d; const unsigned char *q = s; while (n--) *p++ = *q++; return d; }
int   memcmp(const void *a, const void *b, unsigned int n) { const unsigned char *p = a, *q = b; while (n--) { if (*p != *q) return *p - *q; p++; q++; } return 0; }
unsigned int strlen(const char *s) { unsigned int n = 0; while (s[n]) n++; return n; }
