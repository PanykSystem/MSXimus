// ============================================================================
//  hp_bench_top.v — Banco de pruebas del HP0: latencias y ancho de banda,
//  tabla de resultados en la DDR (0x1F000000) para leerla con xsdb. Sin codigo ARM: el PS se inicializa con ps7_init.tcl desde
//  xsdb (relojes, MIO, DDR) y ps7_post_config libera FCLK_RESET0_N.
//
//  LEDs: benchmark en curso (0..6 en binario); 1111 = tabla escrita.
// ============================================================================
module hp_bench_top #(parameter FCLK_MHZ = 100) (
    // Pines dedicados del PS: DDR3 + MIO (inout, sin .xdc)
    inout  wire [14:0] DDR_addr,
    inout  wire [2:0]  DDR_ba,
    inout  wire        DDR_cas_n,
    inout  wire        DDR_ck_n,
    inout  wire        DDR_ck_p,
    inout  wire        DDR_cke,
    inout  wire        DDR_cs_n,
    inout  wire [1:0]  DDR_dm,
    inout  wire [15:0] DDR_dq,
    inout  wire [1:0]  DDR_dqs_n,
    inout  wire [1:0]  DDR_dqs_p,
    inout  wire        DDR_odt,
    inout  wire        DDR_ras_n,
    inout  wire        DDR_reset_n,
    inout  wire        DDR_we_n,
    inout  wire        FIXED_IO_ddr_vrn,
    inout  wire        FIXED_IO_ddr_vrp,
    inout  wire [53:0] FIXED_IO_mio,
    inout  wire        FIXED_IO_ps_clk,
    inout  wire        FIXED_IO_ps_porb,
    inout  wire        FIXED_IO_ps_srstb,

    output wire [3:0]  led
);

    wire        fclk0;
    wire        frst0_n;

    // ---- AXI3 HP0 ----
    wire [5:0]  hp0_awid;    wire [31:0] hp0_awaddr;  wire [3:0] hp0_awlen;
    wire [2:0]  hp0_awsize;  wire [1:0]  hp0_awburst; wire [1:0] hp0_awlock;
    wire [3:0]  hp0_awcache; wire [2:0]  hp0_awprot;  wire [3:0] hp0_awqos;
    wire        hp0_awvalid, hp0_awready;
    wire [5:0]  hp0_wid;     wire [63:0] hp0_wdata;   wire [7:0] hp0_wstrb;
    wire        hp0_wlast, hp0_wvalid, hp0_wready;
    wire [5:0]  hp0_bid;     wire [1:0]  hp0_bresp;   wire hp0_bvalid, hp0_bready;
    wire [5:0]  hp0_arid;    wire [31:0] hp0_araddr;  wire [3:0] hp0_arlen;
    wire [2:0]  hp0_arsize;  wire [1:0]  hp0_arburst; wire [1:0] hp0_arlock;
    wire [3:0]  hp0_arcache; wire [2:0]  hp0_arprot;  wire [3:0] hp0_arqos;
    wire        hp0_arvalid, hp0_arready;
    wire [5:0]  hp0_rid;     wire [63:0] hp0_rdata;   wire [1:0] hp0_rresp;
    wire        hp0_rlast, hp0_rvalid, hp0_rready;

    ps7_bd_wrapper ps7 (
        .DDR_addr(DDR_addr), .DDR_ba(DDR_ba), .DDR_cas_n(DDR_cas_n),
        .DDR_ck_n(DDR_ck_n), .DDR_ck_p(DDR_ck_p), .DDR_cke(DDR_cke),
        .DDR_cs_n(DDR_cs_n), .DDR_dm(DDR_dm), .DDR_dq(DDR_dq),
        .DDR_dqs_n(DDR_dqs_n), .DDR_dqs_p(DDR_dqs_p), .DDR_odt(DDR_odt),
        .DDR_ras_n(DDR_ras_n), .DDR_reset_n(DDR_reset_n), .DDR_we_n(DDR_we_n),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn), .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio(FIXED_IO_mio), .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb), .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),

        .FCLK_CLK0(fclk0),
        .FCLK_RESET0_N(frst0_n),

        .S_AXI_HP0_awid(hp0_awid),       .S_AXI_HP0_awaddr(hp0_awaddr),
        .S_AXI_HP0_awlen(hp0_awlen),     .S_AXI_HP0_awsize(hp0_awsize),
        .S_AXI_HP0_awburst(hp0_awburst), .S_AXI_HP0_awlock(hp0_awlock),
        .S_AXI_HP0_awcache(hp0_awcache), .S_AXI_HP0_awprot(hp0_awprot),
        .S_AXI_HP0_awqos(hp0_awqos),     .S_AXI_HP0_awvalid(hp0_awvalid),
        .S_AXI_HP0_awready(hp0_awready),
        .S_AXI_HP0_wid(hp0_wid),         .S_AXI_HP0_wdata(hp0_wdata),
        .S_AXI_HP0_wstrb(hp0_wstrb),     .S_AXI_HP0_wlast(hp0_wlast),
        .S_AXI_HP0_wvalid(hp0_wvalid),   .S_AXI_HP0_wready(hp0_wready),
        .S_AXI_HP0_bid(hp0_bid),         .S_AXI_HP0_bresp(hp0_bresp),
        .S_AXI_HP0_bvalid(hp0_bvalid),   .S_AXI_HP0_bready(hp0_bready),
        .S_AXI_HP0_arid(hp0_arid),       .S_AXI_HP0_araddr(hp0_araddr),
        .S_AXI_HP0_arlen(hp0_arlen),     .S_AXI_HP0_arsize(hp0_arsize),
        .S_AXI_HP0_arburst(hp0_arburst), .S_AXI_HP0_arlock(hp0_arlock),
        .S_AXI_HP0_arcache(hp0_arcache), .S_AXI_HP0_arprot(hp0_arprot),
        .S_AXI_HP0_arqos(hp0_arqos),     .S_AXI_HP0_arvalid(hp0_arvalid),
        .S_AXI_HP0_arready(hp0_arready),
        .S_AXI_HP0_rid(hp0_rid),         .S_AXI_HP0_rdata(hp0_rdata),
        .S_AXI_HP0_rresp(hp0_rresp),     .S_AXI_HP0_rlast(hp0_rlast),
        .S_AXI_HP0_rvalid(hp0_rvalid),   .S_AXI_HP0_rready(hp0_rready)
    );

    wire done;
    axi_hp_bench #(.BASE(32'h1000_0000), .RESULT(32'h1F00_0000), .FCLK_MHZ(FCLK_MHZ)) bench (
        .ACLK(fclk0), .ARESETN(frst0_n),
        .M_AWID(hp0_awid), .M_AWADDR(hp0_awaddr), .M_AWLEN(hp0_awlen),
        .M_AWSIZE(hp0_awsize), .M_AWBURST(hp0_awburst), .M_AWLOCK(hp0_awlock),
        .M_AWCACHE(hp0_awcache), .M_AWPROT(hp0_awprot), .M_AWQOS(hp0_awqos),
        .M_AWVALID(hp0_awvalid), .M_AWREADY(hp0_awready),
        .M_WID(hp0_wid), .M_WDATA(hp0_wdata), .M_WSTRB(hp0_wstrb),
        .M_WLAST(hp0_wlast), .M_WVALID(hp0_wvalid), .M_WREADY(hp0_wready),
        .M_BID(hp0_bid), .M_BRESP(hp0_bresp), .M_BVALID(hp0_bvalid), .M_BREADY(hp0_bready),
        .M_ARID(hp0_arid), .M_ARADDR(hp0_araddr), .M_ARLEN(hp0_arlen),
        .M_ARSIZE(hp0_arsize), .M_ARBURST(hp0_arburst), .M_ARLOCK(hp0_arlock),
        .M_ARCACHE(hp0_arcache), .M_ARPROT(hp0_arprot), .M_ARQOS(hp0_arqos),
        .M_ARVALID(hp0_arvalid), .M_ARREADY(hp0_arready),
        .M_RID(hp0_rid), .M_RDATA(hp0_rdata), .M_RRESP(hp0_rresp),
        .M_RLAST(hp0_rlast), .M_RVALID(hp0_rvalid), .M_RREADY(hp0_rready),
        .led(led), .done(done)
    );

endmodule
