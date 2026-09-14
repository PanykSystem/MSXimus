// ============================================================================
//  hdmi720_top.sv — TEST HDMI 720p60 en la ZYNQ MINI (XC7Z020): el modo REAL del MSXimus v3
// ----------------------------------------------------------------------------
//  Port 1:1 del fpga/test_hdmi/hdmi_test_top.v de la Console 60K. MISMO
//  pipeline HDMI del MSXimus v3 (hdmi.sv VIC=4/720p60, audio_ce 44.1k a cero,
//  mismo serializer.sv — que en Vivado entra solo por su rama OSERDESE2). Solo cambia
//  la infraestructura de fabricante:
//    pll_27 + pll_74 (Gowin) ->  2x MMCME2_BASE en CASCADA, igual que el Tang:
//                              50 -> 27 (x13.5/25) -> 74.25 y 371.25 (x27.5, /10 y /2)
//                              El 74.25 sale EXACTO (importa para el CTS del audio).
//    ELVDS_OBUF            ->  OBUFDS TMDS_33
//    reloj TMDS            ->  tmds_clock del serializer (OSERDESE2 0000011111),
//                              NO el reloj de pixel directo como en el Tang
//    PMOD de debug         ->  los 4 LEDs del PL
//  Discriminador: barras = el pipeline HDMI del MSXimus funciona en Zynq;
//  negro = infraestructura (MMCM/OSERDES/pines/HDMI_OUT_EN).
//  LEDs: [0]=lock  [1]=latido 27M  [2]=latido 135M  [3]=latido de frame (~1 Hz)
// ============================================================================

