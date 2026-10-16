//! ZyntraUI — separador estático (widgets/separator).
//!
//! Modelo M66 (display puro: sem `id`, sem interação, sem estado):
//! - `separatorLineRect(bounds, orientation, thickness)`: retângulo da
//!   linha centralizada (puro; útil para layout).
//! - `separator(ctx, bounds, orientation, style)`: 1 comando (linha).
//! - `separatorLabeled(...)`: linha **horizontal** com rótulo
//!   centralizado — 2 segmentos laterais + 1 texto (rótulo vazio ⇒
//!   linha simples). Se o rótulo não couber com os vãos, só ele é
//!   desenhado (documentado).
//! - `horizontal` separa itens empilhados; `vertical`, itens lado a
//!   lado. Rótulo só no eixo horizontal (texto não gira).
//! Reusa `SeparatorStyle` + `Theme.separatorStyle()`.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const style_mod = @import("../style/style.zig");
const metrics_mod = @import("../text/metrics.zig");

pub const SeparatorOrientation = enum { horizontal, vertical };

/// Retângulo da linha centralizada em `bounds`, com espessura `thickness`
/// (valores <= 0 viram 0). Determinístico e sem alocação.
pub fn separatorLineRect(
    bounds: types.Rect,
    orientation: SeparatorOrientation,
    thickness: f32,
) types.Rect {
    const t = @max(0, thickness);
    return switch (orientation) {
        .horizontal => .{
            .x = bounds.x,
            .y = bounds.y + @max(0, (bounds.h - t) * 0.5),
            .w = bounds.w,
            .h = t,
        },
        .vertical => .{
            .x = bounds.x + @max(0, (bounds.w - t) * 0.5),
            .y = bounds.y,
            .w = t,
            .h = bounds.h,
        },
    };
}

