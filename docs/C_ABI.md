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
/tmp/opencode/zyntra-c-test        # esperado: "C-ABI OK ..." + "C-ABI modern ..." + "C-ABI pixels ..." + "C-ABI widgets ..."
```
