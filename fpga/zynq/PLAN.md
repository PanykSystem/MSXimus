# Plan Zynq — MSXimus en la ZYNQ MINI (XC7Z020, 2026-09-13)

Estrategia acordada: **un repo, dos targets**. `fpga/zynq/` lleva su propio top,
sus backends AXI, su block design del PS7 y su `build.tcl` (Vivado 2019.2 en
batch), y comparte `fpga/src/`, `fpga/v9968/`, `fpga/video720/`, `fpga/jtopl/`,
`fpga/opl3/`… con el Tang. Nada del core se copia ni se bifurca.

Lo ya validado en placa (13/09, `zynq_bringup/` y `bringup/`):
LEDs · HDMI 480p/720p con el `hdmi.sv`/`serializer.sv` del repo sin tocar ·
PS7 + DDR3 entrenada + AXI3 directo al HP0 · banco de medidas del HP ·
`v9968_axi_backend.v` con cliente sintético, 0 errores.

## A. Árbol de relojes (calcado del Tang, en MMCM)

El Tang saca todo de un VCO de 1350 MHz (PLLA ×27 de 50) más la cascada de
vídeo. El XC7Z020 tiene 4 MMCM + 4 PLL; sobran.

| Zynq | Fuente | Salidas | Sustituye a |
|---|---|---|---|
| MMCM_A (M=27, VCO 1350) | pad 50 MHz | /12.5 = **108** · /25 = **54** · /50 = **27** · /10 = **135** · /36 = **37.5** (wave375) | `Gowin_PLL pll_main` |
| MMCM_C (M=27.5, VCO 742.5) | 27 de MMCM_A | /10 = **74.25** · /2 = **371.25** | `pll_27` + `pll_74` (validado en `bringup/hdmi720_top.sv`) |
| PLLE2_D (M=35, VCO 945) | 27 de MMCM_A | /11 = **85.909** | `pll_86` (V9968) |
| PLLE2_E (M=24, VCO 1200) | pad 50 MHz | /100 = **12** | `pll_12` (usb_hid_host) |
| FCLK0 del PS | PS7 | **150** (aclk) | `clk_x1` de la IP DDR3 (backends) |

`CLKDIV` de Gowin no hace falta: cada frecuencia es una salida del MMCM.

## B. Inventario del `top.v` (63+6 instancias)

### B1. Se queda TAL CUAL (RTL genérico, mismo reloj)
`G80a cpu` · `msx_s1990` · `rtc` · `kanji` · `switched_io_ports` · `monostable`×2 ·
`PINFILTER`×4 · `denoise` · `led_stretch`×8 · `dpram` · toda la cadena V9968
(`v9968_cpu_glue`, `vdp u_v9968`, `v9968_vram_shim`, `v9968_sdram_bridge`×2,
`msx2hdmi_v9968`) · todo el audio (`YM2149`×2, `psg_filter`×2, `jt2413`,
`jtopl2`, `y8950_adpcm`, `opl4fm`, `opl4_pcm`, `scc_glue`, `scc_wave2`×2,
`megaram_scc`, `gm2_slot1`) · SD del PL (`sdc_ioport`, `sd_reader`, `sd_dma`)
· `usb_hid_host`×2, `usb_kbd_decode`×2, `msx_mouse` · `iosys_bl616` ·
`wifi` · `dbg_uart`.

### B2. Cambia de CAPA (misma interfaz de cliente, otra memoria)
| Tang | Zynq | Estado |
|---|---|---|
| `v9968_ddr3_backend` (IP DDR3 Gowin) | **`v9968_axi_backend`** → HP0 | ✅ validado |
| `memory_ctrl` (SDRAM W9825, puertos `ram_*` Z80 + `wv*`) | **`memory_axi`** → HP1, caché en BRAM | ⏳ siguiente |
| `adpcm_sdram` (ADPCM Y8950, 32 KB) | `adpcm_bram` (cabe: 256 Kb) | ⏳ |
| `wave_sdram` (ondas OPL4, puerto `wv` de memory_ctrl) | puerto `wv` de `memory_axi` | ⏳ |
| `flash` (`flash_rw`: BIOS/packs/YRW801 de la SPI al SDRAM) | **el PS carga los packs en la DDR** (xsdb `dow -data` hoy; FSBL/app desde QSPI mañana). En el PL, `flash_idle=1`. | ⏳ |

