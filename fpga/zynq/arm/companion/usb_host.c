/* usb_host.c — USB host del companion (Zynq USB0 + PHY USB3320C por ULPI) con
 * TinyUSB: hub + HID. Teclado, raton y mandos llegan al MSX por el buzon HID de
 * la DDR (MBOX 0x1FF00000) que el PL (dbg_mailbox_axi) lee cada ~1 ms:
 *   +0x00 .. +0x0F : bitmap de 128 bits, bit = usage HID (modificadores en 104+i),
 *                    el mismo formato que usb_kbd_decode.v (y que tools/key.tcl)
 *   +0x10 : joy1[15:0] | joy2[31:16]  formato SNES del companion BL616 (comando 9):
 *           bit 11 R, 10 L, 9 X, 8 A, 7 RT, 6 LT, 5 DOWN, 4 UP, 3 START, 2 SEL, 1 Y, 0 B
 *   +0x14 : mouse_btn[7:0] | mouse_seq[15:8]
 *   +0x18 : mouse_ax[15:0] | mouse_ay[31:16]  (acumulados, int16 con desbordamiento;
 *           el PL saca el delta entre dos lecturas: no se pierde movimiento)
 * Teclado + raton por protocolo boot; mandos genericos por descriptor HID (hid_pad.c). */
#include "tusb.h"
#include "xil_types.h"
#include "log.h"
#include "sleep.h"
#include "hid_pad.h"

#define MBOX        0x1FF00000u
#define GPIO_BASE   0xE000A000u
#define GPIO_DATA_1 (*(volatile u32 *)(GPIO_BASE + 0x044u))
#define GPIO_DIRM_1 (*(volatile u32 *)(GPIO_BASE + 0x244u))
#define GPIO_OEN_1  (*(volatile u32 *)(GPIO_BASE + 0x248u))
#define PHY_RST_BIT (1u << (46 - 32))                       /* USBPHY_nRSET = MIO 46 (banco 1) */
#define USB0_ULPI   (*(volatile u32 *)0xE0002170u)          /* ULPI_VIEWPORT */
#define USB0_PORTSC (*(volatile u32 *)0xE0002184u)
#define USB0_USBMODE (*(volatile u32 *)0xE00021A8u)

static volatile u32 * const mbox = (volatile u32 *)MBOX;
u32 usb_stats_mount, usb_stats_reports;
u32 usb_n_kbd, usb_n_mouse, usb_n_pad;                      /* interfaces HID montadas (osd.c) */
volatile u32 osd_hotkey;                                    /* pulsaciones de F12 (osd.c las cuenta) */

/* ---------------- ULPI viewport ---------------- */
static int ulpi_wait_run(void)
{
    for (u32 i = 0; i < 100000u; i++) if ((USB0_ULPI & (1u << 30)) == 0u) return 1;
    return 0;
}
static int ulpi_write(u8 addr, u8 data)
{
    USB0_ULPI = (1u << 30) | (1u << 29) | ((u32)addr << 16) | data;
    return ulpi_wait_run();
}
static int ulpi_read(u8 addr, u8 *data)
{
    USB0_ULPI = (1u << 30) | ((u32)addr << 16);
    if (!ulpi_wait_run()) return 0;
    *data = (u8)(USB0_ULPI >> 8);
    return 1;
}

/* Gancho de hcd_init (CI_HS_SET_AHB_BURST): tras el reset del controlador y
 * USBMODE=host, antes de ehci_init. */
void zynq_usb_pre_ehci(void)
{
    u32 p = USB0_PORTSC & ~0x2Au;                            /* sin los bits W1C */
    USB0_PORTSC = (p & ~(3u << 30)) | (2u << 30);            /* PTS = ULPI, 8 bits */
    USB0_ULPI = 1u << 31;                                    /* despertar el PHY */
    for (u32 i = 0; i < 100000u; i++) if ((USB0_ULPI & (1u << 31)) == 0u) break;
    u8 id0 = 0, id1 = 0;
    ulpi_read(0x00, &id0);                                   /* la primera transaccion tras despertar el viewport devuelve 0 */
    ulpi_read(0x00, &id0); ulpi_read(0x01, &id1);            /* USB3320: 0x0424 (Microchip/SMSC) */
    log_str("ULPI PHY id "); log_hex(((u32)id1 << 8) | id0); log_str("\n");
    ulpi_write(0x0B, 0x60);                                  /* OTG Control SET: DrvVbus + DrvVbusExternal (CPEN) */
    ulpi_write(0x0B, 0x06);                                  /* DpPulldown + DmPulldown (host) */
}

