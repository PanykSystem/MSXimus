/* oled.h — OLED 128x64 (SSD1306) del conector J4 de la ZYNQ MINI. Ver oled.c. */
#ifndef OLED_H_
#define OLED_H_

void oled_init(void);                 /* GPIO EMIO + reset + secuencia de arranque del SSD1306 */
void oled_tick(void);                 /* refresco de la pagina de estado (lo llama osd_poll, 1 Hz) */

#endif
