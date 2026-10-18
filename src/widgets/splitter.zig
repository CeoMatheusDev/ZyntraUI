//! ZyntraUI — splitter arrastável (widgets/splitter).
//!
//! Modelo M57: `beginSplitter`/`endSplitter` com estado no chamador.
//! - `pos: *f32` — posição da divisória (px do chamador, clampado).
//! - `SplitterOrientation` — `.horizontal` (divide verticalmente,
//!   pos = y) ou `.vertical` (divide horizontalmente, pos = x).
//! - Mouse: press na divisória captura; drag move; release encerra.
//! - Teclado com foco: setas ajustam em 8 px, Home/End saltam.
//! - `splitterPanes(bounds, orientation, pos, style)` (M74): divisão pura
//!   em dois lados + faixa da divisória, para aninhar painéis (item 6).
//! - `SplitterStyle` + `Theme.splitterStyle()` — cores, largura.
//! `id` não-nulo obrigatório.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const input = @import("input.zig");

pub const SplitterOrientation = enum {
    horizontal, // pos = y
    vertical, // pos = x
};

pub const SplitterResult = struct {
    pos: f32 = 0,
    changed: bool = false,
    hovered: bool = false,
    dragging: bool = false,
};

pub fn splitterHandleRect(
    bounds: types.Rect,
    orientation: SplitterOrientation,
    pos: f32,
    style: style_mod.SplitterStyle,
) types.Rect {
    return switch (orientation) {
        .horizontal => types.Rect.init(bounds.x, pos - style.handle_h / 2, bounds.w, style.handle_h),
        .vertical => types.Rect.init(pos - style.handle_w / 2, bounds.y, style.handle_w, bounds.h),
    };
}

pub fn splitterClampPos(bounds: types.Rect, orientation: SplitterOrientation, pos: f32) f32 {
    const lo = switch (orientation) {
        .horizontal => bounds.y,
        .vertical => bounds.x,
    };
    const hi = switch (orientation) {
        .horizontal => bounds.y + bounds.h,
        .vertical => bounds.x + bounds.w,
    };
    if (hi <= lo) return lo;
    return std.math.clamp(pos, lo, hi);
}

/// Divisão de uma área em dois lados + a faixa da divisória, em torno de
/// `pos` (px do chamador, clampado). Pura — base para aninhar painéis
/// (item 6): o chamador posiciona os filhos em `a`/`b` e passa `divider`
/// ao próprio `beginSplitter`. Áreas nunca negativas.
pub const SplitterPanes = struct {
    /// Lado inicial (antes da divisória).
    a: types.Rect,
    /// Lado final (depois da divisória).
    b: types.Rect,
    /// Faixa ocupada pela divisória (espessura = handle do estilo).
    divider: types.Rect,
};

pub fn splitterPanes(
    bounds: types.Rect,
    orientation: SplitterOrientation,
    pos: f32,
    style: style_mod.SplitterStyle,
) SplitterPanes {
    const p = splitterClampPos(bounds, orientation, pos);
    switch (orientation) {
        .horizontal => {
            const half = style.handle_h / 2;
            const d0 = @max(bounds.y, p - half);
            const d1 = @min(bounds.y + bounds.h, p + half);
            return .{
                .a = .{ .x = bounds.x, .y = bounds.y, .w = bounds.w, .h = @max(0, d0 - bounds.y) },
                .divider = .{ .x = bounds.x, .y = d0, .w = bounds.w, .h = @max(0, d1 - d0) },
                .b = .{ .x = bounds.x, .y = d1, .w = bounds.w, .h = @max(0, bounds.y + bounds.h - d1) },
            };
        },
        .vertical => {
            const half = style.handle_w / 2;
            const d0 = @max(bounds.x, p - half);
            const d1 = @min(bounds.x + bounds.w, p + half);
            return .{
                .a = .{ .x = bounds.x, .y = bounds.y, .w = @max(0, d0 - bounds.x), .h = bounds.h },
                .divider = .{ .x = d0, .y = bounds.y, .w = @max(0, d1 - d0), .h = bounds.h },
                .b = .{ .x = d1, .y = bounds.y, .w = @max(0, bounds.x + bounds.w - d1), .h = bounds.h },
            };
        },
    }
}

