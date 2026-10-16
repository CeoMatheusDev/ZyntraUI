<div align="center">

# ZyntraUI

**Modern interfaces. Native performance. Pure Zig.**

A work-in-progress GUI toolkit designed for lightweight, responsive native interfaces, written in Zig.

[![Status](https://img.shields.io/badge/status-stable-green)](https://github.com/CeoMatheusDev/ZyntraUI)
[![Language](https://img.shields.io/badge/language-Zig-f7a41d)](https://ziglang.org/)
[![Contributions](https://img.shields.io/badge/contributions-welcome-brightgreen)](https://github.com/CeoMatheusDev/ZyntraUI/issues)

</div>

---

## Overview

**ZyntraUI** is an early-stage project exploring a modern GUI toolkit with an emphasis on predictable performance, explicit resource management, and a clean developer experience.

The project aims to favor understandable, low-level implementations over heavyweight abstractions. Its API, rendering architecture, and platform support have **not yet been finalized**.

> [!IMPORTANT]
> **Project status: stable (1.0.0).** API pública congelada a partir desta
> versão (mudanças incompatíveis exigem MAJOR). ZyntraUI has no built-in
> GPU renderer or windowing: you feed normalized events in and consume
> draw commands with an external backend.

## Design goals

- **Pure Zig:** implement the toolkit itself in Zig, minimizing external dependencies where practical.
- **Performance first:** prioritize low overhead, efficient rendering, and responsive input handling.
- **Memory conscious:** favor explicit ownership, controlled allocations, and predictable lifetimes.
- **Modular design:** keep platform integration, rendering, layout, and widgets decoupled.
- **Modern UI:** aim for flexible layouts, consistent styling, and polished interactive components.
- **Transparency:** keep the internals understandable, inspectable, and easy to extend.

## Architecture (current layout)

```text
src/
├── root.zig      Public API (the only supported @import)
├── core/         Context, types, stable Ids
├── event/        Normalized input events
├── draw/        Draw lists + external renderer contract
├── layout/      Constraints, insets, stack placement
├── style/       Themes and widget styles
├── widgets/     Button, checkbox, radio, switch, label, slider,
                 text input, combo, scroll, tab bar, splitter,
                 list view, tree view, table, menu, popup, modal,
                 tooltip, progress, spinner, textarea, separator, toolbar,
                 status bar
├── text/        UTF-8 metrics (fallback monospace measurement)
├── anim/        Optional easing, tweens, timers
└── c-abi/       Optional C ABI (zyntra.h) + opaque handles
```

Model: retained core (explicit `Context`, per-frame draw lists) with an
ergonomic builder-style API. No GPU renderer, windowing, audio, or
networking by design — see `docs/` for contracts.

## Roadmap

- [x] Architecture and public API principles
- [x] Event processing (normalized; windowing stays external)
- [x] Rendering and drawing primitives (backend-external contract)
- [x] Layout and input handling
- [x] Initial widget set (button, checkbox, label, slider, text input)
- [x] Examples, tests, and documentation
- [x] Pre-releases (alpha, beta)
- [x] 1.0.0 stable (API freeze + release review)

## Getting started

Requires Zig 0.17.0. Add the dependency:

```sh
zig fetch --save https://github.com/CeoMatheusDev/ZyntraUI/archive/refs/tags/v1.21.1.tar.gz
```

Wire the module in your `build.zig` (the `fetch` above records the
`.url`/`.hash` entry in your `build.zig.zon`):

```zig
const zyntra_dep = b.dependency("zyntra_ui", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zyntra_ui", zyntra_dep.module("zyntra_ui"));
```

The snippet below was compiled and run against this tag (`snippet ok`):

```zig
const zyntra_ui = @import("zyntra_ui");

var ctx = try zyntra_ui.Context.init(allocator, .{
    .viewport = zyntra_ui.Rect.init(0, 0, 800, 600),
});
defer ctx.deinit();

ctx.beginFrame();
try ctx.draw.rectFilled(
    ctx.allocator,
    zyntra_ui.Rect.init(10, 10, 100, 40),
    zyntra_ui.Color.rgb(70, 110, 180),
);
ctx.endFrame();
```

Run `zig build run-example` for the full demo (widgets, layout, text,
animations). Run `zig build run-app` for the integrated mini-app
(toolbar + tabbar + table + statusbar composed across shared frames).
C consumers: see `src/c-abi/zyntra.h` and `docs/C_ABI.md`.

## Contributing

Ideas, technical discussions, and feedback are welcome. Open an [issue](https://github.com/CeoMatheusDev/ZyntraUI/issues) to propose a feature or discuss architectural decisions.

## License

MIT — see [LICENSE](LICENSE).

---

<div align="center">

**ZyntraUI** · Built with Zig · Designed for control and performance

</div>
