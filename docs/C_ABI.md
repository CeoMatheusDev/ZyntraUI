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
| `ZYNTRA_INVALID_ARGUMENT` | handle/saída nulo, viewport negativo, botão > 2, tecla fora de `ZyntraKey`, bit de modificador reservado |
| `ZYNTRA_OUT_OF_MEMORY` | falha de alocação do `page_allocator` |
| `ZYNTRA_INVALID_EVENT` | evento rejeitado na validação (posição não-finita, codepoint fora de `0..0x10FFFF` ou substituto) |
| `ZYNTRA_INVALID_COMMAND` | comando de desenho inválido (ex.: largura/raio negativos, NaN) |
| `ZYNTRA_INVALID_STATE` | `begin` com frame ativo / `end` sem frame ativo |
| `ZYNTRA_INVALID_TEXT` | UTF-8 malformado em `zyntra_draw_text`/`zyntra_text_*` |

## Entrada: mouse, teclado e foco

O mouse entra por `zyntra_context_push_mouse_move`,
`zyntra_context_push_mouse_button` e pela roda
(`zyntra_context_push_mouse_wheel`, `dx`/`dy` em unidades de linha); o teclado
entra por `zyntra_context_push_key` e o texto digitado por
`zyntra_context_push_text` (um codepoint por chamada):

```c
zyntra_context_push_mouse_button(ctx, 0 /* left */, true, (ZyntraVec2){x, y});
zyntra_context_push_mouse_wheel(ctx, 0, -1, (ZyntraVec2){x, y}); /* rola p/ baixo */
zyntra_context_push_key(ctx, ZYNTRA_KEY_DOWN, true, 0);
zyntra_context_push_key(ctx, ZYNTRA_KEY_S, true, ZYNTRA_MOD_CTRL);
zyntra_context_push_text(ctx, 'a');   /* texto digitado */
```

* `ZyntraKey` espelha as teclas normalizadas da API Zig (mesmos valores),
  então as mesmas teclas funcionam nos widgets das duas pontas: setas,
  `HOME`/`END`, `PAGE_UP`/`PAGE_DOWN`, `ENTER`, `ESCAPE`, `TAB`, `SPACE`,
  `BACKSPACE`, `DELETE` e as letras de atalho (`A`, `C`, `V`, `X`, `Y`, `Z`).
* `modifiers` é um bitmask: `ZYNTRA_MOD_SHIFT` (0x01), `ZYNTRA_MOD_CTRL`
  (0x02), `ZYNTRA_MOD_ALT` (0x04) e `ZYNTRA_MOD_SUPER` (0x08). Bits fora
  dessas máscaras são recusados com `ZYNTRA_INVALID_ARGUMENT`.
* Teclas vão para o widget **focado**: `zyntra_context_focus(ctx, id)`
  define o foco (`id == 0` limpa) e `zyntra_context_has_focus` consulta.
  Cliques também focam (um press dentro do widget vira dono do foco), e
  `TAB` percorre os widgets focáveis na ordem de chamada do frame.
* `zyntra_context_push_text` rejeita codepoints fora de `0..0x10FFFF` ou na
  faixa de substitutos com `ZYNTRA_INVALID_EVENT` (mesma regra das posições
  de mouse não-finitas); eventos válidos ficam na fila do frame corrente.

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

Quarto lote (M110): a árvore recursiva `tree_view`.

```c
ZyntraTreeViewStyle tvs;
zyntra_style_tree_view(ZYNTRA_THEME_DARK, &tvs);

/* A árvore é DO CHAMADOR e mutável: `expanded` é o estado que o widget
 * altera e devolve escrito de volta nela. */
ZyntraTreeItem neto[1] = {{{"widget.zig", 10}, NULL, 0, false}};
ZyntraTreeItem filhos[2] = {
    {{"ui", 2}, neto, 1, false},
    {{"app.zig", 7}, NULL, 0, false},
};
ZyntraTreeItem raizes[2] = {
    {{"src", 3}, filhos, 2, false},
    {{"build.zig", 9}, NULL, 0, false},
};
size_t node = 0;
float tree_scroll = 0.0f;
ZyntraTreeViewResult tvr;
zyntra_widget_tree_view(ctx, tree_id, (ZyntraRect){8, 8, 200, 256}, raizes, 2,
    &node, &tree_scroll, &tvs, &tvr);   /* tvr.toggled_index = expansor clicado */
```

* Lote M110: `zyntra_widget_tree_view` com `ZyntraTreeViewStyle` via
  `zyntra_style_tree_view` — nós com rótulo, filhos e `expanded`, seleção,
  hover, rolagem e expansor clicável (`toggled_index`).
* O clique no expansor alterna `expanded` **do nó exato** (sem ambiguidade
  de profundidade) e o estado volta escrito na árvore do chamador; clique
  fora do expansor seleciona o nó (`changed`/`selected`).
* Defesas da conversão recursiva: `items_len == 0`, `children_len > 0` com
  `children == NULL` ou rótulo nulo ⇒ `ZYNTRA_INVALID_ARGUMENT`; árvores
  com mais de 65536 nós ou mais de 128 níveis (caso de ciclo) também são
  recusadas, sem recursão infinita.
* Nós pequenos usam scratch da pilha (64 nós + 64 ponteiros); acima disso o
  alocador do contexto é usado e liberado no retorno.

Quinto lote (M112): os campos de texto `text_input`, `text_input_selected` e
`textarea`.

```c
ZyntraTextInputStyle tis;
zyntra_style_text_input(ZYNTRA_THEME_DARK, &tis);

/* O buffer é do CHAMADOR (capacidade + bytes usados + caret + âncora). */
char buf[128];
size_t len = 0, cursor = 0, anchor = 0;
ZyntraTextInputResult tir;
zyntra_context_focus(ctx, field_id);
zyntra_context_push_text(ctx, 'o');
zyntra_context_push_key(ctx, ZYNTRA_KEY_LEFT, true, ZYNTRA_MOD_SHIFT);
zyntra_widget_text_input_selected(ctx, field_id, (ZyntraRect){8, 8, 240, 28},
    buf, sizeof(buf), &len, &cursor, &anchor, 14.0f, &tis, &tir);

float scroll_y = 0.0f;
ZyntraTextAreaResult tar;
zyntra_widget_text_area(ctx, area_id, (ZyntraRect){8, 44, 320, 200},
    buf, sizeof(buf), &len, &cursor, &anchor, &scroll_y, 14.0f, &tis, &tar);
```