pub fn beginSplitter(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    orientation: SplitterOrientation,
    pos: *f32,
    style: style_mod.SplitterStyle,
) context_mod.ContextError!SplitterResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;
    if (!std.math.isFinite(pos.*)) return error.InvalidArgument;

    pos.* = splitterClampPos(bounds, orientation, pos.*);
    const entry = pos.*;

    const fm = input.FrameMouse.scan(ctx.pendingEvents());
    const handle = splitterHandleRect(bounds, orientation, pos.*, style);
    const hovered = if (ctx.mouse_pos) |p| handle.contains(p) else false;
    var res = SplitterResult{ .pos = pos.*, .hovered = hovered };

    try ctx.registerFocusable(id);
    if (fm.pressedInside(handle)) {
        ctx.focus_owner = id;
    }

    if (ctx.press_owner == null and fm.pressedInside(handle)) {
        ctx.press_owner = id;
    }
    if (ctx.press_owner == id) {
        if (ctx.mouse_down_left) {
            res.dragging = true;
            if (ctx.mouse_pos) |p| {
                pos.* = switch (orientation) {
                    .horizontal => p.y,
                    .vertical => p.x,
                };
                pos.* = splitterClampPos(bounds, orientation, pos.*);
            }
        }
        if (fm.released_pos != null) {
            ctx.press_owner = null;
            res.dragging = false;
        }
    }

    if (ctx.hasFocus(id)) {
        for (ctx.pendingEvents()) |ev| {
            if (ev != .key) continue;
            const k = ev.key;
            if (!k.pressed or k.modifiers.ctrl) continue;
            switch (k.key) {
                .left, .up => pos.* = splitterClampPos(bounds, orientation, pos.* - 8),
                .right, .down => pos.* = splitterClampPos(bounds, orientation, pos.* + 8),
                .home => pos.* = switch (orientation) {
                    .horizontal => bounds.y,
                    .vertical => bounds.x,
                },
                .end => pos.* = switch (orientation) {
                    .horizontal => bounds.y + bounds.h,
                    .vertical => bounds.x + bounds.w,
                },
                .tab => ctx.requestFocusAdvance(if (k.modifiers.shift) .prev else .next),
                else => {},
            }
        }
    }

    res.pos = pos.*;
    res.changed = pos.* != entry;

    // Estado de interação (M105): hover/arraste realçam o puxador e a
    // mudança de posição move as divisórias ⇒ alimenta o dirty rect.
    try ctx.mark_hot(id, bounds, res.hovered or res.dragging or res.changed);

    ctx.draw.rectFilled(ctx.allocator, bounds, style.bg) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    const handle_color = if (res.dragging) style.bg_drag else if (res.hovered) style.bg_hover else style.bg;
    ctx.draw.rectFilled(ctx.allocator, handle, handle_color) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };

    return res;
}

/// Fim do splitter (M57): NO-OP — sem estado retido, sem draws.
/// Existe apenas para simetria de pareamento com outros widgets.
pub fn endSplitter(_: *context_mod.Context) void {}
test "Splitter drag, clamp, teclado" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().splitterStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 400, 300);
    const id = id_mod.Id.fromString("test:split");
    var pos: f32 = 150;

    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(200, 150) },
    });
    const r0 = try beginSplitter(&ctx, id, bounds, .horizontal, &pos, style);
    try stdt.testing.expect(r0.dragging);
    try stdt.testing.expectEqual(@as(f32, 150), pos);
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(200, 200) } });
    const r1 = try beginSplitter(&ctx, id, bounds, .horizontal, &pos, style);
    try stdt.testing.expect(r1.dragging and r1.changed);
    try stdt.testing.expectEqual(@as(f32, 200), pos);
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(200, 9999) } });
    _ = try beginSplitter(&ctx, id, bounds, .horizontal, &pos, style);
    try stdt.testing.expectEqual(@as(f32, 300), pos);
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(200, 9999) },
    });
    const r2 = try beginSplitter(&ctx, id, bounds, .horizontal, &pos, style);
    try stdt.testing.expect(!r2.dragging and ctx.press_owner == null);
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    _ = try beginSplitter(&ctx, id, bounds, .horizontal, &pos, style);
    try stdt.testing.expectEqual(@as(f32, 0), pos);
    ctx.endFrame();

    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, beginSplitter(&ctx, .null, bounds, .horizontal, &pos, style));
    try stdt.testing.expectError(error.InvalidArgument, beginSplitter(&ctx, id, types.Rect.init(0, 0, 0, 0), .horizontal, &pos, style));
    const bad_style = style_mod.SplitterStyle{ .handle_w = -1, .bg = .{}, .bg_hover = .{}, .bg_drag = .{}, .handle_h = 8.0 };
    try stdt.testing.expectError(error.InvalidArgument, beginSplitter(&ctx, id, bounds, .horizontal, &pos, bad_style));
    ctx.endFrame();
}

