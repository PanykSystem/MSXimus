# Documentación del MSXimus

Índice general. Cada capítulo dice para quién es, en qué estado está y de qué fuente sale, para que se pueda escribir y revisar por separado.

El README del repositorio se queda corto a propósito: qué es, qué hace falta y cómo se instala. Todo lo demás vive aquí.

## Cómo está organizada

| Carpeta | Para quién | Qué contiene |
|---|---|---|
| `docs/manual/` | Quien tiene la placa y quiere usarla | Instalación, tarjeta SD, menú, ROMs, discos, WiFi, audio, vídeo, problemas |
| `docs/tecnica/` | Quien quiere entender o modificar el core | Arquitectura, puertos de E/S, mapas de memoria, pack de BIOS, V9968, SD y DMA, campañas de síntesis, simulación, changelog |
| `docs/historico/` | Nadie en particular | Los documentos del porte de julio de 2026 y los informes de la v2, tal cual se escribieron. Se conservan porque explican decisiones, pero ya no describen el estado actual |

Idioma: castellano. El manual de usuario se traducirá al inglés cuando esté cerrado, como el README. La referencia técnica se queda en castellano.

## Manual de usuario (`docs/manual/`)

| Nº | Capítulo | Estado | De dónde sale |
|---|---|---|---|
| 01 | Qué es el MSXimus: la máquina, qué hardware hace falta, qué trae el core | pendiente | README, docs/BOARD_60K.md |
| 02 | Instalación: flashear el core (.fs y _jtag.bin), el pack de BIOS, el BL616, el ESP32-C6 | pendiente | README (secciones Installation, How to flash, About the BIOS pack, Flashing the BL616, Wiring the C6) |
| 03 | La tarjeta SD: formato y particiones, la carpeta FHUNT, dónde van las ROMs y los discos, etiquetas en el nombre, el fichero oculto NEXTOR.EMU | pendiente | menu_main.asm, srm_saves.asm, LEEME de v3.5 |
| 04 | [El menú de arranque](manual/04-menu.md): flujo de arranque, teclas del logo, navegador, lanzar ROM, lanzar disco, Ajustes, WiFi, File-Hunter, Pruebas, mensajes | **escrito** | menu_main.asm, gm2.asm, srm_saves.asm, test_menu.asm |
| 05 | ROMs y mappers: los mappers soportados (Plain, Konami, Konami-SCC, ASCII8, ASCII16, NEO-8, NEO-16), la megaram de 4 MB, la SRAM de cartucho y su guardado en la SD, el Game Master 2 en el slot 1 | pendiente | menu_main.asm, srm_saves.asm, gm2.asm, LEEME v3.5c/v3.5f |
| 06 | MSX-DOS y Nextor: los dos packs (Nextor 2.1.4 y Nextor 3 beta), lanzar un .dsk, la lectura por DMA, qué esperar de cada uno | pendiente | LEEME v3.6/v3.6c, memoria de Nextor 3 |
| 07 | WiFi y File-Hunter: el ESP32-C6, la tecla W, buscar y descargar con la tecla F, límites | pendiente | menu_main.asm, README (Wiring the C6), repo ESP32-for-FPGA |
| 08 | Audio: PSG, SCC, OPLL, OPL4, Y8950 y ADPCM, estéreo, el segundo SCC del slot 1 | pendiente | README, docs/informes_v2/INFORME_GANANCIA_AUDIO.md, memoria OPL4 |
| 09 | Vídeo: el V9968, modos HDMI, scanlines, el panel F12 del BL616 | pendiente | README (The V9968, The status panel), docs/tecnica/05 |
| 10 | Problemas frecuentes y cómo diagnosticarlos: la tecla T, el panel F12, qué mirar cuando la SD no aparece, cuando una ROM no arranca, cuando no hay red | pendiente | LEEMEs, test_menu.asm |

## Referencia técnica (`docs/tecnica/`)

| Nº | Capítulo | Estado | De dónde sale |
|---|---|---|---|
| 01 | [Arquitectura](tecnica/01-arquitectura.md): la placa, diagrama de bloques, relojes y dominios, el bus y los slots, la memoria, el vídeo, el audio, los periféricos, la secuencia de arranque | **escrito** | top.v y sus módulos |
| 02 | [Mapa de puertos de E/S](tecnica/02-puertos-es.md): la E/S conmutada 40h-4Fh con los tres dispositivos, los puertos de la SD, y el resto puerto a puerto | **escrito** | top.v, sdc_ioport.sv, swioports.vhd |
| 03 | [Mapas de memoria](tecnica/03-mapas-memoria.md): slots y páginas, la SDRAM física banco a banco, la megaram y sus segmentos reservados, la flash, la DDR3 | **escrito** | top.v, megaram.v, gm2_slot1.v, desmontar_pack.py |
| 04 | El pack de BIOS: las ROMs que lleva, cómo se monta (hacer_packs.py), el menú de 32 KB en la página 1, una BIOS por máquina | pendiente | repo bios-msxnano-msximus, memoria "anatomía del pack" |
| 05 | [El V9968 en el MSXimus](tecnica/05-v9968.md): qué es, de dónde sale, las tres generaciones del interfaz de registros y en cuál estamos, el puerto 4, cómo está integrado, cómo se comprueba | **escrito** | fpga/v9968/ORIGEN.txt, hra1129/V9968_Cartridge |
| 06 | [La tarjeta SD y la DMA](tecnica/06-sd-dma.md): el controlador, los cuatro caminos con sus velocidades, cómo funciona la DMA, los dos modos de destino, los contadores de mapper, quién usa qué, las firmas | **escrito** | sd_reader.sv, sdc_ioport.sv, sd_dma.sv, sd_rw_ports.inc |
| 07 | [Síntesis y campañas](tecnica/07-sintesis-campanas.md): herramientas, las dos líneas de build, cómo se lanza una campaña, el gate y la regla de los 0,4 ns, lo aprendido del chip, cómo se entrega | **escrito** | lanzar_campana.ps1, gate_check.ps1 |
| 08 | [Simulación](tecnica/08-simulacion.md): el entorno WSL, los bancos por subsistema, las ROMs de prueba, verificar contra openMSX, qué no tiene banco | **escrito** | tools/ |
| 09 | Changelog por versión, de la v3.1 a la v3.6, con el dado y los hashes de cada entrega | pendiente | los LEEME de files/, mi_release/ |

## Histórico (`docs/historico/`)

Pendiente de mover: `AUDIT_PRE_PORT_60K.md`, `BOARD_60K.md`, `CLOCK_CONSTANTS.md`, `CLOCK_PLAN.md`, `DDR3_WRAPPER.md`, `EXPEDIENTE_CAZA_V9968_v212_y_V3.md`, `FILE_MANIFEST.md`, `GW5A_IP.md`, `MEMORY_CONTRACT.md`, `MEMORY_OPTIONS.md`, `MIGRATION_STATUS.md`, `PORT_FINDINGS.md`, `PORT_PLAN.md`, `ROADMAP.md`, `SDR_MEMORY_PORT.md`, `VRAM_BRAM_DESIGN.md`, `email_ducasp_bl616.md` y la carpeta `informes_v2/`. Se mueven cuando los capítulos técnicos que los sustituyen estén escritos, no antes.

Se quedan donde están: `hw/` (esquema de la placa), `img/` y `logo/`.

## Pendiente transversal

- Capturas de pantalla del menú para el capítulo 04. Se pueden sacar del emulador con el pack del MSXimus.
- Créditos completos en el README al publicar la v3.6.
- Traducción al inglés del manual cuando esté cerrado.
