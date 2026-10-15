# Changelog

Todas as mudanças notáveis deste projeto serão documentadas aqui, no formato
[Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/) + [SemVer 2.0.0](https://semver.org/lang/pt-BR/).

## [Não lançado]

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