* Lote M112: `zyntra_widget_text_input` (linha única, sem seleção),
  `zyntra_widget_text_input_selected` (com `anchor` para a faixa de seleção)
  e `zyntra_widget_text_area` (multilinha com `scroll_y`), todos com
  `ZyntraTextInputStyle` via `zyntra_style_text_input` — o mesmo estilo para
  campo e área, como na API Zig.
* Nada aloca na lib: `buffer`/`len`/`cursor`/`anchor`/`scroll_y` pertencem ao
  chamador e persistem entre frames; o widget escreve direto no buffer.
* `buffer_len == 0` aceita `buffer == NULL`; temas de capacidade, `len` acima
  da capacidade declarada e `cursor`/`anchor` acima de `len` são
  `ZYNTRA_INVALID_ARGUMENT` (mesmas invariantes da API Zig), e digitar além
  da capacidade sinaliza `overflowed` sem tocar o buffer.
* `submitted` vem do `ENTER` (sem soltar o foco); `ESCAPE` solta o foco.
  `undone`/`redone` ficam sempre falsos: undo/redo exigem o histórico
  comptime das variantes Zig (`textInputHistory`/`textInputClipboard`).

Sexto lote (M113): docking — `ZyntraDock` opaco (modelo `DockLayout`), o
widget `zyntra_widget_dock_view` e as consultas de geometria.

```c
ZyntraDockStyle ds;
zyntra_style_dock(ZYNTRA_THEME_DARK, &ds);   /* divisória 6 px, fundo do tema */

ZyntraDock *dock = NULL;
zyntra_dock_create(1, &dock);                    /* um painel (id 1) */
uint8_t leaf = 0;
zyntra_dock_split(dock, 0, ZYNTRA_HORIZONTAL, 0.5f, 2, &leaf);  /* abre o 2 */

/* `panes` é do chamador (ZYNTRA_DOCK_MAX_PANES entradas). */
ZyntraDockPaneInfo panes[ZYNTRA_DOCK_MAX_PANES];
ZyntraDockViewResult dres;
int64_t dragging = -1;                          /* -1 = nenhum painel arrastado */

zyntra_context_begin_frame(ctx);
zyntra_draw_clear(ctx, ds.bg);
zyntra_widget_dock_view(ctx, dock_id, (ZyntraRect){0, 0, 640, 480}, dock,
    panes, ZYNTRA_DOCK_MAX_PANES, dragging, 0.25f, &ds, &dres);
/* desenhe os painéis (panel/tab_bar) usando panes[i].rect depois disto */
zyntra_context_end_frame(ctx);
```

* `zyntra_dock_create`/`_destroy` (NULL seguro) e `_init` reinicia como um
  único painel. `_split` divide a folha em dois lados (devolve a folha nova
  em `out_leaf`), `_add_tab` anexa uma aba, `_set_active_tab` ativa uma aba
  e `_remove_pane` remove um painel (dissolve o split se for o último).
* Consultas: `zyntra_dock_group` lê o grupo (abas + ativa) de uma folha;
  `zyntra_dock_panes`/`zyntra_dock_splits` devolvem a geometria atual em
  pré-ordem, com `divider` px de folga entre os lados. `out` só pode ser
  NULL com `out_len == 0` (só a contagem); `out_len` menor que o número de
  entradas ⇒ `ZYNTRA_INVALID_ARGUMENT`.
* O widget desenha fundo/divisórias, trata o arraste das divisórias (o
  ratio muda no **mesmo frame**, sem lag) e o drop de painéis. `dragging` é
  o painel que o chamador arrasta (`-1` = nenhum) e `edge_frac` a fração de
  borda (0..0.5) que dispara uma zona de drop. `out_result` é opcional.
* `ZyntraDockViewResult` devolve `pane_count`/`split_count`, `changed`
  (geometria mudou), `hovered`/`dragging` (índice da divisória, `-1` =
  nenhum) e `has_drop`/`has_dropped` com `drop`/`dropped` (zona, painéis e
  rect do realce). Ao ver `has_dropped`, limpe o estado de arraste.
* `ZyntraDockZone` (`left`/`right`/`top`/`bottom`/`center`) espelha o
  `DockZone` da API Zig com os mesmos valores; `center` acopla como aba.
* Erros: handle/dock nulo, `out_leaf`/`out_count`/`out_group` nulo, folha
  inexistente, `orientation` fora de `ZYNTRA_HORIZONTAL`/`_VERTICAL`,
  buffer pequeno, `dragging` fora de `-1..0xFFFF` ou `edge_frac` fora de
  `[0, 0.5]` ⇒ `ZYNTRA_INVALID_ARGUMENT`.
* `zyntra_dock_create` aloca no `page_allocator` interno; `panes` de
  `zyntra_widget_dock_view` é preenchido pelo widget (nunca alocado pela
  lib). As consultas usam scratch na pilha (até 16 entradas).

Sétimo lote (M115): widgets de composição/exibição — `combo`, `splitter`,
`spinner`, `groupbox` e `tooltip`. Nenhum deles retém estado na lib: o
chamador detém os ponteiros de estado e o texto é emprestado só na chamada.

```c
ZyntraButtonStyle bst;
ZyntraMenuStyle mst;
zyntra_style_button(ZYNTRA_THEME_DARK, &bst);
zyntra_style_menu(ZYNTRA_THEME_DARK, &mst);

ZyntraStr opts[2] = { { "A", 1 }, { "B", 1 } };
size_t sel = 0;
bool open = false;
ZyntraComboResult cres;
zyntra_widget_combo(ctx, id, (ZyntraRect){10, 10, 160, 28}, opts, 2,
    &sel, &open, 10.0f, &bst, &mst, &cres);

ZyntraSplitterStyle sps;
zyntra_style_splitter(ZYNTRA_THEME_DARK, &sps);
float pos = 200;
ZyntraSplitterResult sres;
zyntra_widget_splitter(ctx, sid, (ZyntraRect){0, 0, 640, 480},
    ZYNTRA_HORIZONTAL, &pos, &sps, &sres);
```

