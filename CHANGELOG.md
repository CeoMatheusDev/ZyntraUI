# Changelog

Todas as mudanças notáveis deste projeto serão documentadas aqui, no formato
[Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/) + [SemVer 2.0.0](https://semver.org/lang/pt-BR/).

## [Não lançado]

### Adicionado

- `examples/app.zig` + `zig build run-app` (M69): mini-app de tarefas
  integrando Toolbar + TabBar + Table + StatusBar (com button/label/
  separator) em frames compartilhados, com estado todo no chamador.
  Demonstra adicionar via toolbar, filtrar por aba, selecionar linha,
  alternar estado, filtro vazio com placeholder (sem tabela vazia) e
  resumo na statusbar. Só APIs públicas, sem framework de aplicação,
  sem renderer/GPU, sem dependências novas.
- Guarda de integração do consumidor (M70): teste
  `README fetch usa a tag da versão do pacote` — o tarball do
  `zig fetch` documentado no README deve apontar exatamente para a tag
  de `build.zig.zon` (falha ruidosamente em deriva; `README.md`
  declarado como entrada do passo de teste para invalidar o cache).
  README `Getting started` mostra a fiação do módulo no `build.zig`
  do consumidor (`b.dependency` + `addImport`), verificada de verdade
  contra o tarball publicado.
- `widgets/groupbox` (M73): caixa agrupadora com título (display puro,
  sem `id`/estado). Desenha fundo + borda segmentada no topo
  flanqueando o título + texto; devolve o rect de conteúdo para os
  filhos (padrão de toolbar/statusbar). Degradações documentadas
  (sem título/largo demais/borda/fundo). `GroupBoxStyle` +
  `Theme.groupBoxStyle()`; `groupBoxContentRect` puro.
- `widgets/menu`: endurecimento de contratos (sem mudar API válida) —
  `bounds` não-finitos agora retornam `InvalidArgument` na entrada;
  cobertura nova: tecla `End`, normalização do ativo, item único,
  área menor que uma linha com clip, teto de 4096 itens.
- `widgets/slider`: endurecimento de contratos (sem mudar API válida) —
  `bounds` não-finitos agora retornam `InvalidArgument` na entrada
  (horizontal e vertical); cobertura nova: valor inicial fora da faixa,
  drag em posição finita extrema, faixa minúscula, estilo inválido.
- `widgets/combo`: endurecimento de contratos (sem mudar API válida) —
  `bounds` não-finitos agora retornam `InvalidArgument` na entrada
  (antes caía em erro interno no desenho); cobertura nova: Escape
  fecha sem mudar, mesma escolha fecha sem `changed`, teto de
  256 opções.
- `widgets/list_view` (M78): correção real de robustez (sem mudar
  API válida) — `bounds`/`scroll_offset` não-finitos agora retornam
  `InvalidArgument` na entrada; antes, `bounds.h` infinito/NaN
  alcançava a conversão float→int do layout, caminho numericamente
  ilegal (distinto das trocas de variante de erro de M74/M75/M77);
  cobertura nova: scroll e wheel nos limites.
- `widgets/tooltip` (M79): `anchor` não-finita agora retorna
  `InvalidArgument` na entrada; cobertura nova da máquina de estado:
  texto malformado sem comando parcial, contador pré-saturado sem
  wrap, caixa clampada ao viewport.
- `widgets/radio` (M80): `bounds` não-finitos agora retornam
  `InvalidArgument` na entrada; cobertura nova: tecla `End`, teto de
  256 opções, estilo inválido.
- `widgets/splitter` (M81): correção real de robustez (sem mudar API
  válida) — `bounds` não-finitos agora retornam `InvalidArgument` na
  entrada; antes, `splitterClampPos` com `lo`/`hi` NaN violava a
  asserção interna de `std.math.clamp` (`lower <= upper`) e abortava;
  cobertura nova: orientação vertical, clamp de `pos`, teclado.
- `widgets/text_input` (M82): `bounds` não-finitos agora retornam
  `InvalidArgument` na entrada única (`textInputInner`, cobre as 4
  variantes); restante do editor já era fail-closed (toda falha de
  medida/decodificação UTF-8 mapeada); cobertura nova sem duplicar.
- `widgets/modal` (M83): `bounds` não-finitos agora retornam
  `InvalidArgument` na entrada única (`beginModalInner`, cobre as 3
  variantes); cobertura nova: drag extremo clampa no viewport sem
  corromper o painel do chamador.
- `widgets/tab_bar` (M84): teto explícito de 32 abas (`InvalidArgument`
  em vez de truncamento silencioso que o teclado atravessava além do
  desenhado) e `bounds` não-finitos rejeitados; cobertura nova:
  bordas do teclado, aba única, hover sem selecionar.
- `widgets/popup` (M85): `bounds` não-finitos agora retornam
  `InvalidArgument` na entrada; cobertura nova: borda exclusiva do
  painel, estilo inválido, sem draws em rejeição.
- Uniformidade de validação de geometria (M86): `bounds` não-finitos
  agora retornam `InvalidArgument` na entrada dos pontos restantes
  (`button`, `checkbox`, `scroll`, `progress`, `switch`, `statusbar`,
  `toolbar`, `separator`/`separatorLabeled`, `textarea`) — todos
  auditados como livres de conversão numérica ilegal (pior caso era
  erro interno no desenho); 9 testes novos, cada checagem provada
  load-bearing (só o teste correspondente falha sem ela).
- `README.md` reescrito (M76): estrutura profissional (princípios,
  tabela dos 25 widgets públicos, arquitetura, exemplos, versionamento)
  sem inventar APIs; mesma tag de fetch e instruções verificadas.

## [1.21.1] - 2026-10-16

PATCH estável, 100% compatível: correções de comportamento inválido.

- `widgets/tree_view` (M72): nós aninhados desenhavam o rótulo errado
  (índice relativo ao pai aplicado ao array da raiz) e podiam ler fora
  dos limites quando o índice do filho excedia o tamanho da raiz;
  alternar expansão por (profundidade, índice) podia atingir o nó
  errado sob outro pai. `FlatNode` agora guarda ponteiro direto ao
  item: rótulo sempre do próprio nó, toggle sempre exato. API pública
  inalterada. Afeta todas as versões com TreeView (desde 1.16.0).
- `widgets/table` (M71): `scroll_offset` e `bounds` não-finitos agora
  retornam `InvalidArgument` na entrada em vez de coerção silenciosa/
  erro interno; cobertura nova (1 linha, limites, wheel extremo,
  encolher linhas, área pequena, última linha).
- 129/129 testes, integração C, CI verde.

## [1.21.0] - 2026-10-16

MINOR estável, 100% compatível: chrome de aplicação por composição.

- `widgets/toolbar` (M67): barra de ferramentas por **composição** (sem
  `id`/interação própria). Desenha chrome (`ToolbarStyle` +
  `Theme.toolbarStyle()`) e oferece posicionamento determinístico dos
  itens via `layout.StackPlacer` (sem sistema de layout paralelo):
  `toolbar` devolve `Toolbar` (estado no chamador), `Toolbar.nextItem`
  (altura uniforme, centrada) e `Toolbar.remaining`; largura além do
  restante é **clampada** e sinalizada em `Toolbar.overflowed`;
  `toolbarSeparator` reusa `widgets/separator`; `toolbarContentRect` é
  puro. Os itens são desenhados pelos widgets existentes.
- `widgets/statusbar` (M68): barra de status por **composição** (sem
  `id`/interação própria). Desenha chrome (`StatusBarStyle` +
  `Theme.statusBarStyle()`) e posiciona segmentos à esquerda
  (`StatusBar.nextItem`) e ancorados à direita (`StatusBar.nextRight`,
  ex.: "Ln 1, Col 1") sem sobreposição, via `layout.StackPlacer` +
  escalares espelhados (sem sistema de layout paralelo, sem alterar
  contratos da Toolbar). Largura além do livre é **clampada** e
  sinalizada em `StatusBar.overflowed`; `statusBarText` mede e emite
  1 texto; `statusBarSeparator` reusa `widgets/separator`.
- 123/123 testes, integração C, CI verde.

## [1.20.0] - 2026-10-15

MINOR estável, 100% compatível: separador estático + endurecimento do Textarea.

- `widgets/separator` (M66): divisor estático (display puro, sem `id`/
  estado). `separator` (linha horizontal/vertical, 1 comando) e
  `separatorLabeled` (linha horizontal com rótulo centralizado: 2
  segmentos + 1 texto). `SeparatorStyle` + `Theme.separatorStyle()` e
  `separatorLineRect` puro para layout.
- `widgets/textarea`: arrasto com `y` finito extremo podia estourar
  `@intFromFloat` em `lineAtY` (comportamento ilegal / panic em Debug);
  agora satura na última linha antes da conversão. Afeta a v1.19.0.
- 115/115 testes, integração C, CI verde.

## [1.19.0] - 2026-10-15

MINOR estável, 100% compatível: widgets de entrada e feedback.

- `widgets/spinner` (M64): indicador de carregamento **indeterminado**,
  complementar a `progress`. Display puro (sem interação/estado) guiado
  por tempo do chamador (`t` em segundos) — determinístico; anel de dots
  com cabeça rotativa, `SpinnerStyle` + `Theme.spinnerStyle()`.
- `widgets/textarea` (M65): edição multilinha (separador `'\n'`), estado
  no chamador (buffer/len/cursor/anchor/scroll_y, zero alocação); edição,
  seleção (`Shift`/`Ctrl+A`/click/arrasto), navegação vertical preservando
  coluna, rolagem vertical e horizontal derivada; reusa `TextInputStyle`
  (sem alterar `text_input`). Escopo v1: sem quebra suave.
- Correção (nunca publicada): `spinnerHeadIndex` com `t` extremo deixava
  de estourar para `NaN`/índice inválido (módulo em f64).
- 108/108 testes, integração C, CI verde.

## [1.18.0] - 2026-10-15

MINOR estável, 100% compatível: controle binário.

- `widgets/switch` (M63): switch (toggle) complementar ao checkbox —
  trilho + knob deslizante, mouse com press/release-to-toggle e
  cancelamento fora, foco por click/Tab, Espaço alterna,
  `SwitchStyle` + `Theme.switchStyle()`.
- 103/103 testes, integração C, CI verde.

## [1.17.0] - 2026-10-15

MINOR estável, 100% compatível: visão tabular.

- `widgets/table` (M62): tabela com header fixo e corpo rolável,
  colunas com largura, seleção por click/teclado, wheel, auto-scroll,
  zebra/hover/seleção, separadores, scrollbar e clip.
- 100/100 testes, integração C, CI verde.

## [1.16.0] - 2026-10-15

MINOR estável, 100% compatível: TreeView hierárquica + endurecimento.

- `widgets/tree_view` (M59): árvore hierárquica com expand/collapse,
  seleção por click/teclado, wheel, auto-scroll e scrollbar.
- Colapsar nó no mesmo frame não abre mais OOB (M60, nunca publicado).
- Fuzz de `pushText`/`textOf` com bytes arbitrários (M61).
- 99/99 testes, integração C, CI verde.

## [1.15.0] - 2026-10-15

MINOR estável, 100% compatível: widgets de organização de interfaces.

- `widgets/tab_bar` (M56): barra de abas com click/seleção/teclado.
- `widgets/splitter` (M57): divisor arrastável com mouse/teclado.
- `widgets/list_view` (M58): lista vertical com scroll/seleção/wheel.
- 96/96 testes, integração C, CI verde.

## [1.14.0] - 2026-10-15

MINOR estável, 100% compatível: widgets e versionamento.

- Versão pública sincronizada (M54): `version_*`/C-ABI saem de
  1.0.0 congelado para a versão real; teste de sincronia + C
  com MAJOR/MINOR/PATCH completos; fonte documentada.
- `beginModalTitled` com texto na barra (M53); `Escape` dispensa
  popup (M55, mesmo padrão do modal).
- 93/93 testes, integração C, CI verde.

## [1.13.0] - 2026-10-15

MINOR estável, 100% compatível: entrada e widgets.

- Fronteira de eventos endurecida (M49: mouse não-finito vira
  `InvalidEvent`) + fuzz permanente (M50).
- `widgets/slider.sliderVertical` e navegação por palavra no
  text-input (`Ctrl+Left/Right`, M51+M52).
- 91/91 testes, integração C, CI verde.

## [1.12.0] - 2026-10-15

Décima segunda MINOR estável, 100% compatível: widgets polidos e verificação.

- Modal arrastável, combo pelo teclado, separadores, rolagem no input,
  popupPlace, seleção por mouse (M39–M45).
- Cobertura, culling unificado, fillRect ~1,5×, C-ABI com versão (M44–M48).
- 87/87 testes, integração C, CI verde.

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

### Melhorado — Milestone 48 (fillRect 1,3–1,8×, medido)
- `software/raster.fillRect`: base da linha içada + ramos opaco/blend
  separados (o ramo único matava a vetorização — medido). Ganho real:
  ReleaseFast ~1,46× e Debug ~1,83× na fase raster, pxsum bit-idêntico.
  Regra: abaixo de ~10% medido, reverte.
- Resto aditivo (acumula p/ próxima MINOR).

### Corrigido — Milestone 49 (NaN fora da fila, compatível)
- `event/event.isValid`: posições de mouse não-finitas rejeitadas
  (`mouse_move`, `mouse_button`, `pos` do wheel); NaN envenenaria
  `mouse_pos` retido e cálculos (ex.: drag). Lixo externo vira
  `InvalidEvent`, nunca estado.

### Adicionado — Milestone 50 (fuzz nos eventos, compatível)
- `event/event`: fuzz com bits arbitrários (contrato da M49 sob
  ataque: sem crash nunca, `push` aceita sse `isValid`, finito
  <=> válido nos 3 eventos de mouse).
- Sem mudança de comportamento; resto aditivo (acumula p/ MINOR).

### Adicionado — Milestone 51 (slider vertical, compatível)
- `widgets/slider.sliderVertical`: valor cresce para cima (topo =
  `max`), drag no eixo Y com captura, mesmo teclado do horizontal
  (`Up`/`Right` aumentam, `Down`/`Left` diminuem, `Home`/`End`
  saltam); 4 draws espelhados; reaproveita `SliderStyle`.
- `slider` clássico intacto; resto aditivo (acumula p/ MINOR).

### Adicionado — Milestone 52 (navegação por palavra, compatível)
- `widgets/text_input`: `Ctrl+Left`/`Ctrl+Right` pulam por palavra
  (reaproveita `wordStartBack`/`wordEndFwd` da M34; com `Shift`,
  estende a seleção; sem mutação, fora do histórico). Vale nas
  3 variantes (código partilhado).
- Resto aditivo (acumula p/ MINOR).

### Adicionado — Milestone 53 (título no modal, compatível)
- `widgets/modal.beginModalTitled`: draggable com texto na barra
  (`title`/`font` do chamador, +1 `.text` centralizado com margem 8;
  vazio = 0 extras; overflow contido pelo clip do painel).
- `style/style.ModalStyle.title_text` com default (literais antigos
  compilam; `Theme.modalStyle()` usa `text` do tema).
- `beginModal`/`beginModalDraggable` intactos; resto aditivo.

### Corrigido — Milestone 54 (versão pública sincronizada, compatível)
- Causa: `version_*` em `core/types` congelado em 1.0.0 desde a M1
  (comentário dizia espelhar o zon, mas nenhum prep atualizava);
  `zyntra_version_minor()` retornava 0 em vez de 13.
- Solução manual (sem geração): `build.zig.zon` é a fonte única;
  `types.zig` espelha (agora 1.13.0) e o teste `version_* espelham
  build.zig.zon` quebra o CI em divergência (leitura runtime +
  `build.zig.zon` como entrada de cache do `run test`); teste C
  valida MAJOR/MINOR/PATCH completos. Sem contrato que definisse
  1.0.0 como versão independente (só assinaturas, preservadas).
- Resto aditivo (só valores; acumula p/ MINOR).

### Adicionado — Milestone 55 (Escape dispensa popup, compatível)
- `widgets/popup`: `Escape` pressionado dispensa (mesmo padrão do
  modal; fecha o "futuro" documentado desde a M18). Botão direito
  segue sem dispensar; press fora inalterado.
- Resto aditivo (acumula p/ MINOR).

### Adicionado — Milestone 56 (TabBar, compatível)
- `widgets/tab_bar.beginTabBar`/`endTabBar`: barra de abas com
  estado no chamador (`active: *usize`); click seleciona, teclado
  (`Left`/`Right`/`Home`/`End`/`Tab`) navega; clamp de índice;
  3*N+2 draws; `TabBarStyle` + `Theme.tabBarStyle()` validados.
- `style/style.TabBarStyle` e derivação do tema; `root` exporta
  `tab_bar`; `endTabBar` existe para simetria (sem estado retido).
- Resto aditivo (acumula p/ MINOR).

### Adicionado — Milestone 58 (ListView, compatível)
- `widgets/list_view.beginListView`/`endListView`: lista vertical com
  scroll, seleção por click/teclado (setas/Home/End/PageUp/PageDown),
  wheel, auto-scroll para seleção, scrollbar proporcional, clip;
  helpers puros `listViewContentHeight`/`listViewMaxScroll`;
  `ListViewStyle` + `Theme.listViewStyle()`; `endListView` NO-OP
  documentado; clássicos intactos.
- Resto aditivo (acumula p/ MINOR).

### Adicionado — Milestone 59 (TreeView, compatível)
- `widgets/tree_view.beginTreeView`/`endTreeView`: árvore hierárquica
  com expand/collapse, seleção por click/teclado (setas/Home/End/Enter/
  Space/Left/Right), wheel, auto-scroll, scrollbar; helpers puros
  `treeViewContentHeight`/`treeViewMaxScroll`/`treeViewFlatten`;
  `TreeItem` (label, children, expanded), `TreeViewStyle` +
  `Theme.treeViewStyle()`; `endTreeView` NO-OP documentado.
- Resto aditivo (acumula p/ MINOR).

### Adicionado — Milestone 57 (Splitter, compatível)
- `widgets/splitter.beginSplitter`/`endSplitter`: divisor arrastável
  (`pos: *f32` no chamador); mouse drag com captura, clamp, teclado
  (setas 8 px, Home/End, Tab); helpers puros `splitterHandleRect`/
  `splitterClampPos`; `SplitterOrientation` + `SplitterStyle` +
  `Theme.splitterStyle()`; 2 draws (fundo + handle); `endSplitter`
  NO-OP documentado; clássicos intactos.
- Resto aditivo (acumula p/ MINOR).

### Corrigido — Milestone 60 (colapso no mesmo frame, compatível)
- `widgets/tree_view`: colapsar um nó no meio do frame encolhia a
  lista achatada mas o desenho usava o limite antigo → OOB que
  ABORTAVA com safety (`index out of bounds`, achado pelo teste de
  cobertura M60, nunca publicado). Agora re-deriva `last_visible`,
  seleção e hover da contagem pós-toggle antes de indexar.
- Teste `TreeView colapso, scroll, contagem e profundidade`:
  hierarquia 3 níveis, ordem achatada, no-ops nas extremidades,
  scroll clampado, seleção válida após recolher, helpers puros.
- Resto aditivo (acumula p/ MINOR).

### Adicionado — Milestone 61 (fuzz no pushText, compatível)
- `draw/commands`: fuzz com bytes arbitrários (contrato da M6 sob
  ataque: sem crash nunca, texto válido entra e resolve idêntico
  via `textOf`, inválido rejeitado sem enfileirar, offsets sempre
  contidos na arena).
- Sem mudança de comportamento; resto aditivo (acumula p/ MINOR).

### Adicionado — Milestone 62 (Table, compatível)
- `widgets/table.beginTable`/`endTable`: tabela com header fixo
  (`columns: []const TableColumn` com título/largura) e corpo rolável
  (`rows: []const TableRow`, `cells: []const []const u8`); seleção por
  click/teclado (setas/Home/End/PageUp/PageDown/Tab), wheel, auto-scroll,
  fundo zebrado/hover/seleção, separadores de coluna, scrollbar e clip;
  helpers puros `tableBodyRect`/`tableContentHeight`/`tableMaxScroll`/
  `tableColumnsWidth`; `TableStyle` + `Theme.tableStyle()`; `endTable`
  NO-OP documentado.
- Contratos: `id` não-nulo, estilo válido, `bounds.h > header_height`,
  ≥1 coluna com largura finita positiva, ≥1 linha.
- Resto aditivo (acumula p/ MINOR).
