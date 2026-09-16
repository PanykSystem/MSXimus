# 08. Audio

Todo el sonido del MSXimus sale por el HDMI, mezclado dentro del core. Este capítulo dice qué chips hay, qué ve el software, cómo se reparte el estéreo y cómo se ajusta el volumen.

## 1. Los chips

| Chip | Qué es | Dónde lo ve el software |
|---|---|---|
| **PSG** | El sonido básico de todo MSX, tres voces y ruido | Puertos A0-A2, como siempre |
| ~~Segundo PSG~~ | Retirado en la v3.6h (dieta de área): los puertos 10-12 quedan vacíos | Sigue en el código tras `ENABLE_PSG2`, apagado |
| **SCC y SCC+** | El chip de ondas de Konami, cinco voces | Dentro del cartucho emulado, en el slot 2. Cualquier juego con mapper Konami-SCC lo tiene, y los que usan el SCC+ también |
| **Segundo SCC** | Otro SCC en el slot 1 | Para trackers y reproductores que buscan un SCC como cartucho aparte. Se activa en Ajustes, **Slot 1 = 2o SCC**, y es incompatible con el Game Master 2, que va en el mismo slot |
| **OPLL** | MSX-MUSIC, el FM-PAC de nueve voces | Puertos 7C-7D, con su BIOS en el pack |
| **MSX-Audio** | El Y8950 del Music Module de Philips: FM de nueve voces más un canal ADPCM de muestras | Puertos C0-C1, con 32 KB de memoria de muestras. Las interrupciones del chip funcionan |
| **MoonSound** | El OPL4 completo: FM de 18 voces (OPL3) y 24 voces de tabla de ondas con la ROM YRW801 de 2 MB | Puertos C4-C7 el FM, 7E-7F las ondas |

La ROM de ondas del MoonSound, `yrw801.rom`, se graba en la flash a 0x500000 y el core la copia a la memoria al arrancar. Sin ella el OPL4 tiene FM pero no ondas; el software que use instrumentos de la ROM sonará incompleto.

Todo esto está a la vez y sin conflictos: un juego puede usar PSG y SCC, un reproductor puede tocar el MoonSound mientras el PSG hace los efectos.

## 2. Mono y estéreo

En Ajustes, **Stereo Sound**:

| | Izquierda | Derecha |
|---|---|---|
| **Off** | Todo mezclado | Todo mezclado |
| **On** | PSG principal, SCC del cartucho, OPLL, MSX-Audio | Segundo PSG, segundo SCC, OPLL, MSX-Audio |

El MoonSound tiene sus propios canales izquierdo y derecho y en estéreo los saca tal cual. Con un solo SCC y un solo PSG, el estéreo pone el PSG y el SCC a un lado y el FM en el centro, que es lo que hacían los MSX con salida estéreo.

## 3. El volumen

Cada chip entra al mezclador a su nivel real, medido contra openMSX, y el conjunto lleva una **ganancia maestra** para el grupo clásico (PSG, SCC, OPLL, MSX-Audio) que sirve para ponerlos a la altura del MoonSound, que suena más fuerte de origen. Va de 0 a 7, el valor de fábrica es 5, y se guarda en la flash.

No hay opción de menú para cambiarla: se escribe en el puerto 44h del dispositivo de configuración y se guarda con la orden de Ajustes. Desde BASIC, para dejarla en 4:

```basic
OUT &H40,&H48 : OUT &H44,4 : OUT &H42,INP(&H42) OR &HC0
```

La ganancia cambia en el acto con la segunda orden; la tercera la guarda en la flash y reinicia la máquina, igual que Save & Restart. El mezclador satura suavemente en vez de recortar: con la ganancia alta y muchos chips a la vez se comprime, no distorsiona a saco.

## 4. Lo que se comprobó en placa

- PSG, SCC, OPLL y MoonSound en el propio menú de pruebas (tecla T, opción 2, para PSG y OPLL) y en juegos.
- MSX-Audio con ADPCM en VGMPlay y en juegos que lo usan.
- El MoonSound completo con MoonBlaster y con VGMs de OPL4.
- Dos SCC a la vez con trackers que usan el segundo.

Un caso conocido: **VGMPlay** con VGMs de OPL3 se cuelga bajo Nextor 3 beta, no bajo Nextor 2.1.4 ([capítulo 06](06-msxdos-nextor.md)).

## 5. Lo que no hay

- Salida analógica: todo va por el HDMI, así que hace falta un televisor o un extractor de audio HDMI.
- Chips fuera de la lista: no hay Darky ni SFG-01.