* `zyntra_widget_combo` reusa `ZyntraButtonStyle`/`ZyntraMenuStyle` (como a
  API Zig, sem struct nova). `options` (1..256) é um vetor de `ZyntraStr`
  emprestado só na chamada; `selected`/`open` pertencem ao chamador (o widget
  lê e altera). O menu só é desenhado quando a chamada entra com
  `open == true` — o clique de abertura aparece no frame seguinte. `size` é a
  fonte do rótulo e dos itens.
* `zyntra_widget_splitter`: `orientation` usa `ZYNTRA_HORIZONTAL` (divisória
  horizontal, `pos = y`) ou `ZYNTRA_VERTICAL` (`pos = x`). `pos` é do
  chamador (lido, clampado e alterado pelo arraste e pelo teclado). O puxador
  desenhado usa a posição de **entrada** do frame; a posição nova aparece no
  frame seguinte, mas `SplitterResult.pos`/`changed` já refletem o arraste no
  mesmo frame.
* `zyntra_widget_spinner` (sem id) é display puro: `t` é o tempo decorrido
  em segundos, fornecido pelo chamador; o quadro é função pura de `t`.
* `zyntra_widget_group_box` desenha o chrome e devolve em `out_content`
  (opcional) a área útil (`padding` + reserva de `lineHeight/2` no topo) para
  o chamador posicionar os filhos. `title` é emprestado só na chamada.
* `zyntra_widget_tooltip` conta frames consecutivos com o mouse em `anchor`
  e, ao atingir `delay_frames`, desenha caixa + texto perto do cursor,
  clampado ao viewport. `ZyntraTooltipState` (um por tooltip) pertence ao
  chamador; `out_result` é opcional.
* Estilos do tema: `zyntra_style_splitter`, `_spinner`, `_group_box` e
  `_tooltip` (o combo usa os estilos de botão/menu). `ZyntraComboResult` tem
  `changed`/`open`; `ZyntraSplitterResult` tem `pos`/`changed`/`hovered`/
  `dragging`; `ZyntraTooltipResult` tem `visible`/`hovered`.
* Erros ⇒ `ZYNTRA_INVALID_ARGUMENT`: handle/id/out obrigatório nulo,
  `options` vazio ou > 256, `selected` fora da faixa, fonte (`size`) não
  finita/≤ 0, `orientation` fora de `ZYNTRA_HORIZONTAL`/`_VERTICAL`, posição
  não-finita, âncora sem área, estado do tooltip nulo, texto com ponteiro
  nulo e `len > 0` (UTF-8 malformado vira `ZYNTRA_INVALID_TEXT` no desenho
  do tooltip).

### Oitavo lote (M116): contêineres begin/end

Contêineres que emitem `clip` e exigem pareamento, com estado no chamador:

```c
ZyntraScrollStyle scs;
zyntra_style_scroll(ZYNTRA_THEME_DARK, &scs);
float off = 0;
ZyntraScrollResult sres;
if (zyntra_widget_scroll_begin(ctx, id, (ZyntraRect){0, 0, 320, 240},
        &off, 1200, 24, &scs, &sres) == ZYNTRA_OK) {
  /* posicione os filhos em sres.content (origem já deslocada) */
  zyntra_widget_scroll_end(ctx, (ZyntraRect){0, 0, 320, 240}, off, 1200, &scs);
}

ZyntraPopupStyle pps;
zyntra_style_popup(ZYNTRA_THEME_DARK, &pps);
ZyntraRect placed;
zyntra_popup_place(anchor, (ZyntraSize){200, 120}, viewport, &placed);
ZyntraPopupResult pres;
if (open) {
  zyntra_widget_popup_begin(ctx, id, placed, &pps, &pres);
  /* filhos */
  zyntra_widget_popup_end(ctx);
  if (pres.dismissed) open = 0;
}

ZyntraModalStyle mds;
zyntra_style_modal(ZYNTRA_THEME_DARK, &mds);
ZyntraRect mb = {200, 150, 320, 200};
ZyntraModalDragState md = {0, 0};
ZyntraModalResult mres;
zyntra_widget_modal_titled(ctx, id, &mb, "Título", 6, 14, 28, &md, &mds, &mres);
/* filhos */
zyntra_widget_modal_end(ctx);
if (mres.dismissed) open = 0;
```

* `zyntra_widget_scroll_begin` aplica roda
  (`zyntra_context_push_mouse_wheel`, com hover), teclado
  (`Home`/`End`/`PageUp`/`PageDown` com foco) e arraste do thumb em
  `scroll_y` (do chamador), clampado em `[0, content_h - bounds.h]`. Emite
  `clip(bounds)` e devolve `content` (origem deslocada) para os filhos.
  `zyntra_widget_scroll_end` limpa o clip e desenha a scrollbar (só com
  overflow) usando os mesmos `bounds`/`scroll_y`/`content_h`/`style`.
  **SEMPRE pareie**, mesmo sem filhos.
* `zyntra_widget_popup_begin` desenha painel + borda, emite `clip(bounds)` e
  devolve `dismissed` (press fora ou `Escape`) e `hovered`.
  `zyntra_widget_popup_end` limpa o clip. `zyntra_popup_place` é puro (não
  exige handle/frame): abre abaixo da âncora, vira para cima se faltar
  espaço e prende na horizontal; não-finitos saturam para a origem.
* `zyntra_widget_modal_begin` (básico) escurece o viewport inteiro, desenha
  o painel e emite `clip(bounds)`; `dismissed` sinaliza press fora ou
  `Escape`. `zyntra_widget_modal_titled` acrescenta o título e o arrasto pela
  faixa de título: `bounds` e `drag` pertencem ao chamador e persistem entre
  frames (clampados ao viewport quando o painel cabe).
  `zyntra_widget_modal_end` limpa o clip. O bloqueio dos widgets de trás é
  por convenção: com o modal aberto, o chamador não os sonda.
* `ZyntraScrollStyle` = `bar_width`/`track`/`thumb`; `ZyntraPopupStyle` =
  `bg`/`border`/`border_width`; `ZyntraModalStyle` =
  `dim`/`bg`/`border`/`border_width`/`title_text`. Resultados:
  `ZyntraScrollResult` (`content`/`offset`/`max_offset`/`hovered`/`scrolled`/
  `dragging`), `ZyntraPopupResult` (`dismissed`/`hovered`) e
  `ZyntraModalResult` (`dismissed`/`hovered`/`dragging`).
