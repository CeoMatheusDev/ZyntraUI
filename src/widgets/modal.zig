//! ZyntraUI — janela modal (widgets/modal).
//!
//! Modelo M27 (begin/end, estado no chamador):
//! - `beginModal` escurece a vista inteira, desenha o painel e emite
//!   `clip(bounds)`; `endModal` limpa o clip. SEMPRE parear.
//! - Bloqueio por CONVENÇÃO (documentada, sem invasão nos widgets):
//!   com o modal aberto, o chamador NÃO sonda widgets de trás
//!   (padrão `if (open) { modal } else { fundo }`). Sem flag global.
//! - Dismiss: press fora do painel ou `Escape` → `dismissed=true`
//!   (o chamador fecha, ex. `open=false`).
//! `id` não-nulo; sem estado retido (aberto/fechado é do chamador).

const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const input = @import("input.zig");

pub const ModalResult = struct {
    dismissed: bool = false,
    hovered: bool = false,
};

pub fn beginModal(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    style: style_mod.ModalStyle,
) context_mod.ContextError!ModalResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid()) return error.InvalidArgument;
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;

    const fm = input.FrameMouse.scan(ctx.pendingEvents());
    const hovered = if (ctx.mouse_pos) |p| bounds.contains(p) else false;
    var res = ModalResult{ .hovered = hovered };
    if (fm.pressed_pos) |p| {
        if (!bounds.contains(p)) res.dismissed = true;
    }
    for (ctx.pendingEvents()) |ev| {
        if (ev != .key) continue;
        const k = ev.key;
        if (k.pressed and k.key == .escape) res.dismissed = true;
    }

    ctx.draw.rectFilled(ctx.allocator, ctx.viewport, style.dim) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.rectFilled(ctx.allocator, bounds, style.bg) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.rectOutline(ctx.allocator, bounds, style.border, @max(1.0, style.border_width)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = bounds, .null_rect = false } }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    return res;
}

/// Limpa o clip do `beginModal` correspondente.
pub fn endModal(ctx: *context_mod.Context) context_mod.ContextError!void {
    ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = .{}, .null_rect = true } }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
}

test "modal dim, painel, dispensa fora e com Escape" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().modalStyle();
    var ctx = try context_mod.Context.init(gpa, .{
        .viewport = types.Rect.init(0, 0, 800, 600),
    });
    defer ctx.deinit();
    const bounds = types.Rect.init(300, 200, 200, 150);
    const id = id_mod.Id.fromString("test:modal");

    // Press dentro: mantém (dim + painel×2 + clip + clear = 5).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(400, 250) },
    });
    const keep = try beginModal(&ctx, id, bounds, style);
    try stdt.testing.expect(!keep.dismissed and keep.hovered);
    try endModal(&ctx);
    try stdt.testing.expectEqual(@as(usize, 5), ctx.drawCommands().len);
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 800, 600), ctx.drawCommands()[0].rect_filled.rect);
    ctx.endFrame();

    // Press fora e Escape dispensam.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(10, 10) },
    });
    const out = try beginModal(&ctx, id, bounds, style);
    try stdt.testing.expect(out.dismissed);
    try endModal(&ctx);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .escape, .pressed = true, .modifiers = .{} } });
    const esc = try beginModal(&ctx, id, bounds, style);
    try stdt.testing.expect(esc.dismissed);
    try endModal(&ctx);
    ctx.endFrame();

    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, beginModal(&ctx, .null, bounds, style));
    ctx.endFrame();
}
