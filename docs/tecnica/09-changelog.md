# 09. Changelog de la era v3

Versión a versión, qué cambió, qué dado se entregó y con qué hashes. Sale de los LEEME de cada entrega en `files/<fecha>/`, que quedan fuera de git, y de las notas de `mi_release/`. Las versiones publicadas en GitHub llevan tag; las intermedias son entregas internas probadas en placa.

Los hashes son md5, los ocho primeros dígitos salvo donde se indica. El "dado" es el número primo con que se sembró el place and route ([capítulo 07](07-sintesis-campanas.md)); el margen es el peor setup del informe de temporización.

## v3.1 (26 de agosto de 2026, publicada, tag `v3.1.0`)

La versión que da nombre a la era: **el core reconstruido sin el SSRAM de la GW5AT-60B**, que Gowin retiró por un problema de silicio. Todas las memorias que vivían ahí pasaron a BSRAM o a registros, lo que obligó a rehacer por dentro el motor de ondas del OPL4, los registros del OPL3 y la caché PCM.

- Panel de estado en **F12** por el BL616 de la placa, con el MSX congelado debajo.
- Identificación como **turbo R**: registros del S1990 en E4-E7 y CHGCPU mueve el turbo. Sin R800.
- **Ratón MSX** desde un ratón USB con cable.
- Dos BIOS a elegir: la plana y la del navegador de la SD.
- El turbo pasa a **F11**.

| | |
|---|---|
| Core | `MSXimus_v3.1.fs` 2cbf1690, margen 0,607 ns. Respaldo 4655e7bf (0,473 ns), no publicado |
| Packs | bios-MSX 0d82f357, bios-Menu 28cb2a7b |
| BL616 | `bl616_v3.1.bin` af5a4f79 en 0x40000, con el de Sipeed 4dbe9bb1 en 0x0 |
| C6 | `firmware_esp32c6_unapi_merged.bin` 8acd1918, el mismo de la v2.1.2 |

## v3.2 (4 de septiembre de 2026, publicada, tag `v3.2`)

**El core no cambia**: es el mismo `.fs` de la v3.1. Cambia todo lo de encima.

- **Una sola BIOS**: el navegador es un ajuste, *Menú al arrancar*, guardado en la flash.
- **Descargas desde el menú**: tecla F, File-Hunter, ROMs y discos directos a la tarjeta.
- Logo MSX animado en la pantalla del C6.
- El firmware del C6 pasa a su propio repositorio, `ESP32-for-FPGA`, el mismo binario para el MSXimus y el MSXnano.

## v3.5a (5 de septiembre, interna)

Primera build del **plan 3.5**: la SD y los mappers.

- El controlador de la SD, arreglado de raíz: el token de estado de la escritura nunca se evaluaba y el host daba por escrito un sector que la tarjeta aún estaba programando. Ahora se lee el token y se espera el busy. Reloj de la tarjeta a 6,75 MHz (era 2,25). CRC16 de lectura comprobado, con reintento. CMD12 acotado.
- **Megaram de 4 MB** (era 2): el mapper de RAM se recorta a 2 MB y la megaram se queda con su hueco. ASCII16 recupera el bit 7 del registro; **NEO-8 y NEO-16** nuevos. Puerto 46h.
- Banco de 33.047 operaciones aleatorias contra la megaram de la v3.1 como oráculo.

Core: dado 3001, c3e350b0, margen 1,084 ns. Respaldo 3019. BSRAM al 118/118: desde aquí no queda ninguna.

## v3.5b (6 de septiembre, interna)

- **El menú pasa a ROM de 32 KB**: la segunda página va donde estaba el driver kanji, que desaparece del MSXimus. Ya no se descomprime en RAM.
- **SRAM de cartucho persistente** en la tarjeta: ficheros `.SRM` en `FHUNT`, guardado al siguiente arranque tras reset (bloque 5 del plan).

Core: dado 3041, 508f8330, margen 1,084 ns; respaldo 3083 (0,904 ns). Ocho dados en una noche para sacar dos buenos. Core y pack van en pareja: un core anterior con este pack no arranca el menú.