/// Linha divisória simples (1 comando de desenho).
pub fn separator(
    ctx: *context_mod.Context,
    bounds: types.Rect,
    orientation: SeparatorOrientation,
    style: style_mod.SeparatorStyle,
) context_mod.ContextError!void {
    if (!style.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;
    try fill(ctx, separatorLineRect(bounds, orientation, style.thickness), style.color);
}

/// Linha horizontal com rótulo centralizado. `vertical` ou `font`
/// inválida ⇒ `InvalidArgument` (texto não gira).
pub fn separatorLabeled(
    ctx: *context_mod.Context,
    bounds: types.Rect,
    orientation: SeparatorOrientation,
    label: []const u8,
    font: metrics_mod.FontMetrics,
    text_color: types.Color,
    style: style_mod.SeparatorStyle,
) context_mod.ContextError!void {
    if (orientation != .horizontal) return error.InvalidArgument;
    if (!style.isValid() or !font.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;
    if (label.len == 0) return separator(ctx, bounds, orientation, style);

    const m = metrics_mod.measure(label, font) catch return error.InvalidArgument;
    const line = separatorLineRect(bounds, .horizontal, style.thickness);
    const text_x = bounds.x + @max(0, (bounds.w - m.width) * 0.5);
    const gap = style.label_gap;
    const left_edge = text_x - gap;
    const right_edge = text_x + m.width + gap;
    const right_limit = bounds.x + bounds.w;

    // Segmentos laterais: só quando há espaço além dos vãos.
    if (left_edge > bounds.x) {
        try fill(ctx, .{ .x = bounds.x, .y = line.y, .w = left_edge - bounds.x, .h = line.h }, style.color);
    }
    if (right_edge < right_limit) {
        try fill(ctx, .{ .x = right_edge, .y = line.y, .w = right_limit - right_edge, .h = line.h }, style.color);
    }
    ctx.draw.pushText(
        ctx.allocator,
        .{ .x = text_x, .y = bounds.y + @max(0, (bounds.h - font.lineHeight()) * 0.5) },
        text_color,
        font,
        label,
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
        error.InvalidMetrics, error.InvalidUtf8 => return error.InvalidArgument,
    };
}

fn fill(ctx: *context_mod.Context, rect: types.Rect, color: types.Color) context_mod.ContextError!void {
    ctx.draw.rectFilled(ctx.allocator, rect, color) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
}

test "separatorLineRect centraliza horizontal e vertical" {
    const stdt = @import("std");
    const bounds = types.Rect.init(10, 20, 100, 40);

    const h = separatorLineRect(bounds, .horizontal, 2);
    try stdt.testing.expectEqual(@as(f32, 10), h.x);
    try stdt.testing.expectEqual(@as(f32, 39), h.y); // 20 + (40-2)/2
    try stdt.testing.expectEqual(@as(f32, 100), h.w);
    try stdt.testing.expectEqual(@as(f32, 2), h.h);

    const v = separatorLineRect(bounds, .vertical, 2);
    try stdt.testing.expectEqual(@as(f32, 59), v.x); // 10 + (100-2)/2
    try stdt.testing.expectEqual(@as(f32, 20), v.y);
    try stdt.testing.expectEqual(@as(f32, 2), v.w);
    try stdt.testing.expectEqual(@as(f32, 40), v.h);

    // Espessura não-positiva vira 0 (retângulo centrado, sem deslocamento negativo).
    const z = separatorLineRect(bounds, .horizontal, -3);
    try stdt.testing.expectEqual(@as(f32, 0), z.h);
    try stdt.testing.expectEqual(@as(f32, 40), z.y); // 20 + 40/2
}

test "separator desenha 1 linha e valida contratos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().separatorStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 20);

    ctx.beginFrame();
    try separator(&ctx, bounds, .horizontal, style);
    try stdt.testing.expectEqual(@as(usize, 1), ctx.drawCommands().len);
    const r = ctx.drawCommands()[0].rect_filled.rect;
    try stdt.testing.expectEqual(@as(f32, 200), r.w);
    try stdt.testing.expectEqual(style.thickness, r.h);
    ctx.endFrame();

    ctx.beginFrame();
    try separator(&ctx, bounds, .vertical, style);
    const vr = ctx.drawCommands()[0].rect_filled.rect;
    try stdt.testing.expectEqual(style.thickness, vr.w);
    try stdt.testing.expectEqual(@as(f32, 20), vr.h);
    ctx.endFrame();

    // Contratos inválidos (sem estado a corromper: display puro).
    const bad_bounds = types.Rect.init(0, 0, 0, 20);
    try stdt.testing.expectError(error.InvalidArgument, separator(&ctx, bad_bounds, .horizontal, style));
    const zero_thickness = style_mod.SeparatorStyle{ .color = style.color, .thickness = 0 };
    try stdt.testing.expectError(error.InvalidArgument, separator(&ctx, bounds, .horizontal, zero_thickness));
    const nan_thickness = style_mod.SeparatorStyle{ .color = style.color, .thickness = std.math.nan(f32) };
    try stdt.testing.expectError(error.InvalidArgument, separator(&ctx, bounds, .horizontal, nan_thickness));
}

test "separatorLabeled emite segmentos + rótulo; valida e degrada" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().separatorStyle();
    const font = metrics_mod.FontMetrics.withSize(10); // advance = 6
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 20);

    // Rótulo "OU" (2 glifos = 12px) cabe: 2 segmentos + 1 texto.
    ctx.beginFrame();
    try separatorLabeled(&ctx, bounds, .horizontal, "OU", font, style.color, style);
    try stdt.testing.expectEqual(@as(usize, 3), ctx.drawCommands().len);
    const left = ctx.drawCommands()[0].rect_filled.rect;
    const right = ctx.drawCommands()[1].rect_filled.rect;
    const txt = ctx.drawCommands()[2].text;
    try stdt.testing.expectEqual(@as(f32, 0), left.x);
    try stdt.testing.expect(left.w > 0);
    try stdt.testing.expect(right.x > left.x + left.w);
    try stdt.testing.expectApproxEqAbs(@as(f32, 94), txt.pos.x, 0.001); // (200-12)/2
    try stdt.testing.expectEqualStrings("OU", ctx.draw.textOf(ctx.drawCommands()[2]));
    ctx.endFrame();

    // Rótulo vazio degrada para linha simples (1 comando).
    ctx.beginFrame();
    try separatorLabeled(&ctx, bounds, .horizontal, "", font, style.color, style);
    try stdt.testing.expectEqual(@as(usize, 1), ctx.drawCommands().len);
    try stdt.testing.expectEqual(true, ctx.drawCommands()[0] == .rect_filled);
    ctx.endFrame();

    // Rótulo largo demais: sem espaço p/ vãos ⇒ só o texto.
    ctx.beginFrame();
    try separatorLabeled(&ctx, types.Rect.init(0, 0, 10, 20), .horizontal, "WWWW", font, style.color, style);
    try stdt.testing.expectEqual(@as(usize, 1), ctx.drawCommands().len);
    try stdt.testing.expectEqual(true, ctx.drawCommands()[0] == .text);
    ctx.endFrame();

    // Vertical com rótulo: texto não gira ⇒ InvalidArgument.
    try stdt.testing.expectError(error.InvalidArgument, separatorLabeled(&ctx, bounds, .vertical, "x", font, style.color, style));

    // Vão negativo e fonte inválida são rejeitados.
    const bad_gap = style_mod.SeparatorStyle{ .color = style.color, .label_gap = -1 };
    try stdt.testing.expectError(error.InvalidArgument, separatorLabeled(&ctx, bounds, .horizontal, "x", font, style.color, bad_gap));
    const bad_font = metrics_mod.FontMetrics.withSize(0);
    try stdt.testing.expectError(error.InvalidArgument, separatorLabeled(&ctx, bounds, .horizontal, "x", bad_font, style.color, style));
}

test "separator rejeita bounds não-finitos nas duas variantes" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().separatorStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const nan_bounds = types.Rect.init(0, 0, std.math.nan(f32), 20);
    ctx.beginFrame();
    const before = ctx.drawCommands().len;
    try stdt.testing.expectError(error.InvalidArgument, separator(&ctx, nan_bounds, .horizontal, style));
    try stdt.testing.expectError(error.InvalidArgument, separatorLabeled(&ctx, nan_bounds, .horizontal, "x", font, style.color, style));
    try stdt.testing.expectEqual(before, ctx.drawCommands().len);
    ctx.endFrame();
}
