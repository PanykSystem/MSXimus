// ============================================================================
//  dbg_mailbox_axi.v — buzon de depuracion en la DDR del PS (Zynq), via HP
// ----------------------------------------------------------------------------
//  "Manos y ojos" para xsdb sin hardware extra:
//    * ENTRADA  (MBOX+0x00, 16 B): bitmap de teclado de 128 bits indexado por
//      keycode HID (el mismo formato que usb_kbd_decode). El PL lo lee cada
//      ~1 ms; el top hace OR con el del USB. xsdb "pulsa" una tecla poniendo su
//      bit y quitandolo ~100 ms despues (tools/key.tcl).
//    * SALIDA (MBOX+0x40, 32 B): telemetria escrita cada ~1 ms:
//        +0x40 {seq[31:0], 32'h4D424F58 'MBOX'}  +0x48 {mem_dbg_miss, mem_dbg_hits}
//        +0x50 {status[31:0], kbd_echo[31:0]}    +0x58 reservado (0)
//  AXI3 master minimo a clk_54m (sin CDC con el nucleo): una transaccion en
//  vuelo, lectura de 2 beats, escrituras single-beat. Drena B/R en reset (el HP
//  del PS no se resetea al reprogramar el PL — medido en 05_hp_bench).
// ============================================================================
module dbg_mailbox_axi #(
    parameter [31:0] MBOX    = 32'h1FF0_0000,
    parameter        PERIOD  = 54000,           // ciclos entre rondas (~1 ms a 54 MHz)
    parameter        ENABLE  = 1                // 0 = instanciado pero sin trafico (biseccion)
)(
    input  wire         clk,
    input  wire         aresetn,

    output reg  [127:0] kbd_mbox,               // bitmap HID leido del buzon
    // +0x10..+0x1F (companion ARM, USB host): joysticks en formato SNES del BL616 y
    // raton como acumulados int16 (ax, ay) + botones -> aqui se saca el delta entre
    // dos lecturas (clamp a +-127, el resto queda para la siguiente) y un pulso.
    output reg  [15:0]  joy1,
    output reg  [15:0]  joy2,
    output reg  [7:0]   mouse_btn,
    output reg  [7:0]   mouse_dx,
    output reg  [7:0]   mouse_dy,
    output reg          mouse_rep,              // pulso de un ciclo: nuevo informe de raton
    input  wire [31:0]  tel_hits,
    input  wire [31:0]  tel_miss,
    input  wire [31:0]  tel_status,
    input  wire [31:0]  tel_dbg,
    input  wire [31:0]  tel_dbg2,
    input  wire [31:0]  tel_dbg3,               // +0x60 {tel_dbg3, tel_dbg4}
    input  wire [31:0]  tel_dbg4,

    output reg  [5:0]   M_AWID,
    output reg  [31:0]  M_AWADDR,
    output wire [3:0]   M_AWLEN,
    output wire [2:0]   M_AWSIZE,
    output wire [1:0]   M_AWBURST,
    output wire [1:0]   M_AWLOCK,
    output wire [3:0]   M_AWCACHE,
    output wire [2:0]   M_AWPROT,
    output wire [3:0]   M_AWQOS,
    output reg          M_AWVALID,
    input  wire         M_AWREADY,
    output reg  [5:0]   M_WID,
    output reg  [63:0]  M_WDATA,
    output wire [7:0]   M_WSTRB,
    output wire         M_WLAST,
    output reg          M_WVALID,
    input  wire         M_WREADY,
    input  wire [5:0]   M_BID,
    input  wire [1:0]   M_BRESP,
    input  wire         M_BVALID,
    output reg          M_BREADY,
    output reg  [5:0]   M_ARID,
    output reg  [31:0]  M_ARADDR,
    output wire [3:0]   M_ARLEN,
    output wire [2:0]   M_ARSIZE,
    output wire [1:0]   M_ARBURST,
    output wire [1:0]   M_ARLOCK,
    output wire [3:0]   M_ARCACHE,
    output wire [2:0]   M_ARPROT,
    output wire [3:0]   M_ARQOS,
    output reg          M_ARVALID,
    input  wire         M_ARREADY,
    input  wire [5:0]   M_RID,
    input  wire [63:0]  M_RDATA,
    input  wire [1:0]   M_RRESP,
    input  wire         M_RLAST,
    input  wire         M_RVALID,
    output reg          M_RREADY
);
    assign M_AWLEN = 4'd0;  assign M_AWSIZE = 3'b011; assign M_AWBURST = 2'b01;
    assign M_AWLOCK = 2'b00; assign M_AWCACHE = 4'b0011; assign M_AWPROT = 3'b000; assign M_AWQOS = 4'd0;
    assign M_WSTRB = 8'hFF; assign M_WLAST = 1'b1;
    assign M_ARLEN = 4'd3;  assign M_ARSIZE = 3'b011; assign M_ARBURST = 2'b01;   // 4 beats = 32 B (teclado + joy/raton)
    assign M_ARLOCK = 2'b00; assign M_ARCACHE = 4'b0011; assign M_ARPROT = 3'b000; assign M_ARQOS = 4'd0;

    localparam [2:0] S_WAIT = 3'd0, S_RD = 3'd1, S_RDATA = 3'd2, S_WR = 3'd3, S_WRESP = 3'd4;
    reg [2:0]  st;
    reg [15:0] tick;
    reg [1:0]  r_beat;
    reg [63:0] r_lo, r_hi;
    reg [15:0] ax_p, ay_p;                                 // acumulados ya entregados
    reg [7:0]  btn_p;
    wire [15:0] ax_n = M_RDATA[15:0], ay_n = M_RDATA[31:16];   // beat 3
    wire signed [16:0] ddx = $signed({ax_n[15], ax_n}) - $signed({ax_p[15], ax_p});
    wire signed [16:0] ddy = $signed({ay_n[15], ay_n}) - $signed({ay_p[15], ay_p});
    wire signed [7:0]  cdx = (ddx > 17'sd127) ? 8'sd127 : (ddx < -17'sd127) ? -8'sd127 : ddx[7:0];
    wire signed [7:0]  cdy = (ddy > 17'sd127) ? 8'sd127 : (ddy < -17'sd127) ? -8'sd127 : ddy[7:0];
    reg [2:0]  widx;                 // palabra de telemetria en curso (0..4)
    reg [31:0] seq;
    reg        aw_done, w_done;

    wire aw_acc = M_AWVALID && M_AWREADY;
    wire w_acc  = M_WVALID  && M_WREADY;
    wire b_acc  = M_BVALID  && M_BREADY;
    wire ar_acc = M_ARVALID && M_ARREADY;
    wire r_acc  = M_RVALID  && M_RREADY;

    reg [63:0] wword;
    always @(*) begin
        case (widx)
        3'd0: wword = {seq, 32'h4D42_4F58};
        3'd1: wword = {tel_miss, tel_hits};
        3'd2: wword = {tel_status, kbd_mbox[31:0]};
        3'd3: wword = {tel_dbg, tel_dbg2};
        3'd4: wword = {tel_dbg3, tel_dbg4};
        default: wword = 64'd0;
        endcase
    end

    always @(posedge clk) begin
        if (!aresetn) begin
            st <= S_WAIT; tick <= 16'd0; r_beat <= 2'd0; r_lo <= 64'd0; r_hi <= 64'd0; widx <= 3'd0; seq <= 32'd0;
            aw_done <= 1'b0; w_done <= 1'b0; kbd_mbox <= 128'd0;
            joy1 <= 16'd0; joy2 <= 16'd0; mouse_btn <= 8'd0; mouse_dx <= 8'd0; mouse_dy <= 8'd0; mouse_rep <= 1'b0;
            ax_p <= 16'd0; ay_p <= 16'd0; btn_p <= 8'd0;
            M_AWVALID <= 1'b0; M_WVALID <= 1'b0; M_ARVALID <= 1'b0;
            M_AWID <= 6'd0; M_WID <= 6'd0; M_ARID <= 6'd0;
            M_AWADDR <= 32'd0; M_ARADDR <= 32'd0; M_WDATA <= 64'd0;
            M_BREADY <= 1'b1; M_RREADY <= 1'b1;            // drenar herencias del HP
        end else begin
            M_BREADY <= 1'b1; M_RREADY <= 1'b1;
            mouse_rep <= 1'b0;
            if (aw_acc) begin M_AWVALID <= 1'b0; aw_done <= 1'b1; end
            if (w_acc)  begin M_WVALID  <= 1'b0; w_done  <= 1'b1; end
            if (ar_acc) M_ARVALID <= 1'b0;

            case (st)
            S_WAIT: begin
                tick <= tick + 1'b1;
                if (ENABLE && tick == PERIOD[15:0]) begin
                    tick <= 16'd0;
                    M_ARADDR <= MBOX; M_ARID <= 6'd0; M_ARVALID <= 1'b1; r_beat <= 2'd0;
                    st <= S_RD;
                end
            end
            S_RD: if (ar_acc || !M_ARVALID) st <= S_RDATA;
            S_RDATA: begin
                if (r_acc) begin
                    r_beat <= r_beat + 2'd1;
                    case (r_beat)
                    2'd0: r_lo <= M_RDATA;
                    2'd1: begin r_hi <= M_RDATA; kbd_mbox <= {M_RDATA, r_lo}; end
                    2'd2: begin joy1 <= M_RDATA[15:0]; joy2 <= M_RDATA[31:16]; btn_p <= M_RDATA[39:32]; end   // +0x10 joy, +0x14 btn|seq
                    default: begin                                                                          // +0x18 {ay, ax}
                        if (ax_n != ax_p || ay_n != ay_p || btn_p != mouse_btn) begin
                            mouse_dx <= cdx; mouse_dy <= cdy; mouse_btn <= btn_p; mouse_rep <= 1'b1;
                            ax_p <= ax_p + {{8{cdx[7]}}, cdx}; ay_p <= ay_p + {{8{cdy[7]}}, cdy};
                        end
                        widx <= 3'd0;
                        st <= S_WR;
                    end
                    endcase
                end
            end
            S_WR: begin
                M_AWADDR <= MBOX + 32'h40 + {widx, 3'b000}; M_AWID <= 6'd0; M_WID <= 6'd0;
                M_WDATA  <= wword;
                M_AWVALID <= 1'b1; M_WVALID <= 1'b1;
                aw_done <= 1'b0; w_done <= 1'b0;
                st <= S_WRESP;
            end
            S_WRESP: begin
                if ((aw_done || aw_acc) && (w_done || w_acc) && b_acc) begin
                    if (widx == 3'd4) begin seq <= seq + 1'b1; st <= S_WAIT; end
                    else begin widx <= widx + 1'b1; st <= S_WR; end
                end
            end
            default: st <= S_WAIT;
            endcase
        end
    end
endmodule
