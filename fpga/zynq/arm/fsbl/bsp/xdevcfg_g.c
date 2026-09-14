/* xdevcfg_g.c — tabla de configuracion del DevCfg (PCAP), a mano */
#include "xparameters.h"
#include "xdevcfg.h"

XDcfg_Config XDcfg_ConfigTable[XPAR_XDCFG_NUM_INSTANCES] = {
    { XPAR_XDCFG_0_DEVICE_ID, XPAR_XDCFG_0_BASEADDR }
};
