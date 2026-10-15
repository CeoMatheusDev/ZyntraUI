//! ZyntraUI — popup flutuante (widgets/popup).
//!
//! Modelo M18 (begin/end, estado no chamador):
//! - `beginPopup` desenha painel (fundo + borda) e emite `clip(bounds)`;
//!   conteúdo entre begin/end sai clippado; `endPopup` limpa o clip.
//!   SEMPRE parear.
//! - Dismiss: press esquerdo FORA de `bounds` neste frame →
//!   `dismissed=true` (o chamador fecha, ex. `open=false`). `Escape`
//!   NÃO dispensa (futuro; hoje é do text-input focado).
//! - Eventos são broadcast: press fora dispensa mesmo com outro widget
//!   capturado (captura alheia preservada; fechar com drag ativo é
//!   decisão do app).
//! `id` não-nulo; sem estado retido (aberto/fechado é do chamador).

const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const input = @import("input.zig");

pub const PopupResult = struct {
    dismissed: bool = false,
    hovered: bool = false,
};

pub fn beginPopup(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    style: style_mod.PopupStyle,
) context_mod.ContextError!PopupResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid()) return error.InvalidArgument;
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;

    const fm = input.FrameMouse.scan(ctx.pendingEvents());
    const hovered = if (ctx.mouse_pos) |p| bounds.contains(p) else false;
    var res = PopupResult{ .hovered = hovered };
    if (fm.pressed_pos) |p| {
        if (!bounds.contains(p)) res.dismissed = true;
    }

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

/// Limpa o clip do `beginPopup` correspondente.
pub fn endPopup(ctx: *context_mod.Context) context_mod.ContextError!void {
    ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = .{}, .null_rect = true } }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
}

test "popup dispensa fora, mantém dentro" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().popupStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(100, 100, 160, 120);
    const id = id_mod.Id.fromString("test:pop");

    // Press dentro: mantém (3 draws begin + 1 end).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(150, 150) },
    });
    const keep = try beginPopup(&ctx, id, bounds, style);
    try stdt.testing.expect(!keep.dismissed and keep.hovered);
    try endPopup(&ctx);
    try stdt.testing.expectEqual(@as(usize, 4), ctx.drawCommands().len);
    try stdt.testing.expect(ctx.drawCommands()[2] == .clip);
    ctx.endFrame();

    // Press fora: dispensa.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(10, 10) },
    });
    const out = try beginPopup(&ctx, id, bounds, style);
    try stdt.testing.expect(out.dismissed and !out.hovered);
    try endPopup(&ctx);
    ctx.endFrame();

    // Botão direito fora não dispensa (só esquerdo).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .right, .pressed = true, .pos = types.Vec2.init(10, 10) },
    });
    const rclick = try beginPopup(&ctx, id, bounds, style);
    try stdt.testing.expect(!rclick.dismissed);
    try endPopup(&ctx);
    ctx.endFrame();

    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, beginPopup(&ctx, .null, bounds, style));
    ctx.endFrame();
}