static void phy_reset(void)
{
    /* ps7_init no toca MIO_PIN_46 (queda en reset: tri-state): ponerlo como GPIO LVCMOS18 salida */
    *(volatile u32 *)0xF8000008u = 0xDF0Du;                  /* SLCR unlock */
    *(volatile u32 *)0xF80007B8u = 0x00000200u;              /* MIO_PIN_46: GPIO, LVCMOS18, sin tri-state */
    *(volatile u32 *)0xF8000004u = 0x767Bu;                  /* SLCR lock */
    GPIO_DIRM_1 |= PHY_RST_BIT; GPIO_OEN_1 |= PHY_RST_BIT;
    GPIO_DATA_1 &= ~PHY_RST_BIT; usleep(20000);              /* RESETB bajo 20 ms */
    GPIO_DATA_1 |=  PHY_RST_BIT; usleep(50000);              /* el PHY arranca su CLKOUT de 60 MHz */
}

/* ---------------- estado HID -> buzon ---------------- */
#define MAX_KBD 4
static struct { u8 dev, idx, used; u32 bits[4]; } kbd[MAX_KBD];
static u32 kbd_or[4];
static u8  mouse_btn, mouse_seq;
static s16 mouse_ax, mouse_ay;
static u16 joy[2];

static void mbox_kbd_flush(void)
{
    u32 acc[4] = {0, 0, 0, 0};
    for (int k = 0; k < MAX_KBD; k++) if (kbd[k].used) for (int w = 0; w < 4; w++) acc[w] |= kbd[k].bits[w];
    for (int w = 0; w < 4; w++) { kbd_or[w] = acc[w]; mbox[w] = acc[w]; }
    dsb();
}
static void mbox_misc_flush(void)
{
    mbox[4] = (u32)joy[0] | ((u32)joy[1] << 16);
    mbox[5] = (u32)mouse_btn | ((u32)mouse_seq << 8);
    mbox[6] = ((u32)(u16)mouse_ax) | ((u32)(u16)mouse_ay << 16);
    dsb();
}
static void kbd_set(u32 *bits, u32 usage) { if (usage < 128u) bits[usage >> 5] |= 1u << (usage & 31u); }

static void on_keyboard(u8 dev, u8 idx, const hid_keyboard_report_t *r)
{
    int slot = -1;
    for (int k = 0; k < MAX_KBD; k++) if (kbd[k].used && kbd[k].dev == dev && kbd[k].idx == idx) slot = k;
    if (slot < 0) for (int k = 0; k < MAX_KBD; k++) if (!kbd[k].used) { slot = k; kbd[k].used = 1; kbd[k].dev = dev; kbd[k].idx = idx; break; }
    if (slot < 0) return;
    u32 b[4] = {0, 0, 0, 0};
    static u8 f12_prev;
    u8 f12 = 0;
    for (int i = 0; i < 8; i++) if (r->modifier & (1u << i)) kbd_set(b, 104u + (u32)i);
    for (int i = 0; i < 6; i++) if (r->keycode[i] > 3u) { kbd_set(b, r->keycode[i]); if (r->keycode[i] == 69u) f12 = 1; }
    if (f12 && !f12_prev) osd_hotkey++;                    /* F12: pagina de informacion (osd.c) */
    f12_prev = f12;
    for (int w = 0; w < 4; w++) kbd[slot].bits[w] = b[w];
    mbox_kbd_flush();
}

static void on_mouse(const hid_mouse_report_t *r)
{
    mouse_btn = r->buttons;
    mouse_ax = (s16)(mouse_ax + r->x);
    mouse_ay = (s16)(mouse_ay + r->y);
    mouse_seq++;
    mbox_misc_flush();
}

/* ---------------- callbacks de TinyUSB ---------------- */
void tuh_mount_cb(uint8_t daddr)
{
    uint16_t vid = 0, pid = 0;
    usb_stats_mount++;
    tuh_vid_pid_get(daddr, &vid, &pid);
    log_str("USB: dispositivo "); log_dec(daddr); log_str(" montado, VID:PID "); log_hex(((u32)vid << 16) | pid);
    log_str(", interfaces HID "); log_dec(tuh_hid_itf_get_count(daddr)); log_str("\n");
}
void tuh_umount_cb(uint8_t daddr)  { log_str("USB: dispositivo "); log_dec(daddr); log_str(" quitado\n"); }

