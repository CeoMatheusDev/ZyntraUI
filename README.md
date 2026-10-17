<div align="center">

# ZyntraUI

**Build interfaces with control. Render with freedom. Ship with Zig.**

A lightweight, immediate-mode GUI toolkit written in Zig, built around explicit state ownership, deterministic draw commands, and a renderer-independent architecture.

[![Zig](https://img.shields.io/badge/Zig-0.17.0-F7A41D?logo=zig&logoColor=white)](https://ziglang.org/)
[![Release](https://img.shields.io/badge/release-v1.22.0-2563EB)](https://github.com/CeoMatheusDev/ZyntraUI/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-22C55E)](LICENSE)

[Getting started](#getting-started) · [Features](#why-zyntraui) · [Architecture](#architecture) · [Examples](#examples-and-validation)

</div>

---

## Overview

**ZyntraUI** is a modular GUI toolkit for developers who want to own their application state and rendering pipeline. Its Zig-native core processes normalized input events and produces a backend-neutral sequence of draw commands for the host application's renderer.

Rather than tying UI logic to a window system or GPU API, ZyntraUI keeps those concerns separate. You choose how to supply events, manage widget state, and render each frame.

> **Scope:** ZyntraUI is a UI toolkit, not a complete windowing framework. Integrate your own platform event source and rendering backend. A reference software rasterizer is included.

## Why ZyntraUI?

- **Explicit ownership:** Your application owns widget state, including text buffers, selections, scroll positions, and toggles.
- **Renderer independence:** Consume draw commands with the graphics backend of your choice.
- **Predictable frame lifecycle:** Build each frame using a clear begin → widgets → end flow.
- **Allocation-aware design:** A per-frame arena supports transient draw commands and text copies, avoiding hidden hot-path allocations.
- **Deterministic behavior:** Explicit inputs and draw lists make UI logic suitable for automated and snapshot testing.
- **Pure Zig core:** Use the native Zig API or the optional C ABI without introducing a heavyweight GUI runtime.

## Widgets

ZyntraUI provides **25 public widgets**, organized around common interface needs:

| Category | Widgets |
| --- | --- |
| Input & selection | Button, checkbox, radio, switch, slider, text input, textarea, combo |
| Views & navigation | Label, wrapped label, list view, tree view, table, tab bar, scroll, splitter, menu, popup, modal, tooltip |
| Feedback | Progress, spinner |
| Composition | Separator, labeled separator, toolbar, status bar, group box |

Widgets are exposed through the `widgets` namespace of `@import("zyntra_ui")`. Refer to the in-repository documentation and examples for individual APIs.

## Architecture

ZyntraUI separates UI behavior, layout, styling, input, and rendering into focused modules:

```text
src/
├── root.zig       Public Zig API
├── core/          Context, types, and stable IDs
├── event/         Normalized input events
├── draw/          Draw commands and renderer contract
├── layout/        Constraints and placement
├── style/         Themes and widget styles
├── widgets/       Widget implementations
├── text/          UTF-8 metrics and text measurement
├── anim/          Optional animation helpers
├── software/      Reference software rasterizer
└── c-abi/         Optional C interface
```

### Frame lifecycle

1. Create a `Context` for each UI instance.
2. Start a frame with `beginFrame()` and provide normalized input events.
3. Invoke widgets with application-owned state and explicit styles.
4. Retrieve `drawCommands()` and submit them to your renderer.
5. Finish the frame with `endFrame()`.

Time-dependent widgets can receive an explicit timestamp, allowing repeatable behavior in tests.

## Getting started

**Requirement:** Zig **0.17.0**.

### Install

Add the tagged release to your Zig project:

```sh
zig fetch --save https://github.com/CeoMatheusDev/ZyntraUI/archive/refs/tags/v1.22.0.tar.gz
```

Then import the module in your consumer's `build.zig`:

```zig
const zyntra_dep = b.dependency("zyntra_ui", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zyntra_ui", zyntra_dep.module("zyntra_ui"));
```

### Minimal draw-command example

The following illustrates a frame using the public context and drawing API. It produces commands; displaying them requires a renderer supplied by the application.

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

// Submit ctx.drawCommands() to your rendering backend here.
ctx.endFrame();
```

For a runnable integration example, start with [`examples/minimal.zig`](examples/minimal.zig).

## Examples and validation

Run these commands from the repository root:

```sh
zig build run-example  # Widget and input behavior walkthrough
zig build run-app      # Integrated mini-app example
zig build run-bench    # Frame pipeline benchmark
zig build test         # Unit tests
zig fmt --check src/ examples/ build.zig
```

The included examples exercise the UI pipeline; they do not provide a standalone desktop window. For benchmark methodology and results, see [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md).

## C interoperability

An optional C ABI is available for non-Zig consumers. See [`src/c-abi/zyntra.h`](src/c-abi/zyntra.h) and [`docs/C_ABI.md`](docs/C_ABI.md) for the exported interface and integration details.

## Project resources

- [Changelog](CHANGELOG.md) — release history and API changes
- [Contributing](CONTRIBUTING.md) — development and contribution guidelines
- [Security](SECURITY.md) — vulnerability reporting
- [Documentation](docs/) — technical references and benchmarks

## License

Distributed under the [MIT License](LICENSE).

---

<div align="center">

**ZyntraUI** · Explicit state · Predictable rendering · Pure Zig

</div>
