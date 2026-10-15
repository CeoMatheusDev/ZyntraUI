//! ZyntraUI — splitter arrastável (widgets/splitter).
//!
//! Modelo M57: `beginSplitter`/`endSplitter` com estado no chamador.
//! - `pos: *f32` — posição da divisória (px do chamador, clampado).
//! - `SplitterOrientation` — `.horizontal` (divide verticalmente,
//!   pos = y) ou `.vertical` (divide horizontalmente, pos = x).
//! - Mouse: press na divisória captura; drag move; release encerra.
//! - Teclado com foco: setas ajustam em 8 px, Home/End saltam.
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
