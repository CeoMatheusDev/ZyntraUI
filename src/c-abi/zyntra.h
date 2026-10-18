#ifndef ZYNTRA_H
#define ZYNTRA_H

/* ZyntraUI — C ABI pública (M5).
 * Espelha src/c-abi/types.zig + src/c-abi/api.zig.
 * Tamanhos travados: ZyntraVec2=8, ZyntraRect=16, ZyntraColor=4,
 * ZyntraRenderStats=16.
 * Todo retorno é ZyntraResult (0 = ok). Ver docs/C_ABI.md.
 */

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum ZyntraResult {
    ZYNTRA_OK = 0,
    ZYNTRA_INVALID_ARGUMENT = 1,
    ZYNTRA_OUT_OF_MEMORY = 2,
    ZYNTRA_INVALID_EVENT = 3,
    ZYNTRA_INVALID_COMMAND = 4,
    ZYNTRA_INVALID_STATE = 5,
    ZYNTRA_INVALID_TEXT = 6
} ZyntraResult;

typedef struct ZyntraVec2 {
    float x;
    float y;
} ZyntraVec2;

typedef struct ZyntraSize {
    float w;
    float h;
} ZyntraSize;

typedef struct ZyntraRect {
    float x;
    float y;
    float w;
    float h;
} ZyntraRect;

typedef struct ZyntraColor {
    uint8_t r;
    uint8_t g;
    uint8_t b;
    uint8_t a;
} ZyntraColor;

typedef struct ZyntraContext ZyntraContext;
typedef struct ZyntraFramebuffer ZyntraFramebuffer;

/* Contadores da rasterização de software (zyntra_framebuffer_render*). */
typedef struct ZyntraRenderStats {
    uint32_t submitted;
    uint32_t drawn;
    uint32_t culled;
    uint32_t skipped_text;
} ZyntraRenderStats;

uint32_t zyntra_version_major(void);
uint32_t zyntra_version_minor(void);
uint32_t zyntra_version_patch(void);
const char *zyntra_version_prerelease(void);

ZyntraResult zyntra_context_create(ZyntraRect viewport, ZyntraContext **out_handle);
void zyntra_context_destroy(ZyntraContext *handle);
ZyntraResult zyntra_context_begin_frame(ZyntraContext *handle);
ZyntraResult zyntra_context_end_frame(ZyntraContext *handle);
ZyntraResult zyntra_context_frame_index(ZyntraContext *handle, uint64_t *out_index);
ZyntraResult zyntra_context_set_viewport(ZyntraContext *handle, ZyntraRect viewport);
ZyntraResult zyntra_context_push_mouse_move(ZyntraContext *handle, ZyntraVec2 pos);
ZyntraResult zyntra_context_push_mouse_button(ZyntraContext *handle, uint8_t button, bool pressed, ZyntraVec2 pos);
ZyntraResult zyntra_context_push_quit(ZyntraContext *handle);
ZyntraResult zyntra_context_pending_events(ZyntraContext *handle, size_t *out_len);
/* Repintura parcial (M98/M106): o acumulado do frame atual. */
ZyntraResult zyntra_context_mark_dirty(ZyntraContext *handle, ZyntraRect rect);
ZyntraResult zyntra_context_clear_dirty(ZyntraContext *handle);
ZyntraResult zyntra_context_dirty_rect(ZyntraContext *handle, ZyntraRect *out_rect);

/* Desenho: cada função enfileira um comando (validado; inválido devolve
 * ZYNTRA_INVALID_COMMAND e NÃO entra na lista). Geometria em pixels lógicos. */
ZyntraResult zyntra_draw_clear(ZyntraContext *handle, ZyntraColor color);
ZyntraResult zyntra_draw_clip(ZyntraContext *handle, ZyntraRect rect);
ZyntraResult zyntra_draw_clip_reset(ZyntraContext *handle);
ZyntraResult zyntra_draw_rect_filled(ZyntraContext *handle, ZyntraRect rect, ZyntraColor color);
ZyntraResult zyntra_draw_rect_outline(ZyntraContext *handle, ZyntraRect rect, ZyntraColor color,
    float thickness);
ZyntraResult zyntra_draw_line(ZyntraContext *handle, ZyntraVec2 p0, ZyntraVec2 p1,
    ZyntraColor color, float thickness);
ZyntraResult zyntra_draw_circle_filled(ZyntraContext *handle, ZyntraVec2 center, float radius,
    ZyntraColor color);
/* Cantos arredondados (SDF anti-serrilhado no backend de referência);
 * radius é clampado a min(w,h)/2. */
ZyntraResult zyntra_draw_rect_rounded(ZyntraContext *handle, ZyntraRect rect, float radius,
    ZyntraColor color);
/* Gradiente linear: color0 em p0, color1 em p1, contido em rect. */
ZyntraResult zyntra_draw_rect_gradient(ZyntraContext *handle, ZyntraRect rect, ZyntraVec2 p0,
    ZyntraVec2 p1, ZyntraColor color0, ZyntraColor color1);
/* Sombra projetada da silhueta arredondada (não desenha a forma). */
ZyntraResult zyntra_draw_rect_shadow(ZyntraContext *handle, ZyntraRect rect, float radius,
    ZyntraVec2 offset, float blur, ZyntraColor color);
/* Backdrop blur do que já foi desenhado dentro de rect (ordem importa). */
ZyntraResult zyntra_draw_blur(ZyntraContext *handle, ZyntraRect rect, float radius);

ZyntraResult zyntra_draw_count(ZyntraContext *handle, size_t *out_len);
ZyntraResult zyntra_draw_text(ZyntraContext *handle, ZyntraVec2 pos, ZyntraColor color,
    float size, const char *utf8, size_t utf8_len);
/* Métricas fallback (avanço fixo por glifo) sobre o texto UTF-8. */
ZyntraResult zyntra_text_measure(const char *utf8, size_t utf8_len, float size,
    float *out_width, float *out_height);
/* Bytes iniciais que cabem em max_width (corte em fronteira de codepoint). */
ZyntraResult zyntra_text_truncate(const char *utf8, size_t utf8_len, float size,
    float max_width, size_t *out_bytes);

/* Pixels (M106): framebuffer de software RGBA para rasterizar a DrawList
 * do frame. `create` aloca no page_allocator interno; dimensão 0 ou >8192
 * é inválida. `render` cobre o viewport do contexto clampado ao
 * framebuffer; `render_region` repinta só a região dada (o resto do
 * framebuffer fica como estava). `out_stats` pode ser NULL. */
ZyntraResult zyntra_framebuffer_create(uint32_t width, uint32_t height,
    ZyntraFramebuffer **out_handle);
void zyntra_framebuffer_destroy(ZyntraFramebuffer *handle);
ZyntraResult zyntra_framebuffer_size(ZyntraFramebuffer *handle, uint32_t *out_width,
    uint32_t *out_height);
ZyntraResult zyntra_framebuffer_fill(ZyntraFramebuffer *handle, ZyntraColor color);
ZyntraResult zyntra_framebuffer_pixel(ZyntraFramebuffer *handle, uint32_t x, uint32_t y,
    ZyntraColor *out_color);
ZyntraResult zyntra_framebuffer_render(ZyntraFramebuffer *handle, ZyntraContext *ctx,
    ZyntraRenderStats *out_stats);
ZyntraResult zyntra_framebuffer_render_region(ZyntraFramebuffer *handle, ZyntraContext *ctx,
    ZyntraRect region, ZyntraRenderStats *out_stats);

#ifdef __cplusplus
}
#endif

#endif /* ZYNTRA_H */
