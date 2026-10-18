#ifndef ZYNTRA_H
#define ZYNTRA_H

/* ZyntraUI — C ABI pública (M5).
 * Espelha src/c-abi/types.zig + src/c-abi/api.zig.
 * Tamanhos travados: ZyntraVec2=8, ZyntraRect=16, ZyntraColor=4,
 * ZyntraRenderStats=16.
 * Todo retorno é ZyntraResult (0 = ok). Ver docs/C_ABI.md.
 * M107: tamanhos travados também para ZyntraId=8, ZyntraThemeColors=20,
 * ZyntraTextMetrics=16, estilos (24/24/28/32/16/12) e resultados
 * (20/3/3/4/8).
 * M108: ZyntraStr=16, ZyntraPanelOptions=24, estilos (20/36/36/48) e
 * resultados (3/24/24/20).
 * M109: ZyntraMenuItem=40, ZyntraTableColumn=24, ZyntraTableRow=16,
 * estilos Menu=24/Table=48 e resultados Menu=24/Table=24.
 * M110: ZyntraTreeItem=40, estilo TreeView=40 e resultado TreeView=32.
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

/* Widgets (M107): primeira superfície C. Os estilos são os mesmos `extern
 * struct` da API Zig (uma definição só por widget; as travas de layout em
 * src/c-abi/types.zig falham o build se mudarem). `ZyntraId` é o `u64`
 * opaco da API Zig: derive com `zyntra_id_from_string`/`zyntra_id_child`;
 * 0 é o id nulo e os widgets o rejeitam com ZYNTRA_INVALID_ARGUMENT.
 * `out_*` de resultado é opcional (NULL ignora). */

typedef uint64_t ZyntraId;

typedef enum ZyntraThemeKind {
    ZYNTRA_THEME_DARK = 0,
    ZYNTRA_THEME_LIGHT = 1
} ZyntraThemeKind;

typedef enum ZyntraOrientation {
    ZYNTRA_HORIZONTAL = 0,
    ZYNTRA_VERTICAL = 1
} ZyntraOrientation;

typedef struct ZyntraThemeColors {
    ZyntraColor bg;
    ZyntraColor surface;
    ZyntraColor text;
    ZyntraColor accent;
    ZyntraColor border;
} ZyntraThemeColors;

typedef struct ZyntraTextMetrics {
    float width;
    float height;
    uint32_t lines;
    uint32_t glyphs;
} ZyntraTextMetrics;

typedef struct ZyntraButtonStyle {
    ZyntraColor bg;
    ZyntraColor bg_hover;
    ZyntraColor bg_pressed;
    ZyntraColor border;
    float border_width;
    float radius;
} ZyntraButtonStyle;

typedef struct ZyntraCheckboxStyle {
    float box_size;
    ZyntraColor bg;
    ZyntraColor bg_checked;
    ZyntraColor border;
    ZyntraColor check;
    float border_width;
} ZyntraCheckboxStyle;

typedef struct ZyntraSwitchStyle {
    ZyntraColor track;
    ZyntraColor track_on;
    ZyntraColor track_hover;
    ZyntraColor knob;
    ZyntraColor border;
    float border_width;
    float knob_pad;
} ZyntraSwitchStyle;

typedef struct ZyntraSliderStyle {
    float track_height;
    ZyntraColor track_bg;
    ZyntraColor fill;
    float handle_w;
    float handle_h;
    ZyntraColor handle_bg;
    ZyntraColor border;
    float border_width;
} ZyntraSliderStyle;

typedef struct ZyntraProgressStyle {
    ZyntraColor bg;
    ZyntraColor fill;
    ZyntraColor border;
    float border_width;
} ZyntraProgressStyle;

typedef struct ZyntraSeparatorStyle {
    ZyntraColor color;
    float thickness;
    float label_gap;
} ZyntraSeparatorStyle;

typedef struct ZyntraLabelResult {
    ZyntraTextMetrics metrics;
    bool truncated;
} ZyntraLabelResult;

typedef struct ZyntraButtonResult {
    bool hovered;
    bool pressed;
    bool clicked;
} ZyntraButtonResult;

typedef struct ZyntraCheckboxResult {
    bool hovered;
    bool toggled;
    bool checked;
} ZyntraCheckboxResult;

