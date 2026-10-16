<div align="center">

# ZyntraUI

**Modern interfaces. Native performance. Pure Zig.**

A lightweight GUI toolkit in Zig with caller-owned state, zero hidden
allocations, and a renderer-independent draw-command contract.
Stable public API since 1.0.0 — current release **v1.21.1**.

[![Status](https://img.shields.io/badge/status-stable-green)](https://github.com/CeoMatheusDev/ZyntraUI)
[![Language](https://img.shields.io/badge/language-Zig-f7a41d)](https://ziglang.org/)
[![Release](https://img.shields.io/badge/release-v1.21.1-blue)](https://github.com/CeoMatheusDev/ZyntraUI/releases)
[![Contributions](https://img.shields.io/badge/contributions-welcome-brightgreen)](https://github.com/CeoMatheusDev/ZyntraUI/issues)

</div>

---

## Overview

**ZyntraUI** builds interfaces frame by frame: you feed normalized input
events in, call widgets with state **you own**, and consume an explicit
list of draw commands with a backend of your choice. There is no built-in
GPU renderer, no windowing, no hidden globals —
predictable behavior you can test without a screen.

> [!IMPORTANT]
> **Project status: stable.** The public API is frozen since 1.0.0
> (breaking changes require a MAJOR release, per [SemVer 2.0.0](https://semver.org/)).
> See [CHANGELOG.md](CHANGELOG.md) for the release history.

## Why ZyntraUI

- **Caller-owned state** — selection, scroll offsets, text buffers and
  toggles live in your code, passed by pointer each frame. The library
  never takes ownership of your data.
- **No hidden allocations** — widgets operate on caller memory; text is
  copied once into the frame arena backing the draw list.
- **Renderer-independent** — output is a plain `DrawCommand` list
  (`rect`, `line`, `text`, `clip`, …). A reference software rasterizer
  ships under `src/software/`; production backends stay external.
- **Deterministic and testable** — same events in, same commands out.
  Time-driven widgets (e.g. spinner) take the timestamp as a parameter
  instead of reading a clock.
- **Pure Zig, no mandatory dependencies** — the core builds on the
  standard library only. An optional C ABI (`src/c-abi/zyntra.h`)
  exposes version queries and the frame pipeline to C consumers.
- **Validated in CI** — unit tests plus fuzz tests run on every commit
  (Zig 0.17.0 × Debug/ReleaseFast), with example apps, benchmarks and
  a C-ABI integration test.

## Widgets

25 public widgets, all reachable from the single supported import
(`@import("zyntra_ui")` → `widgets.*`). Unless noted, interactive state
is caller-owned and styling comes from `Theme.*Style()`.

| Category | Widget | What it does |
|---|---|---|
| Input & selection | `button` | Release-to-activate button (release outside cancels) |
| | `checkbox` | On/off checkbox bound to a caller `bool` |
| | `radio` | Exclusive single-choice option group |
| | `switch` | Sliding on/off toggle, companion to checkbox |
| | `slider` / `sliderVertical` | Drag a `f32` value in `[min, max]`, keyboard-adjustable |
| | `text_input` | Single-line field, caller-owned UTF-8 buffer + selection |
| | `textarea` | Multi-line editing over `'\n'`, same ownership model |
| | `combo` | Dropdown selector composing button + menu |
| Views & navigation | `label` / `labelWrapped` | Single-line and word-wrapped text |
| | `list_view` | Scrollable vertical list with keyboard selection |
| | `tree_view` | Hierarchical tree with expand/collapse |
| | `table` | Fixed-header grid with selection and scrolling |
| | `tab_bar` | Tab strip with keyboard navigation |
| | `scroll` | Scrollable container (wheel, thumb drag, keyboard) |
| | `splitter` | Draggable divider between panes |
| | `menu` / `menuNested` | Dropdown and cascading submenus, disabled items |
| | `popup` | Floating dismissible panel with content clip |
| | `modal` | Dialog with dimmed background and title bar |
| | `tooltip` | Hover tooltip shown after a frame delay |
| Feedback | `progress` | Determinate 0..1 bar |
| | `spinner` | Indeterminate, caller-time-driven indicator |
| Composition | `separator` / `separatorLabeled` | Static divider, optionally with centered label |
| | `toolbar` | Bar chrome + deterministic item placement |
| | `statusbar` | Bar chrome + left-anchored and right-anchored segments |
| | `groupbox` | Titled frame returning its content rect for children |

## Architecture

```text
src/
├── root.zig      Public API (the only supported @import)
├── core/         Context, types, stable Ids
├── event/        Normalized input events
├── draw/         Draw lists + external renderer contract
├── layout/       Constraints, insets, stack placement
├── style/        Themes and widget styles
├── widgets/      The 25 widgets listed above
├── text/         UTF-8 metrics (fallback monospace measurement)
├── anim/         Optional easing, tweens, timers
├── software/     Reference software rasterizer
└── c-abi/        Optional C ABI (zyntra.h) + opaque handles
```

Frame model: create one explicit `Context`, push normalized events,
`beginFrame()` → call widgets → `endFrame()`, then submit
`drawCommands()` to your backend. See `docs/` for the detailed contracts
and `examples/app.zig` for toolbar, tab bar, table and status bar
composed across shared frames.

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

## Examples & benchmarks

- `zig build run-example` — per-widget tour: widgets, layout, text and
  animations (`examples/minimal.zig`).
- `zig build run-app` — integrated mini-app: toolbar, tab bar, table
  and status bar sharing state across frames (`examples/app.zig`).
- `zig build run-bench` — pipeline benchmark (`examples/bench.zig`,
  notes in `docs/BENCHMARKS.md`).

C consumers: see `src/c-abi/zyntra.h` and `docs/C_ABI.md`.

## Versioning

Releases follow [SemVer 2.0.0](https://semver.org/); every change is
recorded in [CHANGELOG.md](CHANGELOG.md) (Keep a Changelog format).
`PATCH`/`MINOR` releases ship coherent, validated batches; `MAJOR`
releases require explicit approval and mean breaking changes.

## Contributing

Ideas, technical discussions, and feedback are welcome. Open an [issue](https://github.com/CeoMatheusDev/ZyntraUI/issues) to propose a feature or discuss architectural decisions.

## License

MIT — see [LICENSE](LICENSE).

---

<div align="center">

**ZyntraUI** · Built with Zig · Designed for control and performance

</div>
