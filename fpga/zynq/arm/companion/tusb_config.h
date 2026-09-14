/* tusb_config.h — TinyUSB como HOST en el Zynq-7000 (companion del MSXimus):
 * hub + HID (teclado, raton, mandos). Sin OS, sin caches (memoria coherente). */
#ifndef TUSB_CONFIG_H_
#define TUSB_CONFIG_H_

#define CFG_TUSB_MCU              OPT_MCU_NONE
/* lo que tusb_mcu.h definiria para un MCU conocido con ChipIdea/EHCI */
#define TUP_USBIP_CHIPIDEA_HS
#define TUP_USBIP_EHCI
#define TUP_RHPORT_HIGHSPEED      1
#define TUP_DCD_ENDPOINT_MAX      12

#define CFG_TUSB_OS               OPT_OS_NONE
#define CFG_TUSB_DEBUG            0
#define CFG_TUSB_MEM_SECTION
#define CFG_TUSB_MEM_ALIGN        __attribute__ ((aligned(32)))
#define CFG_TUH_MEM_SECTION
#define CFG_TUH_MEM_ALIGN         __attribute__ ((aligned(32)))
#define CFG_TUH_MEM_DCACHE_ENABLE 0

#define CFG_TUH_ENABLED           1
#define CFG_TUH_MAX_SPEED         OPT_MODE_HIGH_SPEED
#define CFG_TUH_ENUMERATION_BUFSIZE 256
#define CFG_TUH_HUB               1
#define CFG_TUH_DEVICE_MAX        (3 * CFG_TUH_HUB + 1)
#define CFG_TUH_HID               (3 * CFG_TUH_DEVICE_MAX)
#define CFG_TUH_HID_EPIN_BUFSIZE  64
#define CFG_TUH_HID_EPOUT_BUFSIZE 64
#define CFG_TUH_CDC               0
#define CFG_TUH_MSC               0
#define CFG_TUH_VENDOR            0

#endif
