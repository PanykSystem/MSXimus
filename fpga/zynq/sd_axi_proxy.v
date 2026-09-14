// ============================================================================
//  sd_axi_proxy.v — la "SD" del MSXimus en la ZYNQ MINI: proxy de sectores
// ----------------------------------------------------------------------------
//  Sustituto de sd_reader (src/wondertang/sd_reader.sv) con LA MISMA interfaz de
//  cliente: sdc_ioport / sd_dma / top.v no se tocan. La placa no tiene microSD en
//  el PL (TF1 = SD0 y TF2 = SD1 cuelgan del PS), asi que los sectores vienen de
//  la DDR del PS en uno de dos modos, elegido en caliente por la palabra MODE:
//
//    MODE 0 (imagen): el PL lee/escribe directamente una imagen de disco que
//      xsdb cargo en DISK_BASE (tools/boot.tcl <pack> <bit> <imagen>). Sin ARM.
//    MODE 1 (proxy):  por cada orden el PL deja una peticion en SDBOX, avisa al
//      ARM (req_irq -> IRQ_F2P) y espera el acuse; el ARM hace el acceso REAL a
//      la tarjeta (TF1/TF2, driver xsdps) sobre SDBUF. Tiempo real, escrituras
//      write-through a la tarjeta, cambio en caliente (palabra CARD).
//
//  Buzon SDBOX (palabras de 64 bits, little-endian, direccion DDR):
//    +0x00  W0: [0] MODE (1 = proxy)   [32] CARD presente   [63:48] CARD tamano (MB)
//    +0x08  W1: [31:0] REQ_SEQ  [39:32] REQ_OP (1 lee, 2 escribe)  [47:40] REQ_COUNT
//    +0x10  W2: [31:0] REQ_SECTOR
//    +0x18  W3: [31:0] ACK_SEQ  [63:32] ACK_STATUS (0 = OK)          (escribe el ARM)
//  Datos: SDBUF + n*512, n = bloque 0..count-1 de la orden (lectura: los deja el
//  ARM antes del acuse; escritura: los deja el PL antes de la peticion).
//
//  Protocolo de cliente clonado de sd_reader (V3.5c multibloque):
//    init (solo en STANDBY) -> IDLING, card_type SDHCv2, CSD 2.0 sintetico.
//    rstart: por bloque 512 pulsos outen (outaddr arranca en 511 y se incrementa
//      ANTES de cada pulso) con outbyte; entre bloques blk_rdy=1 hasta buf_ack;
//      al final rdone (3 ciclos; el top usa el flanco).
//    wstart: por bloque 512 pulsos outen con outaddr=k ("dame el byte k"); el
//      host (dpram) presenta inbyte=buf[k] al ciclo siguiente.
//    card_stat = estado[3:0] con la numeracion de sd_reader (STANDBY=2, IDLING=1,
//      READING2=14, WRITING2=0). Errores: timeout_error (sin tarjeta, sin acuse
//      del ARM en ACK_TIMEOUT, o estado != 0 del ARM).
//  AXI3 master de 64 bits (rafagas de hasta 16 beats); drena B/R en reset.
// ============================================================================
module sd_axi_proxy #(
    parameter [31:0] DISK_BASE   = 32'h1100_0000,   // imagen (modo 0)
    parameter [31:0] DISK_MB     = 32'd224,         // ventana de la imagen (MB)
    parameter [31:0] SDBOX       = 32'h1FF0_0100,   // buzon de peticiones
    parameter [31:0] SDBUF       = 32'h1FF1_0000,   // datos (255 x 512 B max)
    parameter [3:0]  BYTE_GAP    = 4'd7,            // lectura: un byte cada BYTE_GAP+1 ciclos
    parameter [25:0] ACK_TIMEOUT = 26'd54_000_000   // 2 s a 27 MHz sin acuse del ARM
)(
    input  wire        rstn,                        // bus_reset_n
    input  wire        clk,                         // clk_27m (el de sd_reader)
    output wire [3:0]  card_stat,
    output reg  [1:0]  card_type,
    input  wire        rstart,
    input  wire [31:0] rsector,
    output wire        rbusy,
    output wire        rdone,
    output reg         outen,
    output reg  [8:0]  outaddr,
    output reg  [7:0]  outbyte,
    input  wire        wstart,
    input  wire [7:0]  inbyte,
    output reg  [21:0] c_size,
    output reg  [2:0]  c_size_mult,
    output reg  [3:0]  read_bl_len,
    output reg  [7:0]  mid,
    output reg  [15:0] oid,
    output reg  [39:0] pnm,
    output reg  [31:0] psn,
    output reg         crc_error,
    output reg         rcrc_error,
    output reg         timeout_error,
    input  wire        init,
    input  wire [7:0]  rcount,
    input  wire        buf_ack,
    output reg         blk_rdy,
    output reg         req_irq,                     // peticion pendiente (IRQ_F2P del PS)
    output reg         mode,                        // 0 imagen, 1 proxy (leido de SDBOX)
    output reg  [15:0] dbg_blocks,                  // ordenes servidas

    // ---- AXI3 master hacia S_AXI_HPx (64 bits), ACLK = clk ----
    input  wire        aresetn,
    output reg  [5:0]  M_AWID,
    output reg  [31:0] M_AWADDR,
    output reg  [3:0]  M_AWLEN,
    output wire [2:0]  M_AWSIZE,
    output wire [1:0]  M_AWBURST,
    output wire [1:0]  M_AWLOCK,
    output wire [3:0]  M_AWCACHE,
    output wire [2:0]  M_AWPROT,
    output wire [3:0]  M_AWQOS,
    output reg         M_AWVALID,
    input  wire        M_AWREADY,
    output reg  [5:0]  M_WID,
    output reg  [63:0] M_WDATA,
    output wire [7:0]  M_WSTRB,
    output reg         M_WLAST,
    output reg         M_WVALID,
    input  wire        M_WREADY,
    input  wire [5:0]  M_BID,
    input  wire [1:0]  M_BRESP,
    input  wire        M_BVALID,
    output reg         M_BREADY,
    output reg  [5:0]  M_ARID,
    output reg  [31:0] M_ARADDR,
    output reg  [3:0]  M_ARLEN,
    output wire [2:0]  M_ARSIZE,
    output wire [1:0]  M_ARBURST,
    output wire [1:0]  M_ARLOCK,
    output wire [3:0]  M_ARCACHE,
    output wire [2:0]  M_ARPROT,
    output wire [3:0]  M_ARQOS,
    output reg         M_ARVALID,
    input  wire        M_ARREADY,
    input  wire [5:0]  M_RID,
    input  wire [63:0] M_RDATA,
    input  wire [1:0]  M_RRESP,
    input  wire        M_RLAST,
    input  wire        M_RVALID,
    output reg         M_RREADY
);
    assign M_AWSIZE = 3'b011; assign M_AWBURST = 2'b01; assign M_AWLOCK = 2'b00;
    assign M_AWCACHE = 4'b0011; assign M_AWPROT = 3'b000; assign M_AWQOS = 4'd0;
    assign M_WSTRB = 8'hFF;
    assign M_ARSIZE = 3'b011; assign M_ARBURST = 2'b01; assign M_ARLOCK = 2'b00;
    assign M_ARCACHE = 4'b0011; assign M_ARPROT = 3'b000; assign M_ARQOS = 4'd0;

    // ---- estados visibles (numeracion de sd_reader) ----
    localparam [4:0] S_STANDBY = 5'd18, S_IDLE = 5'd17, S_READING2 = 5'd14, S_WRITING2 = 5'd16;
    // ---- fases de la orden ----
    localparam [3:0] P_IDLE = 4'd0,  P_MB0 = 4'd1,  P_REQ = 4'd2,  P_ACKW = 4'd3,  P_RD_GO = 4'd4,
                     P_RD_W = 4'd5,  P_RD_STREAM = 4'd6, P_RD_LAST = 4'd7, P_RD_HOLD = 4'd8,
                     P_WR_COLLECT = 4'd9, P_WR_GO = 4'd10, P_WR_W = 4'd11, P_WR_LAST = 4'd12,
                     P_WR_HOLD = 4'd13, P_DONE = 4'd14;
    // ---- motor AXI (una rafaga por orden) ----
    localparam [2:0] E_IDLE = 3'd0, E_R = 3'd1, E_W = 3'd2, E_B = 3'd3;

    reg [4:0]  stat;
    reg [3:0]  ph;
    reg        op_wr, multi, idle_poll;
    reg [31:0] sector, req_sector;
    reg [7:0]  blocks_left, req_count, blk_idx;
    reg [1:0]  burst;
    reg [3:0]  beat;
    reg [63:0] lbuf [0:63];                          // el bloque de 512 B
    reg [8:0]  k;
    reg [3:0]  gap;
    reg [1:0]  sub;
    reg [63:0] wshift;
    reg [1:0]  done_cnt;
    reg        card_present;
    reg [15:0] card_mb;
    reg [31:0] req_seq;
    reg [25:0] ack_to;
    reg [19:0] poll_cnt;
    // motor
    reg [2:0]  ax;
    reg        ax_go, ax_wr, ax_mb, ax_done, aw_done, polling;
    reg [31:0] ax_addr;
    reg [3:0]  ax_len;
    reg [63:0] mb_q0, mb_q1, mb_d0, mb_d1;

    wire aw_acc = M_AWVALID && M_AWREADY;
    wire w_acc  = M_WVALID  && M_WREADY;
    wire b_acc  = M_BVALID  && M_BREADY;
    wire ar_acc = M_ARVALID && M_ARREADY;
    wire r_acc  = M_RVALID  && M_RREADY;
    wire in_range = mode || (sector < (DISK_MB << 11));
    wire [31:0] blk_base = mode ? (SDBUF + {15'd0, blk_idx, 9'b0}) : (DISK_BASE + {sector[22:0], 9'b0});
    wire [31:0] blk_addr = blk_base + {23'd0, burst, 7'b0};
    // lbuf con UN puerto de lectura (direccion registrada lb_ra, dato asincrono
    // lb_q) y UN puerto de escritura registrado: se infiere como LUTRAM. Con tres
    // lecturas de direcciones distintas Vivado lo hacia con 4096 FF + muxes (+16 k LUT).
    reg  [5:0]  lb_ra;
    reg         lb_we;
    reg  [5:0]  lb_wa;
    reg  [63:0] lb_wd;
    wire [63:0] lb_q = lbuf[lb_ra];
    always @(posedge clk) if (lb_we) lbuf[lb_wa] <= lb_wd;
    wire [63:0] rd_word  = lb_q;                       // stream: lb_ra = k[8:3]
    wire [63:0] wdata_first = ax_mb ? mb_d0 : lb_q;    // go: lb_ra = {burst, 0}
    wire [3:0]  beat_n = beat + 4'd1;
    wire [63:0] wdata_next  = ax_mb ? mb_d1 : lb_q;    // w_acc: lb_ra ya apunta al beat+1

    assign card_stat = stat[3:0];
    assign rbusy     = (stat != S_IDLE);
    assign rdone     = (ph == P_DONE);

    always @(posedge clk) begin
        if (!rstn || !aresetn) begin
            stat <= S_STANDBY; ph <= P_IDLE; card_type <= 2'd0;
            outen <= 1'b0; outaddr <= 9'd0; outbyte <= 8'd0; blk_rdy <= 1'b0; req_irq <= 1'b0; mode <= 1'b0;
            c_size <= 22'd0; c_size_mult <= 3'd0; read_bl_len <= 4'd0;
            mid <= 8'd0; oid <= 16'h2020; pnm <= 40'h2020202020; psn <= 32'd0;
            crc_error <= 1'b0; rcrc_error <= 1'b0; timeout_error <= 1'b0;
            op_wr <= 1'b0; multi <= 1'b0; idle_poll <= 1'b0; sector <= 32'd0; req_sector <= 32'd0;
            blocks_left <= 8'd0; req_count <= 8'd0; blk_idx <= 8'd0; burst <= 2'd0; beat <= 4'd0;
            k <= 9'd0; gap <= 4'd0; sub <= 2'd0; wshift <= 64'd0; done_cnt <= 2'd0;
            card_present <= 1'b0; card_mb <= 16'd0; req_seq <= 32'd0; ack_to <= 26'd0; poll_cnt <= 20'd0;
            dbg_blocks <= 16'd0;
            ax <= E_IDLE; ax_go <= 1'b0; ax_wr <= 1'b0; ax_mb <= 1'b0; ax_done <= 1'b0; aw_done <= 1'b0; polling <= 1'b0;
            lb_ra <= 6'd0; lb_we <= 1'b0; lb_wa <= 6'd0; lb_wd <= 64'd0;
            ax_addr <= 32'd0; ax_len <= 4'd0; mb_q0 <= 64'd0; mb_q1 <= 64'd0; mb_d0 <= 64'd0; mb_d1 <= 64'd0;
            M_AWVALID <= 1'b0; M_WVALID <= 1'b0; M_ARVALID <= 1'b0; M_WLAST <= 1'b0;
            M_AWID <= 6'd0; M_WID <= 6'd0; M_ARID <= 6'd0; M_AWLEN <= 4'd0; M_ARLEN <= 4'd0;
            M_AWADDR <= 32'd0; M_ARADDR <= 32'd0; M_WDATA <= 64'd0;
            M_BREADY <= 1'b1; M_RREADY <= 1'b1;                    // drenar herencias del HP
        end else begin
            outen <= 1'b0; lb_we <= 1'b0;
            ax_done <= 1'b0;                 // PULSO de un ciclo (14/09: como nivel, la FSM lo veia
                                             // aun a 1 tras relanzar el motor y saltaba rafagas)
            M_BREADY <= 1'b1; M_RREADY <= 1'b1;
            poll_cnt <= poll_cnt + 20'd1;
            if (aw_acc) begin M_AWVALID <= 1'b0; aw_done <= 1'b1; end
            if (ar_acc) M_ARVALID <= 1'b0;

            // ================= motor AXI =================
            case (ax)
            E_IDLE: if (ax_go) begin
                ax_go <= 1'b0; beat <= 4'd0;
                if (ax_wr) begin
                    M_AWADDR <= ax_addr; M_AWLEN <= ax_len; M_AWID <= 6'd0; M_WID <= 6'd0;
                    M_AWVALID <= 1'b1; aw_done <= 1'b0;
                    M_WDATA <= wdata_first; M_WLAST <= (ax_len == 4'd0); M_WVALID <= 1'b1;
                    lb_ra <= {burst, 4'd1};                                    // siguiente beat
                    ax <= E_W;
                end else begin
                    M_ARADDR <= ax_addr; M_ARLEN <= ax_len; M_ARID <= 6'd0; M_ARVALID <= 1'b1;
                    ax <= E_R;
                end
            end
            E_R: if (r_acc) begin
                if (ax_mb) begin if (beat == 4'd0) mb_q0 <= M_RDATA; else mb_q1 <= M_RDATA; end
                else begin lb_we <= 1'b1; lb_wa <= {burst, beat}; lb_wd <= M_RDATA; end
                beat <= beat_n;
                if (M_RLAST) begin ax <= E_IDLE; ax_done <= 1'b1; end
            end
            E_W: if (w_acc) begin
                if (beat == ax_len) begin M_WVALID <= 1'b0; M_WLAST <= 1'b0; ax <= E_B; end
                else begin
                    beat <= beat_n; M_WDATA <= wdata_next; M_WLAST <= (beat_n == ax_len);
                    lb_ra <= {burst, beat_n + 4'd1};
                end
            end
            E_B: if (b_acc && (aw_done || aw_acc)) begin ax <= E_IDLE; ax_done <= 1'b1; end
            default: ax <= E_IDLE;
            endcase

            // ================= ordenes =================
            case (stat)
            S_STANDBY: if (init) begin
                stat <= S_IDLE; card_type <= 2'd3;                         // SDHCv2, CSD 2.0
                c_size <= (DISK_MB << 1) - 22'd1; c_size_mult <= 3'd2; read_bl_len <= 4'hF;
                mid <= 8'h5A; oid <= 16'h5A59; pnm <= 40'h4444525344; psn <= 32'h2026_0914;   // 'ZY' 'DDRSD'
            end
            default: case (ph)
            P_IDLE: begin
                blk_rdy <= 1'b0;
                if (stat == S_IDLE && (rstart || wstart)) begin
                    // busy=1 YA (como sd_reader: IDLING -> READING al ciclo siguiente). El
                    // menu y el driver confirman la orden leyendo busy justo tras el OUT.
                    stat <= rstart ? S_READING2 : S_WRITING2;
                    op_wr <= wstart && !rstart; multi <= (rcount > 8'd1);
                    sector <= rsector; req_sector <= rsector;
                    blocks_left <= (rcount == 8'd0) ? 8'd1 : rcount; req_count <= (rcount == 8'd0) ? 8'd1 : rcount;
                    blk_idx <= 8'd0; burst <= 2'd0;
                    crc_error <= 1'b0; rcrc_error <= 1'b0; timeout_error <= 1'b0;
                    idle_poll <= 1'b0;
                    ax_addr <= SDBOX; ax_len <= 4'd0; ax_wr <= 1'b0; ax_mb <= 1'b1; ax_go <= 1'b1;   // W0: modo/tarjeta
                    ph <= P_MB0;
                end else if (stat == S_IDLE && poll_cnt == 20'd0) begin                            // cambio en caliente (~39 ms)
                    idle_poll <= 1'b1;
                    ax_addr <= SDBOX; ax_len <= 4'd0; ax_wr <= 1'b0; ax_mb <= 1'b1; ax_go <= 1'b1;
                    ph <= P_MB0;
                end
            end
            P_MB0: if (ax_done) begin
                mode <= mb_q0[0]; card_present <= mb_q0[32]; card_mb <= mb_q0[63:48];
                if (mb_q0[0] && mb_q0[32]) c_size <= {card_mb_q(mb_q0[63:48]), 1'b0} - 22'd1;   // MB*2-1 (512 KB)
                if (idle_poll) ph <= P_IDLE;
                else begin
                    if (mb_q0[0] && !mb_q0[32]) begin timeout_error <= 1'b1; done_cnt <= 2'd0; ph <= P_DONE; end   // proxy sin tarjeta
                    else if (op_wr) begin outaddr <= 9'd0; k <= 9'd0; sub <= 2'd0; ph <= P_WR_COLLECT; end
                    else if (mb_q0[0]) begin                                                       // proxy: pedir la lectura
                        mb_d0 <= {16'd0, req_count, 8'd1, req_seq + 32'd1}; mb_d1 <= {32'd0, req_sector};
                        req_seq <= req_seq + 32'd1; req_irq <= 1'b1;
                        ax_addr <= SDBOX + 32'h8; ax_len <= 4'd1; ax_wr <= 1'b1; ax_mb <= 1'b1; ax_go <= 1'b1;
                        ph <= P_REQ;
                    end else begin outaddr <= 9'h1FF; ph <= P_RD_GO; end                            // imagen: directo
                end
            end
            P_REQ: if (ax_done) begin                                                              // peticion escrita: sondear el acuse
                ack_to <= 26'd0; gap <= 4'd0; polling <= 1'b1;
                ax_addr <= SDBOX + 32'h18; ax_len <= 4'd0; ax_wr <= 1'b0; ax_mb <= 1'b1; ax_go <= 1'b1;
                ph <= P_ACKW;
            end
            P_ACKW: begin                                                                          // ax_done es un PULSO: el re-sondeo
                ack_to <= ack_to + 26'd1;                                                          // y el timeout viven fuera del if
                if (ax_done) begin
                    polling <= 1'b0;
                    if (mb_q0[31:0] == req_seq) begin
                        req_irq <= 1'b0;
                        if (mb_q0[63:32] != 32'd0) begin timeout_error <= 1'b1; done_cnt <= 2'd0; ph <= P_DONE; end
                        else if (op_wr) begin done_cnt <= 2'd0; ph <= P_DONE; end
                        else begin outaddr <= 9'h1FF; burst <= 2'd0; ph <= P_RD_GO; end
                    end else gap <= 4'd0;                                                          // acuse viejo: esperar y re-sondear
                end else if (!polling) begin
                    if (ack_to >= ACK_TIMEOUT) begin
                        req_irq <= 1'b0; timeout_error <= 1'b1; done_cnt <= 2'd0; ph <= P_DONE;
                    end else if (gap == 4'hF) begin gap <= 4'd0; polling <= 1'b1; ax_go <= 1'b1; end
                    else gap <= gap + 4'd1;
                end
            end
            // ---------- lectura de un bloque: 4 rafagas DDR -> lbuf -> 512 bytes al host ----------
            P_RD_GO: begin
                if (!in_range) begin k <= 9'd0; gap <= 4'd0; ph <= P_RD_STREAM; end               // fuera de la imagen: sirve lo que haya
                else begin ax_addr <= blk_addr; ax_len <= 4'd15; ax_wr <= 1'b0; ax_mb <= 1'b0; ax_go <= 1'b1; ph <= P_RD_W; end
            end
            P_RD_W: if (ax_done) begin
                burst <= burst + 2'd1;
                if (burst == 2'd3) begin k <= 9'd0; gap <= 4'd0; ph <= P_RD_STREAM; end
                else ph <= P_RD_GO;
            end
            P_RD_STREAM: begin
                lb_ra <= k[8:3];                                                                   // lb_q = palabra del byte k
                if (gap == BYTE_GAP) begin
                    gap <= 4'd0;
                    outen <= 1'b1; outaddr <= outaddr + 9'd1;
                    outbyte <= rd_word[k[2:0]*8 +: 8];
                    k <= k + 9'd1;
                    if (k == 9'd511) ph <= P_RD_LAST;
                end else gap <= gap + 4'd1;
            end
            P_RD_LAST: begin                                                                       // el byte 511 ya esta en el dpram
                if (blocks_left > 8'd1) begin
                    blocks_left <= blocks_left - 8'd1; sector <= sector + 32'd1; blk_idx <= blk_idx + 8'd1;
                    blk_rdy <= 1'b1; ph <= P_RD_HOLD;
                end else begin done_cnt <= 2'd0; ph <= P_DONE; end
            end
            P_RD_HOLD: if (buf_ack) begin blk_rdy <= 1'b0; outaddr <= 9'h1FF; burst <= 2'd0; ph <= P_RD_GO; end
            // ---------- escritura de un bloque: 512 bytes del host -> lbuf -> 4 rafagas DDR ----------
            P_WR_COLLECT: case (sub)                                                               // "dame el byte k" -> inbyte al ciclo siguiente
                2'd0: begin outen <= 1'b1; sub <= 2'd1; end
                2'd1: sub <= 2'd2;
                2'd2: begin
                    wshift <= {inbyte, wshift[63:8]};
                    if (k[2:0] == 3'd7) begin lb_we <= 1'b1; lb_wa <= k[8:3]; lb_wd <= {inbyte, wshift[63:8]}; end
                    sub <= 2'd3;
                end
                default: begin
                    outaddr <= outaddr + 9'd1; k <= k + 9'd1; sub <= 2'd0;
                    if (k == 9'd511) begin burst <= 2'd0; ph <= P_WR_GO; end
                end
            endcase
            P_WR_GO: begin
                if (!in_range) ph <= P_WR_LAST;
                else begin
                    lb_ra <= {burst, 4'd0};                                                        // primer beat listo al arrancar el motor
                    ax_addr <= blk_addr; ax_len <= 4'd15; ax_wr <= 1'b1; ax_mb <= 1'b0; ax_go <= 1'b1; ph <= P_WR_W;
                end
            end
            P_WR_W: if (ax_done) begin
                burst <= burst + 2'd1;
                if (burst == 2'd3) ph <= P_WR_LAST; else ph <= P_WR_GO;
            end
            P_WR_LAST: begin
                if (blocks_left > 8'd1) begin
                    blocks_left <= blocks_left - 8'd1; sector <= sector + 32'd1; blk_idx <= blk_idx + 8'd1;
                    blk_rdy <= 1'b1; ph <= P_WR_HOLD;
                end else if (mode) begin                                                           // proxy: pedir la escritura
                    mb_d0 <= {16'd0, req_count, 8'd2, req_seq + 32'd1}; mb_d1 <= {32'd0, req_sector};
                    req_seq <= req_seq + 32'd1; req_irq <= 1'b1;
                    ax_addr <= SDBOX + 32'h8; ax_len <= 4'd1; ax_wr <= 1'b1; ax_mb <= 1'b1; ax_go <= 1'b1;
                    ph <= P_REQ;
                end else begin done_cnt <= 2'd0; ph <= P_DONE; end
            end
            P_WR_HOLD: if (buf_ack) begin blk_rdy <= 1'b0; outaddr <= 9'd0; k <= 9'd0; sub <= 2'd0; ph <= P_WR_COLLECT; end
            P_DONE: begin                                                                          // rdone alto 3 ciclos
                done_cnt <= done_cnt + 2'd1;
                if (done_cnt == 2'd2) begin stat <= S_IDLE; ph <= P_IDLE; dbg_blocks <= dbg_blocks + 16'd1; end
            end
            default: ph <= P_IDLE;
            endcase
            endcase
        end
    end

    // MB de la tarjeta (16 bits) -> unidades de 512 KB (c_size + 1): MB * 2
    function [20:0] card_mb_q; input [15:0] mb; card_mb_q = {5'd0, mb}; endfunction
endmodule
