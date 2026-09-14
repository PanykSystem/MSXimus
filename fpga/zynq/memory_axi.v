// ============================================================================
//  memory_axi.v — RAM del MSX (puerto ram_* del Z80) en la DDR3 del PS (Zynq)
// ----------------------------------------------------------------------------
//  Sustituye a memory_ctrl (src/memory.v, SDRAM W9825 de la Console 60K) en el
//  puerto del Z80. Conserva EXACTAMENTE el contrato que ve top.v:
//    * ram_req NIVEL, aceptado solo en la ventana dlclk&dhclk (primera mitad
//      de la media CPU); ram_busy sube al aceptar y baja con ram_dout valido;
//      se rearma cuando ram_req baja. Mismo instante de entrega que la SDRAM
//      en los HITS (seq3 tras dl&dh==00): el Z80 no nota la diferencia.
//    * En los FALLOS ram_busy se mantiene alto hasta que llega la linea de la
//      DDR: el /WAIT del Z80, que top.v ya gobierna por ram_busy, frena la CPU.
//      (En el build Zynq el termino ram_busy de las lecturas se aplica tambien
//      sin turbo — ver top_zynq.v.)
//    * Escrituras: write-through (la cache se actualiza si acierta; no se
//      reserva linea al fallar) + single-beat AXI con WSTRB de 1 byte, FIRE &
//      FORGET con barrera: una lectura que va a la DDR espera wr_pend==0.
//
//  Cache: mapeo directo, lineas de 16 B, 2^LINES_LOG lineas en BRAM
//  (12 -> 64 KB de datos + tags). Se INVALIDA ENTERA mientras cpu_run=0 (es
//  cuando el PS carga los packs en la DDR) y en reset. Contadores de
//  hits/fallos para medir la tasa real con software MSX.
//
//  TODO en clk_54m (el reloj del frontal FSM-A) — el puerto HP admite
//  cualquier ACLK hasta 150 MHz: S_AXI_HPx_ACLK = clk_54m. Sin CDC.
//  Medido en el HP0 a 100/150 MHz: 217/181 ns min por lectura suelta; a 54
//  cabe esperar ~280 ns min y ~650 max (refresco) = 1-2 estados de espera.
//
//  Lo que NO tiene (respecto a memory_ctrl): puerto vram_* (VDP clasico; con
//  el V9968 la VRAM va por v9968_axi_backend), wv/wv2/wv3 (ondas OPL4 ->
//  wave_axi; wv2/wv3 inertes con la VRAM en AXI), refresco (lo hace el DDRC).
//  🚨 El HP del PS no se resetea al reprogramar el PL: drena B/R en reset.
// ============================================================================
module memory_axi #(
    parameter [31:0] RAM_BASE  = 32'h1080_0000,   // ventana de 8 MB (addr de 23 bits)
    parameter        LINES_LOG = 12               // 4096 lineas x 16 B = 64 KB
)(
    input  wire        clk_54m,        // reloj del frontal (top.v lo llama clk_27m en memory_ctrl)
    input  wire        bus_reset_n,
    input  wire        video_dhclk,
    input  wire        video_dlclk,
    input  wire        cpu_run,        // 0 = Z80 parado (carga de packs): invalida la cache

    // ---- puerto Z80 (identico a memory_ctrl) ----
    input  wire [7:0]  ram_din,
    input  wire        ram_req,
    input  wire        ram_write,
    input  wire [22:0] ram_addr,
    output reg  [7:0]  ram_dout,
    output reg         ram_busy,
    // ram_slow: SOLO los accesos LARGOS (fallo de cache que va a la DDR). Los aciertos
    // entregan en el mismo instante que la SDRAM del Tang, asi que a 3,58 MHz no hacen
    // falta esperas: top_zynq arma el /WAIT con ram_slow fuera de turbo y con ram_busy
    // en turbo. Antes usaba ram_busy siempre y frenaba TODAS las lecturas: el Z80 se
    // quedaba en 2,95 MHz (83% de un MSX real, benchmark de NataliaPC, 14/09) porque el
    // reanudado se cuantiza al flanco de 3,58 y cada acceso pagaba hasta un T-state.
    output reg         ram_slow,

    // ---- telemetria ----
    output reg  [31:0] dbg_hits,
    output reg  [31:0] dbg_miss,
    output wire [31:0] dbg_state,       // ZYNQ bring-up: estado vivo de la FSM/HP
    output wire        ready,

    // ---- AXI3 master hacia S_AXI_HPx (64 bits), ACLK = clk_54m ----
    input  wire        aresetn,
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

    assign ready = aresetn;

    assign M_AWLEN   = 4'd0;   assign M_AWSIZE  = 3'b011; assign M_AWBURST = 2'b01;
    assign M_AWLOCK  = 2'b00;  assign M_AWCACHE = 4'b0011; assign M_AWPROT = 3'b000;
    assign M_AWQOS   = 4'd0;   assign M_WLAST   = 1'b1;
    assign M_ARLEN   = 4'd1;   assign M_ARSIZE  = 3'b011; assign M_ARBURST = 2'b01;   // linea = 2 beats
    assign M_ARLOCK  = 2'b00;  assign M_ARCACHE = 4'b0011; assign M_ARPROT = 3'b000;
    assign M_ARQOS   = 4'd0;

    // ------------------------------------------------------------------
    // Cache: datos (128 b por linea) + tags (valid + addr[22:LINES_LOG+4])
    // ------------------------------------------------------------------
    localparam TAG_W = 23 - LINES_LOG - 4;
    (* ram_style = "block" *) reg [127:0]     cd  [0:(1<<LINES_LOG)-1];
    (* ram_style = "block" *) reg [TAG_W:0]   ct  [0:(1<<LINES_LOG)-1];   // {valid, tag}

    wire [LINES_LOG-1:0] a_idx = ram_addr[LINES_LOG+3:4];
    wire [TAG_W-1:0]     a_tag = ram_addr[22:LINES_LOG+4];

    // puerto de lectura (lookup) y de escritura (relleno / write-through)
    reg  [LINES_LOG-1:0] cd_raddr;
    reg  [127:0]         cd_q;
    reg  [TAG_W:0]       ct_q;
    reg                  cd_we;
    reg  [LINES_LOG-1:0] cd_waddr;
    reg  [127:0]         cd_wdata;
    reg  [15:0]          cd_wbe;          // byte enables del relleno/escritura
    reg                  ct_we;
    reg  [LINES_LOG-1:0] ct_waddr;
    reg  [TAG_W:0]       ct_wdata;

    integer bi;
    always @(posedge clk_54m) begin
        cd_q <= cd[cd_raddr];
        ct_q <= ct[cd_raddr];
        if (cd_we) begin
            for (bi = 0; bi < 16; bi = bi + 1)
                if (cd_wbe[bi]) cd[cd_waddr][bi*8 +: 8] <= cd_wdata[bi*8 +: 8];
        end
        if (ct_we) ct[ct_waddr] <= ct_wdata;
    end

    // ------------------------------------------------------------------
    // Invalidacion: barrido de tags mientras cpu_run=0 (y tras reset)
    // ------------------------------------------------------------------
    reg                  inv_run;
    reg [LINES_LOG-1:0]  inv_idx;
    reg                  cpu_run_d;

    // ------------------------------------------------------------------
    // AXI: escrituras en vuelo, etiqueta de lectura, canal R
    // ------------------------------------------------------------------
    reg  [3:0] wr_pend;
    wire       aw_acc = M_AWVALID && M_AWREADY;
    wire       w_acc  = M_WVALID  && M_WREADY;
    wire       b_acc  = M_BVALID  && M_BREADY;
    wire       ar_acc = M_ARVALID && M_ARREADY;
    wire       r_acc  = M_RVALID  && M_RREADY;
    reg  [5:0] rd_tag;
    reg        r_beat;
    reg [63:0] r_lo;
    wire [127:0] line = {M_RDATA, r_lo};
    wire       w_free = !M_AWVALID && !M_WVALID;
    wire       r_free = !M_ARVALID;

    // ------------------------------------------------------------------
    // FSM-A: calcada de memory_ctrl. seq0 acepta en dl&dh; seq1 lookup;
    // seq2 espera dl&dh==00 (y la linea si hubo fallo); seq3 entrega.
    // ------------------------------------------------------------------
    reg [2:0]  seq;
    reg [22:0] op_addr;
    reg        op_we;
    reg [7:0]  op_din;
    reg        miss_wait;         // esperando la linea de la DDR
    reg        filled;            // la linea llego: entregar en la proxima ventana
    reg        w_issued;          // la escritura de esta op ya salio por AXI
    // ---- diagnostico de bring-up (dbg_state) ----
    reg        ar_seen;           // algun AR completo handshake (arready visto)
    reg  [7:0] r_cnt;             // beats R recibidos
    reg  [5:0] r_last_rid;        // RID del ultimo beat R
    assign dbg_state = {rd_tag[3:0], r_cnt, r_last_rid, wr_pend,
                        M_ARVALID, ar_seen, inv_run, w_issued, filled, miss_wait, ram_busy, seq};
    reg [127:0] hit_line;
    // el barrido de invalidacion no pisa la escritura de tag del relleno
    wire       fill_now  = r_acc && (M_RID == rd_tag) && r_beat;
    wire [3:0] byte_off = op_addr[3:0];

    wire [31:0] line_axi = RAM_BASE + {9'd0, op_addr[22:4], 4'b0000};
    wire [31:0] word_axi = RAM_BASE + {9'd0, op_addr[22:3], 3'b000};
    wire [7:0]  wstrb    = 8'h01 << op_addr[2:0];

    always @(posedge clk_54m) begin
        if (!bus_reset_n || !aresetn) begin
            seq <= 3'd0; ram_busy <= 1'b0; ram_slow <= 1'b0; ram_dout <= 8'd0;
            op_addr <= 23'd0; op_we <= 1'b0; op_din <= 8'd0; miss_wait <= 1'b0; filled <= 1'b0; w_issued <= 1'b0;
            hit_line <= 128'd0;
            cd_raddr <= {LINES_LOG{1'b0}}; cd_we <= 1'b0; cd_waddr <= {LINES_LOG{1'b0}};
            cd_wdata <= 128'd0; cd_wbe <= 16'd0; ct_we <= 1'b0; ct_waddr <= {LINES_LOG{1'b0}};
            ct_wdata <= {(TAG_W+1){1'b0}};
            inv_run <= 1'b1; inv_idx <= {LINES_LOG{1'b0}}; cpu_run_d <= 1'b0;
            wr_pend <= 4'd0; rd_tag <= 6'd0; r_beat <= 1'b0; r_lo <= 64'd0;
            dbg_hits <= 32'd0; dbg_miss <= 32'd0;
            ar_seen <= 1'b0; r_cnt <= 8'd0; r_last_rid <= 6'd0;
            M_AWVALID <= 1'b0; M_WVALID <= 1'b0; M_ARVALID <= 1'b0;
            M_AWID <= 6'd0; M_WID <= 6'd0; M_ARID <= 6'd0;
            M_AWADDR <= 32'd0; M_ARADDR <= 32'd0; M_WDATA <= 64'd0; M_WSTRB <= 8'd0;
            M_BREADY <= 1'b1;             // drenar herencias del HP
            M_RREADY <= 1'b1;
        end
        else begin
            cd_we <= 1'b0; ct_we <= 1'b0;
            M_BREADY <= 1'b1; M_RREADY <= 1'b1;
            wr_pend <= wr_pend + {3'd0, aw_acc} - {3'd0, b_acc};
            if (ar_acc) ar_seen <= 1'b1;
            if (r_acc) begin r_cnt <= r_cnt + 1'b1; r_last_rid <= M_RID; end
            if (aw_acc) M_AWVALID <= 1'b0;
            if (w_acc)  M_WVALID  <= 1'b0;
            if (ar_acc) M_ARVALID <= 1'b0;

            // ---- invalidacion: arranca al parar la CPU (y tras reset) ----
            cpu_run_d <= cpu_run;
            if (cpu_run_d && !cpu_run) begin inv_run <= 1'b1; inv_idx <= {LINES_LOG{1'b0}}; end
            if (inv_run && !fill_now) begin
                ct_we <= 1'b1; ct_waddr <= inv_idx; ct_wdata <= {(TAG_W+1){1'b0}};
                inv_idx <= inv_idx + 1'b1;
                if (&inv_idx) inv_run <= 1'b0;
            end

            // ---- canal R: ensamblar la linea esperada; rancios se descartan ----
            if (r_acc && M_RID == rd_tag) begin
                if (!r_beat) begin r_lo <= M_RDATA; r_beat <= 1'b1; end
                else begin
                    r_beat <= 1'b0;
                    // relleno de la cache (siempre: es una lectura con fallo)
                    cd_we <= 1'b1; cd_waddr <= op_addr[LINES_LOG+3:4]; cd_wdata <= line; cd_wbe <= 16'hFFFF;
                    ct_we <= 1'b1; ct_waddr <= op_addr[LINES_LOG+3:4];
                    ct_wdata <= {1'b1, op_addr[22:LINES_LOG+4]};
                    hit_line  <= line;
                    miss_wait <= 1'b0;
                    filled    <= 1'b1;
                end
            end

            // ---- FSM-A ----
            case (seq)
            3'd0: begin
                if (ram_req && video_dlclk && video_dhclk && !inv_run) begin
                    ram_busy <= 1'b1;
                    op_addr  <= ram_addr; op_we <= ram_write; op_din <= ram_din;
                    cd_raddr <= a_idx;                 // lookup (dato en seq2)
                    seq <= 3'd1;
                end
            end
            3'd1: begin
                seq <= 3'd2;                            // cd_q/ct_q validos en seq2
            end
            3'd2: begin
                // aviso TEMPRANO de acceso largo: en cuanto se sabe que la lectura no
                // acierta (ct_q/cd_q son validos aqui, ~2 ciclos de 54 MHz tras aceptar
                // la peticion, muy dentro del primer T-state) y hasta que se entrega en
                // seq3. Cubre tambien el rato esperando a poder emitir el AR.
                if (!op_we && !filled &&
                    !(ct_q[TAG_W] && ct_q[TAG_W-1:0] == op_addr[22:LINES_LOG+4]))
                    ram_slow <= 1'b1;
                if (miss_wait) begin
                    // esperando la linea: llega por el canal R (miss_wait -> 0, filled -> 1)
                end
                else if (filled) begin
                    // linea recibida: entregar en la ventana dl&dh==00 como un hit
                    if (!video_dlclk && !video_dhclk) begin filled <= 1'b0; seq <= 3'd3; end
                end
                else if (op_we) begin
                    if (!w_issued) begin
                        if (w_free && !wr_pend[3]) begin
                            // write-through: cache si acierta + single-beat AXI (fire & forget)
                            if (ct_q[TAG_W] && ct_q[TAG_W-1:0] == op_addr[22:LINES_LOG+4]) begin
                                cd_we <= 1'b1; cd_waddr <= op_addr[LINES_LOG+3:4];
                                cd_wdata <= {16{op_din}}; cd_wbe <= 16'h0001 << byte_off;
                            end
                            M_AWADDR <= word_axi; M_AWID <= 6'd0; M_WID <= 6'd0;
                            M_WDATA  <= {8{op_din}}; M_WSTRB <= wstrb;
                            M_AWVALID <= 1'b1; M_WVALID <= 1'b1;
                            w_issued <= 1'b1;
                        end
                        // (cola AXI llena o canal retenido: se espera aqui)
                    end
                    else if (!video_dlclk && !video_dhclk) begin
                        w_issued <= 1'b0;
                        seq <= 3'd3;
                    end
                end
                else if (ct_q[TAG_W] && ct_q[TAG_W-1:0] == op_addr[22:LINES_LOG+4]) begin
                    // HIT: entregar en el mismo instante que la SDRAM
                    hit_line <= cd_q;
                    if (!video_dlclk && !video_dhclk) begin
                        dbg_hits <= dbg_hits + 1'b1;
                        seq <= 3'd3;
                    end
                end
                else if (r_free && wr_pend == 4'd0) begin
                    // FALLO: pedir la linea (barrera lectura-tras-escritura)
                    M_ARADDR <= line_axi; M_ARID <= rd_tag + 6'd1; rd_tag <= rd_tag + 6'd1;
                    M_ARVALID <= 1'b1; r_beat <= 1'b0;
                    miss_wait <= 1'b1;
                    dbg_miss  <= dbg_miss + 1'b1;
                end
            end
            3'd3: begin
                ram_dout <= hit_line[byte_off*8 +: 8];
                ram_busy <= 1'b0;
                ram_slow <= 1'b0;
                seq <= 3'd4;
            end
            3'd4: begin
                if (!ram_req) seq <= 3'd0;
            end
            default: seq <= 3'd0;
            endcase
        end
    end

endmodule
