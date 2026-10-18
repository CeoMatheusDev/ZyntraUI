# ZyntraUI — Integração C (C-ABI)

Camada opcional em `src/c-abi/` (M5). A API Zig (`@import("zyntra_ui")`)
continua sendo a interface principal.

## Inicialização / destruição

```c
ZyntraContext *ctx = NULL;
ZyntraRect vp = {0, 0, 800, 600};
if (zyntra_context_create(vp, &ctx) != ZYNTRA_OK) { /* ... */ }
// ... um frame por vez: begin -> push/draw -> end ...
zyntra_context_destroy(ctx); // exatamente uma vez; NULL é seguro
```

## Handles

* `ZyntraContext*` é opaco: nunca desreferenciar, copiar o struct interno
  (não existe na fronteira) ou liberar com `free`.
* Um handle, uma thread por vez. Sem locks internos.

## Ownership e lifetime

* `create` aloca no `page_allocator` interno da camada C-ABI; `destroy`
  libera eventos + draws + o próprio handle.
* `begin_frame` invalida eventos/desenhos do frame anterior (retém
  capacidade). Contagens obtidas valem até o próximo `begin`/`destroy`.
* Nenhum slice/string Zig cruza a fronteira na M5 — só tipos de tamanho
  fixo (`float`, `u8`, `u32`, `u64`, structs abaixo).

## Erros

Toda função retorna `ZyntraResult` (`0 == ZYNTRA_OK`):

| Código | Significado |
|---|---|
| `ZYNTRA_OK` | sucesso |
| `ZYNTRA_INVALID_ARGUMENT` | handle/saída nulo, viewport negativo, botão > 2 |
| `ZYNTRA_OUT_OF_MEMORY` | falha de alocação do `page_allocator` |
| `ZYNTRA_INVALID_EVENT` | evento rejeitado na validação |
| `ZYNTRA_INVALID_COMMAND` | comando de desenho inválido (ex.: largura/raio negativos, NaN) |
| `ZYNTRA_INVALID_STATE` | `begin` com frame ativo / `end` sem frame ativo |
| `ZYNTRA_INVALID_TEXT` | UTF-8 malformado em `zyntra_draw_text`/`zyntra_text_*` |

## Desenho

Cada `zyntra_draw_*` enfileira um comando na `DrawList` do frame corrente
(geometria em pixels lógicos). Comando inválido (largura/raio negativos,
NaN/Inf) devolve `ZYNTRA_INVALID_COMMAND` e **não** entra na lista.

| Função | Comando |
|---|---|
| `zyntra_draw_clear` | limpa o viewport com cor sólida |
| `zyntra_draw_clip` / `zyntra_draw_clip_reset` | clip retangular (scissor) para os próximos / remoção |
| `zyntra_draw_rect_filled` | retângulo sólido |
| `zyntra_draw_rect_outline` | moldura retangular de `thickness` px |
| `zyntra_draw_line` | reta entre dois pontos |
| `zyntra_draw_circle_filled` | círculo sólido |
| `zyntra_draw_rect_rounded` | cantos arredondados (SDF anti-serrilhado no backend de referência) |
| `zyntra_draw_rect_gradient` | gradiente linear `color0`(p0) → `color1`(p1) contido em `rect` |
| `zyntra_draw_rect_shadow` | sombra projetada da silhueta arredondada (não desenha a forma) |
| `zyntra_draw_blur` | backdrop blur do que já foi desenhado dentro de `rect` (ordem importa) |

Todas as variantes de `DrawCommand` da API Zig têm wrapper C; a ordem dos
comandos é a ordem de chamada e `zyntra_draw_count` conta o que está na
lista.

## Pixels: framebuffer e render

O rasterizador de software do backend de referência também cruza a
fronteira: um `ZyntraFramebuffer*` opaco (RGBA, alocado no
`page_allocator` interno) rasteriza a `DrawList` do frame corrente.

| Função | Efeito |
|---|---|
| `zyntra_framebuffer_create(w, h, &fb)` | cria `w`×`h` (0 ou > 8192 ⇒ `ZYNTRA_INVALID_ARGUMENT`) |
| `zyntra_framebuffer_destroy(fb)` | libera (NULL é seguro) |
| `zyntra_framebuffer_size(fb, &w, &h)` | tamanho atual em pixels |
| `zyntra_framebuffer_fill(fb, color)` | preenche o framebuffer inteiro (source-over) |
| `zyntra_framebuffer_pixel(fb, x, y, &color)` | lê um pixel RGBA (fora dos limites ⇒ `ZYNTRA_INVALID_ARGUMENT`) |
| `zyntra_framebuffer_render(fb, ctx, &stats)` | desenha o viewport do contexto, clampado ao framebuffer |
| `zyntra_framebuffer_render_region(fb, ctx, region, &stats)` | repinta só `region`; o resto do framebuffer fica como estava |

