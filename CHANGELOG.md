# Changelog

Todas as mudanças notáveis deste projeto serão documentadas aqui, no formato
[Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/) + [SemVer 2.0.0](https://semver.org/lang/pt-BR/).

## [Não lançado]

## [1.11.0] - 2026-10-15

Décima primeira MINOR estável, 100% compatível: entrada e verificação.

- Teclado: scroll (M31), `Ctrl+A` (M32), apagar por palavra (M34).
- `widgets/combo` por composição e `labelWrapped` multilinha (M36+M37).
- Verificação: fuzz no layout (M33), bench do raster + blending (M35+M38).
- 76/76 testes, integração C, CI verde.


## [1.10.0] - 2026-10-15

Décima MINOR estável, 100% compatível: teclado nos widgets.

- Button/checkbox focáveis + ativação (M29); slider com setas (M30).
- 69/69 testes, integração C, CI verde.

## [1.9.1] - 2026-10-15

PATCH estável, 100% compatível: endurecimento do rasterizador.

### Corrigido/Endurecido — Milestone 28 (raster, compatível)
- Fuzz nos primitivos do rasterizador + teste determinístico NaN/Inf
  que ABORTAVA (`integer part of floating point value out of bounds`):
  `fillRect/strokeLine/fillCircle/strokeRect` saturam entradas
  não-finitas em no-op. Comportamento inalterado para entradas válidas
  (`render` já validava); só chamadas diretas degeneradas mudam
  (panic → no-op documentado).

## [1.9.0] - 2026-10-15

Nona MINOR estável, 100% compatível: tooltip + modal.

- `widgets/tooltip` com delay por frames (M26).
- `widgets/modal` com dismiss (M27).
- 64/64 testes, integração C, CI verde.

## [1.8.0] - 2026-10-15

Oitava MINOR estável, 100% compatível: teclado na cascata + radio.

- `widgets/menu` com foco atravessando níveis (M24).
- `widgets/radio` com seleção exclusiva (M25).
- 62/62 testes, integração C, CI verde.


## [1.7.0] - 2026-10-15

Sétima MINOR estável, 100% compatível: cascata de menus.

- `widgets/menu` aninhável (M23): `menuNested`, `hovered_index`, helpers.
- 60/60 testes, integração C, CI verde.


## [1.6.0] - 2026-10-15

Sexta MINOR estável, 100% compatível: endurecimento + menu.

- Fuzz em decode/wrap + guarda u32 (M21).
- `widgets/menu` flat com teclado (M22).
- 59/59 testes, integração C, CI verde.

## [1.5.0] - 2026-10-15

Quinta MINOR estável, 100% compatível: edição de texto completa.

- `textInputHistory` (M19): undo/redo com `TextHistory(S,B)` do chamador.
- `textInputClipboard` (M20): `Ctrl+C/X/V` internos com undo integrado.
- 55/55 testes, integração C, CI verde.

## [1.4.0] - 2026-10-15

Quarta MINOR estável, 100% compatível: popup flutuante + progresso.

- `widgets/popup` (M18): painel + clip, dismiss em press fora.
- `widgets/progress` (M18): display 0..1, 3 draws.
- 53/53 testes, integração C, CI verde.

## [1.3.0] - 2026-10-15

Terceira MINOR estável, 100% compatível: scroll completo.

- `widgets/scroll` (M16+M17): wheel, clip, scrollbar, drag no thumb.
- 51/51 testes, integração C, CI verde.

## [1.2.0] - 2026-10-15

Segunda MINOR estável, 100% compatível: rasterizador de referência +
quebra de linha para text-runs.

- `software/raster` (M14): framebuffer RGBA8, clip/cull, PPM sem deps.
- `text/wrap` (M15): `wrapLines`/`countLines` puros para backends.
- 49/49 testes, integração C, CI verde.

## [1.1.0] - 2026-10-15

Primeira MINOR estável: história de teclado completa no text-input, 100%
compatível com a 1.0.0 (só adições + campo com default).

- Travessia de foco por Tab/Shift+Tab (M12).
- Seleção de texto com âncora do chamador (M13); 1.0.0 intacta.
- 43/43 testes, integração C, CI verde, benchmarks mantidos.

### Alterado — Milestone 7 (beta prep: ativação por release + CI)
- `core/context`: estado de mouse retido (`mouse_pos`, `mouse_down_left`,
  atualizados em `pushEvent`, nunca limpos por `beginFrame`), captura
  exclusiva de press (`press_owner` + `clearPressCapture`).
- `widgets/button`, `widgets/checkbox`: release-to-activate (press captura,
  click/toggle só em release dentro; release fora cancela).
- `widgets/input`: `FrameMouse` (press/release do frame, sem âncora).
- Exemplo em 2 frames (press → release) provando captura entre frames.
- CI (`.github/workflows/ci.yml`, actions pinadas por SHA): fmt, testes
  Debug+ReleaseFast, build, exemplo, integração C e smoke do bench.
  Correção real vinda do CI: `std.debug.print` escreve em stderr, então o
  smoke do bench funde stderr (`2>&1`) antes do `grep`.
- Docs: licença MIT no README (antes negava existência); branch `master`
  residual removido; logo mantido fora do git (binário não referenciado).
- Compatibilidade: `Context` ganha 3 campos + 1 método (aditivo);
  **mudança de comportamento**: botão/checkbox ativam no release, não no press.

### Adicionado — Milestone 8 (slider com drag)
- `widgets/slider`: `slider(ctx,id,bounds,value,min,max,style)` — estado
  `*f32` do chamador, press captura, valor segue o mouse X clampado
  (drag continua fora da trilha), release encerra, `changed`/`dragging`.
  Desenho em 4 comandos (trilha, preenchimento, handle, outline).
- `style/style`: `SliderStyle` + `Theme.sliderStyle()` validados.
- Exemplo com drag em 2 frames; resto aditivo.

## [1.0.0] - 2026-10-15

Primeira versão estável: API pública congelada (incompatibilidades exigem
MAJOR). Revisão final sem mudanças de código desde a rc.1 — só versão,
README e changelog. 40/40 testes, integração C, CI verde, benchmarks.

## [1.0.0-rc.1] - 2026-10-15

Release candidate: API em congelamento (só bugfixes até a 1.0.0).
README com status real, arquitetura atual e getting-started verificado
(snippet compilado contra a tag). CI verde.

## [1.0.0-beta.2] - 2026-10-14

Terceira pré-release: caret navegável no text-input (`Key` com
delete/home/end; quebra de assinatura da M10 documentada). CI verde.

## [1.0.0-beta.1] - 2026-10-14

Segunda pré-release: API estabilizando, 5 widgets interativos, CI verde em
Debug+ReleaseFast. Ainda instável até a rc.

### Removido
- `widgets/input.MouseScan` (código morto desde a M7; `FrameMouse` cobre
  todos os widgets; nunca foi re-exportado publicamente).

### Compatibilidade
- Remoção interna apenas; API pública intacta fora os acréscimos das M7–M9.

## [1.0.0-alpha.1] - 2026-10-14

Primeiro pré-lançamento: núcleo validado de ponta a ponta em Zig 0.17.0,
sem renderer próprio (contrato com backend externo) e sem estado global.
Pré-release instável: API pode mudar até a beta.

### Desempenho (medido — ver docs/BENCHMARKS.md)
- Pipeline de 1,1M comandos: ~17 ns/comando (`ReleaseFast`), ~257 ns (`Debug`).
- Step `run-bench` + `examples/bench.zig` reproduzíveis.

### Adicionado — Milestone 1 (fundação)
- `build.zig` / `build.zig.zon` funcionais no Zig 0.17.0 (`zyntra_ui` como módulo + lib estática).
- API pública mínima em `src/root.zig` (`Context`, `Rect`, `Vec2`, `Color`, `Id`).
- `core/types`: `Vec2`, `Size`, `Rect.contains`, `Color pack/unpack` (`extern struct`, prontos para C-ABI).
- `core/id`: `Id` estável via FNV-1a 64 + derivação `child`.
- `core/context`: `Context` com `init/deinit/beginFrame/endFrame/setViewport`, validação sem alocação.
- Exemplo `examples/minimal.zig` + step `run-example`.
- Testes unitários para tipos, ids e contexto.

### Adicionado — Milestone 2 (eventos + draw)
- `event/event`: `Event` normalizado (`mouse_move/button/wheel`, `key`, `text` validado, `resize`, `focus`, `quit`), `MouseButton`/`Key`/`Modifiers` com tags explícitas, `EventQueue` com `push` validante + `clearRetainingCapacity`.
- `draw/commands`: `DrawCommand` (`clear`, `rect_filled/outline`, `line`, `circle_filled`, `clip`) com `isValid` anti-NaN/anti-negativo, `DrawList` com helpers + retenção de capacidade, renderer-independente.
- `core/context`: integra `events` + `draw` (init sem alloc, `deinit` libera, `beginFrame` limpa, `pushEvent`/`pendingEvents`/`drawCommands`).
- `examples/minimal.zig`: simula hover/click via eventos e emite 2 comandos; valida limpeza no frame 2.
- Compatibilidade: API M1 preservada (só adições; `Context` ganha 2 campos + 3 métodos).

### Adicionado — Milestone 3 (layout + estilo + widgets)
- `layout/layout`: `Constraints.constrain`, `EdgeInsets.apply` (nunca negativo), `StackPlacer` vertical/horizontal sem alocação + `centered`.
- `style/style`: `Theme.darkDefault/lightDefault`, `ButtonStyle`/`CheckboxStyle` derivados com `isValid`.
- `widgets/input`: `MouseScan` interno (última posição + press-inside esquerdo).
- `widgets/button`: `button(ctx,id,bounds,style)` press-to-activate (limitação documentada; release-to-activate em M4), 2 draws, exige `id` não-nulo.
- `widgets/checkbox`: estado `*bool` do chamador, toggle por press-inside, 2-3 draws.
- Exemplo M3: `EdgeInsets` + `StackPlacer` + botão/checkbox interativos em 2 frames.
- Compatibilidade: só adições sobre M1/M2, sem breaking.

### Adicionado — Milestone 4 (texto + renderer externo)
- `text/metrics`: decodificador UTF-8 próprio (RFC 3629, sem alloc), `FontMetrics.withSize/lineHeight`, `measure` (multilinha), `truncateToWidth` em fronteira UTF-8.
- `draw/renderer`: contrato de backend externo — `cull` puro, `NullRenderer` test-double (valida + conta), `Backend` via vtable (`submit`/`name`); a ZyntraUI empresta `cmds`, GPU pertence ao backend. Sem renderer próprio.
- `widgets/label`: mede sem emitir draws (rasterização é do backend); `debug_draw` emite 1 outline; detecta `truncated` vs `bounds`.
- Exemplo M4: label medido + `NullRenderer.submit` com stats + frame de culling.
- Compatibilidade: só adições; `DrawCommand` inalterado (sem nova variante).

### Adicionado — Milestone 5 (C-ABI + consumidor C)
- `c-abi/types`: `ZyntraResult` (`c_int`, 0=ok), `ZyntraVec2/Size/Rect/Color` (`extern`, tamanhos travados por `@compileError`).
- `c-abi/api`: handle opaco `ZyntraContext*` (ownership: `create` aloca no `page_allocator` interno, `destroy` exatamente uma vez, null-safe), `export ... callconv(.c)` para versão, ciclo de frame, viewport, eventos (mouse_move/button/quit), draws e contagens. Nulos nunca crasham; sem slices/strings na fronteira.
- `c-abi/zyntra.h`: header C espelhado com `_Static_assert` de ABI.
- `tests/c/test_c_abi.c`: consumidor C real (integração validada via `zig cc` + lib estática).
- `docs/C_ABI.md`: ownership, erros, handles, compatibilidade e comando de teste.
- Build: `src/root.zig` referencia `c_abi.api` em bloco `comptime` — sem
  isso o Zig 0.17.0 nem analisa `api.zig` na lib estática e os símbolos C
  somem do `.a` (comportamento verificado por experimento).
- Compatibilidade Zig: só adições (`c_abi` + 3 re-exportações).

### Adicionado — Milestone 6 (text-runs + texto na fronteira C)
- `draw/commands`: variante `.text` (`pos/color/size/width/start/len` em `extern struct`), arena `text_bytes` com offsets `u32` (estáveis sob realocação), `pushText` (copia + valida UTF-8 no push), `textOf` defensivo. `DrawList` continua sem expor layout (handle opaco no C).
- `draw/renderer`: `commandBounds` para texto (largura medida + altura ~= size).
- `widgets/label`: agora emite 1 comando `.text` (era 0 draws; +1 outline com debug).
- `c-abi`: `ZYNTRA_INVALID_TEXT=6`, `zyntra_draw_text` (cópia imediata, NULL válido com len 0).
- Testes C (Zig + consumidor real) cobrindo cópia, UTF-8 inválido e nulos.
- Compatibilidade: variante nova em `DrawCommand` (switches exaustivos externos precisam de braço `.text`); resto aditivo.

### Adicionado — Milestone 9 (text-input com foco)
- `core/context`: foco de teclado (`focus_owner`, `hasFocus`, `clearFocus`,
  retido entre frames como o mouse).
- `widgets/text_input`: buffer `[]u8` + `len` do chamador (zero alloc),
  click foca, `.text` anexa (encode próprio), backspace multibyte-safe,
  `Enter` submete, `Escape` desfoca, overflow sinalizado sem corromper.
  Caret no fim; sem caret navegável/seleção/Tab (documentado, M10+).
- `style/style`: `TextInputStyle` + `Theme.textInputStyle()`.
- Desenho: caixa com destaque de foco + texto + caret.
- Compatibilidade: `Context` +1 campo e +2 métodos (aditivo).

### Alterado — Milestone 10 (caret navegável; quebra em beta)
- `widgets/text_input`: novo parâmetro `cursor: *usize` (offset de byte,
  sempre fronteira UTF-8); setas movem por codepoint, `Home`/`End` saltam,
  digitação insere no cursor (memmove), backspace/`Delete` apagam ao redor
  do cursor. Caret desenhada na posição do cursor.
- `event/event`: `Key` ganha `delete`, `home`, `end` (enum já tinha `_`).
- Quebra intencional de pré-release: assinatura de `textInput` mudou
  (chamadas antigas não compilam — migração: adicionar `&cursor`).

### Adicionado — Milestone 11 (animações)
- `anim/anim`: `Ease` (7 curvas, saturação documentada), `Tween`
  (`from/to/duration/ease`, `valueAt`, `doneAt`), `AnimTimer`
  (`tick/progress/done/reset`, loop com `@mod`), `lerpColor` por canal.
  Puro, sem alloc, sem estado global; re-exportado (`Ease/Tween/AnimTimer`).
- Exemplo amostra fade quad_out em 4 passos.
- Compatibilidade: só adições.

### Adicionado — Milestone 12 (travessia de foco por Tab)
- `core/context`: registro de focáveis (`registerFocusable`, dedupe O(n),
  reconstruído por frame), `FocusDirection`, `requestFocusAdvance` +
  aplicação no `beginFrame` sobre o registro completo do frame anterior.
- `widgets/text_input`: registra-se todo frame; `Tab`/`Shift+Tab` circulam
  sem virar texto. Fecha o gap documentado desde a M9.
- Exemplo com 2 campos + Tab; resto aditivo (rumo à 1.1.0).

### Adicionado — Milestone 13 (seleção de texto, compatível)
- `widgets/text_input`: `textInputSelected` (novo, 1.0.0 intacto por
  delegação) com `anchor: *usize` do chamador; `Shift`+navegação estende,
  digitar/backspace/`Delete` substituem a faixa, highlight sob o texto.
- `style/style`: `TextInputStyle.selection` COM default (literais antigos
  compilam); `TextInputResult.selected` (só leitura, aditivo).
- Exemplo seleciona tudo + substitui; resto aditivo (rumo à 1.1.0).

### Adicionado — Milestone 14 (rasterizador de referência, compatível)
- `software/raster`: framebuffer RGBA8 + `render` (fill/stroke/clip/cull,
  texto pulado E contado), `encodePpm` (P6 sem deps), sem blending e sem
  glifos — documentado como ferramenta de verificação, não produção.
- Asserts pixel-exatos (rect/clip/linha/círculo/PPM); exemplo rasteriza e
  imprime checksum; resto aditivo (rumo à 1.2.0).

### Adicionado — Milestone 15 (quebra de linha, compatível)
- `text/wrap`: `wrapLines`/`countLines` gananciosos e puros (palavras,
  `'\n'` força, parágrafo vazio gera linha vazia, palavra longa fatia
  por codepoints, UTF-8 validado, `NoSpaceLeft` em `out` curto).
  `LineRange` em offsets `u32` (convenção de `DrawCommand.text`).
- Resto aditivo (rumo à 1.2.0).

### Adicionado — Milestone 16 (scroll container, compatível)
- `widgets/scroll`: `beginScroll`/`endScroll` — `mouse_wheel` com hover,
  offset `*f32` do chamador clampado, `clip` emitido para os filhos,
  scrollbar proporcional no `endScroll` (só com overflow). Primeiro
  consumidor de `mouse_wheel` e `DrawCommand.clip`.
- `style/style`: `ScrollStyle` + `Theme.scrollStyle()`.
- Exemplo com wheel → offset 96; resto aditivo (rumo à 1.3.0).

### Alterado — Milestone 17 (drag no thumb, compatível)
- `widgets/scroll`: press no thumb captura (`press_owner`), arrasto
  posiciona absoluto (pulo, não relativo), release encerra; geometria do
  thumb partilhada entre hit-test e desenho (`thumbRect`); wheel segue
  quando sem drag. `ScrollResult.dragging`. Resto aditivo (rumo à 1.3.0).
### Adicionado — Milestone 18 (popup + progresso, compatível)
- `widgets/popup`: `beginPopup`/`endPopup` — painel + clip, dismiss em
  press esquerdo fora (botão direito não dispensa); `Escape` não dispensa
  (documentado, do text-input). Estado aberto/fechado no chamador.
- `widgets/progress`: display puro 0..1 clampado (NaN rejeitado), 3 draws.
- `style/style`: `PopupStyle`/`ProgressStyle` + derivados do tema.
- Exemplo dispensa popup fora + progresso 75%; resto aditivo (1.4.0).

### Adicionado — Milestone 19 (undo/redo, compatível)
- `widgets/text_input`: `TextHistory(S,B)` genérico (pilhas de snapshots
  em buffers do chamador, rajadas de digitação agrupam, redo esvazia em
  nova mutação) + `textInputHistory(S,B,...)` (`Ctrl+Z`/`Ctrl+Y`/
  `Ctrl+Shift+Z`, flags `undone`/`redone`); `textInput*` antigos intactos.
- `event/event`: `Key` ganha `y` (enum já tinha `_`, aditivo).
- Exemplo desfaz/refaz; resto aditivo (rumo à 1.5.0).

### Adicionado — Milestone 20 (copiar/colar interno, compatível)
- `widgets/text_input`: `Clipboard` (buf+len do chamador, tudo-ou-nada)
  + `textInputClipboard(S,B,...)` — `Ctrl+C/X/V` com undo integrado
  (recortar/colar = passos desfazíveis); legados intactos.
- Exemplo copia/recorta/cola; resto aditivo (rumo à 1.5.0).

### Adicionado — Milestone 21 (fuzz + endurecimento, compatível)
- `text/wrap`: 2 testes fuzz via `std.testing.fuzz` (decode: faixas e
  coerência de len; wrap/measure: faixas contidas, contagens iguais) —
  verdes no CI (Debug com safety).
- Guarda `text.len > u32` em `layout` (offsets `LineRange`/`DrawCommand`
  não endereçam além de 4 GiB; por inspeção, sem alloc de 4 GiB).
- Resto aditivo.

### Adicionado — Milestone 22 (menu dropdown, compatível)
- `widgets/menu`: painel + clip, `active: *usize` unificando hover e
  teclado (setas pulam desabilitados com wrap, `Home`/`End`), click ou
  `Enter` escolhe (one-shot), press fora/`Escape` dispensa. Flat, sem
  cascata (documentado). Itens UTF-8 validados no push.
- `style/style`: `MenuStyle` + `Theme.menuStyle()`.
- Exemplo escolhe item 1; resto aditivo (rumo à 1.6.0).

### Adicionado — Milestone 23 (cascata mouse-driven, compatível)
- `widgets/menu`: `MenuChild` + `menuNested` (press no filho não dispensa
  o pai), `hovered_index` no resultado, `menuRowRect`/`submenuBounds`
  partilhando a geometria; teclado segue por nível (documentado).
- Exemplo com cascata de 2 níveis; resto aditivo (rumo à 1.7.0).

### Adicionado — Milestone 24 (teclado entre níveis, compatível)
- `widgets/menu`: `Right` com foco move ao filho (`MenuChild.id`);
  `Left` no filho pede o pai (`MenuResult.focus_parent`, chamador refoca).
  Um nível por vez; resto aditivo (acumula p/ 1.8.0).

### Adicionado — Milestone 25 (radio group, compatível)
- `widgets/radio`: seleção exclusiva com `selected: *usize` do chamador,
  click seleciona, setas/Home/End com foco movem e selecionam (wrap),
  registra foco para o Tab; sem opções desabilitadas (documentado).
- `style/style`: `RadioStyle` + `Theme.radioStyle()`.
- Exemplo clica Blue + seta; resto aditivo (rumo à 1.8.0).

### Adicionado — Milestone 26 (tooltip, compatível)
- `widgets/tooltip`: hover contado em frames (sem relógio), `delay 0`
  imediato, saída zera, caixa clampada ao viewport, estado `TooltipState`
  do chamador saturado.
- `style/style`: `TooltipStyle` + `Theme.tooltipStyle()`.
- Exemplo visível no 2º frame; resto aditivo (rumo à 1.9.0).

### Adicionado — Milestone 27 (modal, compatível)
- `widgets/modal`: `beginModal`/`endModal` — dim na vista + painel +
  clip; dismiss fora ou com `Escape`. Bloqueio por convenção (fundo não
  sondado com modal aberto; sem flag global, sem invasão).
- `style/style`: `ModalStyle` + `Theme.modalStyle()`.
- Exemplo bloqueia botão e dispensa com Escape; resto aditivo (1.9.0).

### Adicionado — Milestone 29 (teclado em button/checkbox, compatível)
- `widgets/button`: focável (click foca, Tab circula); Espaço/Enter com
  foco clicam (sem visual de segurado); `Ctrl`+tecla ignorado.
- `widgets/checkbox`: idem; Espaço alterna, Enter ignorado.
- Exemplo com Espaço; resto aditivo (acumula p/ 1.10.0).

### Adicionado — Milestone 30 (teclado no slider, compatível)
- `widgets/slider`: focável (click foca, Tab circula); setas ajustam em
  `(max-min)/20`, `Home`/`End` saltam, tudo clampado. Drag segue só mouse.
- Exemplo com Right; resto aditivo (acumula p/ 1.10.0).

### Adicionado — Milestone 31 (teclado no scroll, compatível)
- `widgets/scroll`: focável (click foca, Tab circula; filhos refocam);
  `PageUp`/`PageDown` = ±vista, `Home`/`End` = extremos, clampados.
- `event/event`: `Key` ganha `page_up`/`page_down` (enum com `_`).
- Exemplo com PageDown; resto aditivo (acumula p/ próxima MINOR).

### Adicionado — Milestone 32 (Ctrl+A, compatível)
- `widgets/text_input`: `Ctrl+A` seleciona tudo (só com âncora; sem
  âncora não há onde representar). Sem mutação, fora do histórico.
- Exemplo + teste; resto aditivo (acumula p/ próxima MINOR).

### Adicionado — Milestone 33 (fuzz no layout, compatível)
- `layout/layout`: fuzz com bits arbitrários (invariantes em entradas
  finitas: inset nunca negativo, cursor avança, clamp respeitado;
  sem crash com NaN/Inf — só matemática f32, sem conversão p/ int).
- Resto aditivo (acumula p/ próxima MINOR).

### Adicionado — Milestone 34 (Ctrl+Backspace/Delete, compatível)
- `widgets/text_input`: `Ctrl+Backspace` apaga a palavra anterior,
  `Ctrl+Delete` a próxima (só `' '` separa; multibyte-safe); com seleção,
  vale a faixa; passos isolados no undo; no-op seguro nos limites.
- Exemplo + teste; resto aditivo (acumula p/ próxima MINOR).

### Adicionado — Milestone 35 (bench do raster, compatível)
- `examples/bench`: fase 2 rasteriza 50× a draw list retida em fb
  800×600 (checksum anti-DCE); `docs/BENCHMARKS.md` com números medidos
  (~9,1 ms/render ReleaseFast, ~129 ms Debug).
- Correção metodológica real: sem `clear()`, pxsum divergia entre modos
  (lixo do alocador, `0xAA` em Debug); com `clear`, idêntico (6/6).
  Framebuffer sem limpar = conteúdo indefinido (documentado).
- Fuzz permanente nos primitivos do raster; resto aditivo.

### Adicionado — Milestone 36 (combobox, compatível)
- `widgets/combo`: campo + dropdown por composição (`button` + `menu`,
  id filho via `Id.child(1)`); abre no click e foca o menu; escolha
  fecha, fora/`Escape` fecha sem mudar; chevron em 2 linhas; itens na
  pilha (teto 256, zero alloc).
- Exemplo abre e escolhe item 1 (após soltar captura do scroll, como
  app real); resto aditivo (acumula p/ 1.11.0).

### Adicionado — Milestone 37 (label multilinha, compatível)
- `widgets/label.labelWrapped`: fatia com `text/wrap` em `bounds.w`,
  1 comando por linha não-vazia (máx. 64, trunca), `bounds.w == 0`
  rejeitado; `label` clássico intacto.
- Exemplo com 3 linhas; resto aditivo (acumula p/ 1.11.0).

### Adicionado — Milestone 38 (blending, compatível)
- `software/raster`: source-over com arredondamento em `set()`; opaco
  e transparente preservam o comportamento exato legado (fast paths).
- Resto aditivo (acumula p/ próxima MINOR).

### Adicionado — Milestone 39 (modal arrastável, compatível)
- `widgets/modal`: `beginModalDraggable` (faixa de título captura,
  grab preservado em `ModalDragState` do chamador, clamp ao viewport,
  release encerra); `beginModal` clássico delega sem mudar; `dragging`.
- Exemplo arrasta (290,290); resto aditivo (acumula p/ próxima MINOR).

### Adicionado — Milestone 40 (combo pelo teclado, compatível)
- `widgets/combo`: setas com foco abrem direto no menu focado
  (Espaço/Enter já vinham do button); sem foco, ignoradas.
- Resto aditivo (acumula p/ próxima MINOR).

### Adicionado — Milestone 41 (separadores no menu, compatível)
- `widgets/menu`: `MenuItem.separator` (default false; literais antigos
  compilam) desenha linha divisória sem hover/escolha; teclado pula;
  mapeamento 1:1 linha↔item preservado.
- Resto aditivo (acumula p/ próxima MINOR).

### Adicionado — Milestone 42 (rolagem no input, compatível)
- `widgets/text_input`: texto além da área útil desloca para o caret
  (derivado, sem estado) com clip pareado só no overflow; highlight e
  caret acompanham o offset.
- Resto aditivo (acumula p/ próxima MINOR).

### Adicionado — Milestone 43 (posicionamento de popup, compatível)
- `widgets/popup.popupPlace`: abaixo da âncora, vira p/ cima se
  estourar, prende na horizontal; NaN/negativos saturam sem crash.
- Resto aditivo (acumula p/ próxima MINOR).

### Adicionado — Milestone 44 (versão na C-ABI, compatível)
- `c-abi`: `zyntra_version_prerelease()` (estático, sem free);
  `version_prerelease` agora `[:0]const u8` (literais já sentinela).
- Teste de consistência Zig↔C (major/minor/patch + prerelease);
  C fixa major==1 (quebra alto em MAJOR, de propósito).
- Resto aditivo (acumula p/ próxima MINOR).

### Adicionado — Milestone 45 (seleção por mouse, compatível)
- `widgets/text_input`: click posiciona o caret (captura o press),
  arrasto estende a seleção, release solta; só com atividade de mouse
  fresca no frame (posição retida sozinha não move); vale nas 3 variantes.
- Helpers `offsetAt`/`visibleOffset` (o segundo reutilizado no desenho).
- Resto aditivo (acumula p/ próxima MINOR).

### Adicionado — Milestone 46 (cobertura de caminhos, compatível)
- Testes p/ 3 caminhos sem cobertura: deslocamento do anel de undo
  (`TextHistory(2)` + 4 rajadas), menu todo-desabilitado (nunca escolhe)
  e `StackPlacer` horizontal (avanço + clamp).
- Sem mudança de comportamento; resto aditivo (acumula p/ MINOR).

### Corrigido — Milestone 47 (culling unificado, compatível)
- Auditoria achou fórmulas de bounds divergentes p/ linhas entre
  `render` (t/2 p/ lado) e `cull` (t p/ lado): `render` agora usa a
  fonte canônica `draw/renderer.commandBounds`; duplicata removida.
- Teste de concordância na fronteira (linha y=101/t=2: culled nos
  dois caminhos + pixel intacto). Comportamento válido inalterado.
