/* hid_pad.c — mandos USB genericos: parser minimo del descriptor de informe HID
 * (items cortos, HID 1.11) que localiza en el informe de ENTRADA:
 *   Generic Desktop (pag. 0x01): X 0x30, Y 0x31, Hat switch 0x39
 *   Button (pag. 0x09): botones 1..16
 * y los convierte a la palabra SNES que espera el top (misma que el BL616).
 * Botones -> SNES: 1 A, 2 B, 3 X, 4 Y, 5 LT, 6 RT, 7 SEL, 8 START (los mandos
 * "SNES USB" baratos traen X,A,B,Y,L,R,Sel,Start en ese orden: queda X->A y A->B,
 * o sea disparo A/B del MSX en los dos botones de la derecha; jugable igual).
 * Ejes: < 25 % del recorrido = izq/arriba, > 75 % = der/abajo. Hat: 0..7 desde arriba. */
#include "hid_pad.h"

typedef struct { uint16_t off; uint8_t size; uint8_t used; int32_t lmin, lmax; } field_t;
typedef struct {
    uint8_t  dev, idx, used, rid;          /* rid: Report ID del informe con los ejes (0 = sin ID) */
    field_t  x, y, hat;
    uint16_t btn_off[16];
    uint8_t  nbtn;
} pad_t;

static pad_t pads[HID_PAD_MAX];

static int32_t sext(uint32_t v, unsigned size)
{
    if (size == 1) return (int8_t)v;
    if (size == 2) return (int16_t)v;
    return (int32_t)v;
}

static uint32_t bits_get(const uint8_t *rep, uint16_t nbits_total, uint16_t off, uint8_t size)
{
    uint32_t v = 0;
    for (uint8_t i = 0; i < size && i < 32u; i++) {
        uint16_t b = off + i;
        if (b >= nbits_total) break;
        if (rep[b >> 3] & (1u << (b & 7u))) v |= 1u << i;
    }
    return v;
}

static void parse(pad_t *p, const uint8_t *d, uint16_t len)
{
    uint32_t upage = 0, rsize = 0, rcount = 0, rid = 0;
    int32_t  lmin = 0, lmax = 0;
    uint32_t usages[32]; unsigned nus = 0;
    uint32_t umin = 0, umax = 0; int have_range = 0;
    uint16_t bitpos = 0;                         /* posicion en el informe de ENTRADA del rid actual */
    uint32_t cur_rid_pos = 0;
    uint16_t i = 0;

    while (i < len) {
        uint8_t  b0 = d[i++];
        if (b0 == 0xFE) { if (i + 1 < len) { uint16_t n = d[i]; i += 2 + n; } else break; continue; }   /* item largo */
        uint8_t  bsize = b0 & 3u; if (bsize == 3u) bsize = 4u;
        uint8_t  btype = (b0 >> 2) & 3u, btag = b0 >> 4;
        uint32_t data = 0;
        for (uint8_t k = 0; k < bsize && i < len; k++) data |= (uint32_t)d[i++] << (8u * k);

        if (btype == 1u) {                       /* GLOBAL */
            switch (btag) {
            case 0: upage = data; break;
            case 1: lmin = sext(data, bsize); break;
            case 2: lmax = sext(data, bsize); break;
            case 7: rsize = data; break;
            case 8: if (data != rid) { rid = data; bitpos = 0; cur_rid_pos = data; } break;
            case 9: rcount = data; break;
            default: break;
            }
        } else if (btype == 2u) {                /* LOCAL */
            switch (btag) {
            case 0: if (nus < 32u) usages[nus++] = data & 0xFFFFu; break;
            case 1: umin = data & 0xFFFFu; have_range = 1; break;
            case 2: umax = data & 0xFFFFu;
                    if (have_range) for (uint32_t u = umin; u <= umax && nus < 32u; u++) usages[nus++] = u;
                    have_range = 0; break;
            default: break;
            }
        } else if (btype == 0u) {                /* MAIN */
            if (btag == 8u) {                    /* Input */
                int is_const = data & 1u;
                for (uint32_t k = 0; k < rcount; k++) {
                    uint32_t u = nus ? usages[k < nus ? k : nus - 1u] : 0u;
                    if (!is_const && rsize) {
                        if (upage == 0x01u) {
                            /* X/Y: se queda el ULTIMO (los mandos DragonRise 0079:0011 declaran
                             * X,X,X,X,Y y los ejes reales son los dos ultimos bytes); hat: el primero */
                            field_t *f = (u == 0x30u) ? &p->x : (u == 0x31u) ? &p->y : (u == 0x39u) ? &p->hat : 0;
                            if (f && (u != 0x39u || !f->used)) {
                                f->used = 1; f->off = bitpos; f->size = (uint8_t)(rsize > 32u ? 32u : rsize);
                                f->lmin = lmin; f->lmax = lmax; p->rid = (uint8_t)cur_rid_pos;
                            }
                        } else if (upage == 0x09u && u >= 1u && u <= 16u && rsize == 1u) {
                            if (u > p->nbtn) p->nbtn = (uint8_t)u;
                            p->btn_off[u - 1u] = bitpos;
                        }
                    }
                    bitpos = (uint16_t)(bitpos + rsize);
                }
            }
            /* Output/Feature no gastan bits del informe de entrada; Collection nada */
            nus = 0; have_range = 0;             /* los locales se consumen en cada main item */
        }
    }
}