typedef struct ZyntraSwitchResult {
    bool hovered;
    bool toggled;
    bool checked;
    bool focused;
} ZyntraSwitchResult;

typedef struct ZyntraSliderResult {
    float value;
    bool changed;
    bool hovered;
    bool dragging;
} ZyntraSliderResult;

/* Tema embutido (kind: ZYNTRA_THEME_DARK/LIGHT): cores base e estilos por
 * widget. O estilo devolvido é mutável — ajuste e passe ao widget. */
ZyntraResult zyntra_theme_colors(int32_t theme_kind, ZyntraThemeColors *out_colors);
ZyntraResult zyntra_style_button(int32_t theme_kind, ZyntraButtonStyle *out_style);
ZyntraResult zyntra_style_checkbox(int32_t theme_kind, ZyntraCheckboxStyle *out_style);
ZyntraResult zyntra_style_switch(int32_t theme_kind, ZyntraSwitchStyle *out_style);
ZyntraResult zyntra_style_slider(int32_t theme_kind, ZyntraSliderStyle *out_style);
ZyntraResult zyntra_style_progress(int32_t theme_kind, ZyntraProgressStyle *out_style);
ZyntraResult zyntra_style_separator(int32_t theme_kind, ZyntraSeparatorStyle *out_style);

/* Ids estáveis de widget (FNV-1a 64 do texto; len 0 ou NULL ⇒ 0). O filho
 * de um id nulo também é nulo. */
ZyntraId zyntra_id_from_string(const char *utf8, size_t utf8_len);
ZyntraId zyntra_id_child(ZyntraId parent, uint32_t index);

/* Widgets: exigem um frame ativo (como as funções de desenho) e desenham
 * caixas/linhas; o rótulo do botão é um `zyntra_widget_label` por cima,
 * como na API Zig. `utf8` é emprestado só durante a chamada (a DrawList
 * copia). `checked`/`value` pertencem ao chamador: o widget lê e altera. */
ZyntraResult zyntra_widget_label(ZyntraContext *handle, ZyntraId id, ZyntraRect bounds,
    ZyntraColor color, float size, const char *utf8, size_t utf8_len, bool debug_draw,
    ZyntraLabelResult *out_result);
ZyntraResult zyntra_widget_button(ZyntraContext *handle, ZyntraId id, ZyntraRect bounds,
    const ZyntraButtonStyle *style, ZyntraButtonResult *out_result);
ZyntraResult zyntra_widget_checkbox(ZyntraContext *handle, ZyntraId id, ZyntraRect bounds,
    bool *checked, const ZyntraCheckboxStyle *style, ZyntraCheckboxResult *out_result);
ZyntraResult zyntra_widget_switch(ZyntraContext *handle, ZyntraId id, ZyntraRect bounds,
    bool *checked, const ZyntraSwitchStyle *style, ZyntraSwitchResult *out_result);
ZyntraResult zyntra_widget_slider(ZyntraContext *handle, ZyntraId id, ZyntraRect bounds,
    float *value, float min, float max, const ZyntraSliderStyle *style,
    ZyntraSliderResult *out_result);
ZyntraResult zyntra_widget_progress(ZyntraContext *handle, ZyntraRect bounds, float frac,
    const ZyntraProgressStyle *style);
ZyntraResult zyntra_widget_separator(ZyntraContext *handle, ZyntraRect bounds,
    int32_t orientation, const ZyntraSeparatorStyle *style);

/* Listas de rótulos e painel (M108). Listas trafegam como `ZyntraStr`
 * (ptr + len, emprestados só durante a chamada — os widgets copiam o texto
 * para a DrawList); índices opcionais vêm como `int64_t` com -1 = nenhum. */

typedef struct ZyntraStr {
    const char *ptr;
    size_t len;
} ZyntraStr;

typedef struct ZyntraPanelOptions {
    ZyntraStr title;
    bool collapsible;
    bool closable;
} ZyntraPanelOptions;

typedef struct ZyntraRadioStyle {
    ZyntraColor box;
    ZyntraColor dot;
    ZyntraColor text;
    float border_width;
    float radio_r;
} ZyntraRadioStyle;

