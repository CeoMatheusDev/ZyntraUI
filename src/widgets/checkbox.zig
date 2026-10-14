//! ZyntraUI — checkbox (widgets/checkbox).
//!
//! Estado (`checked: *bool`) pertence ao chamador (padrão ImGui-like),
//! o `Context` não retém estado de widgets na M3.
//! Transição: `pressed-inside` alterna `checked` uma vez por frame
//! (múltiplos presses no mesmo frame contam como um).
//! Desenho: caixa externa (bg ou bg_checked) + outline + marca interna
//! insetada quando marcado. Emite 2-3 comandos.
//! `id` não-nulo obrigatório; `box` deve ter tamanho > 0.

const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const input = @import("input.zig");

pub const CheckboxResult = struct {
    hovered: bool = false,
    toggled: bool = false,
    checked: bool = false,
};

pub fn checkbox(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    box: types.Rect,
    checked: *bool,
    style: style_mod.CheckboxStyle,
) context_mod.ContextError!CheckboxResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid()) return error.InvalidArgument;
    if (box.w <= 0 or box.h <= 0) return error.InvalidArgument;

    const scan = input.MouseScan.scan(ctx.pendingEvents(), box);
    var res = CheckboxResult{ .hovered = scan.hovered, .checked = checked.* };
    if (scan.pressed) {
        checked.* = !checked.*;
        res.toggled = true;
        res.checked = checked.*;
    }

    const bg = if (checked.*) style.bg_checked else style.bg;
    ctx.draw.rectFilled(ctx.allocator, box, bg) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.rectOutline(ctx.allocator, box, style.border, @max(1.0, style.border_width)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    if (checked.*) {
        const inset: f32 = @min(box.w, box.h) * 0.25;
        const mark = types.Rect{
            .x = box.x + inset,
            .y = box.y + inset,
            .w = @max(1, box.w - inset * 2),
            .h = @max(1, box.h - inset * 2),
        };
        ctx.draw.rectFilled(ctx.allocator, mark, style.check) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
        };
    }
    return res;
}

test "checkbox alterna dentro e ignora fora" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().checkboxStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const box = types.Rect.init(0, 0, 18, 18);
    const id = id_mod.Id.fromString("test:chk");
    var checked = false;

    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    const r1 = try checkbox(&ctx, id, box, &checked, style);
    try stdt.testing.expect(r1.toggled);
    try stdt.testing.expect(checked);
    try stdt.testing.expectEqual(@as(usize, 3), ctx.drawCommands().len);
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(500, 500) },
    });
    const r2 = try checkbox(&ctx, id, box, &checked, style);
    try stdt.testing.expect(!r2.toggled);
    try stdt.testing.expect(checked);
    ctx.endFrame();

    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, checkbox(&ctx, .null, box, &checked, style));
    ctx.endFrame();
}