`ZyntraRenderStats` é opcional (NULL é aceito) e devolve
`submitted`/`drawn`/`culled`/`skipped_text` — os mesmos contadores do
`render`/`renderRegion` da API Zig.

Repintura parcial vista do C: `zyntra_context_mark_dirty` une a região que
mudou no frame, `zyntra_context_dirty_rect` lê o acumulado e
`zyntra_context_clear_dirty` zera (`begin_frame` também limpa). É o mesmo
caminho de `software.raster.renderRegion`: o `clear` parcial limpa só a
região e comandos fora dela são cullados.

```c
ZyntraFramebuffer *fb = NULL;
zyntra_framebuffer_create(640, 480, &fb);

zyntra_context_begin_frame(ctx);
zyntra_draw_clear(ctx, (ZyntraColor){20, 20, 24, 255});
zyntra_draw_rect_rounded(ctx, (ZyntraRect){16, 16, 200, 64}, 8.0f,
    (ZyntraColor){230, 230, 240, 255});

ZyntraRect dirty = {0, 0, 640, 480};   /* região que mudou neste frame */
zyntra_context_mark_dirty(ctx, dirty);
zyntra_framebuffer_render_region(fb, ctx, dirty, NULL);
zyntra_context_end_frame(ctx);
```

## Widgets

Primeira superfície C dos widgets (M107): ids, tema embutido e o lote de
caixas/controles sem listas de strings. Os estilos são os mesmos `extern
struct` da API Zig (`ZyntraButtonStyle`, `ZyntraCheckboxStyle`,
`ZyntraSwitchStyle`, `ZyntraSliderStyle`, `ZyntraProgressStyle`,
`ZyntraSeparatorStyle`), com layout travado por `_Static_assert` no C e
`@compileError` no Zig.

```c
ZyntraThemeColors tc;
zyntra_theme_colors(ZYNTRA_THEME_DARK, &tc);  /* bg/surface/text/accent/border */

ZyntraButtonStyle bs;
zyntra_style_button(ZYNTRA_THEME_DARK, &bs);  /* ou _LIGHT; ajuste e reutilize */
bs.radius = 4.0f;

const ZyntraId btn = zyntra_id_from_string("app:ok", 6); /* FNV-1a 64; 0 = nulo */
ZyntraButtonResult bres;

zyntra_context_begin_frame(ctx);
zyntra_draw_clear(ctx, tc.bg);
zyntra_widget_button(ctx, btn, (ZyntraRect){8, 8, 120, 32}, &bs, &bres);
zyntra_widget_label(ctx, zyntra_id_child(btn, 0), (ZyntraRect){16, 16, 100, 16},
    tc.text, 14.0f, "Ok", 2, false, NULL);  /* rótulo por cima, como na API Zig */
if (bres.clicked) { /* ... */ }
zyntra_context_end_frame(ctx);
```

* Lote atual: `zyntra_widget_label`, `_button`, `_checkbox`, `_switch`,
  `_slider`, `_progress`, `_separator` — os widgets que não exigem listas
  de strings nem estado retido.
* `checked` (checkbox/switch) e `value` (slider) pertencem ao chamador: o
  widget lê e altera no clique/arraste; o resultado volta em `out_*`
  (`hovered`/`pressed`/`clicked`/`toggled`/`changed`/`dragging`/...).
* `progress` e `separator` não têm id: não interagem nem entram no foco.
* `out_*` pode ser NULL (importa só o efeito na DrawList/estado).
* Erros: estilo/estado nulo, id nulo (`0`), `size <= 0`, enum fora da
  faixa (`ZYNTRA_THEME_*`, `ZYNTRA_HORIZONTAL`/`_VERTICAL`) ou `utf8` NULL
  com `len > 0` ⇒ `ZYNTRA_INVALID_ARGUMENT`; UTF-8 malformado ⇒
  `ZYNTRA_INVALID_TEXT`.
* `utf8` é emprestado só durante a chamada (a `DrawList` copia).

