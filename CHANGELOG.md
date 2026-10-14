# Changelog

Todas as mudanças notáveis deste projeto serão documentadas aqui, no formato
[Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/) + [SemVer 2.0.0](https://semver.org/lang/pt-BR/).

## [Não lançado]

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
