//! ZyntraUI — grupo de radio (widgets/radio).
//!
//! Modelo M25 (seleção exclusiva, estado no chamador):
//! - `radio(ctx,id,bounds,options,selected,font,style)`: uma opção por
//!   linha (`row_h` da fonte + padding); `selected: *usize` do chamador.
//! - Hover destaca; click seleciona (`changed`); click foca (registrado
//!   para o Tab). Setas/Home/End com foco movem E selecionam (wrap).
//! - MVP sem opções desabilitadas (documentado, futuro).
//! Desenho por linha: círculo + ponto (se selecionado) + texto.
//! `options` vazio ou `selected` fora da faixa → `InvalidArgument`.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const metrics_mod = @import("../text/metrics.zig");
const input = @import("input.zig");

pub const RadioResult = struct {
    changed: bool = false,
    hovered: bool = false,
    focused: bool = false,
};

fn rowHeight(font: metrics_mod.FontMetrics) f32 {
    return font.lineHeight() + 8;
}

pub fn radio(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    options: []const []const u8,
    selected: *usize,
    font: metrics_mod.FontMetrics,
    style: style_mod.RadioStyle,
) context_mod.ContextError!RadioResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid() or !font.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;
    if (options.len == 0 or options.len > 256) return error.InvalidArgument;
    if (selected.* >= options.len) return error.InvalidArgument;

    var res = RadioResult{};
    const fm = input.FrameMouse.scan(ctx.pendingEvents());
    try ctx.registerFocusable(id);
    if (fm.pressedInside(bounds)) {
        ctx.focus_owner = id;
    }
    const focused = ctx.hasFocus(id);
    res.focused = focused;
    const hovered = if (ctx.mouse_pos) |p| bounds.contains(p) else false;
    res.hovered = hovered;

    const rh = rowHeight(font);

    // Click seleciona (one-shot por press).
    if (fm.pressed_pos) |p| {
        if (bounds.contains(p)) {
            const idx: usize = @intFromFloat(@min(@floor((p.y - bounds.y) / rh), @as(f32, @floatFromInt(options.len - 1))));
            if (idx < options.len and idx != selected.*) {
                selected.* = idx;
                res.changed = true;
            }
        }
    }

    if (focused) {
        for (ctx.pendingEvents()) |ev| {
            if (ev != .key) continue;
            const k = ev.key;
            if (!k.pressed) continue;
            switch (k.key) {
                .up => {
                    selected.* = (selected.* + options.len - 1) % options.len;
                    res.changed = true;
                },
                .down => {
                    selected.* = (selected.* + 1) % options.len;
                    res.changed = true;
                },
                .home => {
                    if (selected.* != 0) {
                        selected.* = 0;
                        res.changed = true;
                    }
                },
                .end => {
                    if (selected.* != options.len - 1) {
                        selected.* = options.len - 1;
                        res.changed = true;
                    }
                },
                else => {},
            }
        }
    }

    // Desenho: círculo + ponto + texto por linha.
    const r = @min(style.radio_r, rh / 2 - 1);
    var i: usize = 0;
    while (i < options.len) : (i += 1) {
        const cy = bounds.y + @as(f32, @floatFromInt(i)) * rh + rh / 2;
        const cx = bounds.x + 4 + r;
        ctx.draw.circleFilled(ctx.allocator, .{ .x = cx, .y = cy }, r, style.box) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
        };
        if (i == selected.*) {
            ctx.draw.circleFilled(ctx.allocator, .{ .x = cx, .y = cy }, r / 2, style.dot) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidCommand => return error.InvalidCommand,
            };
        }
        if (options[i].len > 0) {
            ctx.draw.pushText(
                ctx.allocator,
                .{ .x = bounds.x + 8 + 2 * r, .y = bounds.y + @as(f32, @floatFromInt(i)) * rh + 4 },
                style.text,
                font,
                options[i],
            ) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidCommand => return error.InvalidCommand,
                error.InvalidUtf8 => return error.InvalidArgument,
                error.InvalidMetrics => return error.InvalidArgument,
            };
        }
    }
    return res;
}

test "radio click seleciona, setas circulam, contratos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10); // rh=18.625
    const style = style_mod.Theme.darkDefault().radioStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 160, 60);
    const id = id_mod.Id.fromString("test:radio");
    const opts = [_][]const u8{ "A", "B", "C" };
    var sel: usize = 0;

    // Click na linha 2 (y=40 → idx 2).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(10, 40) },
    });
    const r0 = try radio(&ctx, id, bounds, &opts, &sel, font, style);
    try stdt.testing.expect(r0.changed and r0.focused);
    try stdt.testing.expectEqual(@as(usize, 2), sel);
    ctx.endFrame();

    // Click na mesma linha: sem changed. Seta sobe e dá wrap.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(10, 40) },
    });
    const r1 = try radio(&ctx, id, bounds, &opts, &sel, font, style);
    try stdt.testing.expect(!r1.changed);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .up, .pressed = true, .modifiers = .{} } });
    _ = try radio(&ctx, id, bounds, &opts, &sel, font, style);
    try stdt.testing.expectEqual(@as(usize, 1), sel);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .up, .pressed = true, .modifiers = .{} } });
    _ = try radio(&ctx, id, bounds, &opts, &sel, font, style);
    try stdt.testing.expectEqual(@as(usize, 2), sel); // wrap 0→2
    ctx.endFrame();

    // Contratos.
    ctx.beginFrame();
    const empty = [_][]const u8{};
    var bad: usize = 9;
    try stdt.testing.expectError(error.InvalidArgument, radio(&ctx, .null, bounds, &opts, &sel, font, style));
    try stdt.testing.expectError(error.InvalidArgument, radio(&ctx, id, bounds, &empty, &sel, font, style));
    try stdt.testing.expectError(error.InvalidArgument, radio(&ctx, id, bounds, &opts, &bad, font, style));
    ctx.endFrame();
}

test "radio limites: End, teto de opções, estilo e bounds NaN" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().radioStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 160, 60);
    const id = id_mod.Id.fromString("test:radio-lim");
    const opts = [_][]const u8{ "A", "B", "C" };
    var sel: usize = 0;

    // Foca com click; End salta para a última.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(10, 5) },
    });
    _ = try radio(&ctx, id, bounds, &opts, &sel, font, style);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{} } });
    const r0 = try radio(&ctx, id, bounds, &opts, &sel, font, style);
    try stdt.testing.expect(r0.changed);
    try stdt.testing.expectEqual(@as(usize, 2), sel);
    ctx.endFrame();

    // Teto de 256 opções, estilo inválido e bounds NaN: InvalidArgument.
    ctx.beginFrame();
    var many: [257][]const u8 = undefined;
    for (&many) |*o| o.* = "x";
    try stdt.testing.expectError(error.InvalidArgument, radio(&ctx, id, bounds, &many, &sel, font, style));
    var bad_style = style;
    bad_style.radio_r = 0;
    try stdt.testing.expectError(error.InvalidArgument, radio(&ctx, id, bounds, &opts, &sel, font, bad_style));
    const nan_bounds = types.Rect.init(0, 0, std.math.nan(f32), 60);
    try stdt.testing.expectError(error.InvalidArgument, radio(&ctx, id, nan_bounds, &opts, &sel, font, style));
    ctx.endFrame();
}