void tuh_hid_mount_cb(uint8_t dev, uint8_t idx, const uint8_t *desc_report, uint16_t desc_len)
{
    u8 proto = tuh_hid_interface_protocol(dev, idx);
    log_str("HID "); log_dec(dev); log_str("/"); log_dec(idx); log_str(": ");
    log_str(proto == HID_ITF_PROTOCOL_KEYBOARD ? "teclado" : proto == HID_ITF_PROTOCOL_MOUSE ? "raton" : "generico");
    if (proto == HID_ITF_PROTOCOL_KEYBOARD) usb_n_kbd++;
    else if (proto == HID_ITF_PROTOCOL_MOUSE) usb_n_mouse++;
    if (proto == HID_ITF_PROTOCOL_NONE) {                    /* mando? (descriptor: ejes/hat/botones) */
        int pl = hid_pad_mount(dev, idx, desc_report, desc_len);
        if (pl >= 0) { usb_n_pad++; log_str(" -> mando jugador "); log_dec((u32)pl + 1u); }
        else log_str(" (sin ejes ni botones, o ya hay 2 mandos)");
        /* DualShock 4 y sus clones (054C:05C4/09CC): muchos no transmiten hasta que el host
         * lee el informe de calibracion (feature 0x02, 37 B) */
        if (pl >= 0) {
            uint16_t vid = 0, pid = 0;
            tuh_vid_pid_get(dev, &vid, &pid);
            if (vid == 0x054Cu) {
                static u8 ds4_feat[64];
                log_str(" [DS4: pido feature 02]");
                if (!tuh_hid_get_report(dev, idx, 0x02, HID_REPORT_TYPE_FEATURE, ds4_feat, 37)) log_str(" (fallo)");
            }
        }
    }
    log_str("\n");
    if (!tuh_hid_receive_report(dev, idx)) log_str("HID: no se pudo pedir el primer informe\n");
}

void tuh_hid_get_report_complete_cb(uint8_t dev, uint8_t idx, uint8_t report_id, uint8_t report_type, uint16_t len)
{
    (void)report_type;
    log_str("HID "); log_dec(dev); log_str("/"); log_dec(idx); log_str(": feature "); log_hex(report_id);
    log_str(" recibido, "); log_dec(len); log_str(" B\n");
    tuh_hid_receive_report(dev, idx);                        /* por si el IN no estaba en vuelo */
}

void tuh_hid_umount_cb(uint8_t dev, uint8_t idx)
{
    int pl;
    u8 proto = tuh_hid_interface_protocol(dev, idx);
    if (proto == HID_ITF_PROTOCOL_KEYBOARD && usb_n_kbd) usb_n_kbd--;
    else if (proto == HID_ITF_PROTOCOL_MOUSE && usb_n_mouse) usb_n_mouse--;
    for (int k = 0; k < MAX_KBD; k++) if (kbd[k].used && kbd[k].dev == dev && kbd[k].idx == idx) { kbd[k].used = 0; mbox_kbd_flush(); }
    if ((pl = hid_pad_umount(dev, idx)) >= 0) { joy[pl] = 0; mbox_misc_flush(); if (usb_n_pad) usb_n_pad--; }
    log_str("HID "); log_dec(dev); log_str("/"); log_dec(idx); log_str(" quitado\n");
}

void tuh_hid_report_received_cb(uint8_t dev, uint8_t idx, const uint8_t *report, uint16_t len)
{
    u8 proto = tuh_hid_interface_protocol(dev, idx);
    usb_stats_reports++;
    if (proto == HID_ITF_PROTOCOL_KEYBOARD && len >= 8) on_keyboard(dev, idx, (const hid_keyboard_report_t *)report);
    else if (proto == HID_ITF_PROTOCOL_MOUSE && len >= 3) on_mouse((const hid_mouse_report_t *)report);
    else {                                                   /* generico: mando (hid_pad.c) */
        uint16_t w; int pl = hid_pad_report(dev, idx, report, len, &w);
        if (pl >= 0 && joy[pl] != w) { joy[pl] = w; mbox_misc_flush(); }
    }
    tuh_hid_receive_report(dev, idx);
}

/* ---------------- mandos XInput (Xbox y genericos con dongle: clase 0xFF, no HID) ----------------
 * Driver de clase de Ryzee119/tusb_xinput (xinput/, MIT). TinyUSB pide los drivers extra
 * con usbh_app_driver_get_cb. Misma palabra SNES que hid_pad.c; jugador = primer hueco. */
#include "xinput_host.h"
#define XI_TRACE 0                                           /* 1 = volcar el paquete crudo al anillo cada ~1 s */

usbh_class_driver_t const *usbh_app_driver_get_cb(uint8_t *driver_count)
{
    *driver_count = 1;
    return &usbh_xinput_driver;
}

static struct { u8 used, dev, inst; } xi[2];

