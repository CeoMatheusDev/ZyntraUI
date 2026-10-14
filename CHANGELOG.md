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
