//! ZyntraUI — barra de progresso (widgets/progress).
//!
//! Modelo M18 (display puro, sem interação, sem estado):
//! - `progress(ctx, bounds, frac, style)`: `frac` em [0,1] (clampado;
//!   NaN/não-finito → `InvalidArgument`).
//! - Desenho (3 comandos): fundo, preenchimento 0..frac, outline.
//! Útil para carregamentos e níveis; animável via `anim.Tween`.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const style_mod = @import("../style/style.zig");

pub fn progress(
    ctx: *context_mod.Context,
    bounds: types.Rect,
    frac: f32,
    style: style_mod.ProgressStyle,
) context_mod.ContextError!void {
    if (!style.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;
    if (!std.math.isFinite(frac)) return error.InvalidArgument;
    const t = std.math.clamp(frac, 0, 1);

    // Acessibilidade (M164): barra de progresso (o app informa o
    // rótulo e o percentual).
    try ctx.pushA11y(.{
        .role = .progressbar,
        .bounds = bounds,
    });

    ctx.draw.rectFilled(ctx.allocator, bounds, style.bg) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.rectFilled(ctx.allocator, .{
        .x = bounds.x,
        .y = bounds.y,
        .w = @max(0, t * bounds.w),
        .h = bounds.h,
    }, style.fill) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.rectOutline(ctx.allocator, bounds, style.border, @max(1.0, style.border_width)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
}

test "progress preenche proporcional e valida" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().progressStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 20);

    ctx.beginFrame();
    try progress(&ctx, bounds, 0.5, style);
    try stdt.testing.expectEqual(@as(usize, 3), ctx.drawCommands().len);
    const fill = ctx.drawCommands()[1].rect_filled;
    try stdt.testing.expectEqual(@as(f32, 100), fill.rect.w);
    try stdt.testing.expectEqual(@as(f32, 200), ctx.drawCommands()[0].rect_filled.rect.w);
    ctx.endFrame();

    // Clamp nos extremos; NaN rejeitado.
    ctx.beginFrame();
    try progress(&ctx, bounds, 99, style);
    try stdt.testing.expectEqual(@as(f32, 200), ctx.drawCommands()[0].rect_filled.rect.w);
    try stdt.testing.expectEqual(@as(f32, 200), ctx.drawCommands()[1].rect_filled.rect.w);
    try progress(&ctx, bounds, -3, style);
    try stdt.testing.expectEqual(@as(f32, 0), ctx.drawCommands()[4].rect_filled.rect.w);
    try stdt.testing.expectError(error.InvalidArgument, progress(&ctx, bounds, std.math.nan(f32), style));
    ctx.endFrame();
}

test "progress rejeita bounds não-finitos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().progressStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const nan_bounds = types.Rect.init(0, 0, 200, std.math.inf(f32));
    ctx.beginFrame();
    const before = ctx.drawCommands().len;
    try stdt.testing.expectError(error.InvalidArgument, progress(&ctx, nan_bounds, 0.5, style));
    try stdt.testing.expectEqual(before, ctx.drawCommands().len);
    ctx.endFrame();
}

test "progress rejeita frac não-finito (inf e -inf)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().progressStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 20);

    // Coerente com slider/spinner: escalar não-finito é rejeitado na
    // entrada (nunca clampado) — inf não pode virar preenchimento válido
    // nem NaN no `t` clampado.
    ctx.beginFrame();
    const before = ctx.drawCommands().len;
    try stdt.testing.expectError(error.InvalidArgument, progress(&ctx, bounds, std.math.inf(f32), style));
    try stdt.testing.expectError(error.InvalidArgument, progress(&ctx, bounds, -std.math.inf(f32), style));
    try stdt.testing.expectError(error.InvalidArgument, progress(&ctx, bounds, std.math.nan(f32), style));
    try stdt.testing.expectEqual(before, ctx.drawCommands().len);
    ctx.endFrame();
}
