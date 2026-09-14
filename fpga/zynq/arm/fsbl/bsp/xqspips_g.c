/* xqspips_g.c — tabla de configuracion del QSPI, a mano */
#include "xparameters.h"
#include "xqspips.h"

XQspiPs_Config XQspiPs_ConfigTable[XPAR_XQSPIPS_NUM_INSTANCES] = {
    { XPAR_XQSPIPS_0_DEVICE_ID, XPAR_XQSPIPS_0_BASEADDR, XPAR_XQSPIPS_0_QSPI_CLK_FREQ_HZ, XPAR_XQSPIPS_0_QSPI_MODE }
};