### B3. Se va al PS o desaparece
`Gowin_PLL`, `pll_27/74/86/12`, `CLKDIV` → MMCM (A) · `ro_osc` + `fan_ctrl` →
fuera (sin ventilador) · `ws2812` → fuera · pines SDRAM/DDR3/mspi_*/spi_*
BL616/esp_*/bl616_jtagsel/dbg_pmod* → fuera del top.

## C. El puerto `ram_*` del Z80 y la latencia de la DDR (lo medido manda)

`memory_ctrl` acepta `ram_req` en la ventana `dlclk&dhclk` y sirve en la media
CPU (~150 ns). El HP da 180 ns mín / ~227 típico / **567 ns máx** (refresco)
por fallo: a 3,58 MHz el dato tiene que estar ~420 ns tras MREQ. Por eso
`memory_axi` lleva **caché write-through en BRAM** (líneas de 16 B, mapeo
directo, 64–128 KB de los 612 KB del chip) delante del HP: hit = mismo
timing que la SDRAM; fallo = `ram_busy` alto hasta que llega la línea y el
**`/WAIT` del Z80, que YA se gobierna por `ram_busy`** (`wait_io_ff`, rama
turbo y rama `ENABLE_WAIT`), frena la CPU. Único cambio en la lógica de
espera: el término `ram_busy` de las lecturas se aplica también sin turbo.
Con la caché, el turbo 5,37 que en el Tang costaba un 18 % por la guarda de
la SDRAM (`TURBO_SIN_GUARDA_SDRAM`, 26/08) debería salir gratis.

Regla aprendida en el HP (05_hp_bench): AXI no ordena lecturas frente a
escrituras en vuelo → barrera (`wr_pend==0`) antes de leer de la DDR; el HP
no se resetea al reprogramar el PL → drenar B/R en reset.

## D. Pines (34 IOs del header + dedicados)
Dedicados: HDMI (H16/D19/C20/B19 + H18 enable), 4 LED (T12 U12 V12 W13 =
LED1..4), 2 botones (M20 = KEY1, M19 = KEY2), 50 MHz K17, OLED (E18 E19 F16
F17), EEPROM I2C (F19/F20). Todo 3V3 estricto (aviso del fabricante).

**No hay microSD en el PL** (esquemático 13/09, págs. 4 y 8): TF1 = SD0 del PS
(MIO 40‑45) y TF2 = SD1 del PS (MIO 10‑15). El `sd_reader` del MSXimus sale al
header con un breakout pasivo 3V3; a largo plazo, proxy de SD en el PS.

Header CAM1 (2×20; 1 GND · 2 VCC5 · 37/38 GND · 39/40 VCC3V3), pin → encapsulado
(esquemático pág. 9 + símbolo del banco 34 pág. 5 + tabla de Vivado; el método
reproduce los 25 pines ya validados):

| impar | pin | par | pin | | impar | pin | par | pin |
|---|---|---|---|---|---|---|---|---|
| 3 | U15 (11N) | 4 | P15 (24P) | | 21 | U18 (12P) | 22 | R16 (19P) |
| 5 | W15 (10N) | 6 | V15 (10P) | | 23 | T17 (20P) | 24 | T16 (9P) |
| 7 | U17 (9N) | 8 | V17 (21P) | | 25 | R17 (19N) | 26 | W16 (18N) |
| 9 | V18 (21N) | 10 | Y18 (17P) | | 27 | W20 (16N) | 28 | R18 (20N) |
| 11 | W18 (22P) | 12 | Y19 (17N) | | 29 | V20 (16P) | 30 | P19 (13N) |
| 13 | U19 (12N) | 14 | W19 (22N) | | 31 | U20 (15N) | 32 | P18 (23N) |
| 15 | U14 (11P) | 16 | N17 (23P) | | 33 | T20 (15P) | 34 | N18 (13P) |
| 17 | Y14 (8N) | 18 | W14 (8P) | | 35 | P20 (14N) | 36 | N20 (14P) |
| 19 | V16 (18P) | 20 | P16 (24N) | | | | | |

Asignación MSXimus: **microSD = pines 31‑36** (dat2 U20 · dat3 P18 · cmd T20 ·
sclk N18 · dat0 P20 · dat1 N20; GND 37, 3V3 39), ya en `top_zynq.xdc`.
Pendientes: 4 × USB (usb1/2 dp/dn) y 3 × ESP32‑C6 (tx/rx/turbo) en el resto.