int hid_pad_mount(uint8_t dev, uint8_t idx, const uint8_t *desc, uint16_t len)
{
    int slot = -1;
    for (int k = 0; k < HID_PAD_MAX; k++) if (!pads[k].used) { slot = k; break; }
    if (slot < 0) return -1;
    pad_t *p = &pads[slot];
    for (unsigned k = 0; k < sizeof(*p); k++) ((uint8_t *)p)[k] = 0;
    parse(p, desc, len);
    if (!p->x.used && !p->y.used && !p->hat.used && p->nbtn == 0) return -1;
    p->dev = dev; p->idx = idx; p->used = 1;
    return slot;
}

int hid_pad_umount(uint8_t dev, uint8_t idx)
{
    for (int k = 0; k < HID_PAD_MAX; k++)
        if (pads[k].used && pads[k].dev == dev && pads[k].idx == idx) { pads[k].used = 0; return k; }
    return -1;
}

static int axis_dir(const field_t *f, const uint8_t *rep, uint16_t nbits)
{
    if (!f->used) return 0;
    int32_t v = (int32_t)bits_get(rep, nbits, f->off, f->size);
    if (f->lmin < 0) v = sext((uint32_t)v, f->size > 16u ? 4u : f->size > 8u ? 2u : 1u);
    int32_t range = f->lmax - f->lmin; if (range <= 0) return 0;
    if (v < f->lmin + range / 4) return -1;
    if (v > f->lmax - range / 4) return 1;
    return 0;
}

int hid_pad_report(uint8_t dev, uint8_t idx, const uint8_t *rep, uint16_t len, uint16_t *word)
{
    int slot = -1;
    for (int k = 0; k < HID_PAD_MAX; k++) if (pads[k].used && pads[k].dev == dev && pads[k].idx == idx) slot = k;
    if (slot < 0 || len == 0) return -1;
    pad_t *p = &pads[slot];
    if (p->rid) { if (rep[0] != p->rid) return -1; rep++; len--; }
    uint16_t nbits = (uint16_t)(len * 8u), w = 0;
    int dx = axis_dir(&p->x, rep, nbits), dy = axis_dir(&p->y, rep, nbits);
    if (p->hat.used) {
        int32_t h = (int32_t)bits_get(rep, nbits, p->hat.off, p->hat.size) - p->hat.lmin;
        if (h >= 0 && h <= 7) {                  /* 0 arriba, en sentido horario */
            if (h == 7 || h == 0 || h == 1) dy = -1;
            if (h >= 3 && h <= 5) dy = 1;
            if (h >= 1 && h <= 3) dx = 1;
            if (h >= 5 && h <= 7) dx = -1;
        }
    }
    if (dy < 0) w |= 1u << 4;
    if (dy > 0) w |= 1u << 5;
    if (dx < 0) w |= 1u << 10;
    if (dx > 0) w |= 1u << 11;
    /* boton 1..10 -> A B X Y LT RT y luego SEL START (8 botones) o LT RT SEL START (10+: L2/R2 hacen de hombro) */
    static const uint8_t map8[8]   = { 8, 0, 9, 1, 6, 7, 2, 3 };
    static const uint8_t map10[10] = { 8, 0, 9, 1, 6, 7, 6, 7, 2, 3 };
    const uint8_t *map = p->nbtn >= 10u ? map10 : map8;
    uint8_t nmap = p->nbtn >= 10u ? 10u : 8u;
    for (uint8_t b = 0; b < nmap && b < p->nbtn; b++)
        if (bits_get(rep, nbits, p->btn_off[b], 1)) w |= 1u << map[b];
    *word = w;
    return slot;
}