static u16 xinput_to_snes(const xinput_gamepad_t *p)
{
    u16 b = p->wButtons, w = 0;
    if ((b & XINPUT_GAMEPAD_DPAD_UP)    || p->sThumbLY >  16000) w |= 1u << 4;
    if ((b & XINPUT_GAMEPAD_DPAD_DOWN)  || p->sThumbLY < -16000) w |= 1u << 5;
    if ((b & XINPUT_GAMEPAD_DPAD_LEFT)  || p->sThumbLX < -16000) w |= 1u << 6;
    if ((b & XINPUT_GAMEPAD_DPAD_RIGHT) || p->sThumbLX >  16000) w |= 1u << 7;
    if (b & XINPUT_GAMEPAD_A)              w |= 1u << 8;
    if (b & XINPUT_GAMEPAD_B)              w |= 1u << 0;
    if (b & XINPUT_GAMEPAD_X)              w |= 1u << 9;
    if (b & XINPUT_GAMEPAD_Y)              w |= 1u << 1;
    if (b & XINPUT_GAMEPAD_LEFT_SHOULDER)  w |= 1u << 10;
    if (b & XINPUT_GAMEPAD_RIGHT_SHOULDER) w |= 1u << 11;
    if (b & XINPUT_GAMEPAD_BACK)           w |= 1u << 2;
    if (b & XINPUT_GAMEPAD_START)          w |= 1u << 3;
    return w;
}

static int xi_find(u8 dev, u8 inst)
{
    for (int k = 0; k < 2; k++) if (xi[k].used && xi[k].dev == dev && xi[k].inst == inst) return k;
    return -1;
}

void tuh_xinput_mount_cb(uint8_t dev, uint8_t inst, const xinputh_interface_t *itf)
{
    int k = -1;
    for (int i = 0; i < 2; i++) if (!xi[i].used) { k = i; break; }
    log_str("XInput "); log_dec(dev); log_str("/"); log_dec(inst); log_str(" tipo "); log_dec(itf->type);
    if (k < 0) { log_str(": ya hay 2 mandos\n"); return; }
    xi[k].used = 1; xi[k].dev = dev; xi[k].inst = inst;
    usb_n_pad++;
    log_str(" -> mando jugador "); log_dec((u32)k + 1u); log_str("\n");
    tuh_xinput_set_led(dev, inst, (uint8_t)(k + 1), false);
    tuh_xinput_receive_report(dev, inst);
}

void tuh_xinput_umount_cb(uint8_t dev, uint8_t inst)
{
    int k = xi_find(dev, inst);
    if (k >= 0) { xi[k].used = 0; joy[k] = 0; mbox_misc_flush(); if (usb_n_pad) usb_n_pad--; }
    log_str("XInput "); log_dec(dev); log_str("/"); log_dec(inst); log_str(" quitado\n");
}

void tuh_xinput_report_received_cb(uint8_t dev, uint8_t inst, xinputh_interface_t const *itf, uint16_t len)
{
    (void)len;
    static u32 dbg_n;
    int k = xi_find(dev, inst);
    usb_stats_reports++;
    if (k >= 0 && itf->connected && itf->new_pad_data) {
        u16 w = xinput_to_snes(&itf->pad);
        if (joy[k] != w) { joy[k] = w; mbox_misc_flush(); }
    }
    if (XI_TRACE && (++dbg_n % 500u) == 0u) {                /* traza de bring-up: estado crudo cada ~1 s */
        log_str("XI con="); log_dec(itf->connected); log_str(" new="); log_dec(itf->new_pad_data);
        log_str(" btn="); log_hex(itf->pad.wButtons); log_str(" LX="); log_dec((u32)(u16)itf->pad.sThumbLX);
        log_str(" LY="); log_dec((u32)(u16)itf->pad.sThumbLY); log_str(" len="); log_dec(len); log_str(" raw=");
        for (int i = 0; i < 12; i++) { log_hex(itf->epin_buf[i] | 0x100u); log_str(" "); }   /* 1xx = byte */
        log_str("\n");
    }
    tuh_xinput_receive_report(dev, inst);
}

/* ---------------- API para main ---------------- */
int usb_host_init(void)
{
    for (int w = 0; w < 7; w++) mbox[w] = 0;
    phy_reset();
    tuh_hid_set_default_protocol(HID_PROTOCOL_BOOT);
    tusb_rhport_init_t rh = { .role = TUSB_ROLE_HOST, .speed = TUSB_SPEED_AUTO };
    if (!tusb_rhport_init(0, &rh)) { log_str("USB: tusb_rhport_init FALLO\n"); return 0; }
    log_str("USB host: OK (PORTSC "); log_hex(USB0_PORTSC); log_str(")\n");
    return 1;
}

void usb_host_poll(void)
{
    tuh_int_handler(0, false);
    tuh_task_ext(0, false);
}