## E. Orden de trabajo
1. ✅ `memory_axi.v` + cliente sintético en placa (13/09: 0 errores, hit = 222 ns).
2. ✅ `top_zynq.v` (13/09): generado por `tools/make_top_zynq.py`, sintetiza
   (19.361 LUT = 36 %, 66,5 BRAM = 47 %, 9 DSP), timing cerrado, y **el MSX
   arranca** con el pack cargado por `tools/boot.tcl` — JIFFY a 60 Hz y VRAM
   llena leídos por `tools/alive.tcl`. Fuentes compartidos tocados: `opl3/afifo.v`
   (restaura `default_nettype`), `video720/msx2hdmi_v9968.sv` (`ifdef ZYNQ`:
   reloj TMDS del serializer). Pendientes de este paso: CW `sddat0` (tie-off
   hasta cablear TF1) y CW `set_clock_groups clk_fpga_0` en síntesis (el reloj
   del PS solo existe en implementación; benigno).
2b. "Ojos y manos" sin hardware: `dbg_mailbox_axi.v` (HP2 @ 54) lee cada ms un
   bitmap HID de 128 bits en la DDR (0x1FF00000) que se OR-ea con el teclado
   USB, y escribe telemetría (hits/miss de memory_axi, vdp_ops, cpu_run, SD).
   `tools/key.tcl RETURN` / `-type {print 1+1}` pulsa teclas desde xsdb;
   `tools/tel.tcl` lee la telemetría; los ojos son OBS (captura HDMI).
   ✅ 14/09 08:00 VALIDADO de punta a punta: `key.tcl RETURN` arranca el MSX desde
   el menú; `key.tcl -type {print 1+1} RETURN` teclea en BASIC (KEYBUF y BUF lo
   confirman) y `tools/screen.tcl` vuelca la pantalla de texto leyendo la tabla de
   nombres de la VRAM en la DDR ("MSX BASIC version 3.0 … Ok / print 1+1 / 2 / Ok").
   La VRAM del V9968 vive en **DDR 0x10280000** (no en VRAM_BASE 0x10000000 a
   secas: +0x280000; el glifo 'A' de la fuente está en +0x208), y el modo/tabla se
   leen de SCRMOD/NAMBAS/LINL40 en la RAM (pág. 3 del Z80 = DDR 0x10800000+A-0xC000).
   🚨 LECCIÓN (noche del 13 al 14): el "no arranca tras reprogramar" (hits=0 miss=1,
   determinista, 4 bitstreams) era `boot.tcl` ejecutando `ps7_init` (reset/reentreno
   del DDRC) con la imagen anterior del PL aún leyendo la DDR por HP → puerto del
   DDRC atascado hasta un reset del PS. Fix: parar el PL (`FPGA_RST_CTRL=0xF`,
   level shifters 0xA) ANTES de `ps7_init`. Recuperación: `tools/psreset.tcl`.
   Diagnóstico posible gracias a `memory_axi.dbg_state` en el buzón. Variantes de
   bisección en el generador/build por variables de entorno (`ZYNQ_NO_MAILBOX`,
   `ZYNQ_NO_SD`, `ZYNQ_MB_IDLE`); la SD tiene su xdc aparte (`top_zynq_sd.xdc`).