* Erros ⇒ `ZYNTRA_INVALID_ARGUMENT`: handle/id/estilo/ponteiro obrigatório
  nulo, retângulo sem área ou não-finito, `content_h`/`scroll_y` negativos,
  `speed` ≤ 0 ou não-finita, `bar_width` ≤ 0, `border_width` negativo,
  fonte (`size`) ou `title_h` ≤ 0/não-finitos, título com ponteiro nulo e
  `len > 0`.

### Nono lote (M117): arrastar-e-soltar e drag ghost

O serviço de DnD vive no `Context` (uma instância por janela), sem
alocação própria. O fluxo é o mesmo da API Zig:

```c
/* origem, depois de capturar o press e mover além do limiar */
zyntra_dnd_begin(ctx, source_id, "node", 4, my_node, "Nó 1", 5);

/* todo frame, em cada alvo candidato (mesmo sem arraste) */
ZyntraDndAccept acc;
zyntra_dnd_accept(ctx, target_id, target_bounds, &acc);
if (acc == ZYNTRA_DND_HOVER)   { /* realce */ }
if (acc == ZYNTRA_DND_DROPPED) { /* solto neste frame */ }

/* por último, por cima de tudo */
ZyntraDragGhostStyle gs;
zyntra_style_drag_ghost(ZYNTRA_THEME_DARK, &gs);
ZyntraDragGhostResult gres;
zyntra_widget_drag_ghost(ctx, &gs, 12, &gres);
```

* `zyntra_dnd_begin` exige `source != 0`, `kind` não vazio/UTF-8, cursor
  conhecido e nenhum arraste ativo. `kind`/`label` são **emprestados** e
  devem continuar válidos até o solto/cancelamento; `label` vazio usa o
  `kind` no fantasma. `data` é opaco (a lib nunca dereferencia; pode ser
  `NULL`).
* `zyntra_dnd_accept` registra o alvo sob o cursor neste frame (o último
  desenhado vence) e devolve `ZYNTRA_DND_NONE`/`_HOVER`/`_DROPPED`.
  Chamar **todo frame**, mesmo sem arraste, para receber o solto.
  `zyntra_dnd_hover_target` consulta o alvo registrado.
* `zyntra_dnd_last_drop` devolve o solto resolvido no `begin_frame`
  seguinte ao release (ou ao cancelamento), válido por **um frame**:
  `present`, `cancelled`, `target`/`source` (`0` = nenhum), `kind`/`label`
  (ponteiros emprestados do `begin`) e `data`. Sem solto, `present` é falso
  e os demais campos são zerados.
* `zyntra_dnd_cancel` encerra o arraste sem alvo e marca `cancelled` no
  resultado; `zyntra_dnd_is_dragging` e `zyntra_dnd_drag_source` consultam
  o arraste ativo. `zyntra_dnd_drag_position`/`_origin`/`_distance` e
  `zyntra_dnd_drag_exceeds` (px não-finito/negativo ⇒ `false`) acompanham
  o movimento.
* `zyntra_widget_drag_ghost` desenha o fantasma do arraste ativo sob o
  cursor, clampado ao viewport, com sombra/caixa/borda/rótulo conforme
  `ZyntraDragGhostStyle`. Sem arraste, não emite comandos e `drawn` é falso;
  `ZyntraDragGhostResult` traz `rect` e as métricas do rótulo. Chame por
  último para ficar por cima.
* Erros ⇒ `ZYNTRA_INVALID_ARGUMENT`: handle/saída obrigatória nula, origem
  0, arraste já ativo, cursor desconhecido, `kind` vazio/não-UTF8, `label`
  não-UTF8 ou com ponteiro nulo e `len > 0`, estilo inválido e fonte
  (`size`) ≤ 0/não-finita.

### Décimo lote (M118): toolbar e statusbar

As barras são **composição leve**: desenham o chrome, devolvem a área útil e
um estado de posicionamento **detido pelo chamador**; o conteúdo dos itens
continua sendo desenhado por `button`, `label`, `text_input`, etc.

```c
ZyntraToolbarStyle ts;
zyntra_style_toolbar(ZYNTRA_THEME_DARK, &ts);

ZyntraToolbar bar;
zyntra_widget_toolbar(ctx, (ZyntraRect){0, 0, 200, 40}, &ts, &bar);

ZyntraRect item;
zyntra_toolbar_next_item(&bar, 50, &item);   /* item em (8, 6, 50, 28) */
zyntra_button(ctx, btn_id, item, "Abrir", ...);

zyntra_toolbar_separator(ctx, &bar, &sep);
zyntra_toolbar_next_item(&bar, 30, &item);   /* … */

float restante;
zyntra_toolbar_remaining(&bar, &restante);
```

* `zyntra_widget_toolbar`/`zyntra_widget_status_bar` desenham fundo + borda e
  preenchem `ZyntraToolbar`/`ZyntraStatusBar` (não edite os campos; passe o
  mesmo estado aos helpers). A altura dos itens é `min(style.item_height,
  altura do conteúdo)`.
* Toolbar: `zyntra_toolbar_next_item` posiciona da esquerda para a direita
  com `spacing`; a largura é **clampada** ao restante e `overflowed` é
  marcado quando não couber (largura inválida vira 0). `zyntra_toolbar_remaining`
  devolve o espaço restante; `zyntra_toolbar_separator` reusa o separador
  vertical entre grupos e avança o cursor.
* Statusbar: `zyntra_status_bar_next_item` posiciona à esquerda e
  `zyntra_status_bar_next_right` ancora à direita (os lados **nunca se
  sobrepõem**; ambos clampam e marcam `overflowed`). `zyntra_status_bar_remaining`
  devolve o vão livre entre os cursores. `zyntra_status_bar_text` mede, avança
  e emite 1 linha (`out_rect` opcional); `zyntra_status_bar_separator` reusa o
  divisor vertical.
* O estado é por valor (sem alocação e sem handle opaco): cada barra é
  independente e pode viver na pilha do chamador. Chamar um helper com estado
  corrompido (campo não-finito, conteúdo negativo, espaçamento negativo) ⇒
  `ZYNTRA_INVALID_ARGUMENT`.
