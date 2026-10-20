<div align="center">

# ZyntraUI

**Build interfaces with control. Render with freedom. Ship with Zig.**

A lightweight, immediate-mode GUI toolkit written in Zig, built around explicit state ownership, deterministic draw commands, and a renderer-independent architecture.

[![Zig](https://img.shields.io/badge/Zig-0.17.0-F7A41D?logo=zig&logoColor=white)](https://ziglang.org/)
[![Release](https://img.shields.io/badge/release-v1.35.0-2563EB)](https://github.com/CeoMatheusDev/ZyntraUI/releases)
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
- **Multi-surface ready:** A window registry, per-surface input routing, repaint composition and draggable/resizable window frames, all on top of the same draw-command pipeline.

## Widgets

ZyntraUI provides **31 widget modules**, organized around common interface needs (some modules expose more than one entry point, such as `label`/wrapped label or `separator`/labeled separator):

| Category | Widgets |
| --- | --- |
| Input & selection | Button, checkbox, radio, switch, slider, text input, textarea, combo |
| Views & navigation | Label, wrapped label, list view, tree view, table, tab bar, scroll, splitter, menu, popup, modal, tooltip, node graph, timeline, property inspector |
| Feedback | Progress, spinner, drag ghost |
| Composition | Separator, labeled separator, toolbar, status bar, group box, panel, dock view |

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
├── dock/          Docking layout model and serialization
├── graph/         Node graph model (transform, geometry, hit-test)
├── timeline/      Timeline model (time↔pixel, ruler steps, tracks/keys)
├── inspector/     Property inspector model (values, row metrics, formatting)
├── dnd/           Drag-and-drop service (payload, targets, drop resolution)
├── window/        Registry (identity, z-order, focus) + input routing +
│                  repaint composition + window decorations/drag (M100-M103)
├── text/          UTF-8 metrics, wrapping, and text-edit helpers
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
zig fetch --save https://github.com/CeoMatheusDev/ZyntraUI/archive/refs/tags/v1.35.0.tar.gz
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

### Dirty rect / partial repaint

The context accumulates the region that changed during a frame. Call
`mark_dirty(rect)` for each area whose pixels changed (successive calls unite
the region; an empty rect is a no-op). `beginFrame()` resets it, so
`dirty_rect` always describes the current frame.

```zig
ctx.beginFrame();
// ... widgets and draw commands ...

ctx.mark_dirty(zyntra_ui.Rect.init(10, 10, 100, 40)); // this area changed

const dirty = ctx.dirty_rect;
if (!dirty.isEmpty()) {
    _ = try zyntra_ui.software.raster.renderRegion(&fb, ctx.drawCommands(), ctx.viewport, dirty);
}
ctx.endFrame();
```

`renderRegion` paints only the intersection of `region` with the viewport:
commands whose bounds miss it are culled, and a `clear` command clears *only*
that region — the rest of the framebuffer keeps the previous frame, which is
what makes partial repaint correct. Marking nothing lets you skip rendering
entirely. `render` (full frame) is unchanged. Correctness is the caller's
responsibility: mark everything whose final pixels changed, and keep in mind
that effects sampling neighbors (`.blur`, `.rect_shadow`) read the preserved
framebuffer. Per-frame allocation is already avoided — `DrawList` retains its
capacity and its text arena between frames.

Interactive widgets take part automatically: each control calls
`mark_hot(id, bounds, hot)` every frame, and the context repaints its bounds
both when the state starts (hover, press/drag, value change) and when it stops
— the previous frame's hot ids are retained so a highlight left behind in the
framebuffer is erased. Currently wired: `button`, `checkbox`, `radio`,
`switch`, `slider` (both orientations), `list_view`, `table`, `tree_view`,
`tab_bar`, `splitter`, `scroll`, `menu`, `text_input` and `textarea`. The
mechanism is conservative by
design: while hot, the widget is treated as changing and its own rect is
repainted every frame, while the rest of the frame stays skipped. A widget
that is no longer drawn is unknown to the context — mark its rect yourself.

### Multi-window registry

`WindowRegistry` is a pure, allocation-free model of the UI surfaces an
application presents: identity, geometry in desktop space, stacking order
(z-order) and focus. It owns no `Context` and draws nothing — it answers the
questions a host would ask.

```zig
var reg: zyntra_ui.WindowRegistry = .{};
try reg.add(main_id, zyntra_ui.Rect.init(0, 0, 800, 600));      // bottom
try reg.add(dialog_id, zyntra_ui.Rect.init(200, 150, 320, 200)); // on top

// Input: topmost visible surface under the cursor, raised and focused.
const focused = reg.activateAt(cursor); // ?Id

// Draw: bottom → top, one Context per surface.
for (reg.order()) |w| {
    const ctx = contextFor(w.id);
    try ctx.setViewport(w.viewport()); // (0, 0, w, h)
    // ... widgets ... then submit ctx.drawCommands()
}

// Coordinates: desktop ⇄ window-local.
if (reg.toLocal(main_id, cursor)) |local| { /* ... */ }
```

`windows[0]` is the bottom window and the topmost one wins the hit-test
(`windowAt`), skipping hidden surfaces. `add` does not activate anything, and
hiding a window leaves focus untouched — policy stays with your host. The
registry does not create OS windows; it organizes the surfaces you present.

#### Input routing

Bind each surface's `Context` once (`reg.bind(id, &ctx)`) and route events with
`window.input`. The positions you pass in are desktop-space; the events queued
in the context carry window-local coordinates.

```zig
var router: zyntra_ui.WindowRouter = .{};

// Press: raise + focus the surface under the cursor, then route it.
_ = zyntra_ui.window.input.focusAt(&reg, cursor);
if (try zyntra_ui.window.input.pushButton(&router, &reg, .left, true, cursor)) {
    // the surface under the cursor now captures the drag
}
// Moves keep going to the capturing surface even outside its bounds (local
// coordinates may be negative) — that is what keeps a widget drag alive.
_ = try zyntra_ui.window.input.pushMouseMove(&router, &reg, cursor);
// The release ends the capture (and without a capture it is dropped).
_ = try zyntra_ui.window.input.pushButton(&router, &reg, .left, false, cursor);

// The wheel follows the cursor; the keyboard goes to the active surface.
_ = try zyntra_ui.window.input.pushWheel(&reg, 0, dy, cursor);
_ = try zyntra_ui.window.input.pushKey(&reg, key, pressed, modifiers);
```

The topmost visible surface wins the hit-test, so a surface without a bound
context receives nothing (events do not fall through to the ones below).
Switching the active surface clears the outgoing surface's widget focus
(`focusWindow`), so a text input does not stay "focused" without receiving
keys.

#### Repaint composition

`window.compositor` paints the desktop into a single framebuffer, composing
each surface from its own (window-local) draw commands and repainting only
what changed: geometry, visibility and stacking changes are derived from a
snapshot, and the `dirty_rect` that widgets mark (hover, press, value change)
is consumed automatically.

```zig
var comp: zyntra_ui.WindowCompositor = .{};
defer comp.deinit(allocator);

// Per frame: mutations + one frame per surface (beginFrame → widgets →
// endFrame), then a single compose.
_ = try reg.setBounds(dialog_id, moved);        // move: no re-layout, no redraw
_ = try comp.compose(allocator, &fb, &reg, .{ .background = bg });
// Moving a window back recomposes the old bounds, a hidden one restores the
// background, raising one repaints the intersection, and an idle frame
// reports `damaged == 0` (nothing rendered at all).
comp.invalidate(rect);                          // host-driven damage (cursor…)
```

Surfaces without a bound context (or hidden) are not drawn — their area keeps
the background. First composition (or after `comp.reset()`) repaints the whole
desktop, since the framebuffer content is unknown. Composition uses the
reference rasterizer; the `Context`/`Registry`/framebuffer stay yours.

#### Interactive windows

`window.decorations` is the pure geometry of a window frame — title bar,
resize border, close button, client area — plus the hit-test that classifies a
desktop point. No drawing, no state; the same contract serves your renderer and
the drag:

```zig
const deco: zyntra_ui.WindowDecorationStyle = .{}; // title 24, border 4, button 16
const hit = zyntra_ui.window.decorations.hit(bounds, deco, cursor);
switch (hit) {
    .title, .close, .client => {},          // consumed / client: host routes it
    .resize => |e| hostSetCursor(e.right),  // host: resize cursor feedback
    .outside => {},
}
const bar = zyntra_ui.window.decorations.titleBar(bounds, deco); // draw it
```

`window.interact` turns routed desktop mouse input into registry mutations
(`moved`/`resized` never accumulate rounding error: they always apply the total
offset to the rect captured at press time). `WindowInteractor` holds the drag,
so a decoration press does not need the input router's capture:

```zig
var mgr: zyntra_ui.WindowInteractor = .{};
const opts: zyntra_ui.WindowInteractOptions = .{ .bounds = desktop }; // clamp + min size

// Press decides who consumes it:
switch (mgr.press(&reg, cursor, deco, opts)) {
    .move, .resize, .close => {},                              // consumed
    .client => { _ = zyntra_ui.window.input.focusAt(&reg, cursor); route(cursor); },
    .none => {},
}
if (mgr.isDragging()) {
    _ = try mgr.update(&reg, cursor, opts);   // geometry moves; compose sees damage
} else routeMove(cursor);
if (mgr.release()) |id| persistLayout(id);    // mgr.changed tells if it moved
mgr.cancel();                                 // Esc: restore from mgr.origin
```

Pressing the title bar or the border raises and focuses the surface before the
drag (`Options.activate`); pressing the client only focuses it. `.close` never
touches the registry — hiding or removing is your policy. Moves and resizes are
plain `setBounds` calls, so the compositor's snapshot damage already repaints
the vacated and the new area.

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

An optional C ABI is available for non-Zig consumers. It mirrors the Zig draw
surface — solid/outlined/rounded rectangles, lines, circles, linear gradients,
drop shadows, backdrop blur, clip, copied UTF-8 text runs and text metrics —
plus the context/frame/event lifecycle. The software rasterizer is reachable
too: an opaque framebuffer renders the frame's draw list (full or partial
repaint driven by the dirty rect) and single pixels can be read back. The
widget surface is exposed as well: stable ids
(`zyntra_id_from_string`/`zyntra_id_child`), the built-in dark/light theme
colors and per-widget styles (`zyntra_theme_colors`/`zyntra_style_*`), and
`label`/`button`/`checkbox`/`switch`/`slider`/`progress`/`separator` plus
the string-list widgets `radio`/`tab_bar`/`list_view`, the `panel`
container and the flat/recursive structures `menu`/`table`/`tree_view`,
plus `combo`/`splitter`/`spinner`/`groupbox`/`tooltip` (dropdown,
draggable divider, indeterminate indicator, titled box and hover hint),
with their interaction results (click, toggle, selection, drag, collapse,
menu choice, expander) handed back to C. Keyboard input and focus are part
of the same surface (`zyntra_context_push_key`/`_push_text`/`_focus` plus the
`ZyntraKey` mirror), so C consumers drive the same keys the Zig widgets
handle, and the text fields (`text_input`, `text_input_selected`, `textarea`)
edit caller-owned buffers with no allocation inside the library. See
[`src/c-abi/zyntra.h`](src/c-abi/zyntra.h) and [`docs/C_ABI.md`](docs/C_ABI.md)
for the exported interface and integration details.

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
