/* ci_hs_zynq.h — TinyUSB: controlador USB0 del Zynq-7000 (ChipIdea, ULPI) para el
 * companion del MSXimus. Se incluye desde hcd_ci_hs.c con -DCI_HS_ZYNQ7000.
 *   USB0 base 0xE0002000; "ci_hs_regs_t" arranca en la BASE del controlador (ID en +0,
 *   SBUSCFG +0x90, CAPLENGTH +0x100, USBCMD +0x140). Con +0x100 el primer acceso a
 *   USBCMD caia en 0xE0002240 -> data abort (medido con tools/armpc.tcl).
 *   Sin interrupciones: el bucle principal llama a tuh_int_handler() (sondeo).
 *   CI_HS_SET_AHB_BURST es el gancho que hcd_init llama tras el reset del
 *   controlador y USBMODE=host, justo antes de ehci_init: ahi ponemos el puerto
 *   en ULPI y encendemos el VBUS externo del PHY (CPEN -> Q3/Q4 -> 5 V del USB-C). */
#ifndef CI_HS_ZYNQ_H_
#define CI_HS_ZYNQ_H_
#include "portable/chipidea/ci_hs/ci_hs_type.h"

#define ZYNQ_USB0_BASE      0xE0002000u
#define CI_HS_REG(_port)    ((ci_hs_regs_t *)ZYNQ_USB0_BASE)
#define CI_HCD_INT_ENABLE(_p)   do { (void)(_p); } while (0)
#define CI_HCD_INT_DISABLE(_p)  do { (void)(_p); } while (0)
#define CI_DCD_INT_ENABLE(_p)   do { (void)(_p); } while (0)
#define CI_DCD_INT_DISABLE(_p)  do { (void)(_p); } while (0)

void zynq_usb_pre_ehci(void);                 /* usb_host.c */
#define CI_HS_SET_AHB_BURST(_p) zynq_usb_pre_ehci()

#endif
