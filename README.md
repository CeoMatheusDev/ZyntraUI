<div align="center">

# ZyntraUI

**Modern interfaces. Native performance. Pure Zig.**

A lightweight GUI toolkit in Zig with caller-owned state, zero hidden allocations, and a renderer-independent draw-command contract.

Stable public API since 1.0.0 — current release **v1.21.1**.

[![Status](https://img.shields.io/badge/status-stable-green)](https://github.com/CeoMatheusDev/ZyntraUI)
[![Language](https://img.shields.io/badge/language-Zig-f7a41d)](https://ziglang.org/)
[![Release](https://img.shields.io/badge/release-v1.21.1-blue)](https://github.com/CeoMatheusDev/ZyntraUI/releases)
[![Contributions](https://img.shields.io/badge/contributions-welcome-brightgreen)](https://github.com/CeoMatheusDev/ZyntraUI/issues)

</div>

---

## Table of contents

- Overview
- Key features
- Widgets (summary)
- Architecture
- Getting started
- Examples & benchmarks
- Versioning
- Contributing
- License

---

## Overview

ZyntraUI builds interfaces frame-by-frame: you feed normalized input events in, call widgets with state you own, and consume an explicit list of draw commands with the backend of your choice. There is no built-in GPU renderer, no windowing, and no hidden globals — making behavior deterministic and easy to test.

Project status: stable. The public API is frozen since 1.0.0 (breaking changes require a MAJOR release, per SemVer). See `CHANGELOG.md` for the release history.

## Key features

- Caller-owned state: selection, scroll offsets, text buffers and toggles live in user code and are passed by pointer each frame. The library never takes ownership of application data.
- No hidden allocations: widgets operate on caller memory; text is copied once into the frame arena backing the draw list.
- Renderer-independent: output is a plain `DrawCommand` list (`rect`, `line`, `text`, `clip`, …). A reference software rasterizer is included under `src/software/`; production backends remain external.
- Deterministic and testable: same events in, same commands out. Time-dependent widgets accept a timestamp instead of reading a clock.
- Pure Zig core with optional C ABI (`src/c-abi/zyntra.h`) exposing version queries and the frame pipeline to C consumers.
- Validated in CI: unit tests and fuzz tests run on every commit (Zig 0.17.0 × Debug/ReleaseFast), with examples, benchmarks and a C-ABI integration test.

## Widgets (summary)

25 public widgets are provided and reachable via the single supported import (`@import("zyntra_ui")` → `widgets.*`). Interactive state is caller-owned unless noted; styling is provided by `Theme.*Style()`.

Notable categories: Input & selection (buttons, checkboxes, text fields, sliders), Views & navigation (lists, trees, tables, tabs, scroll containers), Feedback (progress, spinner), and Composition (toolbars, status bars, group boxes).

For a complete list of widgets and their APIs, consult the in-repo documentation and examples.

## Architecture

src/
├── root.zig      Public API (the only supported @import)
├── core/         Context, types, stable Ids
├── event/        Normalized input events
├── draw/         Draw lists + external renderer contract
├── layout/       Constraints, insets, stack placement
├── style/        Themes and widget styles
├── widgets/      The public widgets
├── text/         UTF-8 metrics (fallback monospace measurement)
├── anim/         Optional easing, tweens, timers
├── software/     Reference software rasterizer
└── c-abi/        Optional C ABI (zyntra.h) + opaque handles

Frame model: create one explicit `Context`, push normalized events, `beginFrame()` → call widgets → `endFrame()`, then submit `drawCommands()` to your backend. See `docs/` and `examples/` for detailed contracts and usage patterns.

## Getting started

Requires Zig 0.17.0. Add the dependency via `zig fetch`:

```sh
zig fetch --save https://github.com/CeoMatheusDev/ZyntraUI/archive/refs/tags/v1.21.1.tar.gz
```

Then wire the module into your `build.zig`:

```zig
const zyntra_dep = b.dependency("zyntra_ui", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zyntra_ui", zyntra_dep.module("zyntra_ui"));
```

Quick usage snippet (compiled and run against the v1.21.1 tag):

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

- `zig build run-example` — per-widget tour: widgets, layout, text and animations (`examples/minimal.zig`).
- `zig build run-app` — integrated mini-app demonstrating toolbar, tab bar, table and status bar (`examples/app.zig`).
- `zig build run-bench` — pipeline benchmark (`examples/bench.zig`; see `docs/BENCHMARKS.md`).

C consumers: see `src/c-abi/zyntra.h` and `docs/C_ABI.md`.

## Versioning

Releases follow SemVer 2.0.0; every change is recorded in `CHANGELOG.md` (Keep a Changelog format). `PATCH`/`MINOR` releases ship coherent, validated batches; `MAJOR` releases require explicit approval and indicate breaking changes.

## Contributing

Contributions, issues, and discussions are welcome. To propose a feature or discuss architecture, open an issue. Please follow the repository's contribution guidelines when submitting changes (tests, formatting, and clear commit messages are appreciated).

## License

MIT — see `LICENSE`.

---

<div align="center">

**ZyntraUI** · Built with Zig · Designed for control and performance

</div>