typedef struct ZyntraTabBarStyle {
    ZyntraColor bg;
    ZyntraColor bg_active;
    ZyntraColor bg_hover;
    ZyntraColor text;
    ZyntraColor text_active;
    ZyntraColor border;
    float border_width;
    float padding_x;
    float padding_y;
} ZyntraTabBarStyle;

typedef struct ZyntraListViewStyle {
    ZyntraColor bg;
    ZyntraColor bg_selected;
    ZyntraColor bg_hover;
    ZyntraColor text;
    ZyntraColor text_selected;
    ZyntraColor border;
    float border_width;
    float item_height;
    float padding_x;
} ZyntraListViewStyle;

typedef struct ZyntraPanelStyle {
    ZyntraColor bg;
    ZyntraColor header_bg;
    ZyntraColor border;
    float border_width;
    ZyntraColor title;
    ZyntraColor control;
    ZyntraColor control_hover;
    ZyntraColor separator;
    float header_pad;
    float padding_x;
    float padding_y;
    float control_size;
} ZyntraPanelStyle;

typedef struct ZyntraRadioResult {
    bool changed;
    bool hovered;
    bool focused;
} ZyntraRadioResult;

typedef struct ZyntraTabBarResult {
    bool changed;
    bool focused;
    int64_t hovered_index;
    size_t active;
} ZyntraTabBarResult;

typedef struct ZyntraListViewResult {
    size_t selected;
    int64_t hovered_index;
    float scroll_offset;
    bool changed;
} ZyntraListViewResult;

typedef struct ZyntraPanelResult {
    ZyntraRect content;
    bool collapsed;
    bool toggled;
    bool close_requested;
    bool hovered;
} ZyntraPanelResult;

ZyntraResult zyntra_style_radio(int32_t theme_kind, ZyntraRadioStyle *out_style);
ZyntraResult zyntra_style_tab_bar(int32_t theme_kind, ZyntraTabBarStyle *out_style);
ZyntraResult zyntra_style_list_view(int32_t theme_kind, ZyntraListViewStyle *out_style);
ZyntraResult zyntra_style_panel(int32_t theme_kind, ZyntraPanelStyle *out_style);

/* `options`/`tabs`/`items` são vetores de `ZyntraStr` (len > 0 com ptr NULL
 * ⇒ ZYNTRA_INVALID_ARGUMENT; len 0 é string vazia válida). `selected`/
 * `active`/`scroll_offset`/`collapsed` pertencem ao chamador: o widget lê e
 * altera. `size` é a fonte do texto (radio/painel); abas e itens de lista
 * usam a fonte padrão dos widgets (10). */
ZyntraResult zyntra_widget_radio(ZyntraContext *handle, ZyntraId id, ZyntraRect bounds,
    const ZyntraStr *options, size_t options_len, size_t *selected, float size,
    const ZyntraRadioStyle *style, ZyntraRadioResult *out_result);
ZyntraResult zyntra_widget_tab_bar(ZyntraContext *handle, ZyntraId id, ZyntraRect bounds,
    const ZyntraStr *tabs, size_t tabs_len, size_t *active, const ZyntraTabBarStyle *style,
    ZyntraTabBarResult *out_result);
ZyntraResult zyntra_widget_list_view(ZyntraContext *handle, ZyntraId id, ZyntraRect bounds,
    const ZyntraStr *items, size_t items_len, size_t *selected, float *scroll_offset,
    const ZyntraListViewStyle *style, ZyntraListViewResult *out_result);
ZyntraResult zyntra_widget_panel(ZyntraContext *handle, ZyntraId id, ZyntraRect bounds,
    bool *collapsed, ZyntraPanelOptions options, float size, const ZyntraPanelStyle *style,
    ZyntraPanelResult *out_result);

/* Estruturas planas (M109): menu e tabela. `ZyntraMenuItem` espelha o
 * `MenuItem` da API Zig (`has_checked == false` = item não marcável) e a
 * tabela usa um vetor de colunas mais um vetor de linhas, cada linha com seu
 * vetor de células. Tudo emprestado só durante a chamada. */

typedef struct ZyntraMenuItem {
    ZyntraStr label;
    ZyntraStr shortcut;
    bool enabled;
    bool separator;
    bool has_checked;
    bool checked;
} ZyntraMenuItem;

