/* start.S — arranque minimo del Cortex-A9 (core 0) para el proxy de SD.
 * Lo carga xsdb (dow sdproxy.elf; con) con la DDR ya entrenada por ps7_init.
 *   1. SCTLR: MMU, D-cache, I-cache y predictor fuera (la demo de fabrica pudo
 *      dejarlos activos): toda la memoria pasa a ser strongly-ordered, coherente
 *      con el PL (buzon) y con el DMA del SDIO sin mantenimiento de cache.
 *   2. tabla de vectores propia (VBAR): cualquier excepcion se queda en un bucle
 *      con su numero en r0 (leible con xsdb: rrd pc / r0).
 *   3. pila, .bss a cero, main().                                            */
    .syntax unified
    .arm
    .section .vectors, "ax"
    .global _vector_table
_vector_table:
    b   _start
    b   ex_undef
    b   ex_svc
    b   ex_pabt
    b   ex_dabt
    b   .
    b   ex_irq
    b   ex_fiq
ex_undef: mov r0, #1
          b .
ex_svc:   mov r0, #2
          b .
ex_pabt:  mov r0, #3
          b .
ex_dabt:  mov r0, #4
          b .
ex_irq:   mov r0, #6
          b .
ex_fiq:   mov r0, #7
          b .

    .text
    .global _start
_start:
    cpsid   if                          /* sin interrupciones */
    mrc     p15, 0, r0, c1, c0, 0       /* SCTLR */
    bic     r0, r0, #0x1                /* M: MMU off */
    bic     r0, r0, #0x4                /* C: D-cache off */
    bic     r0, r0, #0x1000             /* I: I-cache off */
    bic     r0, r0, #0x800              /* Z: branch predictor off */
    bic     r0, r0, #0x2000             /* V: vectores en VBAR (no en 0xFFFF0000) */
    mcr     p15, 0, r0, c1, c0, 0
    mov     r0, #0
    mcr     p15, 0, r0, c7, c5, 0       /* invalidar I-cache */
    mcr     p15, 0, r0, c7, c5, 6       /* invalidar predictor */
    dsb
    isb
    ldr     r0, =_vector_table
    mcr     p15, 0, r0, c12, c0, 0      /* VBAR */
    cps     #0x13                       /* modo SVC */
    ldr     sp, =__stack_top
    /* .bss a cero */
    ldr     r0, =__bss_start
    ldr     r1, =__bss_end
    mov     r2, #0
1:  cmp     r0, r1
    strlo   r2, [r0], #4
    blo     1b
    bl      main
2:  b       2b