## v3.5c (6 de septiembre, interna)

- **La SD por puertos de E/S**: los registros del controlador en 47h-4Fh del dispositivo 48h, además de la ventana de memoria, que sigue igual. INIR en vez de LDIR.
- **Multibloque** CMD18 y CMD25 con un solo búfer: el core para el reloj de la tarjeta entre bloques.
- Driver de Nextor nuevo, común a 2.1.4 y 3, que sondea el core y usa lo que hay. Ninguna combinación de core y pack deja de arrancar desde aquí.

Core: dado 3169, eece0162, margen 0,481 ns; respaldo 3109 (0,419 ns). Velocidades en placa: 90, 104 y 112 KB/s por ventana, puertos y multibloque.

## v3.5d (6 y 7 de septiembre, interna)

- **Cronómetro de milisegundos** en el core, por el índice 25-27 de 4Eh: el menú medía la carga con el contador de la BIOS, que se para con las interrupciones inhibidas, y daba cifras imposibles.
- **Menú de pruebas** con la tecla T: velocidad de la SD por sus caminos, sonido, configuración.
- Todas las salidas del módulo de puertos de la SD pasan a registradas: la lógica combinacional colgada de IORQ_n y WR_n se llevó por delante tres campañas (0,171 ns, -1,55 ns, -0,791 ns).
- Una carrera metida al registrar la orden por ventana rompió la carga de ROMs en el dado 3257, que se retiró; el 3319 la lleva arreglada.

Core: dado 3319, de39e213, margen 1,309 ns, el mejor de la serie. Seis campañas y dieciocho dados en una noche: el mismo RTL dio desde 1,19 ns hasta -0,18 según el dado.

## v3.5e (8 de septiembre, pack de diagnóstico)

Solo el pack: la tecla T también desde el navegador, no solo en el logo. El core sigue el 3319.

## v3.5f (9 de septiembre, interna)

- **Game Master 2 emulado en el slot 1** (bloque 6): la ROM del cartucho y sus 8 KB de SRAM en la megaram, armado por el menú para los juegos Konami, guardado en `FHUNT\GM2.SRM` como la SRAM de cartucho. Ajustes: *Slot 1* con tres estados.
- Los packs del MSXimus pasan a **512 KB justos, sin la cola de configuración**: grabar un pack ya no pisa los ajustes.
- Se cierra la "pantalla negra" de Metal Gear 2: era la ROM [9692], cuyo arranque comprueba si hay MSX-DOS, no el core.

Core: dado 3461, e140f8da, margen 1,299 ns; respaldo 3457 (0,627 ns).

## v3.5g y v3.5h (9 de septiembre, packs)

- Corregido el "Enviando GET..." colgado de File-Hunter: una rutina de CRC había ido a parar a la página 1, que durante la sesión de red es la ROM del ESP (regresión de la 3.5b).
- **Tecla G** en la pantalla de lanzar: Game Master 2 On/Off por lanzamiento, para los juegos que usan el mapper Konami-SCC sin ser de Konami. Fuera la línea de velocidad de carga.

## v3.6 (9 de septiembre, interna)

- **DMA de lectura de la SD a la RAM**: el core vacía el búfer de sector sin pasar por el Z80, congelando la CPU con el bus en reposo y escribiendo por el camino del streamer de la flash. De 112 a **640 KB/s**. Guarda del refresco de la SDRAM: el refresco autónomo solo en las ventanas de espera de la tarjeta.
- El menú carga las ROMs por DMA, cluster a cluster.
- El puerto 2Fh dice 3.6.

Core: dado 3529, 29ffd767, margen 0,726 ns; respaldo 3527 (0,148 ns, solo respaldo). Commits ec9893d y bc0e3d0 en MSX_up_v3, e446e65 en la BIOS.

## v3.6b (9 de septiembre, pack)

