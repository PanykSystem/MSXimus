// ============================================================================
//  ram_test.v — cliente sintetico del puerto ram_* de memory_axi: hace lo que
//  el lado Z80 de top.v (req a NIVEL, esperar busy alto y bajo, capturar dout,
//  soltar req) sobre dl/dh generados como con el V9968. Verifica datos y mide
//  ciclos de clk_54m por acceso. Tabla de resultados escrita A TRAVES DEL PROPIO
//  memory_axi (bytes) en RES_OFF.
//
//  Fases (LEDs = fase; 1111 = tabla escrita):
//    0 PS_LOAD  lee 16 KB que xsdb pre-cargo en la DDR (mwr) ANTES de soltar el
//               PL: fallos reales + coherencia con el cargador (el PS)
//    1 FILL     escribe 64 KB byte a byte: b(a) = a[7:0] ^ a[15:8] ^ 0x5A
//    2 SEQ      lee los 64 KB en orden (1 fallo cada 16 bytes)
//    3 RND      8192 lecturas aleatorias en los 64 KB
//    4 WR_RD    4096 veces: escribe un byte aleatorio, lo lee inmediatamente y
//               restaura el patron (para que SEQ2/INVAL verifiquen)
//    5 SEQ2     otra pasada secuencial: con 64 KB de cache = todo hits
//    6 INVAL    cpu_run=0 durante 6000 ciclos (barrido) y otra pasada: fallos otra vez
//  Tabla (32 b) en RES_OFF: +0 magic, +4 fclk, +8+16*f {cycles, ops, err, {max,min}},
//  +8+16*7 {dbg_hits, dbg_miss}.
// ============================================================================
module ram_test #(
    parameter [31:0] FCLK_MHZ = 32'd54,
    parameter [22:0] RES_OFF  = 23'h7F0000,
    parameter [22:0] PS_OFF   = 23'h100000     // 16 KB que carga xsdb en RAM_BASE+PS_OFF
)(
    input  wire        clk,            // clk_54m
    input  wire        rst_n,

    output reg         ram_req,
    output reg         ram_write,
    output reg  [22:0] ram_addr,
    output reg  [7:0]  ram_din,
    input  wire [7:0]  ram_dout,
    input  wire        ram_busy,
    output reg         cpu_run,

    input  wire [31:0] dbg_hits,
    input  wire [31:0] dbg_miss,

    output reg  [3:0]  led,
    output reg         done
);
    localparam NF = 7;
    localparam [3:0] S_BOOT=0, S_START=1, S_ISSUE=2, S_WBUSY=3, S_WDONE=4, S_GAP=5,
                     S_STORE=6, S_INV=7, S_WRES=8, S_END=9;
    reg [3:0]  st;
    reg [2:0]  phase;
    reg [19:0] boot;
    reg [25:0] wdog;
    reg [31:0] cycles, ops, errors;
    reg [15:0] cyc_min, cyc_max, cyc_op;
    reg [16:0] idx;
    reg [31:0] lfsr;
    wire [31:0] lfsr_next = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
    reg [1:0]  sub;
    reg [22:0] op_ad;
    reg [7:0]  op_exp;
    reg [12:0] inv_cnt;

    function [7:0] pat; input [22:0] a; begin pat = a[7:0] ^ a[15:8] ^ 8'h5A; end endfunction
    function [7:0] pat_ps; input [22:0] a; begin pat_ps = a[7:0] ^ a[15:8] ^ 8'hC3; end endfunction

    reg [16:0] nops;
    always @(*) begin
        case (phase)
        3'd0: nops = 17'd16384;
        3'd1: nops = 17'd65536;
        3'd2: nops = 17'd65536;
        3'd3: nops = 17'd8192;
        3'd4: nops = 17'd4096;
        3'd5: nops = 17'd65536;
        3'd6: nops = 17'd65536;
        default: nops = 17'd0;
        endcase
    end

    reg [31:0] r_cyc [0:NF-1];
    reg [31:0] r_ops [0:NF-1];
    reg [31:0] r_err [0:NF-1];
    reg [31:0] r_mm  [0:NF-1];
    reg [7:0]  res_idx;          // byte de la tabla en curso (0..127), 128 = fin
    integer i;

    wire [6:0] wr_off = res_idx[6:0] + 7'd4;       // (mod 128) el magic (palabra 0) va al final

    always @(posedge clk) begin
        if (!rst_n) begin
            st <= S_BOOT; phase <= 0; boot <= 0; wdog <= 0;
            ram_req <= 0; ram_write <= 0; ram_addr <= 0; ram_din <= 0; cpu_run <= 1'b0;
            cycles <= 0; ops <= 0; errors <= 0; cyc_min <= 16'hFFFF; cyc_max <= 0; cyc_op <= 0;
            idx <= 0; lfsr <= 32'h2468_ACE1; sub <= 0; op_ad <= 0; op_exp <= 0; inv_cnt <= 0;
            res_idx <= 0; led <= 0; done <= 0;
            for (i = 0; i < NF; i = i + 1) begin r_cyc[i] <= 0; r_ops[i] <= 0; r_err[i] <= 0; r_mm[i] <= 0; end
        end else begin
            case (st)
            S_BOOT: begin
                boot <= boot + 1'b1;
                if (&boot) begin cpu_run <= 1'b1; st <= S_START; end
            end
            S_START: begin
                led <= {1'b0, phase};
                cycles <= 0; ops <= 0; errors <= 0; cyc_min <= 16'hFFFF; cyc_max <= 0;
                idx <= 0; sub <= 2'd0; wdog <= 0;
                if (phase == 3'd6) begin cpu_run <= 1'b0; inv_cnt <= 0; st <= S_INV; end
                else st <= S_ISSUE;
            end
            S_INV: begin                      // barrido de invalidacion con la CPU parada
                inv_cnt <= inv_cnt + 1'b1;
                if (inv_cnt == 13'd6000) begin cpu_run <= 1'b1; st <= S_ISSUE; end
            end
            // ---- emitir un acceso ----
            S_ISSUE: begin
                cycles <= cycles + 1'b1; wdog <= wdog + 1'b1;
                if (idx == nops) st <= S_STORE;
                else begin
                    cyc_op <= 0;
                    ram_req <= 1'b1;
                    case (phase)
                    3'd0: begin ram_write <= 0; ram_addr <= PS_OFF + {9'd0, idx[13:0]}; op_exp <= pat_ps(PS_OFF + {9'd0, idx[13:0]}); end
                    3'd1: begin ram_write <= 1; ram_addr <= {7'd0, idx[15:0]}; ram_din <= pat({7'd0, idx[15:0]}); end
                    3'd2, 3'd5, 3'd6: begin ram_write <= 0; ram_addr <= {7'd0, idx[15:0]}; op_exp <= pat({7'd0, idx[15:0]}); end
                    3'd3: begin ram_write <= 0; ram_addr <= {7'd0, lfsr[15:0]}; op_exp <= pat({7'd0, lfsr[15:0]}); end
                    3'd4: begin   // sub 0 = escribir byte aleatorio; 1 = leerlo; 2 = restaurar pat()
                        if (sub == 2'd0) begin
                            op_ad <= {7'd0, lfsr[15:0]}; op_exp <= lfsr[23:16];
                            ram_write <= 1; ram_addr <= {7'd0, lfsr[15:0]}; ram_din <= lfsr[23:16];
                        end else if (sub == 2'd1) begin
                            ram_write <= 0; ram_addr <= op_ad;
                        end else begin
                            ram_write <= 1; ram_addr <= op_ad; ram_din <= pat(op_ad);
                        end
                    end
                    default: ;
                    endcase
                    st <= S_WBUSY;
                end
            end
            S_WBUSY: begin
                cycles <= cycles + 1'b1; wdog <= wdog + 1'b1; cyc_op <= cyc_op + 1'b1;
                if (ram_busy) st <= S_WDONE;
                else if (&wdog) begin errors <= errors | 32'h8000_0000; ram_req <= 0; st <= S_STORE; end
            end
            S_WDONE: begin
                cycles <= cycles + 1'b1; wdog <= wdog + 1'b1; cyc_op <= cyc_op + 1'b1;
                if (!ram_busy) begin
                    ram_req <= 1'b0;
                    if (cyc_op < cyc_min) cyc_min <= cyc_op;
                    if (cyc_op > cyc_max) cyc_max <= cyc_op;
                    if (!ram_write && ram_dout != op_exp) errors <= errors + 1'b1;
                    // avance
                    if (phase == 3'd4) begin
                        if (sub != 2'd2) sub <= sub + 1'b1;
                        else begin sub <= 2'd0; ops <= ops + 1'b1; idx <= idx + 1'b1; lfsr <= lfsr_next; end
                    end else begin
                        ops <= ops + 1'b1; idx <= idx + 1'b1;
                        if (phase == 3'd3) lfsr <= lfsr_next;
                    end
                    st <= S_GAP;
                end
                else if (&wdog) begin errors <= errors | 32'h8000_0000; ram_req <= 0; st <= S_STORE; end
            end
            S_GAP: begin cycles <= cycles + 1'b1; st <= S_ISSUE; end
            // ---- fin de fase ----
            S_STORE: begin
                r_cyc[phase] <= cycles; r_ops[phase] <= ops; r_err[phase] <= errors; r_mm[phase] <= {cyc_max, cyc_min};
                ram_req <= 0;
                if (phase == NF-1) begin res_idx <= 8'd0; st <= S_WRES; end
                else begin phase <= phase + 1'b1; st <= S_START; end
            end
            // ---- tabla: 32 palabras = 128 bytes, byte a byte por ram_*; magic al final ----
            S_WRES: begin
                if (!ram_req) begin
                    if (res_idx == 8'd128) begin led <= 4'b1111; done <= 1; st <= S_END; end
                    else begin
                        // orden: primero las palabras 1..31, y el magic (palabra 0) los ultimos 4 bytes
                        ram_req <= 1'b1; ram_write <= 1'b1;
                        ram_addr <= RES_OFF + {16'd0, wr_off};
                        ram_din  <= tbl_byte(wr_off);
                    end
                end
                else if (ram_busy) sub <= 2'd1;
                else if (sub != 2'd0) begin sub <= 2'd0; ram_req <= 1'b0; res_idx <= res_idx + 1'b1; end
            end
            S_END: begin end
            default: st <= S_BOOT;
            endcase
        end
    end

    // byte off (0..127) de la tabla: palabra 0 = magic, 1 = fclk, 2..29 = 7 fases
    // x {cyc, ops, err, mm}, 30 = dbg_hits, 31 = dbg_miss
    function [7:0] tbl_byte; input [6:0] off; reg [4:0] w; reg [4:0] k; reg [31:0] wv; begin
        w = off[6:2];
        k = w - 5'd2;
        if (w == 5'd0)       wv = 32'hB0B0_CAFE;
        else if (w == 5'd1)  wv = FCLK_MHZ;
        else if (w < 5'd30) begin
            case (k[1:0])
            2'd0: wv = r_cyc[k[4:2]];
            2'd1: wv = r_ops[k[4:2]];
            2'd2: wv = r_err[k[4:2]];
            default: wv = r_mm[k[4:2]];
            endcase
        end
        else if (w == 5'd30) wv = dbg_hits;
        else                 wv = dbg_miss;
        tbl_byte = wv[off[1:0]*8 +: 8];
    end endfunction

endmodule
