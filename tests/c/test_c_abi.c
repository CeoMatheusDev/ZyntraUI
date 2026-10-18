/* Consumidor C real da ZyntraUI via C-ABI (teste de integração M5/M6).
 * Compilar: zig cc tests/c/test_c_abi.c -Lzig-out/lib -lzyntra_ui -o /tmp/zyntra-c-test
 * (ou contra a lib estática direta). Retorna 0 em sucesso.
 */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "zyntra.h"

#define CHECK(expr) do { \
    ZyntraResult r = (expr); \
    if (r != ZYNTRA_OK) { \
        printf("FAIL %s:%d -> %d\n", __FILE__, __LINE__, (int)r); \
        return 1; \
    } \
} while (0)

int main(void) {
    /* Layout de ABI verificado em tempo de compilação. */
    _Static_assert(sizeof(ZyntraVec2) == 8, "ZyntraVec2 ABI");
    _Static_assert(sizeof(ZyntraRect) == 16, "ZyntraRect ABI");
    _Static_assert(sizeof(ZyntraColor) == 4, "ZyntraColor ABI");
    _Static_assert(ZYNTRA_OK == 0, "ok==0");

    printf("zyntra %u.%u.%u\n",
        zyntra_version_major(), zyntra_version_minor(), zyntra_version_patch());
    /* Versão completa espelha build.zig.zon (atualizar no prep de
     * release; o CI detecta divergência). major==1 também trava
     * MAJOR acidental (ver M44). */
    assert(zyntra_version_major() == 1);
    assert(zyntra_version_minor() == 32);
    assert(zyntra_version_patch() == 0);
    assert(strcmp(zyntra_version_prerelease(), "") == 0);

    ZyntraContext *ctx = NULL;
    ZyntraRect vp = {0, 0, 800, 600};
    CHECK(zyntra_context_create(vp, &ctx));
    assert(ctx != NULL);

    /* Viewport negativo rejeitado sem alocar. */
    {
        ZyntraContext *bad = NULL;
        ZyntraRect neg = {0, 0, -1, 600};
        assert(zyntra_context_create(neg, &bad) == ZYNTRA_INVALID_ARGUMENT);
        assert(bad == NULL);
    }

    CHECK(zyntra_context_begin_frame(ctx));
    assert(zyntra_context_begin_frame(ctx) == ZYNTRA_INVALID_STATE);

    ZyntraVec2 p = {30, 25};
    CHECK(zyntra_context_push_mouse_move(ctx, p));
    CHECK(zyntra_context_push_mouse_button(ctx, 0, true, p));
    assert(zyntra_context_push_mouse_button(ctx, 7, true, p) == ZYNTRA_INVALID_ARGUMENT);

    ZyntraRect btn = {10, 10, 120, 40};
    ZyntraColor red = {200, 0, 0, 255};
    CHECK(zyntra_draw_rect_filled(ctx, btn, red));

    ZyntraRect negw = {0, 0, -1, 5};
    ZyntraColor black = {0, 0, 0, 255};
    assert(zyntra_draw_rect_filled(ctx, negw, black) == ZYNTRA_INVALID_COMMAND);

    size_t events = 0, draws = 0;
    CHECK(zyntra_context_pending_events(ctx, &events));
    CHECK(zyntra_draw_count(ctx, &draws));
    assert(events == 2);
    assert(draws == 1);

    /* Text-run: cópia imediata (buffer local pode morrer após o retorno). */
    {
        char buf[8];
        memcpy(buf, "Hi", 3);
        ZyntraVec2 tp = {1, 2};
        ZyntraColor white = {255, 255, 255, 255};
        CHECK(zyntra_draw_text(ctx, tp, white, 16.0f, buf, 2));
        memset(buf, 'X', sizeof buf); /* prova que houve cópia */
        CHECK(zyntra_draw_count(ctx, &draws));
        assert(draws == 2);
        /* UTF-8 malformado, size inválido, ptr nulo com len. */
        assert(zyntra_draw_text(ctx, tp, white, 16.0f, "\xff", 1) == ZYNTRA_INVALID_TEXT);
        assert(zyntra_draw_text(ctx, tp, white, 0.0f, "Hi", 2) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_draw_text(ctx, tp, white, 16.0f, NULL, 3) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_draw_text(ctx, tp, white, 16.0f, NULL, 0) == ZYNTRA_OK);
        CHECK(zyntra_draw_count(ctx, &draws));
        assert(draws == 3);
    }

    CHECK(zyntra_context_end_frame(ctx));
    assert(zyntra_context_end_frame(ctx) == ZYNTRA_INVALID_STATE);

    uint64_t idx = 0;
    CHECK(zyntra_context_frame_index(ctx, &idx));
    assert(idx == 1);

    /* Frame 2: desenho moderno (SDF/gradiente/sombra/blur), clip e
     * métricas de texto — a mesma DrawList da API Zig. */
    size_t modern = 0;
    float mw = 0, mh = 0;
    size_t kept = 0;
    {
        CHECK(zyntra_context_begin_frame(ctx));
        ZyntraRect box = {10, 10, 40, 30};
        ZyntraColor white = {255, 255, 255, 255};
        ZyntraColor dark = {10, 10, 20, 255};
        ZyntraVec2 o = {0, 2};
        ZyntraVec2 g0 = {0, 0};
        ZyntraVec2 g1 = {0, 30};
        ZyntraVec2 l0 = {0, 0}, l1 = {40, 30};
        ZyntraVec2 c = {30, 20};

        CHECK(zyntra_draw_clear(ctx, dark));
        CHECK(zyntra_draw_clip(ctx, box));
        CHECK(zyntra_draw_rect_shadow(ctx, box, 6, o, 4, dark));
        CHECK(zyntra_draw_rect_rounded(ctx, box, 6, white));
        CHECK(zyntra_draw_rect_gradient(ctx, box, g0, g1, white, dark));
        CHECK(zyntra_draw_rect_outline(ctx, box, white, 1.5f));
        CHECK(zyntra_draw_line(ctx, l0, l1, white, 2.0f));
        CHECK(zyntra_draw_circle_filled(ctx, c, 8.0f, white));
        CHECK(zyntra_draw_blur(ctx, box, 3.0f));
        CHECK(zyntra_draw_clip_reset(ctx));

        /* Inválidos não enfileiram (contagem preservada). */
        assert(zyntra_draw_rect_rounded(ctx, box, -1.0f, white) == ZYNTRA_INVALID_COMMAND);
        assert(zyntra_draw_rect_outline(ctx, box, white, 0.0f) == ZYNTRA_INVALID_COMMAND);
        assert(zyntra_draw_blur(ctx, box, 3.0f) == ZYNTRA_OK);

        CHECK(zyntra_draw_count(ctx, &modern));
        assert(modern == 11); /* 10 + o blur extra acima */

        CHECK(zyntra_text_measure("abc", 3, 10.0f, &mw, &mh));
        assert(mw > 0.0f && mh > 0.0f);
        /* 3 glifos * avanço 6px de `withSize(10)` ≈ 18px de largura
         * (comparação com tolerância: avanço é float). */
        assert(mw > 17.9f && mw < 18.1f);
        CHECK(zyntra_text_truncate("abcdef", 6, 10.0f, mw + 1.0f, &kept));
        assert(kept == 3);
        assert(zyntra_text_measure("\xff", 1, 10.0f, &mw, &mh) == ZYNTRA_INVALID_TEXT);
        assert(zyntra_text_measure("a", 1, 0.0f, &mw, &mh) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_text_truncate("a", 1, 10.0f, -1.0f, &kept) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_text_truncate("a", 1, 10.0f, 5.0f, NULL) == ZYNTRA_INVALID_ARGUMENT);
        CHECK(zyntra_context_end_frame(ctx));
    }

    /* Frame 3: caminho de pixels (M106) — framebuffer de referência.
     * O mesmo rasterizador da API Zig, agora alcançável do C: render
     * integral, leitura de pixel e repintura parcial dirigida por
     * `zyntra_context_mark_dirty`. */
    ZyntraFramebuffer *fb = NULL;
    int grad_left = 0, grad_right = 0, round_in = 0, round_out = 0;
    int part_px = 0, kept_px = 0;
    size_t stats_sub = 0, stats_drawn = 0, stats_culled = 0;
    {
        _Static_assert(sizeof(ZyntraRenderStats) == 16, "ZyntraRenderStats ABI");

        ZyntraFramebuffer *badfb = NULL;
        assert(zyntra_framebuffer_create(0, 32, &badfb) == ZYNTRA_INVALID_ARGUMENT);
        assert(badfb == NULL);
        assert(zyntra_framebuffer_create(32, 9000, &badfb) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_framebuffer_create(64, 32, NULL) == ZYNTRA_INVALID_ARGUMENT);
        CHECK(zyntra_framebuffer_create(64, 32, &fb));
        assert(fb != NULL);

        uint32_t fw = 0, fh = 0;
        CHECK(zyntra_framebuffer_size(fb, &fw, &fh));
        assert(fw == 64 && fh == 32);

        ZyntraRect fvp = {0, 0, 64, 32};
        CHECK(zyntra_context_set_viewport(ctx, fvp));

        ZyntraColor bg = {10, 20, 30, 255};
        ZyntraColor fred = {200, 40, 40, 255};
        ZyntraColor fwhite = {255, 255, 255, 255};
        ZyntraColor fblack = {0, 0, 0, 255};
        ZyntraColor fgreen = {0, 200, 60, 255};
        ZyntraColor fblue = {40, 80, 220, 255};
        ZyntraColor px = {0, 0, 0, 0};

        CHECK(zyntra_framebuffer_fill(fb, bg));
        CHECK(zyntra_framebuffer_pixel(fb, 63, 31, &px));
        assert(px.r == bg.r && px.g == bg.g && px.b == bg.b && px.a == 255);

        CHECK(zyntra_context_begin_frame(ctx));
        ZyntraRect box = {4, 4, 16, 16};
        ZyntraRect grad_box = {32, 4, 24, 16};
        ZyntraRect round_box = {4, 20, 20, 10};
        CHECK(zyntra_draw_clear(ctx, bg));
        CHECK(zyntra_draw_rect_filled(ctx, box, fred));
        ZyntraVec2 g0 = {32, 4}, g1 = {56, 4};
        CHECK(zyntra_draw_rect_gradient(ctx, grad_box, g0, g1, fwhite, fblack));
        CHECK(zyntra_draw_rect_rounded(ctx, round_box, 5.0f, fgreen));

        /* Dirty rect acumula a união e `clear_dirty` zera. */
        CHECK(zyntra_context_mark_dirty(ctx, box));
        CHECK(zyntra_context_mark_dirty(ctx, grad_box));
        ZyntraRect dirty = {0, 0, 0, 0};
        CHECK(zyntra_context_dirty_rect(ctx, &dirty));
        assert(dirty.x == 4.0f && dirty.y == 4.0f && dirty.w == 52.0f && dirty.h == 16.0f);
        CHECK(zyntra_context_clear_dirty(ctx));
        CHECK(zyntra_context_dirty_rect(ctx, &dirty));
        assert(dirty.w == 0.0f && dirty.h == 0.0f);

        ZyntraRenderStats stats = {0, 0, 0, 0};
        CHECK(zyntra_framebuffer_render(fb, ctx, &stats));
        assert(stats.submitted == 4 && stats.drawn == 4 && stats.culled == 0);
        stats_sub = stats.submitted;
        stats_drawn = stats.drawn;
        stats_culled = stats.culled;

        CHECK(zyntra_framebuffer_pixel(fb, 12, 12, &px));
        assert(px.r == fred.r && px.g == fred.g);
        CHECK(zyntra_framebuffer_pixel(fb, 2, 2, &px));
        assert(px.r == bg.r);
        CHECK(zyntra_framebuffer_pixel(fb, 33, 10, &px));
        grad_left = (int)px.r;
        CHECK(zyntra_framebuffer_pixel(fb, 55, 10, &px));
        grad_right = (int)px.r;
        assert(grad_left > 200 && grad_right < 60);
        CHECK(zyntra_framebuffer_pixel(fb, 14, 25, &px));
        round_in = (int)px.g;
        assert(round_in == fgreen.g);
        CHECK(zyntra_framebuffer_pixel(fb, 4, 20, &px));
        round_out = (int)px.r;
        assert(round_out == bg.r); /* fora do raio: fundo, não a forma */

        assert(zyntra_framebuffer_pixel(fb, 64, 0, &px) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_framebuffer_pixel(fb, 0, 32, &px) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_framebuffer_pixel(fb, 0, 0, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_framebuffer_pixel(NULL, 0, 0, &px) == ZYNTRA_INVALID_ARGUMENT);
        CHECK(zyntra_context_end_frame(ctx));

        /* Frame 4: repintura parcial dirigida pelo dirty rect. */
        ZyntraRect patch = {40, 20, 14, 10};
        ZyntraRect patch_box = {40, 20, 12, 8};
        CHECK(zyntra_context_begin_frame(ctx));
        CHECK(zyntra_draw_clear(ctx, bg));
        CHECK(zyntra_draw_rect_filled(ctx, patch_box, fblue));
        CHECK(zyntra_context_mark_dirty(ctx, patch));
        ZyntraRenderStats part = {0, 0, 0, 0};
        CHECK(zyntra_framebuffer_render_region(fb, ctx, patch, &part));
        assert(part.submitted == 2 && part.drawn == 2 && part.culled == 0);

        CHECK(zyntra_framebuffer_pixel(fb, 45, 24, &px));
        assert(px.b == fblue.b);
        part_px = (int)px.b;
        CHECK(zyntra_framebuffer_pixel(fb, 53, 29, &px)); /* região, fora do rect */
        assert(px.r == bg.r);
        CHECK(zyntra_framebuffer_pixel(fb, 12, 12, &px)); /* fora da região */
        assert(px.r == fred.r);
        kept_px = (int)px.r;
        CHECK(zyntra_context_end_frame(ctx));
    }

    /* Frames 5-8: widgets (M107) — estilos do tema escuro, primeiro lote
     * desenhado pelo mesmo rasterizador, e a interação (clique da caixa,
     * alternância do checkbox) reportada de volta ao C. */
    ZyntraFramebuffer *wfb = NULL;
    int w_clicked = 0, w_hovered = 0, w_toggled = 0, w_checked = 0;
    int w_chk_px = 0, w_slide_px = 0, w_sep_px = 0, w_prog_px = 0;
    float w_slider_value = 0;
    size_t w_draws = 0;
    unsigned long long w_id = 0, w_child = 0;
    {
        _Static_assert(sizeof(ZyntraId) == 8, "ZyntraId ABI");
        _Static_assert(sizeof(ZyntraThemeColors) == 20, "ZyntraThemeColors ABI");
        _Static_assert(sizeof(ZyntraTextMetrics) == 16, "ZyntraTextMetrics ABI");
        _Static_assert(sizeof(ZyntraButtonStyle) == 24, "ZyntraButtonStyle ABI");
        _Static_assert(sizeof(ZyntraCheckboxStyle) == 24, "ZyntraCheckboxStyle ABI");
        _Static_assert(sizeof(ZyntraSwitchStyle) == 28, "ZyntraSwitchStyle ABI");
        _Static_assert(sizeof(ZyntraSliderStyle) == 32, "ZyntraSliderStyle ABI");
        _Static_assert(sizeof(ZyntraProgressStyle) == 16, "ZyntraProgressStyle ABI");
        _Static_assert(sizeof(ZyntraSeparatorStyle) == 12, "ZyntraSeparatorStyle ABI");
        _Static_assert(sizeof(ZyntraLabelResult) == 20, "ZyntraLabelResult ABI");
        _Static_assert(sizeof(ZyntraButtonResult) == 3, "ZyntraButtonResult ABI");
        _Static_assert(sizeof(ZyntraCheckboxResult) == 3, "ZyntraCheckboxResult ABI");
        _Static_assert(sizeof(ZyntraSwitchResult) == 4, "ZyntraSwitchResult ABI");
        _Static_assert(sizeof(ZyntraSliderResult) == 8, "ZyntraSliderResult ABI");

        /* Ids: mesmo texto ⇒ mesmo id; filho difere do pai; vazio/NULL
         * dão o id nulo. */
        w_id = (unsigned long long)zyntra_id_from_string("c:btn", 5);
        assert(w_id != 0);
        assert(zyntra_id_from_string("c:btn", 5) == w_id);
        assert(zyntra_id_from_string("", 0) == 0);
        assert(zyntra_id_from_string(NULL, 2) == 0);
        w_child = (unsigned long long)zyntra_id_child(w_id, 2);
        assert(w_child != w_id && zyntra_id_child(w_id, 3) != w_child);
        assert(zyntra_id_child(0, 1) == 0); /* filho de nulo é nulo */

        /* Tema embutido: cores base e estilos por widget. */
        ZyntraThemeColors tc = {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}};
        ZyntraThemeColors tl = tc;
        ZyntraButtonStyle bs;
        ZyntraCheckboxStyle cs;
        ZyntraSwitchStyle ss;
        ZyntraSliderStyle sls;
        ZyntraProgressStyle ps;
        ZyntraSeparatorStyle se;
        CHECK(zyntra_theme_colors(ZYNTRA_THEME_DARK, &tc));
        CHECK(zyntra_theme_colors(ZYNTRA_THEME_LIGHT, &tl));
        assert(tc.bg.r < tl.bg.r && tc.text.r > tl.text.r && tc.text.a == 255);
        CHECK(zyntra_style_button(ZYNTRA_THEME_DARK, &bs));
        CHECK(zyntra_style_checkbox(ZYNTRA_THEME_DARK, &cs));
        CHECK(zyntra_style_switch(ZYNTRA_THEME_DARK, &ss));
        CHECK(zyntra_style_slider(ZYNTRA_THEME_DARK, &sls));
        CHECK(zyntra_style_progress(ZYNTRA_THEME_DARK, &ps));
        CHECK(zyntra_style_separator(ZYNTRA_THEME_DARK, &se));
        assert(zyntra_style_button(9, &bs) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_style_button(ZYNTRA_THEME_DARK, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_theme_colors(ZYNTRA_THEME_DARK, NULL) == ZYNTRA_INVALID_ARGUMENT);
        se.thickness = 2.0f; /* linha em duas linhas de pixel: leitura exata */

        CHECK(zyntra_framebuffer_create(96, 80, &wfb));
        CHECK(zyntra_context_set_viewport(ctx, (ZyntraRect){0, 0, 96, 80}));

        ZyntraRect lbl = {4, 2, 40, 10};
        ZyntraRect wbtn = {4, 16, 40, 16};
        ZyntraRect wsep = {4, 34, 88, 2};
        ZyntraRect wchk = {4, 38, 18, 18};
        ZyntraRect wsw = {28, 38, 36, 18};
        ZyntraRect wsl = {4, 60, 88, 12};
        ZyntraRect wprog = {4, 74, 88, 4};
        bool checked = false, switched = true;
        float value = 30.0f;
        ZyntraLabelResult lres;
        ZyntraButtonResult bres;
        ZyntraCheckboxResult cres;
        ZyntraSwitchResult sres;
        ZyntraSliderResult slres;
        ZyntraColor wpx = {0, 0, 0, 0};

        /* Frame 5: um de cada widget, sem mouse sobre eles, rasterizado. */
        CHECK(zyntra_context_begin_frame(ctx));
        CHECK(zyntra_context_push_mouse_move(ctx, (ZyntraVec2){90, 4}));
        CHECK(zyntra_draw_clear(ctx, tc.bg));
        CHECK(zyntra_widget_label(ctx, w_id, lbl, tc.text, 10.0f, "Ok", 2, false, &lres));
        assert(lres.metrics.width > 0.0f && lres.metrics.lines == 1 && !lres.truncated);
        CHECK(zyntra_widget_button(ctx, w_id, wbtn, &bs, &bres));
        assert(!bres.hovered && !bres.pressed && !bres.clicked);
        CHECK(zyntra_widget_checkbox(ctx, zyntra_id_child(w_id, 1), wchk, &checked, &cs, &cres));
        assert(!cres.checked && !cres.toggled && !checked);
        CHECK(zyntra_widget_switch(ctx, zyntra_id_child(w_id, 2), wsw, &switched, &ss, &sres));
        assert(sres.checked && !sres.toggled);
        CHECK(zyntra_widget_slider(ctx, zyntra_id_child(w_id, 3), wsl, &value, 0.0f, 100.0f, &sls, &slres));
        assert(slres.value == 30.0f && !slres.changed && !slres.dragging);
        CHECK(zyntra_widget_progress(ctx, wprog, 0.5f, &ps));
        CHECK(zyntra_widget_separator(ctx, wsep, ZYNTRA_HORIZONTAL, &se));

        /* Inválidos: id nulo, estilo/estado nulo, enum fora da faixa. */
        assert(zyntra_widget_button(ctx, 0, wbtn, &bs, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_button(ctx, w_id, wbtn, NULL, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_checkbox(ctx, w_id, wchk, NULL, &cs, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_switch(ctx, w_id, wsw, NULL, &ss, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_slider(ctx, w_id, wsl, NULL, 0.0f, 1.0f, &sls, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_label(ctx, w_id, wbtn, tc.text, 0.0f, "x", 1, false, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_label(ctx, w_id, wbtn, tc.text, 10.0f, NULL, 3, false, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_label(ctx, w_id, wbtn, tc.text, 10.0f, "\xff", 1, false, NULL) == ZYNTRA_INVALID_TEXT);
        assert(zyntra_widget_label(ctx, w_id, wbtn, tc.text, 10.0f, NULL, 0, false, NULL) == ZYNTRA_OK);
        assert(zyntra_widget_separator(ctx, wsep, 7, &se) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_progress(NULL, wprog, 0.5f, &ps) == ZYNTRA_INVALID_ARGUMENT);

        CHECK(zyntra_framebuffer_render(wfb, ctx, NULL));
        CHECK(zyntra_framebuffer_pixel(wfb, 24, 24, &wpx)); /* dentro do botão */
        assert(wpx.r == bs.bg.r && wpx.g == bs.bg.g && wpx.b == bs.bg.b);
        CHECK(zyntra_framebuffer_pixel(wfb, 6, 47, &wpx)); /* caixa vazia */
        assert(wpx.r == cs.bg.r && wpx.g == cs.bg.g);
        CHECK(zyntra_framebuffer_pixel(wfb, 34, 47, &wpx)); /* trilho ligado */
        assert(wpx.r == ss.track_on.r && wpx.g == ss.track_on.g);
        CHECK(zyntra_framebuffer_pixel(wfb, 12, 66, &wpx)); /* slider: preenchido */
        w_slide_px = (wpx.r == sls.fill.r && wpx.g == sls.fill.g);
        assert(w_slide_px);
        CHECK(zyntra_framebuffer_pixel(wfb, 80, 66, &wpx)); /* trilho vazio */
        assert(wpx.r == sls.track_bg.r);
        CHECK(zyntra_framebuffer_pixel(wfb, 20, 76, &wpx)); /* progresso: metade */
        w_prog_px = (wpx.r == ps.fill.r);
        assert(w_prog_px);
        CHECK(zyntra_framebuffer_pixel(wfb, 80, 76, &wpx));
        assert(wpx.r == ps.bg.r);
        CHECK(zyntra_framebuffer_pixel(wfb, 50, 34, &wpx)); /* separador */
        w_sep_px = (wpx.r == se.color.r);
        assert(w_sep_px);
        CHECK(zyntra_draw_count(ctx, &w_draws));
        assert(w_draws >= 9); /* rótulo, botão, checkbox, switch, slider, ... */
        CHECK(zyntra_context_end_frame(ctx));

        /* Frame 6: press no botão ⇒ hovered + pressed, sem clique ainda. */
        CHECK(zyntra_context_begin_frame(ctx));
        CHECK(zyntra_context_push_mouse_move(ctx, (ZyntraVec2){24, 24}));
        CHECK(zyntra_context_push_mouse_button(ctx, 0, true, (ZyntraVec2){24, 24}));
        CHECK(zyntra_widget_button(ctx, w_id, wbtn, &bs, &bres));
        assert(bres.hovered && bres.pressed && !bres.clicked);
        CHECK(zyntra_context_end_frame(ctx));

        /* Frame 7: release no botão ⇒ clique. */
        CHECK(zyntra_context_begin_frame(ctx));
        CHECK(zyntra_context_push_mouse_move(ctx, (ZyntraVec2){24, 24}));
        CHECK(zyntra_context_push_mouse_button(ctx, 0, false, (ZyntraVec2){24, 24}));
        CHECK(zyntra_widget_button(ctx, w_id, wbtn, &bs, &bres));
        assert(bres.clicked && bres.hovered);
        w_clicked = bres.clicked;
        w_hovered = bres.hovered;
        CHECK(zyntra_context_end_frame(ctx));

        /* Frame 8: press no checkbox ⇒ captura, sem alternar ainda. */
        CHECK(zyntra_context_begin_frame(ctx));
        CHECK(zyntra_context_push_mouse_move(ctx, (ZyntraVec2){13, 47}));
        CHECK(zyntra_context_push_mouse_button(ctx, 0, true, (ZyntraVec2){13, 47}));
        CHECK(zyntra_widget_checkbox(ctx, zyntra_id_child(w_id, 1), wchk, &checked, &cs, &cres));
        assert(!checked && !cres.toggled && cres.hovered);
        CHECK(zyntra_context_end_frame(ctx));

        /* Frame 9: release no checkbox ⇒ alterna; rasteriza marcada. */
        CHECK(zyntra_context_begin_frame(ctx));
        CHECK(zyntra_context_push_mouse_move(ctx, (ZyntraVec2){13, 47}));
        CHECK(zyntra_context_push_mouse_button(ctx, 0, false, (ZyntraVec2){13, 47}));
        CHECK(zyntra_draw_clear(ctx, tc.bg));
        CHECK(zyntra_widget_checkbox(ctx, zyntra_id_child(w_id, 1), wchk, &checked, &cs, &cres));
        assert(checked && cres.toggled && cres.checked);
        w_toggled = cres.toggled;
        w_checked = checked;
        CHECK(zyntra_framebuffer_render(wfb, ctx, NULL));
        CHECK(zyntra_framebuffer_pixel(wfb, 6, 47, &wpx)); /* agora bg_checked */
        w_chk_px = (wpx.r == cs.bg_checked.r && wpx.g == cs.bg_checked.g);
        assert(w_chk_px);
        CHECK(zyntra_context_end_frame(ctx));

        w_slider_value = value;
        zyntra_framebuffer_destroy(wfb);
        CHECK(zyntra_context_set_viewport(ctx, (ZyntraRect){0, 0, 64, 32}));
    }

    /* Frames 10-14: listas de rótulos e painel (M108) — abas, grupo de
     * radio, lista e painel desenhados pelo rasterizador de referência, com
     * clique real (aba/linha/opção/chevron) e checagem de pixel. */
    ZyntraFramebuffer *lfb = NULL;
    size_t l_active = 0, l_sel = 0, l_radio = 0, l_draws = 0;
    int l_tab_px = 0, l_list_px = 0, l_radio_px = 0, l_panel_px = 0;
    int l_collapsed = 0, l_toggled = 0;
    {
        _Static_assert(sizeof(ZyntraStr) == 2 * sizeof(size_t), "ZyntraStr ABI");
        _Static_assert(sizeof(ZyntraPanelOptions) == 24, "ZyntraPanelOptions ABI");
        _Static_assert(sizeof(ZyntraRadioStyle) == 20, "ZyntraRadioStyle ABI");
        _Static_assert(sizeof(ZyntraTabBarStyle) == 36, "ZyntraTabBarStyle ABI");
        _Static_assert(sizeof(ZyntraListViewStyle) == 36, "ZyntraListViewStyle ABI");
        _Static_assert(sizeof(ZyntraPanelStyle) == 48, "ZyntraPanelStyle ABI");
        _Static_assert(sizeof(ZyntraRadioResult) == 3, "ZyntraRadioResult ABI");
        _Static_assert(sizeof(ZyntraTabBarResult) == 24, "ZyntraTabBarResult ABI");
        _Static_assert(sizeof(ZyntraListViewResult) == 24, "ZyntraListViewResult ABI");
        _Static_assert(sizeof(ZyntraPanelResult) == 20, "ZyntraPanelResult ABI");

        ZyntraRadioStyle rs;
        ZyntraTabBarStyle tbs;
        ZyntraListViewStyle lvs;
        ZyntraPanelStyle pans;
        CHECK(zyntra_style_radio(ZYNTRA_THEME_DARK, &rs));
        CHECK(zyntra_style_tab_bar(ZYNTRA_THEME_DARK, &tbs));
        CHECK(zyntra_style_list_view(ZYNTRA_THEME_DARK, &lvs));
        CHECK(zyntra_style_panel(ZYNTRA_THEME_DARK, &pans));
        assert(zyntra_style_radio(9, &rs) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_style_list_view(ZYNTRA_THEME_DARK, NULL) == ZYNTRA_INVALID_ARGUMENT);
        lvs.item_height = 20.0f; /* linhas previsíveis para os pixels */

        const ZyntraStr tabs[2] = {{"A", 1}, {"BB", 2}};
        const ZyntraStr items[3] = {{"um", 2}, {"dois", 4}, {"tres", 4}};
        const ZyntraStr opts[3] = {{"r0", 2}, {"r1", 2}, {"r2", 2}};
        const ZyntraId lid = zyntra_id_from_string("c:lists", 7);
        assert(lid != 0);

        ZyntraRect tab_bounds = {4, 4, 232, 24};
        ZyntraRect radio_bounds = {4, 34, 120, 60};
        ZyntraRect list_bounds = {4, 112, 120, 80};
        ZyntraRect panel_bounds = {140, 34, 96, 150};
        ZyntraPanelOptions popts = {{"P", 1}, true, false};
        ZyntraTabBarResult tbr;
        ZyntraListViewResult lvr;
        ZyntraRadioResult rar;
        ZyntraPanelResult panr;
        ZyntraColor lpx = {0, 0, 0, 0};
        ZyntraColor lbg = {24, 24, 28, 255};
        size_t active = 0, selected = 0, radio_sel = 0;
        float scroll = 0.0f;
        bool collapsed = false;

        CHECK(zyntra_framebuffer_create(240, 200, &lfb));
        CHECK(zyntra_context_set_viewport(ctx, (ZyntraRect){0, 0, 240, 200}));

        /* Frame 10: tudo frio, rasterizado; linha 0 marcada/selecionada. */
        CHECK(zyntra_context_begin_frame(ctx));
        CHECK(zyntra_context_push_mouse_move(ctx, (ZyntraVec2){236, 196}));
        CHECK(zyntra_draw_clear(ctx, lbg));
        CHECK(zyntra_widget_tab_bar(ctx, lid, tab_bounds, tabs, 2, &active, &tbs, &tbr));
        assert(!tbr.changed && tbr.active == 0 && tbr.hovered_index == -1);
        CHECK(zyntra_widget_radio(ctx, lid, radio_bounds, opts, 3, &radio_sel, 16.0f, &rs, &rar));
        assert(!rar.changed && !rar.hovered && radio_sel == 0);
        CHECK(zyntra_widget_list_view(ctx, lid, list_bounds, items, 3, &selected, &scroll, &lvs, &lvr));
        assert(lvr.selected == 0 && lvr.hovered_index == -1 && lvr.scroll_offset == 0.0f);
        CHECK(zyntra_widget_panel(ctx, lid, panel_bounds, &collapsed, popts, 16.0f, &pans, &panr));
        assert(!panr.collapsed && !panr.toggled && !panr.close_requested && panr.content.w > 0.0f);

        /* Inválidos: lista nula com len, ptr nulo com len, estado nulo. */
        assert(zyntra_widget_tab_bar(ctx, lid, tab_bounds, NULL, 2, &active, &tbs, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_list_view(ctx, lid, list_bounds, NULL, 1, &selected, &scroll, &lvs, NULL) == ZYNTRA_INVALID_ARGUMENT);
        {
            const ZyntraStr broken[1] = {{NULL, 3}};
            assert(zyntra_widget_radio(ctx, lid, radio_bounds, broken, 1, &radio_sel, 16.0f, &rs, NULL) == ZYNTRA_INVALID_ARGUMENT);
        }
        assert(zyntra_widget_radio(ctx, lid, radio_bounds, opts, 3, NULL, 16.0f, &rs, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_radio(ctx, lid, radio_bounds, opts, 3, &radio_sel, 0.0f, &rs, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_list_view(ctx, lid, list_bounds, items, 3, &selected, NULL, &lvs, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_tab_bar(ctx, lid, tab_bounds, tabs, 2, &active, NULL, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_panel(ctx, lid, panel_bounds, NULL, popts, 16.0f, &pans, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_panel(ctx, lid, panel_bounds, &collapsed, popts, 0.0f, &pans, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_radio(NULL, lid, radio_bounds, opts, 3, &radio_sel, 16.0f, &rs, NULL) == ZYNTRA_INVALID_ARGUMENT);

        CHECK(zyntra_draw_count(ctx, &l_draws));
        assert(l_draws >= 20);
        CHECK(zyntra_framebuffer_render(lfb, ctx, NULL));
        CHECK(zyntra_framebuffer_pixel(lfb, 19, 16, &lpx)); /* aba ativa */
        l_tab_px = (lpx.r == tbs.bg_active.r && lpx.g == tbs.bg_active.g);
        assert(l_tab_px);
        CHECK(zyntra_framebuffer_pixel(lfb, 52, 16, &lpx));
        assert(lpx.r == tbs.bg.r);
        CHECK(zyntra_framebuffer_pixel(lfb, 15, 46, &lpx)); /* radio marcado */
        l_radio_px = (lpx.r == rs.dot.r && lpx.g == rs.dot.g);
        assert(l_radio_px);
        CHECK(zyntra_framebuffer_pixel(lfb, 15, 71, &lpx));
        assert(lpx.r == rs.box.r);
        CHECK(zyntra_framebuffer_pixel(lfb, 20, 122, &lpx)); /* linha selecionada */
        l_list_px = (lpx.r == lvs.bg_selected.r && lpx.g == lvs.bg_selected.g);
        assert(l_list_px);
        CHECK(zyntra_framebuffer_pixel(lfb, 20, 142, &lpx));
        assert(lpx.r == lvs.bg.r);
        CHECK(zyntra_framebuffer_pixel(lfb, 145, 40, &lpx)); /* cabeçalho */
        l_panel_px = (lpx.r == pans.header_bg.r);
        assert(l_panel_px);
        CHECK(zyntra_framebuffer_pixel(lfb, 150, 120, &lpx)); /* corpo */
        assert(lpx.r == pans.bg.r);
        CHECK(zyntra_context_end_frame(ctx));

        /* Frame 11: clique na aba 1 (x 34..70) troca a aba ativa. */
        CHECK(zyntra_context_begin_frame(ctx));
        CHECK(zyntra_draw_clear(ctx, lbg));
        CHECK(zyntra_context_push_mouse_move(ctx, (ZyntraVec2){52, 16}));
        CHECK(zyntra_context_push_mouse_button(ctx, 0, true, (ZyntraVec2){52, 16}));
        CHECK(zyntra_widget_tab_bar(ctx, lid, tab_bounds, tabs, 2, &active, &tbs, &tbr));
        assert(tbr.changed && tbr.active == 1 && active == 1);
        l_active = active;
        CHECK(zyntra_framebuffer_render(lfb, ctx, NULL));
        CHECK(zyntra_framebuffer_pixel(lfb, 52, 16, &lpx));
        assert(lpx.r == tbs.bg_active.r); /* era inativa, agora ativa */
        CHECK(zyntra_framebuffer_pixel(lfb, 19, 16, &lpx));
        assert(lpx.r == tbs.bg.r);
        CHECK(zyntra_context_end_frame(ctx));

        /* Frame 12: clique na linha 2 da lista (y 152..172). */
        CHECK(zyntra_context_begin_frame(ctx));
        CHECK(zyntra_draw_clear(ctx, lbg));
        CHECK(zyntra_context_push_mouse_move(ctx, (ZyntraVec2){20, 162}));
        CHECK(zyntra_context_push_mouse_button(ctx, 0, true, (ZyntraVec2){20, 162}));
        CHECK(zyntra_widget_list_view(ctx, lid, list_bounds, items, 3, &selected, &scroll, &lvs, &lvr));
        assert(lvr.changed && lvr.selected == 2 && selected == 2);
        l_sel = selected;
        CHECK(zyntra_framebuffer_render(lfb, ctx, NULL));
        CHECK(zyntra_framebuffer_pixel(lfb, 20, 162, &lpx));
        assert(lpx.r == lvs.bg_selected.r);
        CHECK(zyntra_framebuffer_pixel(lfb, 20, 122, &lpx));
        assert(lpx.r == lvs.bg.r);
        CHECK(zyntra_context_end_frame(ctx));

        /* Frame 13: press na opção 1 do radio (linha y 59..84). */
        CHECK(zyntra_context_begin_frame(ctx));
        CHECK(zyntra_draw_clear(ctx, lbg));
        CHECK(zyntra_context_push_mouse_move(ctx, (ZyntraVec2){15, 71}));
        CHECK(zyntra_context_push_mouse_button(ctx, 0, true, (ZyntraVec2){15, 71}));
        CHECK(zyntra_widget_radio(ctx, lid, radio_bounds, opts, 3, &radio_sel, 16.0f, &rs, &rar));
        assert(rar.changed && radio_sel == 1);
        l_radio = radio_sel;
        CHECK(zyntra_framebuffer_render(lfb, ctx, NULL));
        CHECK(zyntra_framebuffer_pixel(lfb, 15, 71, &lpx));
        assert(lpx.r == rs.dot.r); /* o ponto migrou para a linha 1 */
        CHECK(zyntra_framebuffer_pixel(lfb, 15, 46, &lpx));
        assert(lpx.r == rs.box.r);
        CHECK(zyntra_context_end_frame(ctx));

        /* Frame 14: clique no chevron (canto superior direito) colapsa. */
        CHECK(zyntra_context_begin_frame(ctx));
        CHECK(zyntra_draw_clear(ctx, lbg));
        CHECK(zyntra_context_push_mouse_move(ctx, (ZyntraVec2){219, 48}));
        CHECK(zyntra_context_push_mouse_button(ctx, 0, true, (ZyntraVec2){219, 48}));
        CHECK(zyntra_context_push_mouse_button(ctx, 0, false, (ZyntraVec2){219, 48}));
        CHECK(zyntra_widget_panel(ctx, lid, panel_bounds, &collapsed, popts, 16.0f, &pans, &panr));
        assert(panr.toggled && collapsed && panr.content.w == 0.0f);
        l_collapsed = collapsed;
        l_toggled = panr.toggled;
        CHECK(zyntra_framebuffer_render(lfb, ctx, NULL));
        CHECK(zyntra_framebuffer_pixel(lfb, 145, 40, &lpx));
        assert(lpx.r == pans.header_bg.r); /* cabeçalho fica */
        CHECK(zyntra_framebuffer_pixel(lfb, 150, 120, &lpx));
        assert(lpx.r == lbg.r); /* corpo sumiu: só o claro do frame */
        CHECK(zyntra_context_end_frame(ctx));

        zyntra_framebuffer_destroy(lfb);
        CHECK(zyntra_context_set_viewport(ctx, (ZyntraRect){0, 0, 64, 32}));
    }

    /* Frames 15-19: menu e tabela (M109) — estruturas planas na fronteira C,
     * com hover, escolha one-shot, seleção e checagem de pixel. */
    ZyntraFramebuffer *rfb = NULL;
    long long r_chosen = -1, r_menu_hover = -1;
    size_t r_table_sel = 0;
    int r_changed = 0, r_dismissed = 0;
    int r_px_menu = 0, r_px_hover = 0, r_px_sel = 0, r_px_alt = 0;
    {
        _Static_assert(sizeof(ZyntraMenuItem) == 40, "ZyntraMenuItem ABI");
        _Static_assert(sizeof(ZyntraTableColumn) == 24, "ZyntraTableColumn ABI");
        _Static_assert(sizeof(ZyntraTableRow) == 16, "ZyntraTableRow ABI");
        _Static_assert(sizeof(ZyntraMenuStyle) == 24, "ZyntraMenuStyle ABI");
        _Static_assert(sizeof(ZyntraTableStyle) == 48, "ZyntraTableStyle ABI");
        _Static_assert(sizeof(ZyntraMenuResult) == 24, "ZyntraMenuResult ABI");
        _Static_assert(sizeof(ZyntraTableResult) == 24, "ZyntraTableResult ABI");

        ZyntraMenuStyle ms;
        ZyntraTableStyle rts;
        CHECK(zyntra_style_menu(ZYNTRA_THEME_DARK, &ms));
        CHECK(zyntra_style_table(ZYNTRA_THEME_DARK, &rts));
        assert(zyntra_style_table(7, &rts) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_style_menu(ZYNTRA_THEME_DARK, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(rts.row_height == 24.0f && rts.header_height == 26.0f);

        /* size 16 ⇒ altura de item do menu = 17 + 8 = 25 px. */
        const ZyntraMenuItem mitems[4] = {
            {{"Abrir", 5}, {"", 0}, true, false, false, false},
            {{"", 0}, {"", 0}, true, true, false, false},
            {{"Salvar", 6}, {"Ctrl+S", 6}, true, false, true, true},
            {{"Sair", 4}, {"", 0}, false, false, false, false},
        };
        const ZyntraTableColumn cols[2] = {{{"Nome", 4}, 120.0f}, {{"Tipo", 4}, 100.0f}};
        const ZyntraStr cells0[2] = {{"um", 2}, {"tipo1", 5}};
        const ZyntraStr cells1[2] = {{"dois", 4}, {"tipo2", 5}};
        const ZyntraStr cells2[2] = {{"tres", 4}, {"tipo3", 5}};
        const ZyntraTableRow trows[3] = {{cells0, 2}, {cells1, 2}, {cells2, 2}};
        const ZyntraId rid = zyntra_id_from_string("c:rich", 6);
        assert(rid != 0);

        ZyntraRect menu_bounds = {8, 8, 160, 104};
        ZyntraRect table_bounds = {8, 120, 220, 72};
        ZyntraMenuResult mr;
        ZyntraTableResult tr;
        ZyntraColor rpx = {0, 0, 0, 0};
        ZyntraColor rbg = {24, 24, 28, 255};
        size_t r_active = 0, r_selected = 0;
        float r_scroll = 0.0f;

        CHECK(zyntra_framebuffer_create(240, 200, &rfb));
        CHECK(zyntra_context_set_viewport(ctx, (ZyntraRect){0, 0, 240, 200}));

        /* Frame 15: frio — menu sem hover, tabela com linha 0 selecionada. */
        CHECK(zyntra_context_begin_frame(ctx));
        CHECK(zyntra_context_push_mouse_move(ctx, (ZyntraVec2){236, 196}));
        CHECK(zyntra_draw_clear(ctx, rbg));
        CHECK(zyntra_widget_menu(ctx, rid, menu_bounds, mitems, 4, &r_active, 16.0f, &ms, &mr));
        assert(mr.chosen == -1 && mr.hovered_index == -1 && !mr.hovered && !mr.dismissed);
        CHECK(zyntra_widget_table(ctx, rid, table_bounds, cols, 2, trows, 3, &r_selected, &r_scroll, &rts, &tr));
        assert(tr.selected == 0 && tr.hovered_index == -1 && !tr.changed);
        CHECK(zyntra_framebuffer_render(rfb, ctx, NULL));
        CHECK(zyntra_framebuffer_pixel(rfb, 50, 20, &rpx)); /* linha 0 sem hover */
        r_px_menu = (rpx.r == ms.bg.r && rpx.b == ms.bg.b);
        assert(r_px_menu);
        CHECK(zyntra_framebuffer_pixel(rfb, 20, 130, &rpx)); /* cabeçalho */
        assert(rpx.r == rts.bg.r);
        CHECK(zyntra_framebuffer_pixel(rfb, 20, 158, &rpx)); /* linha 0 selecionada */
        r_px_sel = (rpx.r == rts.bg_selected.r && rpx.b == rts.bg_selected.b);
        assert(r_px_sel);
        CHECK(zyntra_framebuffer_pixel(rfb, 20, 182, &rpx)); /* linha 1 alternada */
        r_px_alt = (rpx.r == rts.bg_alt.r);
        assert(r_px_alt);
        CHECK(zyntra_context_end_frame(ctx));

        /* Frame 16: hover na linha 2 do menu (y 58..83) realça a linha. */
        CHECK(zyntra_context_begin_frame(ctx));
        CHECK(zyntra_draw_clear(ctx, rbg));
        CHECK(zyntra_context_push_mouse_move(ctx, (ZyntraVec2){50, 70}));
        CHECK(zyntra_widget_menu(ctx, rid, menu_bounds, mitems, 4, &r_active, 16.0f, &ms, &mr));
        assert(mr.hovered && mr.hovered_index == 2 && r_active == 2);
        r_menu_hover = (long long)mr.hovered_index;
        CHECK(zyntra_framebuffer_render(rfb, ctx, NULL));
        CHECK(zyntra_framebuffer_pixel(rfb, 50, 70, &rpx));
        r_px_hover = (rpx.r == ms.item_hover.r && rpx.b == ms.item_hover.b);
        assert(r_px_hover);
        CHECK(zyntra_framebuffer_pixel(rfb, 50, 20, &rpx));
        assert(rpx.r == ms.bg.r);
        CHECK(zyntra_context_end_frame(ctx));

        /* Frame 17: press na linha 2 escolhe (one-shot). */
        CHECK(zyntra_context_begin_frame(ctx));
        CHECK(zyntra_context_push_mouse_button(ctx, 0, true, (ZyntraVec2){50, 70}));
        CHECK(zyntra_widget_menu(ctx, rid, menu_bounds, mitems, 4, &r_active, 16.0f, &ms, &mr));
        assert(mr.chosen == 2 && !mr.dismissed);
        r_chosen = (long long)mr.chosen;
        CHECK(zyntra_context_end_frame(ctx));

        /* Frame 18: press fora dispensa. */
        CHECK(zyntra_context_begin_frame(ctx));
        CHECK(zyntra_context_push_mouse_button(ctx, 0, true, (ZyntraVec2){236, 196}));
        CHECK(zyntra_widget_menu(ctx, rid, menu_bounds, mitems, 4, &r_active, 16.0f, &ms, &mr));
        assert(mr.chosen == -1 && mr.dismissed);
        r_dismissed = mr.dismissed;
        CHECK(zyntra_context_end_frame(ctx));

        /* Frame 19: clique na linha 1 da tabela (y 170..194). */
        CHECK(zyntra_context_begin_frame(ctx));
        CHECK(zyntra_draw_clear(ctx, rbg));
        CHECK(zyntra_context_push_mouse_move(ctx, (ZyntraVec2){20, 182}));
        CHECK(zyntra_context_push_mouse_button(ctx, 0, true, (ZyntraVec2){20, 182}));
        CHECK(zyntra_widget_table(ctx, rid, table_bounds, cols, 2, trows, 3, &r_selected, &r_scroll, &rts, &tr));
        assert(tr.changed && tr.selected == 1 && r_selected == 1);
        r_table_sel = r_selected;
        r_changed = tr.changed;
        CHECK(zyntra_framebuffer_render(rfb, ctx, NULL));
        CHECK(zyntra_framebuffer_pixel(rfb, 20, 182, &rpx));
        assert(rpx.r == rts.bg_selected.r);
        CHECK(zyntra_framebuffer_pixel(rfb, 20, 158, &rpx));
        assert(rpx.r == rts.bg.r);
        CHECK(zyntra_context_end_frame(ctx));

        /* Inválidos: vetores nulos, célula sem ponteiro, estados nulos. */
        assert(zyntra_widget_menu(ctx, rid, menu_bounds, NULL, 3, &r_active, 16.0f, &ms, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_menu(ctx, rid, menu_bounds, mitems, 4, &r_active, 0.0f, &ms, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_menu(ctx, rid, menu_bounds, mitems, 4, NULL, 16.0f, &ms, NULL) == ZYNTRA_INVALID_ARGUMENT);
        {
            const ZyntraMenuItem broken[1] = {{{NULL, 3}, {"", 0}, true, false, false, false}};
            assert(zyntra_widget_menu(ctx, rid, menu_bounds, broken, 1, &r_active, 16.0f, &ms, NULL) == ZYNTRA_INVALID_ARGUMENT);
        }
        assert(zyntra_widget_table(ctx, rid, table_bounds, cols, 0, trows, 3, &r_selected, &r_scroll, &rts, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_table(ctx, rid, table_bounds, NULL, 2, trows, 3, &r_selected, &r_scroll, &rts, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_table(ctx, rid, table_bounds, cols, 2, NULL, 1, &r_selected, &r_scroll, &rts, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_table(ctx, rid, table_bounds, cols, 2, trows, 3, NULL, &r_scroll, &rts, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_table(ctx, rid, table_bounds, cols, 2, trows, 3, &r_selected, NULL, &rts, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_table(ctx, rid, (ZyntraRect){8, 120, 220, 20}, cols, 2, trows, 3, &r_selected, &r_scroll, &rts, NULL) == ZYNTRA_INVALID_ARGUMENT);
        {
            const ZyntraTableRow broken[1] = {{NULL, 2}};
            assert(zyntra_widget_table(ctx, rid, table_bounds, cols, 2, broken, 1, &r_selected, &r_scroll, &rts, NULL) == ZYNTRA_INVALID_ARGUMENT);
        }
        assert(zyntra_widget_menu(NULL, rid, menu_bounds, mitems, 4, &r_active, 16.0f, &ms, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_table(NULL, rid, table_bounds, cols, 2, trows, 3, &r_selected, &r_scroll, &rts, NULL) == ZYNTRA_INVALID_ARGUMENT);

        zyntra_framebuffer_destroy(rfb);
        CHECK(zyntra_context_set_viewport(ctx, (ZyntraRect){0, 0, 64, 32}));
    }

    /* Frames 20-23: tree_view (M110) — árvore recursiva na fronteira C, com
     * expansor clicável, `expanded` devolvido na árvore e checagem de pixel. */
    ZyntraFramebuffer *tfb = NULL;
    long long t_toggled = -1;
    size_t t_sel = 0;
    int t_changed = 0, t_expand_root = 0, t_expand_child = 0;
    int t_px_sel = 0, t_px_exp = 0, t_px_text = 0;
    {
        _Static_assert(sizeof(ZyntraTreeItem) == 40, "ZyntraTreeItem ABI");
        _Static_assert(sizeof(ZyntraTreeViewStyle) == 40, "ZyntraTreeViewStyle ABI");
        _Static_assert(sizeof(ZyntraTreeViewResult) == 32, "ZyntraTreeViewResult ABI");

        ZyntraTreeViewStyle tvs;
        CHECK(zyntra_style_tree_view(ZYNTRA_THEME_DARK, &tvs));
        assert(zyntra_style_tree_view(3, &tvs) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_style_tree_view(ZYNTRA_THEME_DARK, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(tvs.item_height == 24.0f && tvs.indent == 16.0f && tvs.expander_size == 12.0f);

        /* src > (ui > widget.zig, app.zig), build.zig */
        ZyntraTreeItem neto[1] = {{{"widget.zig", 10}, NULL, 0, false}};
        ZyntraTreeItem filhos[2] = {
            {{"ui", 2}, neto, 1, false},
            {{"app.zig", 7}, NULL, 0, false},
        };
        ZyntraTreeItem raizes[2] = {
            {{"src", 3}, filhos, 2, false},
            {{"build.zig", 9}, NULL, 0, false},
        };
        const ZyntraId tid = zyntra_id_from_string("c:tree", 6);
        assert(tid != 0);

        ZyntraRect tree_bounds = {8, 8, 200, 128};
        ZyntraTreeViewResult tvr;
        ZyntraColor tpx = {0, 0, 0, 0};
        ZyntraColor tbg = {24, 24, 28, 255};
        size_t t_sel_local = 0;
        float t_scroll = 0.0f;

        CHECK(zyntra_framebuffer_create(240, 200, &tfb));
        CHECK(zyntra_context_set_viewport(ctx, (ZyntraRect){0, 0, 240, 200}));

        /* Frame 20: frio — só as duas raízes visíveis. */
        CHECK(zyntra_context_begin_frame(ctx));
        CHECK(zyntra_context_push_mouse_move(ctx, (ZyntraVec2){236, 196}));
        CHECK(zyntra_draw_clear(ctx, tbg));
        CHECK(zyntra_widget_tree_view(ctx, tid, tree_bounds, raizes, 2, &t_sel_local, &t_scroll, &tvs, &tvr));
        assert(tvr.selected == 0 && tvr.toggled_index == -1 && !tvr.changed);
        assert(!raizes[0].expanded && !filhos[0].expanded);
        CHECK(zyntra_framebuffer_render(tfb, ctx, NULL));
        CHECK(zyntra_framebuffer_pixel(tfb, 100, 20, &tpx)); /* nó 0 selecionado */
        t_px_sel = (tpx.r == tvs.bg_selected.r && tpx.b == tvs.bg_selected.b);
        assert(t_px_sel);
        CHECK(zyntra_framebuffer_pixel(tfb, 12, 12, &tpx)); /* expansor do nó 0 */
        t_px_exp = (tpx.r == tvs.text_selected.r && tpx.g == tvs.text_selected.g);
        assert(t_px_exp);
        CHECK(zyntra_framebuffer_pixel(tfb, 100, 44, &tpx)); /* nó 1 sem expansor */
        assert(tpx.r == tvs.bg.r);
        CHECK(zyntra_framebuffer_pixel(tfb, 28, 32, &tpx)); /* sem nó em profundidade 1 */
        assert(tpx.r == tvs.bg.r);
        CHECK(zyntra_context_end_frame(ctx));

        /* Frame 21: clique no expansor do nó 0 — alterna e devolve `expanded`. */
        CHECK(zyntra_context_begin_frame(ctx));
        CHECK(zyntra_draw_clear(ctx, tbg));
        CHECK(zyntra_context_push_mouse_move(ctx, (ZyntraVec2){12, 12}));
        CHECK(zyntra_context_push_mouse_button(ctx, 0, true, (ZyntraVec2){12, 12}));
        CHECK(zyntra_widget_tree_view(ctx, tid, tree_bounds, raizes, 2, &t_sel_local, &t_scroll, &tvs, &tvr));
        assert(tvr.toggled_index == 0 && raizes[0].expanded && tvr.selected == 0);
        t_toggled = (long long)tvr.toggled_index;
        t_expand_root = raizes[0].expanded;
        CHECK(zyntra_framebuffer_render(tfb, ctx, NULL));
        CHECK(zyntra_framebuffer_pixel(tfb, 28, 32, &tpx)); /* expansor de "ui" (nó 1) */
        t_px_text = (tpx.r == tvs.text.r && tpx.g == tvs.text.g);
        assert(t_px_text);
        CHECK(zyntra_framebuffer_pixel(tfb, 100, 44, &tpx));
        assert(tpx.r == tvs.bg.r);
        CHECK(zyntra_context_end_frame(ctx));

        /* Frame 22: clique no expansor de "ui" — alterna o nível aninhado. */
        CHECK(zyntra_context_begin_frame(ctx));
        CHECK(zyntra_context_push_mouse_button(ctx, 0, true, (ZyntraVec2){28, 32}));
        CHECK(zyntra_widget_tree_view(ctx, tid, tree_bounds, raizes, 2, &t_sel_local, &t_scroll, &tvs, &tvr));
        assert(tvr.toggled_index == 1 && filhos[0].expanded && raizes[0].expanded);
        t_expand_child = filhos[0].expanded;
        CHECK(zyntra_context_end_frame(ctx));

        /* Frame 23: clique no nó 4 ("build.zig", sem expansor) seleciona. */
        CHECK(zyntra_context_begin_frame(ctx));
        CHECK(zyntra_context_push_mouse_button(ctx, 0, true, (ZyntraVec2){100, 116}));
        CHECK(zyntra_widget_tree_view(ctx, tid, tree_bounds, raizes, 2, &t_sel_local, &t_scroll, &tvs, &tvr));
        assert(tvr.changed && tvr.selected == 4 && t_sel_local == 4 && tvr.toggled_index == -1);
        t_changed = tvr.changed;
        t_sel = t_sel_local;
        CHECK(zyntra_context_end_frame(ctx));

        /* Inválidos: vetores nulos, rótulo/filhos sem ponteiro, estados nulos
         * e ciclo na árvore (cortado pela profundidade máxima). */
        assert(zyntra_widget_tree_view(ctx, tid, tree_bounds, raizes, 0, &t_sel_local, &t_scroll, &tvs, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_tree_view(ctx, tid, tree_bounds, NULL, 1, &t_sel_local, &t_scroll, &tvs, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_tree_view(ctx, tid, tree_bounds, raizes, 2, NULL, &t_scroll, &tvs, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_tree_view(ctx, tid, tree_bounds, raizes, 2, &t_sel_local, NULL, &tvs, NULL) == ZYNTRA_INVALID_ARGUMENT);
        assert(zyntra_widget_tree_view(ctx, tid, tree_bounds, raizes, 2, &t_sel_local, &t_scroll, NULL, NULL) == ZYNTRA_INVALID_ARGUMENT);
        {
            ZyntraTreeItem sem_rotulo[1] = {{{NULL, 3}, NULL, 0, false}};
            assert(zyntra_widget_tree_view(ctx, tid, tree_bounds, sem_rotulo, 1, &t_sel_local, &t_scroll, &tvs, NULL) == ZYNTRA_INVALID_ARGUMENT);
        }
        {
            ZyntraTreeItem sem_filhos[1] = {{{"x", 1}, NULL, 2, false}};
            assert(zyntra_widget_tree_view(ctx, tid, tree_bounds, sem_filhos, 1, &t_sel_local, &t_scroll, &tvs, NULL) == ZYNTRA_INVALID_ARGUMENT);
        }
        {
            ZyntraTreeItem ciclo[1];
            ciclo[0] = (ZyntraTreeItem){{"loop", 4}, ciclo, 1, false};
            assert(zyntra_widget_tree_view(ctx, tid, tree_bounds, ciclo, 1, &t_sel_local, &t_scroll, &tvs, NULL) == ZYNTRA_INVALID_ARGUMENT);
        }
        assert(zyntra_widget_tree_view(NULL, tid, tree_bounds, raizes, 2, &t_sel_local, &t_scroll, &tvs, NULL) == ZYNTRA_INVALID_ARGUMENT);

        zyntra_framebuffer_destroy(tfb);
        CHECK(zyntra_context_set_viewport(ctx, (ZyntraRect){0, 0, 64, 32}));
    }

    /* Nulos nunca crasham. */
    assert(zyntra_context_begin_frame(NULL) == ZYNTRA_INVALID_ARGUMENT);
    assert(zyntra_context_pending_events(ctx, NULL) == ZYNTRA_INVALID_ARGUMENT);
    assert(zyntra_framebuffer_render(NULL, ctx, NULL) == ZYNTRA_INVALID_ARGUMENT);
    assert(zyntra_framebuffer_render(fb, NULL, NULL) == ZYNTRA_INVALID_ARGUMENT);
    assert(zyntra_framebuffer_fill(NULL, (ZyntraColor){0, 0, 0, 255}) == ZYNTRA_INVALID_ARGUMENT);
    assert(zyntra_context_mark_dirty(NULL, (ZyntraRect){0, 0, 1, 1}) == ZYNTRA_INVALID_ARGUMENT);
    assert(zyntra_context_dirty_rect(ctx, NULL) == ZYNTRA_INVALID_ARGUMENT);
    zyntra_framebuffer_destroy(NULL); /* no-op */
    zyntra_context_destroy(NULL);

    zyntra_context_destroy(ctx);
    printf("C-ABI OK events=%zu draws=%zu frame=%llu\n",
        events, draws, (unsigned long long)idx);
    printf("C-ABI modern draws=%zu width=%.0f height=%.0f kept=%zu\n",
        modern, (double)mw, (double)mh, kept);
    printf("C-ABI pixels grad=%d/%d round=%d/%d part=%d kept=%d stats=%zu/%zu/%zu\n",
        grad_left, grad_right, round_in, round_out, part_px, kept_px,
        stats_sub, stats_drawn, stats_culled);
    printf("C-ABI widgets click=%d hover=%d toggle=%d checked=%d chk=%d slider=%.0f"
        " fill=%d sep=%d prog=%d id=%llu child=%llu\n",
        w_clicked, w_hovered, w_toggled, w_checked, w_chk_px, (double)w_slider_value,
        w_slide_px, w_sep_px, w_prog_px, w_id, w_child);
    printf("C-ABI lists tab=%zu list=%zu radio=%zu collapsed=%d toggled=%d"
        " px_tab=%d px_list=%d px_radio=%d px_panel=%d\n",
        l_active, l_sel, l_radio, l_collapsed, l_toggled,
        l_tab_px, l_list_px, l_radio_px, l_panel_px);
    printf("C-ABI rich chosen=%lld menu_hover=%lld table_sel=%zu changed=%d dismissed=%d"
        " px_menu=%d px_hover=%d px_sel=%d px_alt=%d\n",
        r_chosen, r_menu_hover, r_table_sel, r_changed, r_dismissed,
        r_px_menu, r_px_hover, r_px_sel, r_px_alt);
    printf("C-ABI tree toggled=%lld sel=%zu changed=%d expand_root=%d expand_child=%d"
        " px_sel=%d px_exp=%d px_text=%d\n",
        t_toggled, t_sel, t_changed, t_expand_root, t_expand_child,
        t_px_sel, t_px_exp, t_px_text);
    zyntra_framebuffer_destroy(fb);
    return 0;
}