El análisis del mapper de una ROM sin etiqueta pasa de leer sector a sector por la ventana a una DMA de 256 KB a la megaram y un escaneo con CPIR desde ahí: de siete segundos a dos. Commit 152693e en la BIOS.

## v3.6c (9 de septiembre, interna, validada en placa)

- **DMA en modo lógico**: el destino puede ser una dirección del Z80 que el core traduce con los registros del mapper, que para el Z80 son de solo escritura. Es lo que necesitaba el driver de Nextor.
- **Contadores de patrones de mapper** en la propia DMA: el análisis de una ROM sin etiqueta pasa a coste cero.
- **El driver de Nextor lee por DMA** cuando el búfer está en RAM del mapper: el arranque de DOS y la carga de programas se notan.
- Firma 'M' en el índice 31 de 4Eh.

Core: dado 3533, 1d3ab9ee, margen 0,913 ns; respaldo 3541 (0,039 ns, en el término del refresco, solo respaldo). Commits e5f1a54 en MSX_up_v3, 9aff42a en la BIOS. Validado en placa el 9 de septiembre: DMA a 640 KB/s, DOS arranca mucho más rápido, los discos cargan bien con Nextor 2.1.4 y con Nextor 3, Manbow 2 y Metal Gear 2 con Game Master 2 funcionan.

## v3.6d (9 de septiembre, sin campaña)

`cpu_run`, el término de seis señales que gobierna el refresco de la SDRAM, pasa a registrado antes de entrar al controlador de memoria: era el peor camino de temporización en los tres dados de la v3.6c. Commit 74f95de. Entra en la siguiente campaña.

## v3.6e (14 de septiembre, interna)

Dos errores del core que salieron a la luz portándolo a la Zynq (`fpga/zynq/`, repo privado `MSXimus_zynq`), donde el buzón de depuración permite inyectar mandos y ratón y leer la telemetría sin hardware. Los dos están en `top.v` y afectan igual a la Console 60K; entran en la siguiente campaña.

- **La cruceta de los mandos, mal cableada desde la v3.1**: `assign joystick0/1` tenía dos errores a la vez. El eje vertical estaba al revés de como lo consume `joy0_msx` (el byte que ve el PSG): ponía arriba en el bit 0 y abajo en el 1, y el consumidor lee arriba en el 3 y abajo en el 2. Y el eje horizontal se tomaba de los bits 10 y 11 de la palabra del BL616, que son los **hombros L y R**, no la cruceta: en el formato del firmware (`usb_gamepad.cpp:337` con `hidparser.cpp`: right/left/down/up en los bits 0-3 del byte HID, subidos a 7/6/5/4) izquierda y derecha son los bits **6 y 7**. En la Console 60K el resultado era: arriba daba derecha, abajo daba izquierda, izquierda y derecha no hacían nada y los hombros movían arriba y abajo. El primer error salió en la Zynq; el segundo, al revisar ese arreglo contra el firmware: el companion de la Zynq (`hid_pad.c`) había copiado del comentario de `top.v` la misma idea equivocada de que la cruceta iba en 10/11, así que allí el arreglo a medias parecía completo. Ahora `top.v` lee 4/5/6/7 y `hid_pad.c` emite ese mismo formato, con los hombros en 10/11. Los botones A/B y el autodisparo no cambian.
- **El ratón perdía el movimiento**: la relectura del registro 15 del PSG devolvía FFh (solo el 14 estaba implementado en la multiplexación de `cpu_din`; el `O_DA` del YM2149 sigue sin conectar). La interrupción de la BIOS lee, modifica y escribe ese registro dos veces por frame para los gatillos de `ON STRIG` (puerto 1 `AND AFh OR 03h`, puerto 2 `AND DFh OR 4Ch`): con FFh de partida escribía AFh y luego DFh, es decir, el pin 8 del puerto 2 subía y bajaba a 60 Hz, y cada pulso hacía que `msx_mouse` capturase y vaciase su acumulador en un ciclo fantasma que nadie leía. `PAD(17)`/`PAD(18)` devolvían 0 salvo con programas que leen cada frame (INDEV lo disimulaba). Ahora el registro 15 se relee (`psgPB`) y las escrituras quedan en CFh/8Fh, con el pin 8 quieto.
- `msx_mouse` gana dos salidas de diagnóstico (`dbg_cur_x`, `dbg_rel_x`) que en la 60K quedan sin conectar.

