/* lscript.ld — proxy de SD en la DDR baja del PS (0x00100000, 4 MB), lejos de
 * la VRAM (0x10000000), la RAM del Z80 (0x10800000), la imagen (0x11000000)
 * y los buzones (0x1FF00000). */
ENTRY(_start)
MEMORY { ddr (rwx) : ORIGIN = 0x00100000, LENGTH = 0x00400000 }
SECTIONS
{
    .vectors : { KEEP(*(.vectors)) } > ddr
    .text    : { *(.text*) *(.rodata*) *(.glue_7) *(.glue_7t) } > ddr
    .data    : { *(.data*) } > ddr
    .bss (NOLOAD) : { __bss_start = .; *(.bss*) *(COMMON) . = ALIGN(4); __bss_end = .; } > ddr
    .stack (NOLOAD) : { . = ALIGN(16); . = . + 0x8000; __stack_top = .; } > ddr
}