module hdmi720_top (
    input  wire       clk,            // K17, 50 MHz
    input  wire       rst_n,          // M19 (K2), activo bajo

    output wire [2:0] tmds_data_p,
    output wire [2:0] tmds_data_n,
    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire       hdmi_out_en,    // H18: habilita el buffer HDMI de la placa

    output wire [3:0] led
);

    assign hdmi_out_en = 1'b1;

    // ---- relojes: CASCADA como el Tang (pll_27 -> pll_74) ----
    //   MMCM1: 50 MHz x13.5 = 675 VCO ; /25 = 27 MHz   (clk27_video)
    //   MMCM2: 27 MHz x27.5 = 742.5 VCO ; /10 = 74.25 (pixel) ; /2 = 371.25 (x5)
    wire fb1, fb1_buf, fb2, fb2_buf;
    wire clk27_raw, clk27_video;
    wire clk_hdmi_raw, clk_hdmi5_raw;
    wire clk_hdmi, clk_hdmi5;
    wire lock1, lock2;
    wire clock_locked = lock1 & lock2;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"), .CLKIN1_PERIOD(20.000), .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(13.500), .CLKFBOUT_PHASE(0.0),
        .CLKOUT0_DIVIDE_F(25.000), .CLKOUT0_DUTY_CYCLE(0.5), .CLKOUT0_PHASE(0.0),
        .REF_JITTER1(0.010), .STARTUP_WAIT("FALSE")
    ) pll27_video (
        .CLKIN1(clk), .CLKFBIN(fb1_buf), .CLKFBOUT(fb1), .CLKFBOUTB(),
        .CLKOUT0(clk27_raw), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .LOCKED(lock1), .PWRDWN(1'b0), .RST(~rst_n)
    );
    BUFG bufg_fb1 (.I(fb1),       .O(fb1_buf));
    BUFG bufg_27  (.I(clk27_raw), .O(clk27_video));

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"), .CLKIN1_PERIOD(37.037), .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(27.500), .CLKFBOUT_PHASE(0.0),
        .CLKOUT0_DIVIDE_F(2.000), .CLKOUT0_DUTY_CYCLE(0.5), .CLKOUT0_PHASE(0.0),   // 371.25
        .CLKOUT1_DIVIDE(10),      .CLKOUT1_DUTY_CYCLE(0.5), .CLKOUT1_PHASE(0.0),   //  74.25
        .REF_JITTER1(0.010), .STARTUP_WAIT("FALSE")
    ) pll74_video (
        .CLKIN1(clk27_video), .CLKFBIN(fb2_buf), .CLKFBOUT(fb2), .CLKFBOUTB(),
        .CLKOUT0(clk_hdmi5_raw), .CLKOUT0B(), .CLKOUT1(clk_hdmi_raw), .CLKOUT1B(),
        .CLKOUT2(), .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .LOCKED(lock2), .PWRDWN(1'b0), .RST(~lock1)
    );
    BUFG bufg_fb2   (.I(fb2),           .O(fb2_buf));
    BUFG bufg_hdmi5 (.I(clk_hdmi5_raw), .O(clk_hdmi5));
    BUFG bufg_hdmi  (.I(clk_hdmi_raw),  .O(clk_hdmi));

    // ---- reset de encendido (contador sobre el pixel, gateado por los DOS locks) ----
    reg [15:0] por_cnt = 0;
    wire       reset_w = ~(&por_cnt);
    always @(posedge clk_hdmi) begin
        if (!clock_locked)      por_cnt <= 0;
        else if (~&por_cnt)     por_cnt <= por_cnt + 1'b1;
    end

    // ---- audio a cero. audio_ce = clock-enable de 1 ciclo a 44100 Hz exactos
    //      de media (acumulador fraccional 44100/74.25e6), CALCADO de
    //      msx2hdmi_v9968.sv ----
    localparam AUDIO_RATE = 44100;
    localparam AUDIO_BIT_WIDTH = 16;
    localparam NUM_CHANNELS = 3;
    localparam VBLANK_Y = 720;   // START_Y: reset -> inicio del vblank (como msx2hdmi_v9968)

    reg [26:0] audio_acc = 27'd0;
    reg        audio_ce  = 1'b0;
    always @(posedge clk_hdmi) begin : audio_div_frac
        reg [27:0] acc_n;
        acc_n = {1'b0, audio_acc} + 28'd44100;
        if (acc_n >= 28'd74250000) begin
            audio_acc <= acc_n[26:0] - 27'd74250000;
            audio_ce  <= 1'b1;
        end else begin
            audio_acc <= acc_n[26:0];
            audio_ce  <= 1'b0;
        end
    end
    wire [15:0] audio_zero [1:0];
    assign audio_zero[0] = 16'd0;
    assign audio_zero[1] = 16'd0;

    // ---- hdmi con los MISMOS parametros que hdmi_ntsc de msx2hdmi_v9968.sv ----
    logic [10:0] cx;   // BIT_WIDTH = 11 para VIC 4
    logic [9:0] cy;
    logic [9:0] tmds_internal [NUM_CHANNELS-1:0];

    // patron: barras verticales de 128 px (area activa de VIC=4: 1280x720)
    reg [23:0] rgb;
    always @(posedge clk_hdmi) begin
        case (cx[9:7])
            3'd0: rgb <= 24'hFFFFFF;  // blanco
            3'd1: rgb <= 24'hFFFF00;  // amarillo
            3'd2: rgb <= 24'h00FFFF;  // cian
            3'd3: rgb <= 24'h00FF00;  // verde
            3'd4: rgb <= 24'hFF00FF;  // magenta
            3'd5: rgb <= 24'hFF0000;  // rojo
            3'd6: rgb <= 24'h0000FF;  // azul
            default: rgb <= 24'h404040; // gris
        endcase
    end

    hdmi #( .VIDEO_ID_CODE(4),                  // 720p60, frame 1650x750
            .DVI_OUTPUT(0),
            .VIDEO_REFRESH_RATE(60.0),
            .IT_CONTENT(1),
            .AUDIO_RATE(AUDIO_RATE),
            .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
            .VENDOR_NAME({"Unknown", 8'd0}),
            .PRODUCT_DESCRIPTION({"FPGA", 96'd0}),
            .SOURCE_DEVICE_INFORMATION(8'h00),
            .START_X(0),
            .START_Y(VBLANK_Y),
            .NUM_CHANNELS(NUM_CHANNELS),
            .PIPELINE_QM(1'b1)                  // como la linea V9968
          )
    hdmi_test (
        .clk_pixel_x5(clk_hdmi5),
        .clk_pixel(clk_hdmi),
        .audio_ce(audio_ce),
        .rgb(rgb),
        .reset(reset_w),
        .reset_cx(11'd0),
        .audio_sample_word(audio_zero),
        .aspect_16_9(1'b0),
        .cx(cx),
        .cy(cy),
        .frame_width(), .frame_height(), .screen_width(), .screen_height(),
        .tmds_internal(tmds_internal),
        .audio_pkt_pulse(), .audio_ovr_pulse()
    );

    // ---- serializer (rama OSERDESE2) + OBUFDS ----
    logic [2:0] tmds;
    logic       tmds_clock;
    serializer #(.NUM_CHANNELS(NUM_CHANNELS), .VIDEO_RATE(0)) serializer(
        .clk_pixel(clk_hdmi), .clk_pixel_x5(clk_hdmi5), .reset(reset_w),
        .tmds_internal(tmds_internal), .tmds(tmds), .tmds_clock(tmds_clock) );

    OBUFDS #(.IOSTANDARD("TMDS_33")) obuf_clk (
        .I(tmds_clock), .O(tmds_clk_p), .OB(tmds_clk_n));
    OBUFDS #(.IOSTANDARD("TMDS_33")) obuf_d0 (
        .I(tmds[0]), .O(tmds_data_p[0]), .OB(tmds_data_n[0]));
    OBUFDS #(.IOSTANDARD("TMDS_33")) obuf_d1 (
        .I(tmds[1]), .O(tmds_data_p[1]), .OB(tmds_data_n[1]));
    OBUFDS #(.IOSTANDARD("TMDS_33")) obuf_d2 (
        .I(tmds[2]), .O(tmds_data_p[2]), .OB(tmds_data_n[2]));

    // ---- debug en LEDs (activos a 1 en esta placa) ----
    reg [23:0] hb27 = 0;  always @(posedge clk_hdmi)  hb27  <= hb27  + 1'b1;
    reg [26:0] hb135 = 0; always @(posedge clk_hdmi5)  hb135 <= hb135 + 1'b1;
    reg [5:0] frame_div = 0;
    reg cy0_d = 0;
    always @(posedge clk_hdmi) begin
        cy0_d <= (cy == 10'd0);
        if ((cy == 10'd0) && !cy0_d) frame_div <= frame_div + 1'b1;  // 1 tick/frame
    end
    assign led[0] = clock_locked;
    assign led[1] = hb27[23];
    assign led[2] = hb135[26];
    assign led[3] = frame_div[5];   // ~1 Hz si el frame corre (60/64)

endmodule
