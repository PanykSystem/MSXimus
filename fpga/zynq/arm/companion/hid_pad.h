/* hid_pad.h — mandos USB genericos (HID joystick/gamepad) -> palabra SNES del BL616
 *   bit 11 R(der), 10 L(izq), 9 X, 8 A, 7 RT, 6 LT, 5 DOWN, 4 UP, 3 START, 2 SEL, 1 Y, 0 B
 * Se parsea el descriptor de informe HID al montar (ejes X/Y, hat, botones) y con
 * cada informe se decodifica a la palabra. Hasta HID_PAD_MAX mandos (jugador 1 y 2). */
#ifndef HID_PAD_H_
#define HID_PAD_H_
#include <stdint.h>

#define HID_PAD_MAX 2

/* devuelve el jugador (0/1) o -1 si no cabe o el descriptor no tiene ejes ni botones */
int  hid_pad_mount(uint8_t dev, uint8_t idx, const uint8_t *desc, uint16_t len);
/* devuelve el jugador liberado o -1 */
int  hid_pad_umount(uint8_t dev, uint8_t idx);
/* decodifica un informe; devuelve el jugador (0/1) y deja la palabra en *word, o -1 */
int  hid_pad_report(uint8_t dev, uint8_t idx, const uint8_t *rep, uint16_t len, uint16_t *word);

#endif