Commits 39289a2 y 816937c en MSX_up_v3 (rama V3.5). El ratón y la cruceta se validaron en la Zynq desde BASIC: `STICK(1)` 1/5/7/3 para arriba/abajo/izquierda/derecha, `STRIG(1)`/`STRIG(3)` con A/B, `PAD(17)` = 20 para un delta de 80 (sensibilidad ÷4). Queda confirmar el sentido del ratón (`NEGAR_DELTA`) con un programa real.

Core: dado 3557, e67ba712, margen 1,170 ns (el peor camino es ahora interno del V9968: el término del refresco que registró la v3.6d ha salido del informe). Los dados 3547 y 3559 no rutaron (425 y 84 redes sin rutar), así que no hay respaldo. Campaña v36e, quince minutos de place and route en el dado bueno. Es el primer core de la 60K con el que se puede probar un mando.

Un apunte que sale de la misma revisión, sin arreglar: los registros 0 a 13 del PSG tampoco se releen (devuelven FFh; `O_DA` del YM2149 está sin conectar, aunque el modelo sí los sirve). Ningún juego probado lo ha echado en falta, pero un reproductor que haga `RDPSG 7` para tocar el mezclador se encontraría todo silenciado.

**Un error del V9968, encontrado la misma noche y sin arreglar: el marcador de Xevious Fardraut Saga sale en blanco.** El juego (Namco 1989, 256 KB, `[GoodMSX] [2489]`) arranca, y el logo, la intro, la demostración y las escenas se dibujan bien; pero en partida la banda del marcador, arriba, sale blanca con puntos de colores en vez del `TOP / HI SCORE / AREA / LEFT` que muestra openMSX. El campo de juego, los sprites y el scroll van bien. Pasa igual en la Console 60K (dado 3557) y en la Zynq, luego es del VDP compartido y no de ninguno de los dos portes. En la Zynq se volcó la VRAM durante la partida: la línea 0 de la página 0 tiene gráficos reales, y la zona de las líneas 212 a 255 (`6A00h`-`7FFFh`, fuera de la ventana visible) está entera a `FFh`, que en SCREEN 5 es blanco. Es decir, el VDP está mostrando arriba una zona de VRAM que nadie ha escrito. El juego usa el truco clásico de mover el desplazamiento vertical (R#23) a media pantalla con la interrupción de línea (R#19) para que el marcador quede quieto mientras el campo hace scroll, y los dos registros existen en `vdp_cpu_interface.v`, así que es un detalle de comportamiento y no una función que falte. Quedan dos mecanismos por separar: o el marcador vive en otra zona y a media pantalla se aplica el desplazamiento equivocado, o el juego sí lo dibuja en las líneas 212-255 y el V9968 pierde las escrituras por encima de la línea 211. Lo primero que hay que hacer es mirar en openMSX dónde escribe el juego el marcador y qué valor toma R#23 al principio del cuadro. Herramientas de la Zynq para seguirlo: `tools/vram.tcl` vuelca la VRAM cruda desde la DDR y `tools/vramfill.tcl` la rellena. Sin probar en el MSXnano, que lleva el VDP clásico.

## Pendiente

- Xevious Fardraut Saga: el marcador en blanco (V9968, ver arriba).

- Validar en la 60K el dado 3557: un mando real por el USB-C del BL616 (no se sabe de ninguno que haya funcionado con las direcciones bien desde la v3.1) y el ratón sin INDEV.
- Fase 3 de la SD: reloj de la tarjeta a 13,5 MHz, que exige rehacer el divisor y el muestreo.
- Guardado de Manbow 2, que usa una flash AMD en el cartucho en vez de SRAM.
- Publicar la v3.6: carpeta de release, notas y créditos.
