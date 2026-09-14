// ============================================================================
//  axi_hp_bench.v — banco de pruebas del S_AXI_HP0 (AXI3, 64 bits) del PS7.
// ----------------------------------------------------------------------------
//  Mide con contadores en hardware lo que decide el backend de memoria del
//  MSXimus en Zynq, y deja la tabla de resultados en la DDR (RESULT) para
//  leerla con xsdb.  Benchmarks, en orden:
//    0  RD single-beat secuencial, 1 en vuelo      -> latencia AR..R (media/min/max)
//    1  RD single-beat ALEATORIO (LFSR, 64 MB)     -> latencia con fallo de fila
//    2  WR single-beat secuencial, 1 en vuelo      -> latencia AW..B
//    3  RD rafaga 16 (128 B) secuencial, 1 en vuelo -> BW
//    4  RD rafaga 16 secuencial, 8 en vuelo        -> BW maximo del puerto
//    5  WR rafaga 16 secuencial, 4 AW en vuelo     -> BW escritura
//    6  RD single ALEATORIO con 8 en vuelo         -> throughput de accesos VRAM
//  Tabla en RESULT (little-endian, 32 bits):
//    +0  magic 0xB0B0CAFE (se escribe el ULTIMO: si esta, la tabla es valida)
//    +4  FCLK_MHZ
//    +8 + 16*b : { cycles, ops, lat_min, lat_max }  del benchmark b
//  Un watchdog por benchmark (2^27 ciclos) marca lat_max = 0xDEAD0000|b y deja
//  en lat_min una foto de los handshakes y contadores (ver S_RUN).
//  LEDs: benchmark en curso (binario); 1111 = tabla escrita.
// ============================================================================
module axi_hp_bench #(
    parameter [31:0] BASE     = 32'h1000_0000,
    parameter [31:0] RESULT   = 32'h1F00_0000,
    parameter [31:0] FCLK_MHZ = 32'd100,
    parameter        N_SINGLE = 4096,          // ops en los bench single-beat
    parameter        N_BURST  = 512            // rafagas de 16 en los bench burst (64 KB)
)(
    input  wire        ACLK,
    input  wire        ARESETN,

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
    output reg         M_RREADY,

    output reg  [3:0]  led,
    output reg         done
);

    assign M_AWSIZE  = 3'b011;  assign M_AWBURST = 2'b01;  assign M_AWLOCK = 2'b00;
    assign M_AWCACHE = 4'b0011; assign M_AWPROT  = 3'b000; assign M_AWQOS  = 4'd0;
    assign M_WSTRB   = 8'hFF;
    assign M_ARSIZE  = 3'b011;  assign M_ARBURST = 2'b01;  assign M_ARLOCK = 2'b00;
    assign M_ARCACHE = 4'b0011; assign M_ARPROT  = 3'b000; assign M_ARQOS  = 4'd0;

    // ------------------------------------------------------------------
    //  Descripcion de cada benchmark
    // ------------------------------------------------------------------
    localparam NB = 7;
    reg        b_is_wr, b_rand;
    reg [3:0]  b_len;          // AxLEN (0 = 1 beat, 15 = 16 beats)
    reg [3:0]  b_maxout;       // maximo en vuelo
    reg [15:0] b_nops;
    always @(*) begin
        b_is_wr = 0; b_rand = 0; b_len = 0; b_maxout = 1; b_nops = N_SINGLE;
        case (bench)
        3'd0: begin end
        3'd1: begin b_rand = 1; end
        3'd2: begin b_is_wr = 1; end
        3'd3: begin b_len = 15; b_nops = N_BURST; end
        3'd4: begin b_len = 15; b_nops = N_BURST; b_maxout = 8; end
        3'd5: begin b_len = 15; b_nops = N_BURST; b_maxout = 4; b_is_wr = 1; end
        3'd6: begin b_rand = 1; b_maxout = 8; end
        default: begin end
        endcase
    end

    // ------------------------------------------------------------------
    //  FSM principal
    // ------------------------------------------------------------------
    localparam [2:0] S_BOOT = 3'd0, S_START = 3'd1, S_RUN = 3'd2, S_STORE = 3'd3,
                     S_WRES = 3'd4, S_WMAGIC = 3'd5, S_END = 3'd6;
    reg [2:0]  st;
    reg [2:0]  bench;
    reg [19:0] boot;
    reg [26:0] wdog;
    reg        run;                 // los canales trabajan mientras run=1

    // contadores del benchmark en curso
    reg [31:0] cycles;
    reg [15:0] issued, completed;   // transacciones (rafagas) emitidas / completadas
    reg [15:0] w_bursts;            // rafagas de datos W emitidas
    reg [4:0]  w_beat;              // beat dentro de la rafaga W
    reg [15:0] lat_min, lat_max, lat_cur;
    wire [3:0] outstanding = issued[3:0] - completed[3:0];   // maxout <= 8, cabe en 4 bits

    // resultados
    reg [31:0] r_cycles [0:NB-1];
    reg [31:0] r_ops    [0:NB-1];
    reg [31:0] r_lmin   [0:NB-1];
    reg [31:0] r_lmax   [0:NB-1];

    // direccion secuencial / aleatoria
    reg [31:0] addr_seq;
    reg [31:0] lfsr;
    wire [31:0] addr_rand = BASE + {6'd0, lfsr[22:0], 3'b000};      // 64 MB, alineado a 8
    wire [31:0] next_addr = b_rand ? addr_rand : addr_seq;
    wire [31:0] lfsr_next = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};

    // escritura de resultados: 2 palabras de 64 por bench + magic
    reg [4:0]  res_idx;             // 0..2*NB-1 ; luego magic
    reg        res_pend;            // palabra emitida, esperando su B
    wire [2:0] res_b   = res_idx[4:1];
    wire       res_hi  = res_idx[0];
    wire [63:0] res_word = res_hi ? {r_lmax[res_b], r_lmin[res_b]} : {r_ops[res_b], r_cycles[res_b]};
    wire [31:0] res_addr = RESULT + 32'd8 + {res_idx, 3'b000};

    integer i;

    always @(posedge ACLK) begin
        if (!ARESETN) begin
            st <= S_BOOT; bench <= 0; boot <= 0; wdog <= 0; run <= 0;
            M_AWVALID <= 0; M_WVALID <= 0; M_BREADY <= 0; M_ARVALID <= 0; M_RREADY <= 0;
            M_AWID <= 0; M_WID <= 0; M_ARID <= 0; M_AWLEN <= 0; M_ARLEN <= 0; M_WLAST <= 0;
            M_AWADDR <= 0; M_ARADDR <= 0; M_WDATA <= 0;
            cycles <= 0; issued <= 0; completed <= 0; w_bursts <= 0; w_beat <= 0;
            lat_min <= 16'hFFFF; lat_max <= 0; lat_cur <= 0;
            addr_seq <= BASE; lfsr <= 32'hACE1_2357;
            res_idx <= 0; res_pend <= 0; led <= 0; done <= 0;
            for (i = 0; i < NB; i = i + 1) begin
                r_cycles[i] <= 0; r_ops[i] <= 0; r_lmin[i] <= 0; r_lmax[i] <= 0;
            end
        end else begin
            case (st)
            // ---------------------------------------------------------
            S_BOOT: begin
                // Drenar respuestas huerfanas: el HP del PS conserva su estado
                // al reprogramar el PL, y un B/R sin consumir de la sesion
                // anterior desincronizaria los contadores del primer bench.
                M_BREADY <= 1'b1;
                M_RREADY <= 1'b1;
                boot <= boot + 1'b1;
                if (&boot) begin
                    M_BREADY <= 1'b0;
                    M_RREADY <= 1'b0;
                    st <= S_START;
                end
            end
            // ---------------------------------------------------------
            S_START: begin
                led      <= {1'b0, bench};
                cycles   <= 0; issued <= 0; completed <= 0; w_bursts <= 0; w_beat <= 0;
                lat_min  <= 16'hFFFF; lat_max <= 0; lat_cur <= 0;
                addr_seq <= BASE;
                wdog     <= 0;
                M_ARLEN  <= b_len; M_AWLEN <= b_len;
                M_RREADY <= ~b_is_wr;
                M_BREADY <= b_is_wr;
                run      <= 1'b1;
                st       <= S_RUN;
            end
            // ---------------------------------------------------------
            S_RUN: begin
                cycles <= cycles + 1'b1;
                wdog   <= wdog + 1'b1;
                lat_cur <= lat_cur + 1'b1;

                if (!b_is_wr) begin
                    // ---- lecturas: emisor AR ----
                    if (!M_ARVALID) begin
                        if (issued < b_nops && outstanding < b_maxout) begin
                            M_ARADDR  <= next_addr;
                            M_ARID    <= issued[5:0];
                            M_ARVALID <= 1'b1;
                        end
                    end else if (M_ARREADY) begin
                        M_ARVALID <= 1'b0;
                        issued    <= issued + 1'b1;
                        addr_seq  <= addr_seq + ({28'd0, b_len} + 1'b1) * 8;
                        lfsr      <= lfsr_next;
                        if (b_maxout == 1) lat_cur <= 0;   // arranca la medida
                    end
                    // ---- colector R ----
                    if (M_RVALID && M_RREADY && M_RLAST) begin
                        completed <= completed + 1'b1;
                        if (b_maxout == 1) begin
                            if (lat_cur < lat_min) lat_min <= lat_cur;
                            if (lat_cur > lat_max) lat_max <= lat_cur;
                        end
                    end
                end else begin
                    // ---- escrituras: emisor AW ----
                    if (!M_AWVALID) begin
                        if (issued < b_nops && outstanding < b_maxout) begin
                            M_AWADDR  <= next_addr;
                            M_AWID    <= issued[5:0];
                            M_AWVALID <= 1'b1;
                        end
                    end else if (M_AWREADY) begin
                        M_AWVALID <= 1'b0;
                        issued    <= issued + 1'b1;
                        addr_seq  <= addr_seq + ({28'd0, b_len} + 1'b1) * 8;
                        if (b_maxout == 1) lat_cur <= 0;
                    end
                    // ---- emisor W: solo rafagas cuya AW ya se emitio ----
                    if (!M_WVALID) begin
                        if (w_bursts < issued) begin
                            M_WDATA  <= {~cycles, cycles};
                            M_WID    <= w_bursts[5:0];
                            M_WLAST  <= (w_beat == {1'b0, b_len});
                            M_WVALID <= 1'b1;
                        end
                    end else if (M_WREADY) begin
                        if (M_WLAST) begin
                            M_WVALID <= 1'b0;
                            M_WLAST  <= 1'b0;
                            w_beat   <= 0;
                            w_bursts <= w_bursts + 1'b1;
                        end else begin
                            w_beat  <= w_beat + 1'b1;
                            M_WDATA <= {~cycles, cycles};
                            M_WLAST <= (w_beat + 1'b1 == {1'b0, b_len});
                        end
                    end
                    // ---- colector B ----
                    if (M_BVALID && M_BREADY) begin
                        completed <= completed + 1'b1;
                        if (b_maxout == 1) begin
                            if (lat_cur < lat_min) lat_min <= lat_cur;
                            if (lat_cur > lat_max) lat_max <= lat_cur;
                        end
                    end
                end

                // ---- fin del benchmark / watchdog ----
                if (completed == b_nops || (&wdog)) begin
                    run <= 1'b0;
                    M_RREADY <= 1'b0; M_BREADY <= 1'b0;
                    M_ARVALID <= 1'b0; M_AWVALID <= 1'b0; M_WVALID <= 1'b0;
                    r_cycles[bench] <= cycles;
                    r_ops[bench]    <= {16'd0, completed};
                    // en timeout, lat_min guarda una foto del atasco:
                    //   [31:24] = {awvalid,awready,wvalid,wready,bvalid,arvalid,arready,rvalid}
                    //   [23:16] = issued[7:0]  [15:8] = w_bursts[7:0]  [7:0] = completed[7:0]
                    r_lmin[bench]   <= (&wdog) ? {M_AWVALID, M_AWREADY, M_WVALID, M_WREADY,
                                                  M_BVALID, M_ARVALID, M_ARREADY, M_RVALID,
                                                  issued[7:0], w_bursts[7:0], completed[7:0]}
                                               : {16'd0, lat_min};
                    r_lmax[bench]   <= (&wdog) ? (32'hDEAD_0000 | {29'd0, bench}) : {16'd0, lat_max};
                    st <= S_STORE;
                end
            end
            // ---------------------------------------------------------
            S_STORE: begin
                if (bench == NB-1) begin
                    res_idx  <= 0;
                    res_pend <= 1'b0;
                    st       <= S_WRES;
                end else begin
                    bench <= bench + 1'b1;
                    st    <= S_START;
                end
            end
            // ---------------------------------------------------------
            // escritura de la tabla: single-beat, AW+W juntos, UNA en vuelo:
            // no se emite la siguiente hasta recibir el B (res_pend).
            S_WRES: begin
                if (M_AWVALID && M_AWREADY) M_AWVALID <= 1'b0;
                if (M_WVALID  && M_WREADY)  M_WVALID  <= 1'b0;
                if (res_pend) begin
                    if (M_BVALID && M_BREADY) begin
                        res_pend <= 1'b0;
                        res_idx  <= res_idx + 1'b1;
                    end
                end else if (res_idx == 2*NB) begin
                    M_BREADY <= 1'b0;
                    st <= S_WMAGIC;
                end else begin
                    M_AWADDR <= res_addr; M_AWLEN <= 0; M_AWID <= 0; M_AWVALID <= 1'b1;
                    M_WDATA  <= res_word; M_WLAST <= 1'b1; M_WID <= 0; M_WVALID <= 1'b1;
                    M_BREADY <= 1'b1;
                    res_pend <= 1'b1;
                end
            end
            // ---------------------------------------------------------
            S_WMAGIC: begin
                if (!M_AWVALID && !M_WVALID && !M_BREADY) begin
                    M_BREADY <= 1'b1;
                    M_AWADDR <= RESULT; M_AWLEN <= 0; M_AWVALID <= 1'b1;
                    M_WDATA  <= {FCLK_MHZ, 32'hB0B0_CAFE}; M_WLAST <= 1'b1; M_WVALID <= 1'b1;
                end else begin
                    if (M_AWVALID && M_AWREADY) M_AWVALID <= 1'b0;
                    if (M_WVALID  && M_WREADY)  M_WVALID  <= 1'b0;
                    if (M_BVALID && M_BREADY) begin
                        M_BREADY <= 1'b0;
                        led  <= 4'b1111;
                        done <= 1'b1;
                        st   <= S_END;
                    end
                end
            end
            S_END: begin end
            default: st <= S_BOOT;
            endcase
        end
    end

endmodule