Segundo lote (M108): widgets com listas de rótulos e painel. Listas
trafegam como vetor de `ZyntraStr` (`ptr` + `len`), emprestado só durante a
chamada; índices opcionais voltam como `int64_t` com `-1` = nenhum.

```c
ZyntraTabBarStyle tbs;
zyntra_style_tab_bar(ZYNTRA_THEME_DARK, &tbs);
ZyntraListViewStyle lvs;
zyntra_style_list_view(ZYNTRA_THEME_DARK, &lvs);
ZyntraRadioStyle rs;
zyntra_style_radio(ZYNTRA_THEME_DARK, &rs);
ZyntraPanelStyle pans;
zyntra_style_panel(ZYNTRA_THEME_DARK, &pans);
lvs.item_height = 24.0f;   /* estilo é reutilizável: ajuste antes de desenhar */

const ZyntraStr tabs[2] = {{"Arquivo", 7}, {"Editar", 6}};
size_t active = 0;
ZyntraTabBarResult tbres;

/* rótulos emprestados só na chamada; `selected`/`active`/`scroll_offset`/
 * `collapsed` pertencem ao chamador (o widget lê e altera) */
zyntra_widget_tab_bar(ctx, tab_id, (ZyntraRect){0, 0, 320, 28}, tabs, 2,
    &active, &tbs, &tbres);
zyntra_widget_radio(ctx, radio_id, (ZyntraRect){0, 32, 160, 72},
    options, option_count, &selected, 14.0f, &rs, &rres);
zyntra_widget_list_view(ctx, list_id, (ZyntraRect){0, 108, 160, 200},
    items, item_count, &row, &scroll, &lvs, &lres);
zyntra_widget_panel(ctx, panel_id, (ZyntraRect){168, 32, 160, 276},
    &collapsed, (ZyntraPanelOptions){{"Inspetor", 8}, true, false}, 14.0f,
    &pans, &pres);   /* pres.content = área útil do corpo */
```

* Lote M108: `zyntra_widget_radio`, `_tab_bar`, `_list_view`, `_panel`
  (estilos `ZyntraRadioStyle`/`ZyntraTabBarStyle`/`ZyntraListViewStyle`/
  `ZyntraPanelStyle` via `zyntra_style_*`).
* `ZyntraStr` com `len > 0` e `ptr == NULL` ⇒ `ZYNTRA_INVALID_ARGUMENT`;
  `len == 0` é string vazia válida (aceita `ptr` NULL). Vetor com `len == 0`
  (ou NULL) é lista vazia, que os widgets rejeitam conforme a API Zig
  (`radio`/`tab_bar`/`list_view` exigem ao menos um item).
* `size` (radio/painel) é a fonte do texto; abas e itens de lista usam a
  fonte padrão dos widgets (10) — use `zyntra_text_measure` para prever as
  larguras das abas.
* `panel`: `options.title` é emprestado só na chamada, `collapsible`
  desenha o chevron (colapsa com clique ou tecla) e `closable` desenha o
  `×` e sinaliza `close_requested`; `content` volta zerado quando
  colapsado.

Terceiro lote (M109): estruturas planas — `menu` e `table`.

```c
ZyntraMenuStyle ms;
zyntra_style_menu(ZYNTRA_THEME_DARK, &ms);
ZyntraTableStyle ts;
zyntra_style_table(ZYNTRA_THEME_DARK, &ts);

const ZyntraMenuItem itens[3] = {
    {{"Abrir", 5}, {"Ctrl+O", 6}, true, false, false, false},
    {{"", 0}, {"", 0}, true, true, false, false},          /* separador */
    {{"Grade", 5}, {"", 0}, true, false, true, true},      /* marcável/marcado */
};
size_t active = 0;
ZyntraMenuResult mres;
zyntra_widget_menu(ctx, menu_id, (ZyntraRect){8, 8, 200, 76}, itens, 3,
    &active, 14.0f, &ms, &mres);   /* mres.chosen = índice no press/Enter */

const ZyntraTableColumn cols[2] = {{{"Nome", 4}, 160.0f}, {{"Tipo", 4}, 120.0f}};
const ZyntraStr linha0[2] = {{"audio.wav", 9}, {"audio", 5}};
const ZyntraTableRow linhas[1] = {{linha0, 2}};
size_t row = 0;
float row_scroll = 0.0f;
ZyntraTableResult tres;
zyntra_widget_table(ctx, table_id, (ZyntraRect){8, 92, 280, 200}, cols, 2,
    linhas, 1, &row, &row_scroll, &ts, &tres);
```

