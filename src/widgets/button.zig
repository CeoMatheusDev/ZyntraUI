//! ZyntraUI — botão (widgets/button).
//!
//! Modelo M3 (press-to-activate, documentado):
//! - `hovered`: última posição conhecida dentro de `bounds`.
//! - `pressed/clicked`: houve `mouse_button left pressed` dentro.
//!   `clicked == pressed` nesta milestone (sem tracking de
//!   press/release entre frames; M4 adicionará release-to-activate).
//! Ownership: sem estado retido; chamador detém `bounds`/`style`.
//! O `id` deve ser não-nulo (identidade estável para M4+ e C-ABI).
//! Emite 2 comandos (fill + outline). Erros: OOM ou estilo inválido.

const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const input = @import("input.zig");

pub const ButtonResult = struct {
    hovered: bool = false,
    pressed: bool = false,
    clicked: bool = false,
};

pub fn button(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    style: style_mod.ButtonStyle,
) context_mod.ContextError!ButtonResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid()) return error.InvalidArgument;
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;

    const scan = input.MouseScan.scan(ctx.pendingEvents(), bounds);
    const res = ButtonResult{
        .hovered = scan.hovered,
        .pressed = scan.pressed,
        .clicked = scan.pressed,
    };
    const bg = if (res.pressed)
        style.bg_pressed
    else if (res.hovered)
        style.bg_hover
    else
        style.bg;

    ctx.draw.rectFilled(ctx.allocator, bounds, bg) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.rectOutline(ctx.allocator, bounds, style.border, @max(1.0, style.border_width)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    return res;
}

test "button hover/click + 2 draws" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const theme = style_mod.Theme.darkDefault();
    const style = theme.buttonStyle();

    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(10, 10, 120, 40);
    const id = id_mod.Id.fromString("test:btn");

    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(20, 20) } });
    const hover = try button(&ctx, id, bounds, style);
    try stdt.testing.expect(hover.hovered);
    try stdt.testing.expect(!hover.clicked);
    try stdt.testing.expectEqual(@as(usize, 2), ctx.drawCommands().len);
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(20, 20) },
    });
    const click = try button(&ctx, id, bounds, style);
    try stdt.testing.expect(click.clicked);
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(500, 500) },
    });
    const outside = try button(&ctx, id, bounds, style);
    try stdt.testing.expect(!outside.clicked);
    try stdt.testing.expect(!outside.hovered);
    ctx.endFrame();

    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, button(&ctx, .null, bounds, style));
    ctx.endFrame();
}
