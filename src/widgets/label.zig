//! ZyntraUI — rótulo de texto (widgets/label).
//!
//! Modelo M6:
//! - Mede o texto (fallback monospace) e emite 1 comando `.text` com os
//!   bytes copiados para a arena da `DrawList` (sem dangling — ver
//!   `draw/commands.pushText`). A rasterização de glifos pertence ao
//!   backend externo, que resolve os bytes via `DrawList.textOf`.
//! - Com `debug_draw=true` emite ainda 1 outline dos `bounds`.
//! Ownership: `text` é emprestado só durante a chamada; a lista retém
//! uma cópia até o próximo `beginFrame`/`deinit`.
//! `id` não-nulo obrigatório.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const metrics_mod = @import("../text/metrics.zig");

pub const LabelResult = struct {
    metrics: metrics_mod.TextMetrics = .{},
    /// True quando a largura medida excede `bounds.w` (backend deve clipar).
    truncated: bool = false,
};

pub fn measure(text: []const u8, metrics: metrics_mod.FontMetrics) !metrics_mod.TextMetrics {
    return try metrics_mod.measure(text, metrics);
}

pub fn label(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    text: []const u8,
    color: types.Color,
    font: metrics_mod.FontMetrics,
    debug_draw: bool,
) !LabelResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!font.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h) or
        bounds.w < 0 or bounds.h < 0)
    {
        return error.InvalidArgument;
    }
    const m = try metrics_mod.measure(text, font);
    const res = LabelResult{
        .metrics = m,
        .truncated = bounds.w > 0 and m.width > bounds.w,
    };
    ctx.draw.pushText(
        ctx.allocator,
        .{ .x = bounds.x, .y = bounds.y },
        color,
        font,
        text,
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
        error.InvalidUtf8 => return error.InvalidUtf8,
        error.InvalidMetrics => return error.InvalidArgument,
    };
    if (debug_draw) {
        ctx.draw.rectOutline(ctx.allocator, bounds, color, 1.0) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
        };
    }
    return res;
}

test "label emite texto, detecta truncate e debug desenha" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const font = metrics_mod.FontMetrics.withSize(10); // advance=6
    const id = id_mod.Id.fromString("test:label");

    ctx.beginFrame();
    const r = try label(&ctx, id, types.Rect.init(0, 0, 100, 20), "AB", types.Color.rgb(255, 255, 255), font, false);
    try stdt.testing.expectEqual(@as(f32, 12), r.metrics.width);
    try stdt.testing.expect(!r.truncated);
    try stdt.testing.expectEqual(@as(usize, 1), ctx.drawCommands().len);
    try stdt.testing.expectEqualStrings("AB", ctx.draw.textOf(ctx.drawCommands()[0]));
    ctx.endFrame();

    ctx.beginFrame();
    const r2 = try label(&ctx, id, types.Rect.init(0, 0, 5, 20), "AB", types.Color.rgb(255, 255, 255), font, true);
    try stdt.testing.expect(r2.truncated);
    try stdt.testing.expectEqual(@as(usize, 2), ctx.drawCommands().len);
    ctx.endFrame();

    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidUtf8, label(&ctx, id, types.Rect.init(0, 0, 100, 20), "\xff", types.Color.rgb(0, 0, 0), font, false));
    try stdt.testing.expectError(error.InvalidArgument, label(&ctx, .null, types.Rect.init(0, 0, 100, 20), "A", types.Color.rgb(0, 0, 0), font, false));
    ctx.endFrame();
}