* Erros ⇒ `ZYNTRA_INVALID_ARGUMENT`: handle/estado/saída obrigatória nula,
  geometria sem área ou não-finita, estilo inválido, `text` nulo com
  `len > 0`, texto não-UTF8 e fonte (`size`) ≤ 0/não-finita.

### Décimo primeiro lote (M119): grafo de nós

```c
ZyntraGraphStyle gs;
zyntra_style_graph(ZYNTRA_THEME_DARK, &gs);

ZyntraGraphViewState state;
zyntra_graph_view_state_init(&state);       /* zoom 1, nada selecionado */

ZyntraGraphViewOptions opt;
zyntra_graph_view_options_default(&opt);

ZyntraGraphNode nodes[2] = {
    {.pos = {20, 20}, .size = {100, 60}, .title = {"A", 1},
     .inputs = 0, .outputs = 1},
    {.pos = {140, 20}, .size = {100, 60}, .title = {"B", 1},
     .inputs = 1, .outputs = 0},
};
ZyntraGraphEdge edge = {.from = 0, .to = 1};

ZyntraGraphViewResult res;
zyntra_widget_graph_view(ctx, graph_id, bounds, nodes, 2, &edge, 1,
    &state, &opt, &gs, 12, &res);
```

* `ZyntraGraphNode`/`ZyntraGraphEdge`/`ZyntraGraphTransform` espelham o
  modelo: posição/tamanho em **espaço-mundo**, pinos de entrada à esquerda e
  saída à direita, arestas por índice. `title` é **emprestado só durante a
  chamada** (como nos demais widgets); vazio ⇒ sem título. Arestas com índice
  fora de faixa são ignoradas no desenho.
* `ZyntraGraphViewState` pertence ao chamador e é retido entre frames:
  transform (`pan`/`zoom`), seleção e estado transiente de arraste/pan.
  **Inicie com `zyntra_graph_view_state_init`** — o zero de C deixa `zoom == 0`
  (inválido) e todos os índices em 0. Índices opcionais usam `-1` para
  “nenhum”.
* Interação: press sobre um nó seleciona e arrasta pela “pega”; press no vazio
  faz pan; roda com hover dá zoom em torno do cursor (sinal de `dy`, passo
  `zoom_step`, clamp `[min_zoom, max_zoom]`); setas/Home/Page Up/Page Down e
  Tab seguem o comportamento da API Zig. O arraste **atualiza `nodes[i].pos`
  na memória do chamador**.
* `ZyntraGraphViewResult` reporta `hovered`/`selected`/`dragging` (`-1` =
  nenhum), `drag_delta`/`pan_delta` do frame, `zoom_changed`, `panning` e
  `changed`. `out_result` é opcional.
* Memória: o wrapper converte nós/arestas para buffers temporários no
  alocador do `Context` a cada chamada (o chamador não precisa montar structs
  internas). Falha de alocação ⇒ `ZYNTRA_OUT_OF_MEMORY`.
* Erros ⇒ `ZYNTRA_INVALID_ARGUMENT`: handle/id/estado/opções/estilo nulos,
  geometria sem área ou não-finita, nó com `size` ≤ 0/não-finito, `title` com
  ponteiro nulo e `len > 0`, transform inválido (`zoom` ≤ 0/não-finito),
  opções inválidas (`0 < min_zoom <= max_zoom`, `zoom_step > 0`, `pan_step >= 0`,
  `edge_segments >= 1`) e fonte (`size`) ≤ 0/não-finita.

### Décimo segundo lote (M120): timeline

```c
ZyntraTimelineStyle ts;
zyntra_style_timeline(ZYNTRA_THEME_DARK, &ts);

ZyntraTimelineViewState state;
zyntra_timeline_view_state_init(&state);     /* 10 s, playhead 0, 80 px/s */

ZyntraTimelineViewOptions opt;
zyntra_timeline_view_options_default(&opt);

ZyntraTimelineKey keys[2] = {{0.5f, 7}, {1.0f, 8}};  /* t (s), tag opaca */
ZyntraTimelineTrack tracks[1] = {
    {.name = {"T", 1}, .keys = keys, .keys_len = 2},
};

ZyntraTimelineViewResult res;
zyntra_widget_timeline_view(ctx, id, bounds, tracks, 1,
    &state, &opt, &ts, 10, &res);
```

* `ZyntraTimelineTrack` traz nome **emprestado só durante a chamada** e
  `keys` **mutável**: arrastar uma chave atualiza `keys[i].t` na memória do
  chamador (o `tag` é preservado; o widget não interpreta o dado). Chaves com
  índice fora de faixa são ignoradas.
* `ZyntraTimelineViewState` pertence ao chamador e é retido entre frames:
  `transform` (`start`/`pps`), `duration`, `playhead`, seleção e estado
  transiente de scrub/pan/arraste. **Inicie com
  `zyntra_timeline_view_state_init`** — o zero de C deixa `pps == 0`
  (inválido). Índices opcionais usam `-1`; `drag` usa
  `ZYNTRA_TIMELINE_DRAG_*` como `int32_t` (valor desconhecido ⇒
  `ZYNTRA_INVALID_ARGUMENT`).
* Interação: press na régua faz scrub do `playhead`; arraste no corpo faz pan
  (`start` recalculado e clampado); press numa chave seleciona/arrasta
  (`snap_keys` alinha ao passo da régua); roda com hover dá zoom em torno do
  cursor (passo `zoom_step`, clamp `[min_pps, max_pps]`). Teclado/Home/End e
  Tab seguem o comportamento da API Zig.
* `ZyntraTimelineViewResult` reporta pares `track`/`key` (`-1` = nenhum) para
  hover, seleção e arraste, além de `key_delta` (s), `playhead`,
  `scrubbing`, `panning`, `zoom_changed` e `changed`. `out_result` é
  opcional.
* Memória: as trilhas são convertidas e as chaves achatadas num buffer
  temporário no alocador do `Context`; os nomes não são copiados. Falha de
  alocação ⇒ `ZYNTRA_OUT_OF_MEMORY`.
