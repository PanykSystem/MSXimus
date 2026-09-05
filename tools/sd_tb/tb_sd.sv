// ============================================================================
// tb_sd.sv — banco del sd_reader/sdcmd_ctrl del MSXimus (V3.5) contra el modelo
// de tarjeta sd_card_model.
//
// Parametros de compilacion:
//   FASTDIV : FAST_DIV del sd_reader (0 = 6,75 MHz, 4 = los 2,25 MHz de siempre)
//   TOD     : retardo de salida de la tarjeta en ns (spec: <=14; se prueba mas)
//
// Pruebas (todas deben decir OK):
//   T1 init completa (CMD0..CMD16), SDHC, CSD/CID capturados
//   T2 lectura limpia: datos = memoria del modelo, rcrc_error=0
//   T3 escritura limpia: memoria del modelo = buffer, token 010, crc_error=0
//   T4 relectura del sector escrito
//   T5 lectura con UN bit corrupto: rcrc_error=1 (y la siguiente limpia lo borra)
//   T6 escritura RECHAZADA por la tarjeta (token 101): crc_error=1; y una
//      lectura posterior NO hereda ese crc_error (AUDIT #6)
//   T7 tarjeta que no manda datos NI responde al CMD12: timeout_error=1 y el
//      lector VUELVE a IDLING (antes: CMD12 eterno = busy pegado hasta reset);
//      despues una lectura normal funciona
//   T8 el modelo no ha visto ni un comando mal formado ni un CRC16 de
//      escritura malo (= el muestreo/conduccion a esta velocidad es correcto)
// ============================================================================
`timescale 1ns/1ps

module tb_sd;
    parameter integer FASTDIV = 0;
    parameter integer TOD     = 14;

    reg clk = 1'b0;
    always #18.5185 clk = ~clk;          // 27 MHz

    reg rstn = 1'b0;
    wire sdclk;
    wire sdcmd;
    wire sddat0;
    pullup (sdcmd);
    pullup (sddat0);

    reg         rstart = 1'b0;
    reg         wstart = 1'b0;
    reg         init   = 1'b0;
    reg  [31:0] rsector = 32'd0;
    wire        rbusy, rdone, outen;
    wire [8:0]  outaddr;
    wire [7:0]  outbyte;
    reg  [7:0]  inbyte = 8'h00;
    wire [3:0]  card_stat;
    wire [1:0]  card_type;
    wire        crc_error, rcrc_error, timeout_error;
    wire [21:0] c_size;
    wire [2:0]  c_size_mult;
    wire [3:0]  read_bl_len;
    wire [7:0]  mid;
    wire [15:0] oid;
    wire [39:0] pnm;
    wire [31:0] psn;

    sd_reader #(
        .CLK_DIV(3'd2),
        .FAST_DIV(FASTDIV[15:0]),
        .SIMULATE(1)
    ) dut (
        .rstn(rstn), .clk(clk),
        .sdclk(sdclk), .sdcmd(sdcmd), .sddat0(sddat0),
        .card_stat(card_stat), .card_type(card_type),
        .rstart(rstart), .rsector(rsector), .rbusy(rbusy), .rdone(rdone),
        .outen(outen), .outaddr(outaddr), .outbyte(outbyte),
        .wstart(wstart), .inbyte(inbyte),
        .c_size(c_size), .c_size_mult(c_size_mult), .read_bl_len(read_bl_len),
        .mid(mid), .oid(oid), .pnm(pnm), .psn(psn),
        .crc_error(crc_error), .rcrc_error(rcrc_error), .timeout_error(timeout_error),
        .init(init)
    );

    sd_card_model card (
        .sdclk(sdclk), .sdcmd(sdcmd), .sddat0(sddat0)
    );

    // --- el dpram del top.v, reducido a lo que ve el sd_reader ---
    reg [7:0] rbuf [0:511];
    reg [7:0] wbuf [0:511];
    always @(posedge clk) begin
        if (outen && rstart) rbuf[outaddr] <= outbyte;
        if (outen && wstart) inbyte <= wbuf[outaddr];
    end

    // --- depuracion: transiciones de la FSM de datos ---
    reg [3:0] dstat_d = 4'd0;
    always @(posedge clk) begin
        dstat_d <= dut.sddat_stat;
        if (dut.sddat_stat != dstat_d && (dut.sddat_stat == 4'd7 || dut.sddat_stat == 4'd8 || dut.sddat_stat == 4'd9 || dut.sddat_stat == 4'd2 || dut.sddat_stat == 4'd3))
            $display("    [dbg] t=%0t sddat_stat %0d -> %0d  ridx=%0d crc_stat=%b crc_error=%b rcrc_bad=%b", $time, dstat_d, dut.sddat_stat, dut.ridx, dut.crc_stat, dut.crc_error, dut.rcrc_bad);
    end
    integer errors = 0;
    integer i;
    integer mism;

    task check;
        input cond;
        input [8*80-1:0] msg;
        begin
            if (cond) $display("  OK   %0s", msg);
            else begin
                $display("  FAIL %0s   (t=%0t)", msg, $time);
                errors = errors + 1;
            end
        end
    endtask

    // espera a card_stat==IDLING con tope en ciclos de clk
    task wait_idle;
        input integer maxclk;
        integer n;
        begin
            n = 0;
            while (dut.sdcmd_stat != 5'd17 && n < maxclk) begin
                @(posedge clk); n = n + 1;
            end
        end
    endtask

    // lectura como la hace top.v: el strobe se mantiene hasta el flanco de done
    task do_read;
        input [31:0] sec;
        integer n;
        begin
            rsector = sec;
            @(posedge clk); rstart = 1'b1;
            n = 0; while (!rbusy && n < 100) begin @(posedge clk); n = n + 1; end
            n = 0; while (!rdone && n < 20000000) begin @(posedge clk); n = n + 1; end
            @(posedge clk); rstart = 1'b0;
            n = 0; while (rbusy && n < 20000000) begin @(posedge clk); n = n + 1; end
            repeat (10) @(posedge clk);
        end
    endtask

    task do_write;
        input [31:0] sec;
        integer n;
        begin
            rsector = sec;
            @(posedge clk); wstart = 1'b1;
            n = 0; while (!rbusy && n < 100) begin @(posedge clk); n = n + 1; end
            n = 0; while (!rdone && n < 20000000) begin @(posedge clk); n = n + 1; end
            @(posedge clk); wstart = 1'b0;
            n = 0; while (rbusy && n < 20000000) begin @(posedge clk); n = n + 1; end
            repeat (10) @(posedge clk);
        end
    endtask

    function integer cmp_read;      // nº de bytes distintos entre rbuf y el sector del modelo
        input integer sec;
        integer k, m;
        begin
            m = 0;
            for (k = 0; k < 512; k = k + 1)
                if (rbuf[k] !== card.mem[(sec % 16)*512 + k]) m = m + 1;
            cmp_read = m;
        end
    endfunction

    function integer cmp_write;     // nº de bytes distintos entre wbuf y el sector del modelo
        input integer sec;
        integer k, m;
        begin
            m = 0;
            for (k = 0; k < 512; k = k + 1)
                if (wbuf[k] !== card.mem[(sec % 16)*512 + k]) m = m + 1;
            cmp_write = m;
        end
    endfunction

    initial begin
        $display("=== tb_sd  FAST_DIV=%0d  (sdclk periodo %0d clk = %0.2f MHz)  TOD=%0d ns ===",
                 FASTDIV, 2*FASTDIV+4, 27.0/(2*FASTDIV+4), TOD);
        card.tod_ns = TOD;
        for (i = 0; i < 512; i = i + 1) rbuf[i] = 8'h00;

        repeat (5) @(posedge clk);
        rstn = 1'b1;
        repeat (5) @(posedge clk);

        // ---------------- T1: init ----------------
        init = 1'b1;
        wait_idle(3000000);
        check(dut.sdcmd_stat == 5'd17, "T1 init: sd_reader en IDLING");
        check(card_type == 2'd3,  "T1 init: SDHCv2 detectada (ACMD41 con CCS)");
        check(c_size == 22'h001E3F, "T1 init: C_SIZE del CSD v2 capturado");
        check(mid == 8'hAB,       "T1 init: MID del CID capturado");
        check(dut.clkdiv == FASTDIV[15:0], "T1 init: divisor RAPIDO activo tras CMD7");
        check(timeout_error == 1'b0, "T1 init: sin timeout");

        // ---------------- T2: lectura limpia ----------------
        do_read(32'd5);
        $display("    [dbg] leido  : %02x %02x %02x %02x %02x %02x %02x %02x ... %02x %02x", rbuf[0],rbuf[1],rbuf[2],rbuf[3],rbuf[4],rbuf[5],rbuf[6],rbuf[7],rbuf[510],rbuf[511]);
        $display("    [dbg] modelo : %02x %02x %02x %02x %02x %02x %02x %02x ... %02x %02x", card.mem[5*512+0],card.mem[5*512+1],card.mem[5*512+2],card.mem[5*512+3],card.mem[5*512+4],card.mem[5*512+5],card.mem[5*512+6],card.mem[5*512+7],card.mem[5*512+510],card.mem[5*512+511]);
        $display("    [dbg] bytes distintos: %0d", cmp_read(5));
        check(cmp_read(5) == 0,   "T2 lectura sector 5: 512 bytes identicos al modelo");
        check(rcrc_error == 1'b0, "T2 lectura: rcrc_error=0");
        check(crc_error == 1'b0,  "T2 lectura: crc_error=0");
        check(timeout_error == 1'b0, "T2 lectura: timeout_error=0");
        check(dut.sdcmd_stat == 5'd17, "T2 lectura: vuelve a IDLING");

        // ---------------- T3: escritura limpia ----------------
        for (i = 0; i < 512; i = i + 1) wbuf[i] = (i * 8'h35 + 8'hA5) ^ (i >> 3);
        do_write(32'd6);
        check(cmp_write(6) == 0,  "T3 escritura sector 6: el modelo guardo los 512 bytes");
        check(crc_error == 1'b0,  "T3 escritura: token 010 -> crc_error=0");
        check(timeout_error == 1'b0, "T3 escritura: timeout_error=0");
        check(card.n_write_crc_bad == 0, "T3 escritura: CRC16 del host correcto para la tarjeta");

        // ---------------- T4: relectura ----------------
        do_read(32'd6);
        check(cmp_read(6) == 0,   "T4 relectura sector 6: identico");
        mism = 0;
        for (i = 0; i < 512; i = i + 1) if (rbuf[i] !== wbuf[i]) mism = mism + 1;
        check(mism == 0,          "T4 relectura sector 6: identico a lo escrito");

        // ---------------- T5: lectura con un bit corrupto ----------------
        card.corrupt_read_bit = 1234;
        do_read(32'd5);
        check(cmp_read(5) == 1,   "T5 bit corrupto: exactamente 1 byte distinto");
        check(rcrc_error == 1'b1, "T5 bit corrupto: rcrc_error=1 (detectado)");
        check(crc_error == 1'b0,  "T5 bit corrupto: crc_error (escritura) sigue a 0");
        do_read(32'd5);
        check(cmp_read(5) == 0,   "T5 relectura limpia: datos bien");
        check(rcrc_error == 1'b0, "T5 relectura limpia: rcrc_error vuelve a 0");

        // ---------------- T6: escritura rechazada ----------------
        for (i = 0; i < 512; i = i + 1) wbuf[i] = i;
        card.reject_writes = 1;
        do_write(32'd7);
        check(crc_error == 1'b1,  "T6 escritura rechazada: crc_error=1");
        check(cmp_write(7) != 0,  "T6 escritura rechazada: el modelo NO la guardo");
        do_read(32'd7);
        check(crc_error == 1'b0,  "T6 lectura tras rechazo: crc_error=0 (AUDIT #6 cerrado)");
        check(rcrc_error == 1'b0, "T6 lectura tras rechazo: rcrc_error=0");
        check(cmp_read(7) == 0,   "T6 lectura tras rechazo: datos bien");

        // ---------------- T7: tarjeta muda (sin datos, sin CMD12) ----------------
        card.no_data   = 1'b1;
        card.no_resp12 = 1'b1;
        do_read(32'd3);
        check(timeout_error == 1'b1, "T7 tarjeta muda: timeout_error=1");
        check(dut.sdcmd_stat == 5'd17, "T7 tarjeta muda: el lector VUELVE a IDLING (CMD12 acotado)");
        check(rbusy == 1'b0,      "T7 tarjeta muda: busy NO se queda pegado");
        check(card.n_cmd12 >= 1,  "T7 tarjeta muda: se intento el CMD12");
        card.no_data   = 1'b0;
        card.no_resp12 = 1'b0;
        do_read(32'd3);
        check(cmp_read(3) == 0,   "T7 recuperacion: lectura normal despues del timeout");
        check(timeout_error == 1'b0, "T7 recuperacion: timeout_error se limpia");

        // ---------------- T8: salud del enlace ----------------
        check(card.n_cmd_crc_bad == 0, "T8 el modelo no vio comandos mal formados (CRC7 ok)");
        check(card.n_write_crc_bad == 1, "T8 solo la escritura rechazada a proposito fallo el CRC");
        $display("comandos vistos por la tarjeta: %0d  lecturas: %0d  escrituras: %0d",
                 card.n_cmd, card.n_reads, card.n_writes);

        if (errors == 0) $display("=== tb_sd FAST_DIV=%0d TOD=%0d: TODO OK ===", FASTDIV, TOD);
        else             $display("=== tb_sd FAST_DIV=%0d TOD=%0d: %0d FALLOS ===", FASTDIV, TOD, errors);
        $finish;
    end

    // guardian global
    initial begin
        #1500000000;  // 1,5 s (T7 a 2,25 MHz tarda 444 ms de sim)
        $display("FAIL: tope de tiempo global");
        $finish;
    end
endmodule
