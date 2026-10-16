<div align="center">

# ZyntraUI

**Modern interfaces. Native performance. Pure Zig.**

A lightweight GUI toolkit em Zig com estado controlado pelo chamador, zero alocações ocultas e um contrato de desenho independente de renderizador.

[![Status](https://img.shields.io/badge/status-stable-green)](https://github.com/CeoMatheusDev/ZyntraUI)
[![Language](https://img.shields.io/badge/language-Zig-f7a41d)](https://ziglang.org/)
[![Release](https://img.shields.io/badge/release-v1.21.1-blue)](https://github.com/CeoMatheusDev/ZyntraUI/releases)
[![License](https://img.shields.io/badge/license-MIT-blue)](https://github.com/CeoMatheusDev/ZyntraUI/blob/main/LICENSE)

</div>

---

## Sumário

- Overview
- Key features
- Widgets (resumo)
- Architecture
- Getting started
- Examples & benchmarks
- Contributing & Security
- License

---

## Overview

ZyntraUI constrói interfaces frame-a-frame: você envia eventos normalizados, chama widgets passando estados que você possui e consome uma lista explícita de DrawCommands que seu backend converte em pixels. Não há renderer embutido, nem janela, nem estados globais ocultos — isso torna o comportamento determinístico e testável.

Project status: stable. A API pública está congelada desde 1.0.0 (quebras exigem MAJOR release). Consulte `CHANGELOG.md` para o histórico.

## Key features

- Estado do chamador: seleção, offsets de scroll, buffers de texto e toggles vivem no código do usuário.
- Zero alocações ocultas no caminho quente; desenho baseado em arena por frame.
- Saída independente de renderer: lista de `DrawCommand` simples (`rect`, `line`, `text`, `clip`, ...).
- Determinístico e testável: widgets dependentes de tempo recebem timestamp em vez de ler relógio global.
- Core em Zig puro; ABI C opcional exposta em `src/c-abi/zyntra.h`.

## Widgets (resumo)

25 widgets públicos acessíveis por `@import("zyntra_ui")` → `widgets.*`. Exemplos: `button`, `checkbox`, `text_input`, `list_view`, `table`, `tab_bar`, `progress`, `spinner`, `toolbar`, `statusbar`.

Consulte a documentação no repositório para a lista completa e assinaturas.

## Architecture

src/
├── root.zig      Public API
├── core/         Context, types, stable Ids
├── event/        Normalized input events
├── draw/         Draw lists + renderer contract
├── layout/       Constraints, placement
├── style/        Themes and styles
├── widgets/      Widgets
├── text/         UTF-8 metrics
├── anim/         Optional easing/tweens
├── software/     Reference software rasterizer
└── c-abi/        Optional C ABI (zyntra.h)

Frame model: criar `Context`, push eventos, `beginFrame()` → chamar widgets → `endFrame()` → submeter `drawCommands()` ao backend.

## Getting started

Requer Zig 0.17.0.

Adicionar como dependência:

```sh
zig fetch --save https://github.com/CeoMatheusDev/ZyntraUI/archive/refs/tags/v1.21.1.tar.gz
```

Import no `build.zig` do consumidor:

```zig
const zyntra_dep = b.dependency("zyntra_ui", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zyntra_ui", zyntra_dep.module("zyntra_ui"));
```

Exemplo mínimo (compilado contra a tag):

```zig
const zyntra_ui = @import("zyntra_ui");

var ctx = try zyntra_ui.Context.init(allocator, .{ .viewport = zyntra_ui.Rect.init(0,0,800,600) });
defer ctx.deinit();

ctx.beginFrame();
try ctx.draw.rectFilled(ctx.allocator, zyntra_ui.Rect.init(10,10,100,40), zyntra_ui.Color.rgb(70,110,180));
ctx.endFrame();
```

## Examples & benchmarks

- `zig build run-example` — tour por widget (`examples/minimal.zig`).
- `zig build run-app` — mini-app integrado (`examples/app.zig`).
- `zig build run-bench` — benchmark de pipeline (`docs/BENCHMARKS.md`).

## Contributing & Security

Leia `CONTRIBUTING.md` e `SECURITY.md` no repositório para diretrizes de contribuição, padrões de commits, execução de testes e política de divulgação responsável.

## License

MIT — ver `LICENSE`.

---

<div align="center">

**ZyntraUI** · Built with Zig · Designed for control and performance

</div>