* Erros ⇒ `ZYNTRA_INVALID_ARGUMENT`: handle/id/estado/opções/estilo nulos,
  geometria sem área ou não-finita, trilha/chave com ponteiro nulo e
  `len > 0`, transform inválido (`pps` ≤ 0/não-finito), `duration` ≤ 0,
  `playhead` não-finito, `drag` desconhecido, opções inválidas
  (`0 < min_pps <= max_pps`, `zoom_step > 0`, `key_hit_px >= 0`) e fonte
  (`size`) ≤ 0/não-finita.

### Décimo terceiro lote (M121): inspector de propriedades

```c
ZyntraInspectorStyle is;
zyntra_style_inspector(ZYNTRA_THEME_DARK, &is);

ZyntraInspectorViewState state;
zyntra_inspector_view_state_init(&state);   /* nada ativo, scroll 0 */

ZyntraInspectorViewOptions opt;
zyntra_inspector_view_options_default(&opt);

bool visible = true;
int64_t count = 3;
float scale = 1.5f;
uint32_t mode = 0;
ZyntraStr modes[2] = {{"Fast", 4}, {"Slow", 4}};

ZyntraInspectorProperty props[4] = {
    {.name = {"Visible", 7}, .kind = ZYNTRA_INSPECTOR_BOOLEAN,
     .value = &visible},
    {.name = {"Count", 5}, .kind = ZYNTRA_INSPECTOR_INTEGER,
     .value = &count},
    {.name = {"Scale", 5}, .kind = ZYNTRA_INSPECTOR_REAL,
     .value = &scale},
    {.name = {"Mode", 4}, .kind = ZYNTRA_INSPECTOR_CHOICE,
     .choice = {.index = &mode, .options = modes, .options_len = 2}},
};

ZyntraInspectorViewResult res;
zyntra_widget_inspector_view(ctx, id, bounds, props, 4,
    &state, &opt, &is, 10, &res);
```

* `ZyntraInspectorProperty.kind` usa `ZYNTRA_INSPECTOR_*` como `int32_t`.
  Para booleano/inteiro/real, `value` aponta para `bool`/`int64_t`/`float` na
  memória do chamador — o widget lê e **escreve** por ali. `text` e
  `choice.options` são emprestados só durante a chamada; `choice.index`
  aponta para a memória do chamador. `name` vazio ⇒ sem texto.
* `has_step`/`step`, `has_decimals`/`decimals` e `has_range`/`range`
  habilitam os campos opcionais (mesmas regras de `Property`: passo > 0,
  decimais ≤ 6, faixa aplicada só quando `min < max`). `readonly` bloqueia
  edição, mas a linha ainda pode ser ativada/rolada.
* `ZyntraInspectorViewState` pertence ao chamador e é retido entre frames:
  linha ativa, `scroll`, arraste transiente (`dragging`/`drag_anchor`/
  `drag_x`). **Inicie com `zyntra_inspector_view_state_init`** — índices
  opcionais usam `-1`.
* Interação: press ativa a linha; booleano alterna, escolha avança uma opção,
  inteiro/real arrastam horizontalmente com passo por pixel e clamp; roda
  rola verticalmente; setas, Shift/Alt (grosso/fino), Espaço/Enter e Tab
  seguem o comportamento da API Zig.
* `ZyntraInspectorViewResult` reporta `hovered`/`active`/`changed`/
  `dragging` (`-1` = nenhum), `active_changed`, `scroll_delta` e `scrolled`.
  `out_result` é opcional.
* Memória: as propriedades são convertidas e os rótulos de escolha achatados
  num buffer temporário no alocador do `Context`; nenhum nome/valor é
  copiado. Falha de alocação ⇒ `ZYNTRA_OUT_OF_MEMORY`.
* Erros ⇒ `ZYNTRA_INVALID_ARGUMENT`: handle/id/estado/opções/estilo nulos,
  geometria sem área ou não-finita, `kind` desconhecido, ponteiro de valor
  nulo/desalinhado, nome/texto com ponteiro nulo e `len > 0`, escolha sem
  opções/índice, propriedade inválida (passo/decimais/faixa), `scroll`
  não-finito, opções inválidas (`step > 0`, `decimals <= 6`,
  `scroll_step >= 0`, `coarse_factor >= 1`, `0 < fine_factor <= 1`) e fonte
  (`size`) ≤ 0/não-finita.

### Décimo quarto lote (M122): animação (easing, tween, timer e cor)

```c
float v;
zyntra_ease_apply(ZYNTRA_EASE_QUAD_OUT, 0.5f, &v);   /* v = 0.75 */

ZyntraTween tw;
zyntra_tween_init(&tw, 0.0f, 100.0f, 2.0f, ZYNTRA_EASE_LINEAR);
zyntra_tween_value_at(&tw, 1.0f, &v);                /* v = 50 */

ZyntraAnimTimer tm;
zyntra_anim_timer_init(&tm, 1.0f, false);
zyntra_anim_timer_tick(&tm, 0.25f);
zyntra_anim_timer_progress(&tm, &v);                 /* v = 0.25 */

ZyntraColor c;
zyntra_anim_lerp_color((ZyntraColor){0, 0, 0, 255},
    (ZyntraColor){255, 255, 255, 255}, 0.5f, &c);    /* cinza 128 */
```

* Helpers puros, sem alocação/estado global: o chamador dita o tempo. O enum
  `ZyntraEase` espelha `anim.Ease` (0..6); timers guardam apenas
  `duration`/`elapsed`/`looping`.
* `zyntra_ease_apply` satura a entrada em 0..1 (NaN ⇒ 0). `zyntra_tween_*`
  validam o struct (`from`/`to`/`duration` finitos, `duration > 0`, `ease`
  conhecido); `elapsed` é saturado. `zyntra_anim_timer_tick` ignora `dt`
  negativo/não-finito, como a API Zig; `progress` satura em 0..1 e `done`
  ignora loop.
* `zyntra_anim_lerp_color` interpola RGBA por canal com `t` saturado e
  arredondamento para o `u8` mais próximo.
* Erros ⇒ `ZYNTRA_INVALID_ARGUMENT`: ponteiros de saída nulos, `ease`
  desconhecido, tween/timer inválido (duração ≤ 0/não-finita, `from`/`to`
  não-finitos, `elapsed` não-finito) ou `out_*` nulo.

