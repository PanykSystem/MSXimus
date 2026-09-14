// ============================================================================
// v9968_axi_backend.v — VRAM del V9968 en la DDR3 del PS (Zynq-7000, S_AXI_HP)
//
// Port de v9968_ddr3_backend.v (Tang Console 60K, IP DDR3 de Gowin) a la
// Zynq: MISMA interfaz de cliente (los dos v9968_sdram_bridge se conectan tal
// cual, con su lado far a aclk) y MISMA logica de servicio; solo cambia la
// capa de memoria, que ahora es un master AXI3 directo al puerto HP del PS.
//
// Lo que se conserva del backend DDR3 (numeros _NNN = builds del Tang):
//   wv2   req NIVEL, servir UNA vez por flanco (*_srv, rearme al bajar req),
//         done PULSO 1 ciclo, dout estable tras done. Prioridad A > B.
//   _130  cache de UNA linea de 128 bits por canal: hits en 1 ciclo sin tocar
//         la memoria. Coherencia write-through: las escrituras actualizan las
//         lineas cacheadas de AMBOS canales si el tag casa.
//   COMBO si A (lectura) y B pendientes en la misma linea, una sola lectura
//         responde a los dos.
//   _148  escritura de PALABRA de 32 bits con mascara de bytes (1 = escribir).
//   _95   watchdog de operacion: si la memoria no responde en ~0.9 ms se
//         completa EN FALSO con FFFF (la CPU no se cuelga) y se cuenta.
//   _132  anti-desincronizacion: una lectura abandonada por el watchdog puede
//         llegar tarde; su dato NO debe tomarse como el de la siguiente.
//   _129b dbg_ops = {lecturas[31:16], escrituras[15:0]} servidas.
//
// Lo que cambia con AXI:
//   * Lectura de linea = rafaga de 2 beats de 64 bits (ARLEN=1). Cada lectura
//     lleva su ARID (etiqueta rotatoria): un R con RID distinto del esperado
//     es un rancio y se descarta (version limpia del rd_pend del _132).
//   * Escritura = single-beat de 64 bits con WSTRB = la mascara del VDP en su
//     carril (addr[2]). FIRE & FORGET como hoy: a_done al aceptar AW y W; el B
//     se cobra en segundo plano (wr_pend). BARRERA: una lectura que va a la
//     DDR espera a wr_pend == 0, porque AXI no ordena lecturas frente a
//     escrituras en vuelo (el DDR3 de Gowin si lo hacia por su cola unica).
//   * La DDR ya esta entrenada por ps7_init antes de que el PL arranque:
//     ready = aresetn. Sin calibracion, sin PLL, sin danza mDRP.
//   * 🚨 El HP del PS NO se resetea al reprogramar el PL (medido en el banco
//     05_hp_bench): en reset se DRENAN B y R para no heredar respuestas.
//
// Medido en 05_hp_bench @150 MHz: lectura suelta 181 ns (153-467), escritura
// 127 ns (107-113), el maximo es el refresco. El Tang servia ~730 ns/lectura.
// ============================================================================
module v9968_axi_backend #(
    parameter [31:0] VRAM_BASE = 32'h1000_0000   // ventana de 4 MB en la DDR del PS
)(
    // ---- canales VRAM (dominio aclk; protocolo wv2 nivel/pulso) ----
    input  wire        a_req,         // NIVEL: se mantiene hasta ver a_done
    input  wire        a_we,
    input  wire [21:0] a_addr,        // direccion de BYTE
    input  wire [31:0] a_wdata,       // _148: palabra completa
    input  wire [3:0]  a_wmask,       // _148: 1 = escribir ese byte
    output reg  [15:0] a_dout,        // palabra 16b (addr[0] ignorado)
    output reg         a_done,        // PULSO 1 ciclo

    input  wire        b_req,         // NIVEL (solo lecturas)
    input  wire [21:0] b_addr,
    output reg  [15:0] b_dout,
    output reg         b_done,        // PULSO 1 ciclo

    output wire        clk_x1_out,    // reloj de los canales (= aclk)
    output wire        ready,         // memoria operativa (= aresetn)
    output wire [7:0]  diag,          // mismo formato que el DDR3 (ver abajo)
    output wire [31:0] dbg_ops,       // {lecturas[31:16], escrituras[15:0]}
    input  wire        recal_req,     // sin uso (como en el DDR3)

    // ---- relojes ----
    input  wire        aclk,          // FCLK del PS (150 MHz)
    input  wire        aresetn,       // FCLK_RESET0_N (lo suelta ps7_post_config)

    // ---- AXI3 master hacia S_AXI_HPx (64 bits) ----
    output reg  [5:0]  M_AWID,
    output reg  [31:0] M_AWADDR,
    output wire [3:0]  M_AWLEN,
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
    output reg  [7:0]  M_WSTRB,
    output wire        M_WLAST,
    output reg         M_WVALID,
    input  wire        M_WREADY,
    input  wire [5:0]  M_BID,
    input  wire [1:0]  M_BRESP,
    input  wire        M_BVALID,
    output reg         M_BREADY,
    output reg  [5:0]  M_ARID,
    output reg  [31:0] M_ARADDR,
    output wire [3:0]  M_ARLEN,
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

    wire rc_unused = recal_req;
    assign clk_x1_out = aclk;
    assign ready      = aresetn;

    // Constantes AXI3: 8 bytes/beat, INCR, no-cacheable bufferable
    assign M_AWLEN   = 4'd0;            // escritura: 1 beat
    assign M_AWSIZE  = 3'b011;
    assign M_AWBURST = 2'b01;
    assign M_AWLOCK  = 2'b00;
    assign M_AWCACHE = 4'b0011;
    assign M_AWPROT  = 3'b000;
    assign M_AWQOS   = 4'd0;
    assign M_WLAST   = 1'b1;
    assign M_ARLEN   = 4'd1;            // lectura: 2 beats = linea de 128 bits
    assign M_ARSIZE  = 3'b011;
    assign M_ARBURST = 2'b01;
    assign M_ARLOCK  = 2'b00;
    assign M_ARCACHE = 4'b0011;
    assign M_ARPROT  = 3'b000;
    assign M_ARQOS   = 4'd0;

    // ------------------------------------------------------------------
    // Estado del servicio (calcado del DDR3)
    // ------------------------------------------------------------------
    reg a_srv, b_srv;                      // ya servido (hasta que baje el req)
    reg op_b;                              // op en curso: canal B
    reg op_combo;                          // esta lectura responde a A y B
    reg [21:0] op_addr;
    reg [21:0] op_baddr;                   // addr de B en un combo
    reg [31:0] op_wdata;
    reg [3:0]  op_wmask;
    wire [6:0] cl_off = {op_addr[3:2], 5'b00000};   // bit del byte 0 de la palabra

    localparam ST_IDLE = 2'd0, ST_WISSUE = 2'd1, ST_RISSUE = 2'd2, ST_WAITRD = 2'd3;
    reg [1:0] st;

    // _130 cache de linea (una por canal)
    reg [127:0] clA_data, clB_data;
    reg [17:0]  clA_tag,  clB_tag;         // addr[21:4]
    reg         clA_v, clB_v;
    wire a_hit = clA_v && (a_addr[21:4] == clA_tag);
    wire b_hit = clB_v && (b_addr[21:4] == clB_tag);

    // escrituras en vuelo (AW aceptadas - B recibidas). El HP encola hasta 8.
    reg [3:0] wr_pend;
    wire      aw_acc = M_AWVALID && M_AWREADY;
    wire      w_acc  = M_WVALID  && M_WREADY;
    wire      b_acc  = M_BVALID  && M_BREADY;
    reg       aw_done, w_done;             // aceptaciones parciales de la op en curso
    // _132: solo se emite con el canal LIBRE. Una op abandonada por el
    // watchdog deja su VALID retenido (AXI prohibe retirarlo o cambiar la
    // direccion); mientras siga ahi no se emite nada nuevo por ese canal.
    wire      w_free = !M_AWVALID && !M_WVALID;
    wire      r_free = !M_ARVALID;

    // lecturas: etiqueta rotatoria y beats
    reg [5:0] rd_tag;                      // ARID de la ultima lectura emitida
    wire      ar_acc = M_ARVALID && M_ARREADY;
    wire      r_acc  = M_RVALID  && M_RREADY;
    reg       r_beat;                      // 0 = primer beat (bytes 0-7), 1 = segundo
    reg [63:0] r_lo;                       // primer beat de la linea
    wire [127:0] line = {M_RDATA, r_lo};   // la linea completa en el 2o beat

    // _95 watchdog de operacion (bit 17 a 150 MHz = 0.87 ms)
    reg [17:0] op_wd;
    reg [3:0]  wd_ops;

    // _129b contadores
    reg inc_rd_a, inc_rd_b, inc_wr;
    reg [15:0] op_rd_cnt, op_wr_cnt;
    always @(posedge aclk) begin
        if (!aresetn) begin
            op_rd_cnt <= 16'd0; op_wr_cnt <= 16'd0;
        end else begin
            op_rd_cnt <= op_rd_cnt + {15'd0, inc_rd_a} + {15'd0, inc_rd_b};
            if (inc_wr) op_wr_cnt <= op_wr_cnt + 16'd1;
        end
    end
    assign dbg_ops = {op_rd_cnt, op_wr_cnt};

    // diag con el formato del DDR3: {x1_alive, pll_lock, por_done, calib_ever,
    // wd_fires[2:0], calib_drop}. Aqui no hay PLL ni calibracion: los tres
    // primeros fijos a 1, calib_ever = ready, wd_fires = 0, calib_drop = 0.
    assign diag = {1'b1, 1'b1, 1'b1, aresetn, 3'd0, 1'b0};

    // ------------------------------------------------------------------
    // Direcciones AXI
    //   linea de 128 b: VRAM_BASE + {addr[21:4], 4'b0}  (rafaga de 2 beats)
    //   palabra de 32 b: VRAM_BASE + {addr[21:3], 3'b0} (beat que la contiene)
    // ------------------------------------------------------------------
    wire [31:0] a_line_addr = VRAM_BASE + {10'd0, a_addr[21:4], 4'b0000};
    wire [31:0] b_line_addr = VRAM_BASE + {10'd0, b_addr[21:4], 4'b0000};
    wire [31:0] a_word_addr = VRAM_BASE + {10'd0, a_addr[21:3], 3'b000};
    wire [7:0]  a_strb      = a_addr[2] ? {a_wmask, 4'b0000} : {4'b0000, a_wmask};

    // ------------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            st <= ST_IDLE;
            a_srv <= 1'b0; b_srv <= 1'b0;
            a_done <= 1'b0; b_done <= 1'b0;
            a_dout <= 16'd0; b_dout <= 16'd0;
            op_b <= 1'b0; op_combo <= 1'b0;
            op_addr <= 22'd0; op_baddr <= 22'd0; op_wdata <= 32'd0; op_wmask <= 4'd0;
            op_wd <= 18'd0; wd_ops <= 4'd0;
            clA_v <= 1'b0; clB_v <= 1'b0;
            clA_tag <= 18'd0; clB_tag <= 18'd0;
            clA_data <= 128'd0; clB_data <= 128'd0;
            inc_rd_a <= 1'b0; inc_rd_b <= 1'b0; inc_wr <= 1'b0;
            wr_pend <= 4'd0; aw_done <= 1'b0; w_done <= 1'b0;
            rd_tag <= 6'd0; r_beat <= 1'b0; r_lo <= 64'd0;
            M_AWVALID <= 1'b0; M_WVALID <= 1'b0; M_ARVALID <= 1'b0;
            M_AWID <= 6'd0; M_WID <= 6'd0; M_ARID <= 6'd0;
            M_AWADDR <= 32'd0; M_ARADDR <= 32'd0; M_WDATA <= 64'd0; M_WSTRB <= 8'd0;
            // 🚨 drenar respuestas heredadas del HP mientras dure el reset
            M_BREADY <= 1'b1;
            M_RREADY <= 1'b1;
        end
        else begin
            a_done <= 1'b0;                          // pulsos de 1 ciclo
            b_done <= 1'b0;
            inc_rd_a <= 1'b0; inc_rd_b <= 1'b0; inc_wr <= 1'b0;

            // ---- canal B: siempre listo; escrituras en vuelo = AW aceptadas - B ----
            M_BREADY <= 1'b1;
            wr_pend <= wr_pend + {3'd0, aw_acc} - {3'd0, b_acc};

            // ---- canal R: siempre listo; ensambla la linea si es la esperada ----
            M_RREADY <= 1'b1;

            // ---- aceptaciones de la escritura en curso ----
            if (aw_acc) begin
                M_AWVALID <= 1'b0;
                aw_done   <= 1'b1;
            end
            if (w_acc) begin
                M_WVALID <= 1'b0;
                w_done   <= 1'b1;
            end
            if (ar_acc) M_ARVALID <= 1'b0;

            // ---- watchdog: cuenta fuera de IDLE, o en IDLE con peticion que
            //      no puede emitirse (barrera/cola llena) ----
            if (st == ST_IDLE && !((a_req && !a_srv) || (b_req && !b_srv)))
                 op_wd <= 18'd0;
            else op_wd <= op_wd + 18'd1;

            if (!a_req) a_srv <= 1'b0;               // rearme por bajada del nivel
            if (!b_req) b_srv <= 1'b0;

            case (st)
            // ---------------------------------------------------------
            ST_IDLE: begin
                // _130: HITS servidos aqui mismo, sin salir de IDLE (solo lecturas)
                if (a_req && !a_srv && !a_we && a_hit) begin
                    a_dout <= clA_data[a_addr[3:1]*16 +: 16];
                    a_done <= 1'b1; a_srv <= 1'b1;
                    inc_rd_a <= 1'b1;
                end
                if (b_req && !b_srv && b_hit) begin
                    b_dout <= clB_data[b_addr[3:1]*16 +: 16];
                    b_done <= 1'b1; b_srv <= 1'b1;
                    inc_rd_b <= 1'b1;
                end

                // ---- A: escritura (fire & forget; hasta 8 en vuelo) ----
                if (a_req && !a_srv && a_we) begin
                    if (w_free && !wr_pend[3]) begin
                        op_addr  <= a_addr;
                        op_wdata <= a_wdata;
                        op_wmask <= a_wmask;
                        M_AWADDR <= a_word_addr;
                        M_AWID   <= 6'd0;
                        M_WID    <= 6'd0;
                        M_WDATA  <= {a_wdata, a_wdata};
                        M_WSTRB  <= a_strb;
                        M_AWVALID <= 1'b1;
                        M_WVALID  <= 1'b1;
                        aw_done <= 1'b0; w_done <= 1'b0;
                        st <= ST_WISSUE;
                    end
                    else if (op_wd[17]) begin
                        // _95: cola de escritura muerta — completar en falso
                        a_dout <= 16'hFFFF; a_done <= 1'b1; a_srv <= 1'b1;
                        if (wd_ops != 4'd15) wd_ops <= wd_ops + 4'd1;
                    end
                end
                // ---- A: lectura con fallo de cache ----
                else if (a_req && !a_srv && !a_we && !a_hit) begin
                    if (r_free && wr_pend == 4'd0) begin   // barrera lectura-tras-escritura
                        op_b     <= 1'b0;
                        op_addr  <= a_addr;
                        op_combo <= (b_req && !b_srv && !b_hit
                                     && b_addr[21:4] == a_addr[21:4]);
                        op_baddr <= b_addr;
                        M_ARADDR <= a_line_addr;
                        M_ARID   <= rd_tag + 6'd1;
                        rd_tag   <= rd_tag + 6'd1;
                        M_ARVALID <= 1'b1;
                        r_beat <= 1'b0;
                        st <= ST_RISSUE;
                    end
                    else if (op_wd[17]) begin
                        a_dout <= 16'hFFFF; a_done <= 1'b1; a_srv <= 1'b1;
                        if (wd_ops != 4'd15) wd_ops <= wd_ops + 4'd1;
                    end
                end
                // ---- B: lectura con fallo de cache ----
                else if (b_req && !b_srv && !b_hit) begin
                    if (r_free && wr_pend == 4'd0) begin
                        op_b     <= 1'b1;
                        op_addr  <= b_addr;
                        op_combo <= 1'b0;
                        M_ARADDR <= b_line_addr;
                        M_ARID   <= rd_tag + 6'd1;
                        rd_tag   <= rd_tag + 6'd1;
                        M_ARVALID <= 1'b1;
                        r_beat <= 1'b0;
                        st <= ST_RISSUE;
                    end
                    else if (op_wd[17]) begin
                        b_dout <= 16'hFFFF; b_done <= 1'b1; b_srv <= 1'b1;
                        if (wd_ops != 4'd15) wd_ops <= wd_ops + 4'd1;
                    end
                end
            end
            // ---------------------------------------------------------
            ST_WISSUE: begin
                if ((aw_done || aw_acc) && (w_done || w_acc)) begin
                    // AW y W aceptados: la escritura esta en la cola del HP
                    a_done <= 1'b1; a_srv <= 1'b1;
                    inc_wr <= 1'b1;
                    // _130/_148: coherencia de las lineas cacheadas
                    if (clA_v && op_addr[21:4] == clA_tag) begin
                        if (op_wmask[0]) clA_data[cl_off + 7'd0  +: 8] <= op_wdata[ 7: 0];
                        if (op_wmask[1]) clA_data[cl_off + 7'd8  +: 8] <= op_wdata[15: 8];
                        if (op_wmask[2]) clA_data[cl_off + 7'd16 +: 8] <= op_wdata[23:16];
                        if (op_wmask[3]) clA_data[cl_off + 7'd24 +: 8] <= op_wdata[31:24];
                    end
                    if (clB_v && op_addr[21:4] == clB_tag) begin
                        if (op_wmask[0]) clB_data[cl_off + 7'd0  +: 8] <= op_wdata[ 7: 0];
                        if (op_wmask[1]) clB_data[cl_off + 7'd8  +: 8] <= op_wdata[15: 8];
                        if (op_wmask[2]) clB_data[cl_off + 7'd16 +: 8] <= op_wdata[23:16];
                        if (op_wmask[3]) clB_data[cl_off + 7'd24 +: 8] <= op_wdata[31:24];
                    end
                    st <= ST_IDLE;
                end
                else if (op_wd[17]) begin
                    // _95: sin aceptar en 0.87 ms — completar en falso. AW/W
                    // QUEDAN retenidos: si el HP vuelve, la escritura sigue
                    // siendo correcta (soltarlos a medias desincroniza).
                    a_dout <= 16'hFFFF; a_done <= 1'b1; a_srv <= 1'b1;
                    if (wd_ops != 4'd15) wd_ops <= wd_ops + 4'd1;
                    st <= ST_IDLE;
                end
            end
            // ---------------------------------------------------------
            ST_RISSUE: begin
                if (ar_acc || !M_ARVALID) st <= ST_WAITRD;
                else if (op_wd[17]) begin            // AR nunca aceptado
                    if (op_combo || !op_b) begin a_dout <= 16'hFFFF; a_done <= 1'b1; a_srv <= 1'b1; end
                    if (op_combo ||  op_b) begin b_dout <= 16'hFFFF; b_done <= 1'b1; b_srv <= 1'b1; end
                    if (wd_ops != 4'd15) wd_ops <= wd_ops + 4'd1;
                    st <= ST_IDLE;                   // ARVALID sigue retenido
                end
            end
            // ---------------------------------------------------------
            ST_WAITRD: begin
                if (r_acc) begin
                    if (M_RID == rd_tag) begin
                        // beat 0 = bytes 0-7, beat 1 = bytes 8-15 de la linea
                        if (!r_beat) begin
                            r_lo   <= M_RDATA;
                            r_beat <= 1'b1;
                        end
                        else begin
                            if (op_combo) begin
                                a_dout <= line[op_addr[3:1]*16  +: 16];
                                b_dout <= line[op_baddr[3:1]*16 +: 16];
                                a_done <= 1'b1; a_srv <= 1'b1;
                                b_done <= 1'b1; b_srv <= 1'b1;
                                inc_rd_a <= 1'b1; inc_rd_b <= 1'b1;
                                clA_data <= line; clA_tag <= op_addr[21:4]; clA_v <= 1'b1;
                                clB_data <= line; clB_tag <= op_addr[21:4]; clB_v <= 1'b1;
                            end
                            else if (op_b) begin
                                b_dout <= line[op_addr[3:1]*16 +: 16];
                                b_done <= 1'b1; b_srv <= 1'b1;
                                inc_rd_b <= 1'b1;
                                clB_data <= line; clB_tag <= op_addr[21:4]; clB_v <= 1'b1;
                            end
                            else begin
                                a_dout <= line[op_addr[3:1]*16 +: 16];
                                a_done <= 1'b1; a_srv <= 1'b1;
                                inc_rd_a <= 1'b1;
                                clA_data <= line; clA_tag <= op_addr[21:4]; clA_v <= 1'b1;
                            end
                            st <= ST_IDLE;
                        end
                    end
                    // RID distinto: rancio de una lectura abandonada — se descarta
                end
                else if (op_wd[17]) begin            // _95: lectura que nunca vuelve
                    if (op_combo || !op_b) begin a_dout <= 16'hFFFF; a_done <= 1'b1; a_srv <= 1'b1; end
                    if (op_combo ||  op_b) begin b_dout <= 16'hFFFF; b_done <= 1'b1; b_srv <= 1'b1; end
                    if (wd_ops != 4'd15) wd_ops <= wd_ops + 4'd1;
                    st <= ST_IDLE;
                end
            end
            default: st <= ST_IDLE;
            endcase
        end
    end

endmodule
