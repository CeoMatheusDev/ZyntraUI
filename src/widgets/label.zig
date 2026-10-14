//! ZyntraUI — rótulo de texto (widgets/label).
//!
//! Modelo M4 (honesto sobre a fronteira de rasterização):
//! - Mede o texto com `text/metrics` (fallback monospace) e valida
//!   UTF-8; a rasterização real de glifos pertence ao backend externo.
//! - Em modo normal emite **zero** comandos (apenas mede). Com
//!   `debug_draw=true` emite 1 outline dos `bounds` para depurar layout.
//! Ownership: `text` é emprestado do chamador, válido só na chamada;
//! nada é retido. `id` não-nulo obrigatório (futura resolução de runs).

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
    if (debug_draw) {
        ctx.draw.rectOutline(ctx.allocator, bounds, color, 1.0) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
        };
    }
    return res;
}

test "label mede, detecta truncate e debug desenha" {
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
    try stdt.testing.expectEqual(@as(usize, 0), ctx.drawCommands().len);
    ctx.endFrame();

    ctx.beginFrame();
    const r2 = try label(&ctx, id, types.Rect.init(0, 0, 5, 20), "AB", types.Color.rgb(255, 255, 255), font, true);
    try stdt.testing.expect(r2.truncated);
    try stdt.testing.expectEqual(@as(usize, 1), ctx.drawCommands().len);
    ctx.endFrame();

    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidUtf8, label(&ctx, id, types.Rect.init(0, 0, 100, 20), "\xff", types.Color.rgb(0, 0, 0), font, false));
    try stdt.testing.expectError(error.InvalidArgument, label(&ctx, .null, types.Rect.init(0, 0, 100, 20), "A", types.Color.rgb(0, 0, 0), font, false));
    ctx.endFrame();
}