### Décimo quinto lote (M129): imagem RGBA8 e escala DPI

```c
const uint8_t pixels[16] = {255,0,0,255, 0,255,0,255,
                             0,0,255,255, 255,255,255,255};
zyntra_draw_image(ctx, (ZyntraRect){0, 0, 32, 32}, pixels, 2, 2, 8,
    (ZyntraColor){255, 255, 255, 255});
/* Sprite/atlas: recorta a região de origem (pixels inteiros). */
zyntra_draw_image_region(ctx, (ZyntraRect){0, 0, 16, 16}, pixels, 2, 2, 8,
    1, 0, 1, 1, (ZyntraColor){255, 255, 255, 255});
```

* Imagem RGBA8 não-premultiplicada, row-major: `pixels` é **emprestado**
  (não copiado) e precisa viver até o backend consumir o frame; `stride` é
  a distância em bytes entre linhas; `tint` modula RGBA (branco opaco =
  identidade). O backend de referência amostra com bilinear em alfa
  pré-multiplicado, respeitando clip e culling.
* `zyntra_draw_image_region` recorta na **origem** (região inteira de
  pixels) — o mesmo mecanismo de sprites e atlas de glifos.
* Escala DPI: `zyntra_context_set_scale(ctx, factor)` define pixels de
  dispositivo por pixel lógico (1 = 100%, 2 = 200%);
  `zyntra_context_get_scale` devolve o fator vigente;
  `zyntra_context_set_device_viewport` converte um rect de dispositivo
  para o viewport lógico. `zyntra_context_push_device_mouse_move`/
  `_mouse_button`/`_mouse_wheel` enfileiram entrada em pixels de
  dispositivo, convertida para pixels lógicos.
* Erros ⇒ `ZYNTRA_INVALID_ARGUMENT`: handle nulo, `pixels` nulo,
  `width`/`height` zero, `stride` menor que `width * 4`, região de
  origem fora da imagem, fator de escala não-finito/≤ 0, ponteiro de
  saída nulo e botão de mouse desconhecido.

### Décimo sexto lote (M130): composição de IME

```c
uint8_t pre[32];
ZyntraImeComposition comp = {pre, sizeof(pre), 0, 0, false, false};

/* Callback de IME da plataforma: */
zyntra_ime_update(&comp, "ni", 2, 2);  /* pré-edit + cursor */
zyntra_ime_commit(&comp);              /* texto confirmado */

/* No frame: o widget aplica o texto confirmado no buffer do campo. */
zyntra_widget_text_input_ime(ctx, id, bounds, buffer, sizeof(buffer), &len,
    &cursor, &anchor, &comp, 10.0f, &style, &result);
```

* `ZyntraImeComposition` guarda o pré-edit no buffer do CHAMADOR
  (`buf`/`cap`): a biblioteca não aloca. `len`/`cursor` descrevem o
  pré-edit, `active` marca a composição em andamento e `committed` o
  texto confirmado à espera de aplicação.
* `zyntra_ime_update` substitui o pré-edit e ajusta o cursor para uma
  fronteira de codepoint; `zyntra_ime_commit` confirma; `zyntra_ime_cancel`
  descarta. O texto é **emprestado** só durante a chamada.
* `zyntra_widget_text_input_ime` aplica o texto confirmado no buffer do
  campo (substituindo a seleção), desenha o pré-edit na posição do caret e
  mantém o caret dentro do pré-edit durante a composição. Sem foco, a
  composição é cancelada. `zyntra_widget_text_area_ime` faz o mesmo na
  área de texto multilinha (o pré-edit é desenhado na linha do caret).
* Erros ⇒ `ZYNTRA_INVALID_ARGUMENT`: composição nula, buffer/pré-edit
  nulos ou inconsistentes, pré-edit maior que o buffer, cursor fora do
  buffer; UTF-8 malformado ⇒ `ZYNTRA_INVALID_TEXT`.

### Fonte de bitmap global (M144)

```c
zyntra_context_set_bitmap_font(ctx, atlas, 10.0f); /* monoespaçado */
/* agora TODOS os widgets do contexto desenham o texto do atlas */
zyntra_context_clear_bitmap_font(ctx);
```

* O atlas precisa ser **monoespaçado** (todos os glifos com o mesmo
  avanço) e o avanço precisa bater com o das métricas do `size` usado
  pelos widgets — assim medido e desenhado nunca divergem.
* `zyntra_draw_text` e os widgets passam a emitir blits do atlas (o
  texto fica visível até no rasterizador de referência).
* Erros ⇒ `ZYNTRA_INVALID_ARGUMENT`: atlas nulo, `size` inválido, atlas
  proporcional ou avanço incompatível com o `size`.

### Alfa global (fade) nos draw commands

```c
zyntra_draw_alpha(ctx, 0.5f);              /* a partir daqui: atenuado */
zyntra_draw_rect_filled(ctx, rect, color);
zyntra_draw_alpha(ctx, 1.0f);              /* volta ao normal */
```

* `zyntra_draw_alpha` multiplica o alfa das cores desenhadas **depois**
  dele, até o próximo alfa ou o fim do frame. Fator 0 não desenha nada;
  valores acima de 1 contam como 1. É o gancho de animações (fade) sobre
  os widgets.
* Erros ⇒ `ZYNTRA_INVALID_ARGUMENT`: handle nulo ou fator não-finito/
  negativo.

### Décimo sétimo lote (M139): atlas de glifos (fonte real)

```c
ZyntraFontAtlas *atlas = NULL;
zyntra_font_atlas_create(16, 16, 1, &atlas);

uint32_t x = 0, y = 0;
zyntra_font_atlas_add_glyph(atlas, 'A', 5, 7, 5.0f, -7.0f, &x, &y);
/* O chamador rasteriza o glifo em (x, y) na própria imagem. */
zyntra_font_atlas_set_image(atlas, pixels, 16, 16, 16 * 4);

float w = 0;
zyntra_font_atlas_measure(atlas, "AB", 2, &w);   /* 8.0 (avanços reais) */
zyntra_widget_label_atlas(ctx, id, bounds, "AB", 2, color, atlas);
```

