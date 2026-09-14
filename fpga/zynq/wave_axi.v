// ============================================================================
//  wave_axi.v — memoria de ondas del OPL4 (MoonSound) en la DDR del PS (Zynq)
// ----------------------------------------------------------------------------
//  Sustituye a wave_sdram.v (Tang). Solo hace falta la cara del MOTOR (opl4_pcm):
//    eng_req   pulso de 1 ciclo = nueva operacion; eng_we, eng_addr (byte, 4 MB),
//    eng_wdata; devuelve eng_rdata (el byte) y eng_rword (la PALABRA de 16 bits
//    que lo contiene, little-endian, para la cache de palabra) y conmuta
//    eng_done_t. El motor no encadena peticiones: espera el toggle.
//  Mapa: BASE + 0x000000..0x1FFFFF = YRW801 (la carga boot.tcl / BOOT.bin),
//        BASE + 0x200000..0x3FFFFF = RAM de muestras (escrituras del OPL4).
//  AXI3 maestro de 32 bits en el S_AXI_GP0 del PS7, MISMO reloj que el motor
//  (clk_wave375 = 37,5 MHz): sin CDC. Una transaccion de un beat por operacion:
//  lectura de la palabra de 32 bits alineada y seleccion del byte/palabra;
//  escritura con WSTRB del byte. Drena B/R en reset (el PS no se resetea con el PL).
// ============================================================================
module wave_axi #(
    parameter [31:0] BASE = 32'h0F00_0000
)(
    input  wire        clk,             // clk_wave375 = ACLK del GP0
    input  wire        aresetn,         // reset del PL (frst0_n): NUNCA corta una transaccion AXI
    input  wire        eng_rst_n,       // reset del motor (opl4pcm_rst_n): eng_done_t a 0 y sin toggles
                                        // mientras dure, para que el motor arranque con done_d1 == done_t

    input  wire        eng_req,
    input  wire        eng_we,
    input  wire [21:0] eng_addr,
    input  wire [7:0]  eng_wdata,
    output reg  [7:0]  eng_rdata,
    output reg  [15:0] eng_rword,
    output reg         eng_done_t,
    output wire [7:0]  diag,            // {err_resp, 3'b0, ops[3:0]}   (formato del 34h del Tang)
    output wire [23:0] tel,             // telemetria: {lat_max[7:0] ciclos AR->R, rd_cnt[7:0], wr_cnt[7:0]}

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
    output reg  [31:0] M_WDATA,
    output reg  [3:0]  M_WSTRB,
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
    input  wire [31:0] M_RDATA,
    input  wire [1:0]  M_RRESP,
    input  wire        M_RLAST,
    input  wire        M_RVALID,
    output reg         M_RREADY
);
    assign M_AWLEN = 4'd0;  assign M_AWSIZE = 3'b010; assign M_AWBURST = 2'b01;
    assign M_AWLOCK = 2'b00; assign M_AWCACHE = 4'b0011; assign M_AWPROT = 3'b000; assign M_AWQOS = 4'd0;
    assign M_WLAST = 1'b1;
    assign M_ARLEN = 4'd0;  assign M_ARSIZE = 3'b010; assign M_ARBURST = 2'b01;
    assign M_ARLOCK = 2'b00; assign M_ARCACHE = 4'b0011; assign M_ARPROT = 3'b000; assign M_ARQOS = 4'd0;

    localparam [2:0] S_IDLE = 3'd0, S_AW = 3'd1, S_B = 3'd2, S_AR = 3'd3, S_R = 3'd4;
    reg [2:0]  st;
    reg        pend, pend_we;              // peticion latcheada (por si llega ocupado)
    reg [21:0] pend_addr;
    reg [7:0]  pend_wdata;
    reg [1:0]  lane;
    reg        aw_done, w_done;
    reg        err_resp;
    reg [3:0]  ops;
    reg [7:0]  lat, lat_max, rd_cnt, wr_cnt;
    assign diag = {err_resp, 3'b000, ops};
    assign tel  = {lat_max, rd_cnt, wr_cnt};
    reg [1:0]  ers = 2'b00;                 // eng_rst_n sincronizado (como hace opl4_pcm)
    always @(posedge clk) ers <= {ers[0], eng_rst_n};
    wire erst = ers[1];

    wire aw_acc = M_AWVALID && M_AWREADY;
    wire w_acc  = M_WVALID  && M_WREADY;
    wire b_acc  = M_BVALID  && M_BREADY;
    wire ar_acc = M_ARVALID && M_ARREADY;
    wire r_acc  = M_RVALID  && M_RREADY;

    always @(posedge clk) begin
        if (!aresetn) begin
            st <= S_IDLE; pend <= 1'b0; pend_we <= 1'b0; pend_addr <= 22'd0; pend_wdata <= 8'd0;
            lane <= 2'd0; aw_done <= 1'b0; w_done <= 1'b0; err_resp <= 1'b0; ops <= 4'd0;
            lat <= 8'd0; lat_max <= 8'd0; rd_cnt <= 8'd0; wr_cnt <= 8'd0;
            eng_rdata <= 8'd0; eng_rword <= 16'd0; eng_done_t <= 1'b0;
            M_AWVALID <= 1'b0; M_WVALID <= 1'b0; M_ARVALID <= 1'b0;
            M_AWID <= 6'd0; M_WID <= 6'd0; M_ARID <= 6'd0;
            M_AWADDR <= 32'd0; M_ARADDR <= 32'd0; M_WDATA <= 32'd0; M_WSTRB <= 4'd0;
            M_BREADY <= 1'b1; M_RREADY <= 1'b1;            // drenar herencias del PS
        end else begin
            M_BREADY <= 1'b1; M_RREADY <= 1'b1;
            if (!erst) begin pend <= 1'b0; eng_done_t <= 1'b0; end
            else if (eng_req) begin pend <= 1'b1; pend_we <= eng_we; pend_addr <= eng_addr; pend_wdata <= eng_wdata; end
            if (aw_acc) begin M_AWVALID <= 1'b0; aw_done <= 1'b1; end
            if (w_acc)  begin M_WVALID  <= 1'b0; w_done  <= 1'b1; end
            if (ar_acc) M_ARVALID <= 1'b0;
            if (st == S_R) begin
                if (lat != 8'hFF) lat <= lat + 8'd1;
            end else lat <= 8'd0;

            case (st)
            S_IDLE: if (pend) begin
                pend <= 1'b0;
                lane <= pend_addr[1:0];
                if (pend_we) begin
                    M_AWADDR <= BASE + {10'd0, pend_addr[21:2], 2'b00};
                    M_WDATA  <= {4{pend_wdata}};
                    M_WSTRB  <= 4'b0001 << pend_addr[1:0];
                    M_AWVALID <= 1'b1; M_WVALID <= 1'b1;
                    aw_done <= 1'b0; w_done <= 1'b0;
                    st <= S_B;
                end else begin
                    M_ARADDR <= BASE + {10'd0, pend_addr[21:2], 2'b00};
                    M_ARVALID <= 1'b1;
                    st <= S_R;
                end
            end
            S_B: if ((aw_done || aw_acc) && (w_done || w_acc) && b_acc) begin
                if (M_BRESP != 2'b00) err_resp <= 1'b1;
                ops <= ops + 4'd1; wr_cnt <= wr_cnt + 8'd1;
                if (erst) eng_done_t <= ~eng_done_t;
                st <= S_IDLE;
            end
            S_R: if (r_acc) begin
                if (M_RRESP != 2'b00) err_resp <= 1'b1;
                if (lat > lat_max) lat_max <= lat;
                rd_cnt <= rd_cnt + 8'd1;
                case (lane)
                2'd0: eng_rdata <= M_RDATA[7:0];
                2'd1: eng_rdata <= M_RDATA[15:8];
                2'd2: eng_rdata <= M_RDATA[23:16];
                default: eng_rdata <= M_RDATA[31:24];
                endcase
                eng_rword <= lane[1] ? M_RDATA[31:16] : M_RDATA[15:0];
                ops <= ops + 4'd1;
                if (erst) eng_done_t <= ~eng_done_t;
                st <= S_IDLE;
            end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule
