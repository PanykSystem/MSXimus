//--------------------------------------------------------------------------------------------------------
// Module  : sd_dma
// Function: V3.6 (bloque 2 del plan 3.5, la parte que quedaba): DMA de LECTURA de la
//           SD a la RAM. El Z80 hoy vacia el bufer de 512 B con dos INIR (~21 T por
//           byte = 3 ms por bloque) y la tarjeta, que tarda 0,6 ms, espera parada el
//           80 % del tiempo. Con esto el bufer lo vacia el core y el Z80 solo
//           programa destino y cuenta.
//
//   COMO: el Z80 da la orden de lectura por #47 con el bit2 puesto (05h = leer +
//   DMA) tras haber dejado el destino fisico de 23 bits en sdc_ioport (OUT #4F,80h y
//   despues los 3 bytes). Esta FSM (clk_54m, el dominio de la RAM):
//     1. pide congelar la CPU (active) y espera a que el pegamento la pare con el
//        bus en reposo (frz = 1). Sin CPU no hay arbitro que valga: el puerto de
//        RAM de la CPU queda libre y lo usa la DMA por el MISMO camino que el
//        streamer de la flash del arranque (ram_addr/ram_din/ram_write "stream").
//     2. por cada bloque: espera blk_rdy (multibloque: la tarjeta para el reloj en
//        RHOLD) o el fin de la orden (rbusy = 0: el ULTIMO bloque de un CMD18 y el
//        unico de un CMD17 no levantan blk_rdy, van a RDONE); copia los 512 B del
//        bufer (puerto B del dpram, el lado de la tarjeta, ocioso mientras espera)
//        a la RAM, un byte por turno del controlador (~150 ns), y manda buf_ack.
//     3. con rbusy = 0 (CMD12 contestado) y el bufer vaciado, suelta la CPU. El Z80
//        se despierta en la instruccion siguiente al OUT y mira el estado como
//        siempre (bits 1-2 = timeout / CRC).
//   Si la orden acaba con error (timeout o CRC de lectura), el bloque no se copia
//   (seria basura) y la FSM termina igual: nunca se queda colgada.
//
//   Reloj: la FSM va en clk_54m; blk_rdy/rbusy/q_b vienen de clk_27m (hermano del
//   PLLA, fase conocida, como todo el pegamento del SD) y las salidas hacia ese lado
//   (buf_addr/buf_rd/ack) se mantienen >= 4 ciclos para que las vea.
//
//   Coste: sin BSRAM (la del 60K esta al 100 %), ~70 registros, nada en el cono de
//   la CPU: el mux de ram_addr sigue siendo "stream ? : cascada", como con la flash.
//--------------------------------------------------------------------------------------------------------
module sd_dma (
    input  wire        clk,            // clk_54m
    input  wire        rstn,           // bus_reset_n
    input  wire        start,          // pulso (dominio 27 MHz, 2 ciclos aqui): orden con DMA
    input  wire [22:0] dest,           // destino fisico de 23 bits (sdc_ioport, estable)
    input  wire        bus_idle,       // CPU sin ciclo en curso y RAM libre: se puede parar
    input  wire        blk_rdy,        // sd_reader: bloque en el bufer, reloj parado
    input  wire        rbusy,          // sd_reader: orden en curso
    input  wire        sd_err,         // rcrc_error | timeout_error
    input  wire [7:0]  buf_q,          // q_b del dpram del sector
    input  wire        ram_busy,       // memory_ctrl
    output reg         active,         // hay una DMA en marcha (pide congelar la CPU)
    output reg         frz,            // CPU congelada: la DMA manda en el puerto de RAM
    output reg  [8:0]  buf_addr,       // direccion del puerto B del dpram
    output reg         buf_rd,         // rden_b
    output reg         ack,            // buf_ack hacia sd_reader (>= 4 ciclos)
    output reg         ram_req,        // = ram_write del camino stream
    output reg  [22:0] ram_addr,
    output reg  [7:0]  ram_din,
    output reg  [7:0]  blocks,         // bloques copiados en la ultima orden (depuracion)
    output wire        rfsh_ok         // CPU congelada Y sin escritura en vuelo: el refresco
                                       // autonomo de memory.v puede disparar (ver abajo)
);

    localparam [3:0] S_IDLE   = 4'd0,
                     S_FREEZE = 4'd1,   // esperando bus en reposo para parar la CPU
                     S_WAIT   = 4'd2,   // esperando bloque (blk_rdy) o fin (rbusy=0)
                     S_RD1    = 4'd3,   // direccion puesta: dejar que el puerto B la vea
                     S_WR     = 4'd4,   // esperando que el controlador acepte (busy=1)
                     S_WR2    = 4'd5,   // esperando que termine (busy=0)
                     S_ACK    = 4'd6,   // buf_ack a la tarjeta
                     S_LAST   = 4'd7,   // rbusy cayo: ultimo bloque pendiente?
                     S_DONE   = 4'd8,   // soltar la CPU
                     S_GUARD  = 4'd9;   // antes del primer byte: que acabe un refresco en vuelo

    reg [3:0] st = S_IDLE;
    reg [2:0] hold = 3'd0;        // temporizador corto (ciclos de 54 MHz)
    reg [7:0] tmo  = 8'd0;        // margen para que la orden arranque (rbusy suba)
    reg       start_d = 1'b0;
    reg       have_blk = 1'b0;    // se recibio un bloque (rbusy alto tras la orden)
    reg       rbusy_d = 1'b0;
    reg       last_done = 1'b0;   // el bloque final (RDONE) ya se copio

    wire start_edge = start & ~start_d;
    // REFRESCO (leccion _175/_181 de memory.v): el refresco autonomo sirve en bucle
    // abierto y puede robarle la media a una aceptacion en vuelo -> la escritura se
    // pierde EN SILENCIO. Por eso aqui el refresco solo se permite mientras la DMA
    // espera a la tarjeta (S_WAIT, >= 600 us por bloque: sobra) y NUNCA durante la
    // rafaga de escrituras; y antes del primer byte de cada bloque se dejan pasar
    // ~40 ciclos (S_GUARD) para que un refresco ya lanzado (2 medias) termine.
    assign rfsh_ok = frz && (st == S_WAIT);

    always @(posedge clk or negedge rstn) begin
        if (~rstn) begin
            st       <= S_IDLE;
            active   <= 1'b0;
            frz      <= 1'b0;
            buf_addr <= 9'd0;
            buf_rd   <= 1'b0;
            ack      <= 1'b0;
            ram_req  <= 1'b0;
            ram_addr <= 23'd0;
            ram_din  <= 8'd0;
            blocks   <= 8'd0;
            hold     <= 3'd0;
            tmo      <= 8'd0;
            start_d  <= 1'b0;
            have_blk <= 1'b0;
            rbusy_d  <= 1'b0;
            last_done <= 1'b0;
        end else begin
            start_d <= start;
            rbusy_d <= rbusy;
            case (st)
                S_IDLE: begin
                    ack     <= 1'b0;
                    buf_rd  <= 1'b0;
                    ram_req <= 1'b0;
                    frz     <= 1'b0;
                    if (start_edge) begin
                        active    <= 1'b1;
                        ram_addr  <= dest;
                        blocks    <= 8'd0;
                        have_blk  <= 1'b0;
                        last_done <= 1'b0;
                        tmo       <= 8'd255;
                        st        <= S_FREEZE;
                    end
                end

                S_FREEZE: begin
                    // el OUT que dio la orden aun esta en curso: esperar a que el
                    // Z80 suelte el bus y no haya acceso a RAM pendiente
                    if (bus_idle) begin
                        frz <= 1'b1;
                        st  <= S_WAIT;
                    end
                end

                S_WAIT: begin
                    ack    <= 1'b0;
                    buf_rd <= 1'b0;
                    if (rbusy) have_blk <= 1'b1;
                    if (blk_rdy) begin
                        tmo      <= 8'd40;
                        st       <= S_GUARD;
                    end else if (!rbusy && rbusy_d == 1'b0 && have_blk) begin
                        // la orden termino (CMD12 contestado o CMD17 completo)
                        st <= S_LAST;
                    end else if (!rbusy && !have_blk) begin
                        // la orden aun no ha arrancado (el strobe llega por el lado
                        // de 27 MHz). Si en 255 ciclos no arranca (tarjeta sin
                        // inicializar), terminar: la FSM nunca se queda colgada
                        if (tmo == 8'd0) st <= S_DONE;
                        else tmo <= tmo - 8'd1;
                    end
                end

                S_LAST: begin
                    // ultimo bloque: esta en el bufer si la orden acabo BIEN y no
                    // se ha copiado ya (RDONE no levanta blk_rdy)
                    if (sd_err || last_done) st <= S_DONE;
                    else begin
                        last_done <= 1'b1;
                        tmo       <= 8'd40;
                        st        <= S_GUARD;
                    end
                end

                S_GUARD: begin
                    // rfsh_ok ya esta a 0 (no estamos en S_WAIT): ningun refresco nuevo;
                    // dejar que termine el que pudiera estar en vuelo y empezar el bloque
                    if (tmo == 8'd0) begin
                        buf_addr <= 9'd0;
                        buf_rd   <= 1'b1;
                        hold     <= 3'd4;
                        st       <= S_RD1;
                    end else
                        tmo <= tmo - 8'd1;
                end

                S_RD1: begin
                    // >= 2 flancos de clk_27m con la direccion puesta: q_b valido
                    if (hold == 3'd0) begin
                        ram_din <= buf_q;
                        ram_req <= 1'b1;
                        st      <= S_WR;
                    end else
                        hold <= hold - 3'd1;
                end

                S_WR: begin
                    // memory_ctrl acepta en su ventana dl&dh y sube ram_busy; la
                    // direccion y el dato se quedan quietos hasta entonces
                    if (ram_busy) begin
                        ram_req <= 1'b0;
                        st      <= S_WR2;
                    end
                end

                S_WR2: begin
                    if (!ram_busy) begin
                        ram_addr <= ram_addr + 23'd1;
                        if (buf_addr == 9'd511) begin
                            buf_rd <= 1'b0;
                            blocks <= blocks + 8'd1;
                            if (last_done) st <= S_DONE;     // era el bloque final
                            else begin
                                ack  <= 1'b1;                // bufer vaciado: siguiente
                                hold <= 3'd4;
                                st   <= S_ACK;
                            end
                        end else begin
                            buf_addr <= buf_addr + 9'd1;
                            hold     <= 3'd4;
                            st       <= S_RD1;
                        end
                    end
                end

                S_ACK: begin
                    // ack >= 4 ciclos (2 flancos de 27 MHz); luego a esperar el
                    // siguiente bloque. blk_rdy tarda unos ciclos en bajar tras el
                    // ack: el hold cubre ese hueco para no releer el mismo bloque
                    if (hold == 3'd0) begin
                        ack <= 1'b0;
                        if (!blk_rdy) st <= S_WAIT;
                    end else
                        hold <= hold - 3'd1;
                end

                S_DONE: begin
                    frz    <= 1'b0;
                    active <= 1'b0;
                    st     <= S_IDLE;
                end

                default: st <= S_IDLE;
            endcase
        end
    end

endmodule