* O atlas é construído pelo CHAMADOR: `create` (dimensões + padding),
  `add_glyph` (devolve a região `x`/`y` onde rasterizar) e `set_image`
  (aponta a imagem RGBA8, **emprestada**, já rasterizada). A imagem precisa
  viver enquanto o atlas for usado; `destroy` fecha o ciclo.
* `advance`/`bearing_y` são em pixels **lógicos** (`bearing_y` negativo =
  o bitmap fica acima da linha de base). A medição usa os avanços reais
  (fonte proporcional), então o que se mede é o que se desenha.
* `zyntra_font_atlas_draw_run` desenha um trecho (cada glifo vira um blit
  da sua região — o texto fica visível até no rasterizador de referência,
  que não rasteriza glifos); `zyntra_widget_label_atlas` faz o mesmo
  posicionando pelo canto superior-esquerdo do rect.
* `zyntra_widget_text_input_atlas` e `zyntra_widget_text_area_atlas` são
  o campo e a área de texto com a mesma fonte: caret, seleção, clique e
  rolagem horizontal seguem os AVANÇOS REAIS dos glifos (fonte
  proporcional). A área de texto não faz quebra suave (as linhas visuais
  são as linhas lógicas).
* `zyntra_widget_text_block` desenha um parágrafo: quebra pela largura
  do rect e alinha as linhas (`align`: 0 = start, 1 = center, 2 = end);
  devolve `ZyntraTextBlockResult` (linhas + `truncated`).
* Erros ⇒ `ZYNTRA_INVALID_ARGUMENT`: atlas/ponteiros nulos, dimensões
  zero, `stride` menor que `width * 4`, codepoint fora de
  `0..0x10FFFF` (ou surrogate), avanço/medida inválidos, glifo
  duplicado, glifo que não cabe no atlas e ponteiros de saída nulos;
  UTF-8 malformado ⇒ `ZYNTRA_INVALID_TEXT`.

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
* M111: também travados `ZyntraKey` (enum `c_int`, 0..20, mesmos valores de
  `event.Key`) e as máscaras `ZYNTRA_MOD_*` (bits 0..3 de `Modifiers`).
* M112: também travados `ZyntraTextInputStyle=32` e os resultados
  `ZyntraTextInputResult=16`/`ZyntraTextAreaResult=16`.
* M110: também travados `ZyntraTreeItem=40`, estilo `TreeView=40` e
  resultado `TreeView=32`.
* M113: também travados `ZyntraDockGroup=10`, `ZyntraDockPaneInfo=28`,
  `ZyntraDockSplitInfo=40`, `ZyntraDockDrop=24`, `ZyntraDockViewResult=88` e
  `ZyntraDockStyle=36`; `ZyntraDockZone` é enum `c_int` (0..4, mesmos
  valores de `dock.DockZone`).
* M115: também travados os estilos `ZyntraSplitterStyle=20`,
  `ZyntraSpinnerStyle=20`, `ZyntraGroupBoxStyle=24`,
  `ZyntraTooltipStyle=20` e os resultados `ZyntraComboResult=2`,
  `ZyntraSplitterResult=8`, `ZyntraTooltipState=4`,
  `ZyntraTooltipResult=2`.
* M116: também travados os estilos `ZyntraScrollStyle=12`,
  `ZyntraPopupStyle=12`, `ZyntraModalStyle=20`, os resultados
  `ZyntraScrollResult=28`, `ZyntraPopupResult=2`, `ZyntraModalResult=3` e o
  `ZyntraModalDragState=8`.
* M117: também travados `ZyntraDragGhostStyle=48`, `ZyntraDndDrop=64`,
  `ZyntraDragGhostResult=36` e o enum `ZyntraDndAccept` (0..2, mesmos
  valores de `dnd.AcceptResult`).
* M118: também travados `ZyntraToolbar=32` e `ZyntraStatusBar=36` (estados
  de posicionamento do chamador).
* M119: também travados `ZyntraGraphStyle=68`, `ZyntraGraphNode=40`,
  `ZyntraGraphEdge=16`, `ZyntraGraphTransform=12`,
  `ZyntraGraphViewState=56`, `ZyntraGraphViewOptions=20` e
  `ZyntraGraphViewResult=48`.
* M120: também travados `ZyntraTimelineStyle=80`, `ZyntraTimelineKey=8`,
  `ZyntraTimelineTrack=32`, `ZyntraTimelineTransform=8`,
  `ZyntraTimelineViewState=64`, `ZyntraTimelineViewOptions=20`,
  `ZyntraTimelineViewResult=64` e o enum `ZyntraTimelineDragMode` (0..3,
  mesmos valores de `timeline_view.TimelineDragMode`).
* M121: também travados `ZyntraInspectorStyle=72`,
  `ZyntraInspectorRange=8`, `ZyntraInspectorChoice=24`,
  `ZyntraInspectorProperty=88`, `ZyntraInspectorViewState=32`,
  `ZyntraInspectorViewOptions=20`, `ZyntraInspectorViewResult=48` e o enum
  `ZyntraInspectorKind` (0..4, mesmos valores de `inspector.Kind`).
* M122: também travados `ZyntraTween=16`, `ZyntraAnimTimer=12` e o enum
  `ZyntraEase` (0..6, mesmos valores de `anim.Ease`).
* M129: sem novos structs — a imagem e a escala DPI usam só parâmetros
  escalares e o buffer do chamador (nenhuma trava de layout nova).
* M130: travado `ZyntraImeComposition=40` (ponteiro + 3 `size_t` + 2
  `bool`, alinhamento 8).
* M139: handle opaco `ZyntraFontAtlas` (sem layout exposto) — nenhuma
  trava de layout nova.
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
/tmp/opencode/zyntra-c-test        # esperado: "C-ABI OK ..." + "C-ABI modern ..." + "C-ABI pixels ..." + "C-ABI widgets ..." + "C-ABI lists ..." + "C-ABI rich ..." + "C-ABI tree ..." + "C-ABI keys ..." + "C-ABI text ..." + "C-ABI dock ..." + "C-ABI widgets2 ..." + "C-ABI containers ..." + "C-ABI dnd ..." + "C-ABI bars ..." + "C-ABI graph ..." + "C-ABI timeline ..." + "C-ABI inspector ..." + "C-ABI anim ..." + "C-ABI imagem ..." + "C-ABI ime ..." + "C-ABI atlas ..."
```