3. Teclado USB (PL, 4 pines del header) → MSX-BASIC tecleable.
4. "SD" del MSXimus = **proxy de sectores** (`sd_axi_proxy.v`, HP3 @ 27 MHz, decidido
   14/09 con Albert: opción B). Misma interfaz que `sd_reader`; dos modos elegidos en
   caliente por la palabra MODE del buzón SDBOX (DDR 0x1FF00100): **0 = imagen** de disco
   en la DDR (DISK_BASE 0x11000000, 224 MB; la carga `boot.tcl <pack> <bit> <img>`;
   `tools/mkfat16.py` fabrica imágenes FAT16 de prueba) y **1 = proxy**: petición
   {seq, op, count, sector} en SDBOX + `IRQ_F2P[0]` → el ARM accede a la tarjeta real
   (TF1 = SD0 o TF2 = SD1, driver xsdps) sobre SDBUF (0x1FF10000, hasta 255 sectores)
   y acusa en W3. Tiempo real, escrituras write-through, cambio en caliente por la
   palabra CARD (presente + MB). El programa del ARM (bare-metal, `arm-none-eabi-gcc`
   14.2 + `data/embeddedsw` de Vivado) es el siguiente gran bloque; también hará de
   FSBL/cargador (BOOT.bin en TF1) y, según Albert, "otras cosas, la pantalla por ejemplo".
   El breakout en el header (pines 31‑36) queda como alternativa sin software.
   ✅ 14/09 11:05 VALIDADO en modo imagen: el menú premonta la imagen (MBR, boot,
   raíz: 3 órdenes) y muestra el navegador; ESC → **MSX‑DOS con NEXTOR.SYS 2.13**,
   `AUTOEXEC.BAT` completo (ECHO, DIR de los 4 ficheros, TYPE README), prompt A:\>,
   51 órdenes sin error. Bugs cazados por el camino: (1) `ax_done` era un nivel y la
   FSM lo veía un ciclo de más tras relanzar el motor → saltaba ráfagas (la MBR llegaba
   desplazada 384 B; delatado por `SD_BUF` del menú en la DDR); (2) `busy` debe subir en
   el ciclo siguiente a la orden (el menú/driver lo confirman con `sd_cmd_go`); (3) el
   `lbuf` con tres puertos de lectura costaba +16 k LUT → un solo puerto (LUTRAM).
   Herramientas: `tools/mkfat16.py` (imagen FAT16 de prueba), `boot.tcl <pack> <bit>
   <img>`, telemetría del proxy en `tel.tcl` (órdenes, flags, stat).
   🔨 14/09 11:40 MODO PROXY (ARM) EN MARCHA: `arm/sdproxy/` (bare-metal Cortex‑A9 core 0,
   sin MMU ni cachés, `arm-none-eabi-gcc` 14.2 + driver `xsdps` y BSP standalone de
   Vivado 2019.2 sin SDK; `build.sh` → `sdproxy.elf`, 14 KB). `boot.tcl` con
   `BOOT_PROXY=1` lo carga y arranca ANTES de soltar el PL y desde entonces la memoria
   se lee por el core 1 (parado); `tools/armlog.tcl` lee su log en anillo (DDR
   0x1FF00800) y las estadísticas (SDBOX+0x20). El PS7 lleva ya SD0 (TF1, MIO 40‑45)
   y SD1 (TF2, MIO 10‑15) habilitados: `ps7_init` nuevo con SDIO a 50 MHz (IO PLL
   1800/36) y MIO 10‑15 en LVCMOS33 con pull‑up. VERIFICADO: la tarjeta real de TF2
   se inicializa (16 GB, SDHC, 4 bits, 50 MHz) y el ARM sirve la primera lectura
   del premontaje (seq=1 op=1 sector=0 → ACK OK). Bug en curso: `P_ACKW` del proxy
   ✅ 14/09 11:50 **VALIDADO EN MODO PROXY REAL**: el menú premonta la tarjeta de TF2
   (8 lecturas por el ARM), el navegador lista su contenido real (17 entradas), ESC →
   MSX‑DOS arranca desde la tarjeta (40 lecturas) y ejecuta su AUTOEXEC. `P_ACKW`
   corregido con el flag `polling`. El ARM detecta también la retirada de la tarjeta
   en reposo (ACMD13 cada 2 s) y reintenta el init cada 0,5 s. Pendiente: probar
   escrituras sobre la tarjeta real (pedir permiso: son datos de Albert) y, más
   ✅ 12:30 ESCRITURA EN LA TARJETA REAL VALIDADA (con permiso de Albert): `A:\TMP\ZYNQ.TXT`
   creado/leído/listado/borrado desde MSX-DOS; 1210 lecturas, 272 escrituras, 0 errores.
   (Un fichero basura `TMPTYPE` creado por una línea concatenada — `key.tcl` no tenía `\` —
   se borró; `key.tcl` ya mapea `\` y `|`.)
   🌡️ Temperatura: el die del Zynq va a **~80 °C sin disipador** (XADC por PS, `tools/temp.tcl`;
   Tj máx. 85 °C comercial) → disipador recomendado a Albert. El bucle del ARM aporta ~2‑3 °C.
   `wfi` NO funciona con el JTAG conectado (halting‑debug → NOP en el A9): el ahorro llegará
   con `BOOT.bin` sin depurador; mientras, espera de 10 µs por timer entre sondeos.
   📌 FUTURO (Albert, 14/09): mostrar la temperatura del Zynq en la pantalla del MSX (el ARM
   la lee por XADC y la deja en el buzón; el menú/OSD la pinta) — para una release posterior.
   Siguiente: `BOOT.bin` en TF1 (SD0): FSBL (ps7_init) → bitstream del MSXimus → sdproxy, que
   además cargue el pack de BIOS desde un fichero de la tarjeta → arranque autónomo sin PC.
   (Aparcado 14/09 por Albert hasta que ponga una SD en SD0, "esta noche".)
4b. 🔨 14/09 12:30 **USB HOST en el ARM** (teclado, ratón y mandos por el USB‑C P3, con hub):
   `arm/companion/` = sdproxy + TinyUSB (clon en `arm/tinyusb/`, master 7b787da; `hcd_ci_hs.c`
   parcheado con `#elif defined(CI_HS_ZYNQ7000)` → `ci_hs_zynq.h`) sobre el USB0 del PS
   (ChipIdea/EHCI, PHY USB3320C por ULPI, MIO 28‑39; reset del PHY = MIO 46, VBUS por
   CPEN del PHY → Q3/Q4). PS7 regenerado con USB0 (`bd_ps7.tcl`: `PCW_USB0_*`), build
   12:22 OK (36,8 % LUT, WNS 0,97). Sin interrupciones: `tuh_int_handler` + `tuh_task_ext`
   por sondeo en el bucle del proxy; `tusb_time_millis_api` del timer global.
   ✅ 12:35 USB0 VIVO: `ULPI PHY id` responde, `USB host: OK (PORTSC 8C001000)` = ULPI,
   puerto alimentado (PP=1), nada conectado; el proxy de SD sigue sirviendo (navegador OK).
   Cazado por el camino: (1) `ps7_init` NO configura `MIO_PIN_46` (queda en tri‑state) → el
   companion lo pone él (SLCR: GPIO LVCMOS18); (2) `ci_hs_regs_t` arranca en la BASE del
   controlador (USBCMD +0x140), no en CAPLENGTH: con +0x100 el primer acceso caía en
   0xE0002240 → data abort (nueva herramienta `tools/armpc.tcl`: PC/LR/bt del core 0).
   Buzón HID del companion (MBOX+0x00 teclado como xsdb; +0x10 joy1|joy2<<16 en formato
   SNES del BL616; +0x14 btn|seq<<8 del ratón; +0x18 ax|ay<<16 acumulados int16).
   Lado PL (build `build_hid.out` en marcha 12:40): `dbg_mailbox_axi` lee 4 beats (32 B),
   saca `joy1/joy2` (OR con los del BL616 en `mcu_hid1/2`, 2FF a 27 MHz) y pulso+delta de
   ratón (clamp ±127, resto para la siguiente ronda) que entra en `msx_mouse` (mismo
   clk_54m) multiplexado con el de `usb_hid_host`. `armlog.tcl` muestra PORTSC y el buzón HID.
   ✅ 12:55 Mandos genéricos ya en el companion: `hid_pad.c` parsea el descriptor de informe HID
   (X/Y, hat, botones, Report ID) y saca la palabra SNES; botones 1‑8 → A B X Y LT RT SEL START
   (10+ botones: 9/10 = SEL/START). Probado en el PC (`tests/run.sh` con el gcc de WSL: DragonRise
   0079:0011 con sus X,X,X,X,Y, mando de 8 botones, estilo DS4 con Report ID, ejes con signo: 19/19).
   PENDIENTE: Albert enchufa hub + teclado/ratón/mando en P3 → `armlog.tcl` (montajes/informes,
   PORTSC, buzón HID) → teclear en DOS, mover el ratón, jugar.
   ✅ 13:10 Lado PL de los mandos VALIDADO sin USB (`tools/hid.tcl joy1 <hex>` escribe el buzón
   como lo haría el ARM; en BASIC `STICK(1)`/`STRIG(1)`): A → STRIG −1 ✓, pero DN daba
   izquierda, L abajo y R arriba → 🚨 **el `assign joystick0` del `top.v` compartido tenía el
   orden de bits al revés** (`joy0_msx` consume [3]=arriba…[0]=der; el comentario decía
   [0]=arriba): los mandos del BL616 en la Tang salían girados 180°. Corregido en `top.v`
   (afecta a las dos placas). Ratón por buzón: `PAD(16)` = −1 (presente) pero `PAD(17/18)` = 0 →
   en investigación con la telemetría nueva (+0x60: present/port2/strobe/fase/dx/dy/informes).
   13:45: el pulso y el delta llegan hasta `msx_mouse` (telemetría dx=40, informes cuenta), el
   strobe cambia (1→0 tras cada lectura de la BIOS), pero el protocolo manual desde BASIC
   (`OUT &HA1` pin 8 bajo/alto/bajo/alto + `INP(&HA2)`) devuelve `F0 F0 F0 F0`: el módulo
   NUNCA captura (rel_x/rel_y = 0). Botones: eran un pulso y `msx_mouse` los saca por
   combinacional → `mb_btn_q` de nivel (OR con el USB). Build `build_mouse.out` con
   `dbg_cur_x/dbg_rel_x` nuevos en `msx_mouse.v` + contador de flancos del strobe en +0x60.
   🏆🚨 14:25 **RAÍZ ENCONTRADA — bug del core compartido**: el strobe recibía ~60 flancos/s
   porque la BIOS (KEYINT, gatillos para ON STRIG) hace lee‑modifica‑escribe del reg. 15 del
   PSG dos veces por frame y **la relectura del reg. 15 devolvía FFh** (`top.v`: solo el 14
   estaba implementado; el `O_DA` del YM2149 no está conectado) → puerto 1 escribía AFh
   (bit 5 = 1) y puerto 2 DFh (bit 5 = 0) → pin 8 del puerto 2 conmutando a 60 Hz → el ratón
   perdía sus deltas en ciclos fantasma. Visto con la telemetría de escrituras al reg. 15
   (`DF AF DF`, ~66/s). Fix en `fpga/top.v` (reg. 15 → `psgPB`), build `build_psg15.out`.
   En la Tang pasaba lo mismo (INDEV lo disimulaba leyendo cada frame).
   🏆 14:45 **VALIDADO en BASIC con el bit corregido**: las escrituras al reg. 15 son ahora
   `CF 8F` (bit 5 quieto); `hid.tcl mouse -8 12` → `PAD(17)=-2 PAD(18)=3` (÷4 y signo MSX);
   mandos con el `assign` corregido: UP→1, DOWN→5, LEFT→7, RIGHT→3, A→`STRIG(1)`=−1.
   Queda probarlo con teclado/ratón/mando USB reales en P3 (Albert, esta noche).
4c. 🔨 13:15 **PÁGINA DE INFORMACIÓN (OSD) — pedido por Albert para ver la temperatura al poner
   el disipador esta noche**: el companion hace de BL616 con el protocolo de `iosys_bl616`
   (0xAA len cmd…: 4 cursor, 5 texto, 8 overlay) por la **UART0 del PS en EMIO** (bd:
   `PCW_UART0_UART0_IO EMIO`, puertos `UART0_TX/RX` → `bl616_jtagsel`/`iosys_uart_tx` en el
   generador; 2 Mbps = ref 100 MHz / (CD 10 · 5)). `arm/companion/osd.c`: XADC por el PS (die,
   máx., VCCINT/AUX/BRAM), SD (MB, lecturas/escrituras/errores), USB (dispositivos, teclados,
   ratones, mandos, informes), MSX (cpu_run, vdp ops, hits/miss de la RAM), uptime; refresco 1 s.
   Se enciende con **F12** del teclado USB o `tools/osd.tcl on|off` (MBOX+0x30); con el
   overlay encendido el Z80 queda congelado (`iosys_frz`) = pausa con datos. Mientras está
   apagado reenvía "overlay off" cada segundo (el PL se carga después que el ARM y su overlay
   nace encendido). `MBOX+0x34` = estado + temperatura (décimas) para `armlog.tcl`/`osd.tcl`.
   🏆 13:30 **VALIDADO por OBS**: `osd.tcl on` pinta la página (die 80,1 °C = `temp.tcl`,
   Vint 0,98 / Vaux 1,80 / Vbram 0,98, SD 14910 MB, USB 0, SCREEN 5 en pausa, caché 99,9 %,
   uptime) y `off` devuelve el control al Z80 (`frz=0 cpu_run=1`). Se escriben las 28 filas
   (la BSRAM de textdisp nace con el texto demo) y líneas ≤ 30 columnas (el borde derecho
   queda fuera de la captura). 🚨 Cazado por el camino: **sin MMU, un acceso desalineado es
   DATA ABORT** (memoria Strongly-Ordered) y gcc fusionaba `strb` en `strh/str` sobre los
   `char[]` de la página → `-mno-unaligned-access` en `build.sh` (protege a todo el companion).
   Más adelante: turbo y más datos (Albert). Pendiente de HW: F12 con el teclado USB.
5. Audio, SCC, OPL4 (ondas por `wv`), ESP32.
6. PS: FSBL + app que cargue packs de QSPI/SD y haga de BL616 (USB host,
   menú). Ahí entra el SDK (instalación offline desde el .tar.gz).