test "splitter vertical, limites de pos e bounds NaN" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().splitterStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 400, 300);
    const id = id_mod.Id.fromString("test:split-v");
    var pos: f32 = 9999; // fora da faixa → clampa na entrada

    // Pos inicial além do máximo clampa sem changed.
    ctx.beginFrame();
    const r0 = try beginSplitter(&ctx, id, bounds, .vertical, &pos, style);
    try stdt.testing.expectEqual(@as(f32, 400), pos);
    try stdt.testing.expect(!r0.changed);
    ctx.endFrame();

    // Press no handle vertical (x=400, handle_w=8 → faixa 396..404):
    // captura e drag segue o mouse X.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(400, 150) },
    });
    const r1 = try beginSplitter(&ctx, id, bounds, .vertical, &pos, style);
    try stdt.testing.expect(r1.dragging);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(100, 150) } });
    const r2 = try beginSplitter(&ctx, id, bounds, .vertical, &pos, style);
    try stdt.testing.expect(r2.dragging and r2.changed);
    try stdt.testing.expectEqual(@as(f32, 100), pos);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(100, 150) },
    });
    _ = try beginSplitter(&ctx, id, bounds, .vertical, &pos, style);
    try stdt.testing.expect(ctx.press_owner == null);
    ctx.endFrame();

    // Teclado vertical: Left/Right ajustam, Home/End saltam.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(100, 150) },
    });
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(100, 150) },
    });
    _ = try beginSplitter(&ctx, id, bounds, .vertical, &pos, style);
    try stdt.testing.expect(ctx.hasFocus(id));
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{} } });
    _ = try beginSplitter(&ctx, id, bounds, .vertical, &pos, style);
    try stdt.testing.expectEqual(@as(f32, 92), pos);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{} } });
    _ = try beginSplitter(&ctx, id, bounds, .vertical, &pos, style);
    try stdt.testing.expectEqual(@as(f32, 400), pos);
    ctx.endFrame();

    // Pos e bounds não-finitos: InvalidArgument, sem corromper pos.
    ctx.beginFrame();
    var nan_pos: f32 = std.math.nan(f32);
    try stdt.testing.expectError(error.InvalidArgument, beginSplitter(&ctx, id, bounds, .vertical, &nan_pos, style));
    const nan_bounds = types.Rect.init(std.math.nan(f32), 0, 400, 300);
    const before = pos;
    try stdt.testing.expectError(error.InvalidArgument, beginSplitter(&ctx, id, nan_bounds, .vertical, &pos, style));
    try stdt.testing.expectEqual(before, pos);
    ctx.endFrame();
}

test "splitterPanes: dois lados + divisória, clamp e aninhamento" {
    const stdt = @import("std");
    const style = style_mod.Theme.darkDefault().splitterStyle(); // handle 8
    const bounds = types.Rect.init(0, 0, 400, 300);

    // Horizontal (pos = y): divisória centrada em 150.
    const h = splitterPanes(bounds, .horizontal, 150, style);
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 400, 146), h.a);
    try stdt.testing.expectEqual(types.Rect.init(0, 146, 400, 8), h.divider);
    try stdt.testing.expectEqual(types.Rect.init(0, 154, 400, 146), h.b);

    // Vertical (pos = x).
    const v = splitterPanes(bounds, .vertical, 100, style);
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 96, 300), v.a);
    try stdt.testing.expectEqual(types.Rect.init(96, 0, 8, 300), v.divider);
    try stdt.testing.expectEqual(types.Rect.init(104, 0, 296, 300), v.b);

    // Pos clampa à borda: lado final fica vazio, sem medidas negativas.
    const edge = splitterPanes(bounds, .horizontal, 9999, style);
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 400, 296), edge.a);
    try stdt.testing.expectEqual(types.Rect.init(0, 296, 400, 4), edge.divider);
    try stdt.testing.expectEqual(@as(f32, 0), edge.b.h);

    // Aninhamento: divide o lado `a` de novo (grade 2x2 determinística).
    const top_left = splitterPanes(h.a, .vertical, 200, style);
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 196, 146), top_left.a);
    try stdt.testing.expectEqual(types.Rect.init(204, 0, 196, 146), top_left.b);
}

test "splitter alimenta o dirty rect (M105): hover e arraste marcam os bounds" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().splitterStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 100);
    const id = id_mod.Id.fromString("test:sp:hot");
    var pos: f32 = 100;
    const away = types.Vec2.init(500, 500);
    const handle = types.Vec2.init(100, 50); // puxador (pos=100, largura 8)

    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = away } });
    _ = try beginSplitter(&ctx, id, bounds, .vertical, &pos, style);
    try stdt.testing.expect(ctx.dirty_rect.isEmpty());
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = handle } });
    _ = try beginSplitter(&ctx, id, bounds, .vertical, &pos, style);
    try stdt.testing.expectEqual(bounds, ctx.dirty_rect);
    ctx.endFrame();

    // Arraste: o puxador se move com o mouse ⇒ a divisória é repintada.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{ .button = .left, .pressed = true, .pos = handle } });
    const dragging = try beginSplitter(&ctx, id, bounds, .vertical, &pos, style);
    try stdt.testing.expect(dragging.dragging);
    try stdt.testing.expectEqual(bounds, ctx.dirty_rect);
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = away } });
    try ctx.pushEvent(.{ .mouse_button = .{ .button = .left, .pressed = false, .pos = away } });
    _ = try beginSplitter(&ctx, id, bounds, .vertical, &pos, style);
    try stdt.testing.expectEqual(bounds, ctx.dirty_rect);
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = away } });
    _ = try beginSplitter(&ctx, id, bounds, .vertical, &pos, style);
    try stdt.testing.expect(ctx.dirty_rect.isEmpty());
    ctx.endFrame();
}
