<div align="center">

# ZyntraUI

**Modern interfaces. Native performance. Pure Zig.**

A modern, lightweight and high-performance GUI toolkit written entirely in Zig. ZyntraUI is designed for applications that need precise control over UI state, predictable rendering output, and maximum performance with minimal runtime dependencies.

[![Status](https://img.shields.io/badge/status-stable-green)](https://github.com/CeoMatheusDev/ZyntraUI)
[![Language](https://img.shields.io/badge/language-Zig-f7a41d)](https://ziglang.org/)
[![Release](https://img.shields.io/badge/release-v1.21.1-blue)](https://github.com/CeoMatheusDev/ZyntraUI/releases)
[![License](https://img.shields.io/badge/license-MIT-blue)](https://github.com/CeoMatheusDev/ZyntraUI/blob/main/LICENSE)

</div>

---

## Sumário

- Overview
- Use cases
- Key features
- Widgets (resumo)
- Architecture & API surface
- Getting started (quickstart)
- Examples & benchmarks
- CI, testing and validation
- Contributing & Security
- License

---

## Overview

ZyntraUI builds immediate-mode style interfaces frame-by-frame with an emphasis on explicit ownership and determinism. You provide normalized input events and caller-owned widget state each frame; the library emits an explicit draw-list (`DrawCommand` sequence) that any renderer can consume.

The public API is stable (since 1.0.0). Breaking changes require a MAJOR release; see `CHANGELOG.md` for history.

## Use cases

- Desktop applications that need a lightweight, testable UI layer without heavy runtime dependencies.
- Embedded or headless environments where predictable render outputs are required for snapshots or testing.
- Tooling and internal apps where deterministic behavior and precise control over memory are important.

## Key features

- Caller-owned state: selection, scroll offsets, text buffers, toggles are all managed by the application.
- Zero hidden allocations in the hot path; per-frame arena backs draw lists and text copies.
- Renderer-agnostic: draw list is backend neutral (rect, line, text, clip, etc.).
- Deterministic output suitable for unit and fuzz testing.
- Pure Zig core with an optional C ABI (`src/c-abi/zyntra.h`).
- Minimal dependencies and a small compile-time footprint.

## Widgets (resumo)

25 public widgets are available via `@import("zyntra_ui")` → `widgets.*`. Major categories:

- Input & selection: `button`, `checkbox`, `radio`, `switch`, `slider`, `text_input`, `textarea`, `combo`
- Views & navigation: `label`, `labelWrapped`, `list_view`, `tree_view`, `table`, `tab_bar`, `scroll`, `splitter`, `menu`, `popup`, `modal`, `tooltip`
- Feedback: `progress`, `spinner`
- Composition: `separator`, `separatorLabeled`, `toolbar`, `statusbar`, `groupbox`

Consult in-repo docs for per-widget API details and examples.

## Architecture & API surface

Directory layout (important modules):

src/
├── root.zig      Public API (single supported `@import`)
├── core/         Context, types, stable Ids
├── event/        Normalized input events
├── draw/         Draw lists + renderer contract
├── layout/       Constraints, insets, placement
├── style/        Theme and widget styles
├── widgets/      Widget implementations
├── text/         UTF-8 metrics and fallback measurement
├── anim/         Optional easing and tween helpers
├── software/     Reference software rasterizer (example backend)
└── c-abi/        Optional C ABI (zyntra.h)

API notes:
- Create one `Context` per UI instance, push events, call `beginFrame()` → widgets → `endFrame()`, then submit `drawCommands()` to your renderer.
- Widgets take caller-provided state handles and explicit style inputs.
- Time-dependent widgets accept an explicit timestamp parameter for deterministic testing.

## Getting started (quickstart)

Requirements: Zig 0.17.0.

Add as a dependency:

```sh
zig fetch --save https://github.com/CeoMatheusDev/ZyntraUI/archive/refs/tags/v1.21.1.tar.gz
```

In consumer `build.zig`:

```zig
const zyntra_dep = b.dependency("zyntra_ui", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zyntra_ui", zyntra_dep.module("zyntra_ui"));
```

Small runtime snippet (compiled against v1.21.1):

```zig
const zyntra_ui = @import("zyntra_ui");

var ctx = try zyntra_ui.Context.init(allocator, .{ .viewport = zyntra_ui.Rect.init(0,0,800,600) });
defer ctx.deinit();

ctx.beginFrame();
try ctx.draw.rectFilled(ctx.allocator, zyntra_ui.Rect.init(10,10,100,40), zyntra_ui.Color.rgb(70,110,180));
ctx.endFrame();
```

## Examples & benchmarks

- `zig build run-example` — per-widget tour (`examples/minimal.zig`).
- `zig build run-app` — integrated mini-app demonstrating toolbars, tab bars, tables and status bars (`examples/app.zig`).
- `zig build run-bench` — pipeline benchmark and notes in `docs/BENCHMARKS.md`.

C consumers: see `src/c-abi/zyntra.h` and `docs/C_ABI.md`.

## CI, testing and validation

- Unit tests and fuzz tests run on CI for Zig 0.17.0 (Debug/ReleaseFast).
- Example apps and a C-ABI integration test are exercised in CI flows.
- Recommended local quick checks:

```bash
zig fmt --check src/ examples/ build.zig
zig build test
zig build run-example
```

## Contributing & Security

Read `CONTRIBUTING.md` and `SECURITY.md` for contribution workflows, commit conventions, and vulnerability reporting. Keep commits small and focused; follow Conventional Commits.

## License

MIT — see `LICENSE`.

---

<div align="center">

**ZyntraUI** · Built with Zig · Designed for control, determinism, and performance

</div>
