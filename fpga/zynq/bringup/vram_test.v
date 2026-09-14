// ============================================================================
//  vram_test.v — cliente sintetico del v9968_axi_backend: hace lo que el shim
//  del V9968 (protocolo wv2 por los canales A y B), verifica los datos y mide
//  ciclos por operacion. Deja la tabla de resultados EN LA PROPIA VRAM (via el
//  canal A) en RES_OFF: si aparece, el camino de escritura funciona.
//
//  Fases (LEDs = fase en binario; 1111 = tabla escrita):
//    0 FILL     escribe N_WORDS palabras de 32 b: w(i) = {~lo(i), lo(i)}, lo = addr[15:0]
//    1 SEQ_A    lee todas las palabras de 16 b por A en orden (hits de cache)
//    2 RND_A    4096 lecturas de 16 b por A en direcciones LFSR (fallos)
//    3 SEQ_B    como 1 por el canal B
//    4 COMBO    4096 veces: A y B piden a la vez dos palabras de la MISMA linea
//    5 MASKED   4096 veces: restaurar la palabra, escribir UN byte invertido
//               (wmask de 1 bit), leer las dos mitades: el byte cambiado y los
//               otros tres intactos (WSTRB + coherencia de la cache)
//    6 WR_RD    4096 veces: escribe una palabra y la lee INMEDIATAMENTE (barrera)
//  Tabla (32 b, little-endian) en RES_OFF:
//    +0 magic 0xB0B0CAFE  +4 FCLK_MHZ
//    +8 + 16*f : { cycles, ops, errors, {max_cyc[15:0], min_cyc[15:0]} }
//  Watchdog por fase (2^26 ciclos): errors |= 0x80000000 y salta a la siguiente.
// ============================================================================
module vram_test #(
    parameter [31:0] FCLK_MHZ = 32'd150,
    parameter        N_WORDS  = 16384,          // 64 KB de VRAM bajo prueba
    parameter [21:0] RES_OFF  = 22'h3F0000      // tabla al final de la ventana de 4 MB
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- canal A (wv2, lado cliente) ----
    output reg         a_req,
    output reg         a_we,
    output reg  [21:0] a_addr,
    output reg  [31:0] a_wdata,
    output reg  [3:0]  a_wmask,
    input  wire [15:0] a_dout,
    input  wire        a_done,
    // ---- canal B ----
    output reg         b_req,
    output reg  [21:0] b_addr,
    input  wire [15:0] b_dout,
    input  wire        b_done,

    output reg  [3:0]  led,
    output reg         done
);

    localparam NF = 7;
    localparam [3:0] S_BOOT = 0, S_START = 1, S_RUN = 2, S_STORE = 3,
                     S_WRES = 4, S_END = 5;
    reg [3:0]  st;
    reg [2:0]  phase;
    reg [19:0] boot;
    reg [25:0] wdog;

    // contadores de la fase
    reg [31:0] cycles, ops, errors;
    reg [15:0] cyc_min, cyc_max, cyc_op;
    reg [15:0] idx;                      // indice de operacion en la fase
    reg [31:0] lfsr;
    wire [31:0] lfsr_next = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};

    // sub-secuencia dentro de una operacion (fases con varios pasos)
    reg [2:0]  sub;
    reg        a_wait, b_wait;           // esperando done de A / B
    reg [15:0] a_got, b_got;
    reg        a_ok,  b_ok;              // done visto en esta operacion
    reg        gap;                      // ciclo de req bajo entre operaciones

    // patron: palabra de 32 b en la direccion ad (alineada a 4) = {~lo, lo},
    // lo = ad[15:0]. La palabra de 16 b en ad16 (alineada a 2) es la mitad
    // baja (lo) si ad16[1]=0 y la alta (~lo) si ad16[1]=1.
    function [31:0] pat32; input [21:0] ad; begin pat32 = {~ad[15:0], ad[15:0]}; end endfunction
    function [15:0] pat16; input [21:0] ad; reg [15:0] lo; begin
        lo = {ad[15:2], 2'b00};
        pat16 = ad[1] ? ~lo : lo;
    end endfunction
    // esperados de la fase MASKED: la palabra w con el byte sel invertido
    function [31:0] masked32; input [31:0] w; input [1:0] sel; begin
        masked32 = w;
        case (sel)
        2'd0: masked32[7:0]   = ~w[7:0];
        2'd1: masked32[15:8]  = ~w[15:8];
        2'd2: masked32[23:16] = ~w[23:16];
        2'd3: masked32[31:24] = ~w[31:24];
        endcase
    end endfunction

    // direccion de la operacion idx en cada fase
    wire [21:0] ad_seq32 = {4'd0, idx, 2'b00};                 // palabra de 32 b
    wire [21:0] ad_seq16 = {5'd0, idx, 1'b0};                  // palabra de 16 b (idx recorre 2*N_WORDS... ver nops)
    wire [21:0] ad_rnd16 = {6'd0, lfsr[14:0], 1'b0};           // dentro de 64 KB
    wire [21:0] ad_rnd32 = {6'd0, lfsr[13:0], 2'b00};
    reg  [15:0] nops;
    always @(*) begin
        case (phase)
        3'd0: nops = N_WORDS;
        3'd1: nops = 2*N_WORDS;
        3'd2: nops = 16'd4096;
        3'd3: nops = 2*N_WORDS;
        3'd4: nops = 16'd4096;
        3'd5: nops = 16'd4096;
        3'd6: nops = 16'd4096;
        default: nops = 16'd0;
        endcase
    end

    // resultados
    reg [31:0] r_cyc [0:NF-1];
    reg [31:0] r_ops [0:NF-1];
    reg [31:0] r_err [0:NF-1];
    reg [31:0] r_mm  [0:NF-1];
    reg [4:0]  res_idx;                  // 0..4*NF-1, luego magic (2 palabras)
    integer i;

    // valor esperado para las lecturas de la fase 5/6 (guardado al escribir)
    reg [31:0] exp32;
    reg [21:0] op_ad;
    wire [31:0] exp_masked = masked32(exp32, lfsr[17:16]);   // fase MASKED

    always @(posedge clk) begin
        if (!rst_n) begin
            st <= S_BOOT; phase <= 0; boot <= 0; wdog <= 0;
            a_req <= 0; a_we <= 0; a_addr <= 0; a_wdata <= 0; a_wmask <= 0;
            b_req <= 0; b_addr <= 0;
            cycles <= 0; ops <= 0; errors <= 0; cyc_min <= 16'hFFFF; cyc_max <= 0; cyc_op <= 0;
            idx <= 0; lfsr <= 32'h1234_ABCD; sub <= 0;
            a_wait <= 0; b_wait <= 0; a_got <= 0; b_got <= 0; a_ok <= 0; b_ok <= 0; gap <= 0;
            res_idx <= 0; led <= 0; done <= 0; exp32 <= 0; op_ad <= 0;
            for (i = 0; i < NF; i = i + 1) begin r_cyc[i] <= 0; r_ops[i] <= 0; r_err[i] <= 0; r_mm[i] <= 0; end
        end else begin
            // captura de dones (pueden llegar en cualquier ciclo de espera)
            if (a_done) begin a_got <= a_dout; a_ok <= 1'b1; end
            if (b_done) begin b_got <= b_dout; b_ok <= 1'b1; end

            case (st)
            S_BOOT: begin
                boot <= boot + 1'b1;
                if (&boot) st <= S_START;
            end
            // ---------------------------------------------------------
            S_START: begin
                led <= {1'b0, phase};
                cycles <= 0; ops <= 0; errors <= 0; cyc_min <= 16'hFFFF; cyc_max <= 0; cyc_op <= 0;
                idx <= 0; sub <= 0; wdog <= 0; gap <= 0;
                a_req <= 0; b_req <= 0; a_ok <= 0; b_ok <= 0;
                st <= S_RUN;
            end
            // ---------------------------------------------------------
            S_RUN: begin
                cycles <= cycles + 1'b1;
                wdog   <= wdog + 1'b1;
                cyc_op <= cyc_op + 1'b1;

                if (&wdog) begin
                    errors <= errors | 32'h8000_0000;
                    a_req <= 0; b_req <= 0;
                    st <= S_STORE;
                end
                else if (gap) begin
                    // ciclo de req en bajo entre operaciones (rearme de *_srv)
                    gap <= 1'b0;
                    if (idx == nops) st <= S_STORE;
                end
                else if (!a_req && !b_req && !a_wait && !b_wait) begin
                    // ---- emitir la operacion idx (o su sub-paso) ----
                    a_ok <= 0; b_ok <= 0; cyc_op <= 0;
                    case (phase)
                    3'd0: begin   // FILL
                        a_req <= 1; a_we <= 1; a_addr <= ad_seq32;
                        a_wdata <= pat32(ad_seq32); a_wmask <= 4'b1111; a_wait <= 1;
                    end
                    3'd1: begin   // SEQ_A
                        a_req <= 1; a_we <= 0; a_addr <= ad_seq16; a_wait <= 1;
                    end
                    3'd2: begin   // RND_A
                        a_req <= 1; a_we <= 0; a_addr <= ad_rnd16; a_wait <= 1;
                    end
                    3'd3: begin   // SEQ_B
                        b_req <= 1; b_addr <= ad_seq16; b_wait <= 1;
                    end
                    3'd4: begin   // COMBO: A = palabra baja, B = palabra alta de la misma linea
                        a_req <= 1; a_we <= 0; a_addr <= {ad_rnd32[21:4], 4'b0010}; a_wait <= 1;
                        b_req <= 1;            b_addr <= {ad_rnd32[21:4], 4'b1100}; b_wait <= 1;
                    end
                    3'd5: begin   // MASKED: sub 0 = restaurar la palabra entera (el LFSR
                                  // repite direcciones); sub 1 = escribir 1 byte invertido;
                                  // sub 2 = leer mitad baja; sub 3 = leer mitad alta
                        if (sub == 0) begin
                            op_ad <= ad_rnd32;
                            exp32 <= pat32(ad_rnd32);
                            a_req <= 1; a_we <= 1; a_addr <= ad_rnd32;
                            a_wdata <= pat32(ad_rnd32); a_wmask <= 4'b1111; a_wait <= 1;
                        end else if (sub == 1) begin
                            a_req <= 1; a_we <= 1; a_addr <= op_ad;
                            a_wdata <= ~exp32;                     // byte elegido por lfsr[17:16]
                            a_wmask <= 4'b0001 << lfsr[17:16];
                            a_wait <= 1;
                        end else if (sub == 2) begin
                            a_req <= 1; a_we <= 0; a_addr <= op_ad; a_wait <= 1;
                        end else begin
                            a_req <= 1; a_we <= 0; a_addr <= op_ad | 22'd2; a_wait <= 1;
                        end
                    end
                    3'd6: begin   // WR_RD: sub 0 = escribir palabra nueva; sub 1 = leer mitad baja
                        if (sub == 0) begin
                            op_ad <= ad_rnd32;
                            exp32 <= pat32(ad_rnd32) ^ {lfsr[31:16], lfsr[31:16]};
                            a_req <= 1; a_we <= 1; a_addr <= ad_rnd32;
                            a_wdata <= pat32(ad_rnd32) ^ {lfsr[31:16], lfsr[31:16]};
                            a_wmask <= 4'b1111; a_wait <= 1;
                        end else begin
                            a_req <= 1; a_we <= 0; a_addr <= op_ad; a_wait <= 1;
                        end
                    end
                    default: st <= S_STORE;
                    endcase
                end
                else begin
                    // ---- esperando dones ----
                    if (a_wait && (a_ok || a_done)) begin a_wait <= 0; a_req <= 0; end
                    if (b_wait && (b_ok || b_done)) begin b_wait <= 0; b_req <= 0; end

                    if ((!a_wait || a_ok || a_done) && (!b_wait || b_ok || b_done)) begin
                        // operacion (o sub-paso) completada: verificar y avanzar
                        if (cyc_op < cyc_min) cyc_min <= cyc_op;
                        if (cyc_op > cyc_max) cyc_max <= cyc_op;
                        gap <= 1'b1;
                        case (phase)
                        3'd0: begin ops <= ops + 1; idx <= idx + 1; end
                        3'd1, 3'd2: begin
                            ops <= ops + 1;
                            if ((a_done ? a_dout : a_got) != pat16(a_addr)) errors <= errors + 1;
                            idx <= idx + 1; lfsr <= lfsr_next;
                        end
                        3'd3: begin
                            ops <= ops + 1;
                            if ((b_done ? b_dout : b_got) != pat16(b_addr)) errors <= errors + 1;
                            idx <= idx + 1;
                        end
                        3'd4: begin
                            ops <= ops + 1;
                            if ((a_done ? a_dout : a_got) != pat16(a_addr)) errors <= errors + 1;
                            if ((b_done ? b_dout : b_got) != pat16(b_addr)) errors <= errors + 1;
                            idx <= idx + 1; lfsr <= lfsr_next;
                        end
                        3'd5: begin
                            if (sub == 0) sub <= 1;
                            else if (sub == 1) sub <= 2;
                            else if (sub == 2) begin
                                if ((a_done ? a_dout : a_got) != exp_masked[15:0]) errors <= errors + 1;
                                sub <= 3;
                            end else begin
                                if ((a_done ? a_dout : a_got) != exp_masked[31:16]) errors <= errors + 1;
                                sub <= 0; ops <= ops + 1; idx <= idx + 1; lfsr <= lfsr_next;
                            end
                        end
                        3'd6: begin
                            if (sub == 0) sub <= 1;
                            else begin
                                if ((a_done ? a_dout : a_got) != exp32[15:0]) errors <= errors + 1;
                                sub <= 0; ops <= ops + 1; idx <= idx + 1; lfsr <= lfsr_next;
                            end
                        end
                        default: ;
                        endcase
                    end
                end
            end
            // ---------------------------------------------------------
            S_STORE: begin
                r_cyc[phase] <= cycles; r_ops[phase] <= ops; r_err[phase] <= errors;
                r_mm[phase]  <= {cyc_max, cyc_min};
                a_req <= 0; b_req <= 0; a_wait <= 0; b_wait <= 0;
                if (phase == NF-1) begin res_idx <= 0; gap <= 0; st <= S_WRES; end
                else begin phase <= phase + 1'b1; st <= S_START; end
            end
            // ---------------------------------------------------------
            // tabla via canal A: 4 palabras por fase + {magic, fclk}
            S_WRES: begin
                if (gap) begin
                    gap <= 0;
                    if (res_idx == 4*NF + 2) begin led <= 4'b1111; done <= 1; st <= S_END; end
                end
                else if (!a_req && !a_wait) begin
                    a_req <= 1; a_we <= 1; a_wmask <= 4'b1111; a_wait <= 1; a_ok <= 0;
                    if (res_idx < 4*NF) begin
                        a_addr  <= RES_OFF + 22'd8 + {res_idx, 2'b00};
                        case (res_idx[1:0])
                        2'd0: a_wdata <= r_cyc[res_idx[4:2]];
                        2'd1: a_wdata <= r_ops[res_idx[4:2]];
                        2'd2: a_wdata <= r_err[res_idx[4:2]];
                        2'd3: a_wdata <= r_mm [res_idx[4:2]];
                        endcase
                    end
                    else if (res_idx == 4*NF) begin a_addr <= RES_OFF + 22'd4; a_wdata <= FCLK_MHZ; end
                    else begin a_addr <= RES_OFF; a_wdata <= 32'hB0B0_CAFE; end
                end
                else if (a_wait && (a_ok || a_done)) begin
                    a_wait <= 0; a_req <= 0; gap <= 1; res_idx <= res_idx + 1'b1;
                end
            end
            S_END: begin end
            default: st <= S_BOOT;
            endcase
        end
    end

endmodule