* Lote M109: `zyntra_widget_menu` (rótulos/atalhos, itens desabilitados,
  separadores, coluna de tique com `has_checked`/`checked`) e
  `zyntra_widget_table` (colunas com título/largura, linhas de células,
  seleção, hover, rolagem, linhas alternadas); estilos
  `ZyntraMenuStyle`/`ZyntraTableStyle` via `zyntra_style_menu`/`_table`.
* `has_checked == false` = item não marcável (o tique só aparece quando há
  item marcável no menu), espelhando o `checked == null` da API Zig.
* Tabela: `columns_len == 0` ou `bounds.h <= style.header_height` ⇒
  `ZYNTRA_INVALID_ARGUMENT`; células além das colunas são ignoradas e
  células faltantes ficam vazias, como na API Zig.
* Vetores pequenos são convertidos sem alocação (scratch na pilha: 64
  itens de menu; 16 colunas, 64 linhas e 256 células na tabela); acima
  disso o alocador do contexto é usado e liberado no retorno.

## Strings, buffers, callbacks

* M6: `zyntra_draw_text(handle, pos, color, size, utf8, utf8_len)` copia os
  bytes para a arena da `DrawList` — o chamador pode liberar o buffer logo
  após o retorno. UTF-8 malformado retorna `ZYNTRA_INVALID_TEXT`.
  `utf8_len == 0` aceita ponteiro NULL (run vazio válido).
* Métricas fallback (mesmas da API Zig: avanço fixo por glifo,
  `FontMetrics.withSize`): `zyntra_text_measure(utf8, len, size, &w, &h)`
  mede e `zyntra_text_truncate(utf8, len, size, max_width, &bytes)` devolve
  quantos bytes iniciais cabem (corte em fronteira de codepoint). `size` ou
  `max_width` inválidos ⇒ `ZYNTRA_INVALID_ARGUMENT`; UTF-8 malformado ⇒
  `ZYNTRA_INVALID_TEXT`.
* Sem callbacks na fronteira. Demais strings/buffers: fora de escopo.

## Compatibilidade ABI

* Structs `extern` com tamanhos travados (`_Static_assert` no C,
  `@compileError` no Zig): `ZyntraVec2=8`, `ZyntraSize=8`,
  `ZyntraRect=16`, `ZyntraColor=4`, `ZyntraRenderStats=16`;
  `ZyntraResult` é `c_int`.
* M107: também travados `ZyntraId=8`, `ZyntraThemeColors=20`,
  `ZyntraTextMetrics=16`, estilos (`Button=24`, `Checkbox=24`, `Switch=28`,
  `Slider=32`, `Progress=16`, `Separator=12`) e resultados
  (`Label=20`, `Button=3`, `Checkbox=3`, `Switch=4`, `Slider=8`).
* M108: também travados `ZyntraStr=16` (2 × `size_t`),
  `ZyntraPanelOptions=24`, estilos (`Radio=20`, `TabBar=36`, `ListView=36`,
  `Panel=48`) e resultados (`Radio=3`, `TabBar=24`, `ListView=24`,
  `Panel=20`).
* M109: também travados `ZyntraMenuItem=40`, `ZyntraTableColumn=24`,
  `ZyntraTableRow=16`, estilos (`Menu=24`, `Table=48`) e resultados
  (`Menu=24`, `Table=24`).
* Símbolos C estáveis listados em `src/c-abi/zyntra.h`.
* Quebra de layout/assinatura exige MAJOR bump.

## Versão

Fonte única de verdade: `build.zig.zon` (`.version`). Espelhos manuais
atualizados juntos no prep de release: `version_*` em
`src/core/types.zig` (API Zig + `zyntra_version_*`) e as asserções de
versão completa em `tests/c/test_c_abi.c`. Divergência quebra o CI:
teste `version_* espelham build.zig.zon` (+ `build.zig.zon` como
entrada de cache do `run test`) e o próprio teste C.

## Teste de integração

Consumidor C real em `tests/c/test_c_abi.c`:

```sh
zig build                          # gera zig-out/lib/libzyntra_ui.a
zig cc tests/c/test_c_abi.c zig-out/lib/libzyntra_ui.a \
  -Isrc/c-abi -o /tmp/opencode/zyntra-c-test
/tmp/opencode/zyntra-c-test        # esperado: "C-ABI OK ..." + "C-ABI modern ..." + "C-ABI pixels ..." + "C-ABI widgets ..." + "C-ABI lists ..." + "C-ABI rich ..."
```
