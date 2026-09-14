// ============================================================================
//  gowin_prims.v — primitivas de Gowin que el RTL compartido instancia por su
//  nombre, envueltas sobre su equivalente Xilinx. Asi los fuentes de fpga/src,
//  video720... no llevan `ifdef por fabricante para estas piezas.
//
//  ELVDS_OBUF: buffer diferencial de salida (TMDS del HDMI en msx2hdmi_*.sv).
//              El IOSTANDARD real (TMDS_33) lo fija top_zynq.xdc en los pads.
// ============================================================================
module ELVDS_OBUF (
    input  wire I,
    output wire O,
    output wire OB
);
    OBUFDS u_obufds (.I(I), .O(O), .OB(OB));
endmodule