typedef struct ZyntraTableColumn {
    ZyntraStr title;
    float width;
} ZyntraTableColumn;

typedef struct ZyntraTableRow {
    const ZyntraStr *cells;
    size_t cells_len;
} ZyntraTableRow;

typedef struct ZyntraMenuStyle {
    ZyntraColor bg;
    ZyntraColor border;
    ZyntraColor item_hover;
    ZyntraColor text;
    ZyntraColor text_disabled;
    float border_width;
} ZyntraMenuStyle;

typedef struct ZyntraTableStyle {
    ZyntraColor bg;
    ZyntraColor bg_alt;
    ZyntraColor bg_selected;
    ZyntraColor bg_hover;
    ZyntraColor text;
    ZyntraColor text_header;
    ZyntraColor text_selected;
    ZyntraColor border;
    float border_width;
    float row_height;
    float header_height;
    float padding_x;
} ZyntraTableStyle;

typedef struct ZyntraMenuResult {
    int64_t chosen;
    int64_t hovered_index;
    bool dismissed;
    bool hovered;
    bool focus_parent;
} ZyntraMenuResult;

typedef struct ZyntraTableResult {
    size_t selected;
    int64_t hovered_index;
    float scroll_offset;
    bool changed;
} ZyntraTableResult;

ZyntraResult zyntra_style_menu(int32_t theme_kind, ZyntraMenuStyle *out_style);
ZyntraResult zyntra_style_table(int32_t theme_kind, ZyntraTableStyle *out_style);

/* `items` (menu) e `columns`/`rows` (tabela) são vetores emprestados só na
 * chamada; `active` e `selected`/`scroll_offset` pertencem ao chamador (o
 * widget lê e altera). `size` é a fonte dos itens do menu; a tabela usa a
 * fonte padrão dos widgets (10). */
ZyntraResult zyntra_widget_menu(ZyntraContext *handle, ZyntraId id, ZyntraRect bounds,
    const ZyntraMenuItem *items, size_t items_len, size_t *active, float size,
    const ZyntraMenuStyle *style, ZyntraMenuResult *out_result);
ZyntraResult zyntra_widget_table(ZyntraContext *handle, ZyntraId id, ZyntraRect bounds,
    const ZyntraTableColumn *columns, size_t columns_len, const ZyntraTableRow *rows,
    size_t rows_len, size_t *selected, float *scroll_offset, const ZyntraTableStyle *style,
    ZyntraTableResult *out_result);

/* Árvore recursiva (M110): `children` aponta para a árvore DO CHAMADOR
 * (mutável) porque `expanded` é o único estado que o widget altera e devolve
 * escrito de volta na árvore; os rótulos são emprestados só na chamada. */

typedef struct ZyntraTreeItem ZyntraTreeItem;

struct ZyntraTreeItem {
    ZyntraStr label;
    ZyntraTreeItem *children;
    size_t children_len;
    bool expanded;
};

typedef struct ZyntraTreeViewStyle {
    ZyntraColor bg;
    ZyntraColor bg_selected;
    ZyntraColor bg_hover;
    ZyntraColor text;
    ZyntraColor text_selected;
    ZyntraColor border;
    float border_width;
    float item_height;
    float indent;
    float expander_size;
} ZyntraTreeViewStyle;

typedef struct ZyntraTreeViewResult {
    size_t selected;
    int64_t hovered_index;
    float scroll_offset;
    bool changed;
    int64_t toggled_index;
} ZyntraTreeViewResult;

ZyntraResult zyntra_style_tree_view(int32_t theme_kind, ZyntraTreeViewStyle *out_style);

/* `items` é a árvore do chamador (`expanded` volta atualizado); `selected` e
 * `scroll_offset` pertencem ao chamador. Nós totais > 65536 ou profundidade
 * > 128 (inclusive ciclos) ⇒ ZYNTRA_INVALID_ARGUMENT. */
ZyntraResult zyntra_widget_tree_view(ZyntraContext *handle, ZyntraId id, ZyntraRect bounds,
    ZyntraTreeItem *items, size_t items_len, size_t *selected, float *scroll_offset,
    const ZyntraTreeViewStyle *style, ZyntraTreeViewResult *out_result);

#ifdef __cplusplus
}
#endif

#endif /* ZYNTRA_H */
