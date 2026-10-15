//! ZyntraUI — rótulo de texto (widgets/label).
//!
//! Modelo M6+M37 (simples + multilinha):
//! - `label`: mede e emite 1 comando `.text` (bytes copiados p/ arena).
//! - `labelWrapped`: fatia com `text/wrap` em `bounds.w`, 1 comando por
//!   linha não-vazia (máx. 64; além disso trunca, `truncated=true`).
//!   Linhas vazias ocupam altura sem comando.
//! - Rasterização de glifos: backend externo via `DrawList.textOf`.
//! - Com `debug_draw=true` emite ainda 1 outline dos `bounds`.
//! Ownership: `text` é emprestado só durante a chamada; a lista retém
//! uma cópia até o próximo `beginFrame`/`deinit`.
//! `id` não-nulo obrigatório.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const metrics_mod = @import("../text/metrics.zig");
const wrap_mod = @import("../text/wrap.zig");

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

/// Máximo de linhas desenhadas por `labelWrapped` (restante trunca).
pub const max_wrapped_lines: usize = 64;

/// Rótulo multilinha (M37, aditivo): fatia `text` com `text/wrap` em
/// `bounds.w` (`bounds.w == 0` é `InvalidArgument`) e emite 1 comando
/// `.text` por linha não-vazia, de cima para baixo com `lineHeight`.
/// Além de 64 linhas trunca (`truncated=true`); `bounds.h > 0` menor
/// que a altura total também trunca. Mesmos erros de `label`.
pub fn labelWrapped(
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
        bounds.w <= 0 or bounds.h < 0)
    {
        return error.InvalidArgument;
    }
    const m = try metrics_mod.measure(text, font);
    var ranges: [max_wrapped_lines]wrap_mod.LineRange = undefined;
    var capped = false;
    const n = wrap_mod.wrapLines(text, font, bounds.w, &ranges) catch |err| switch (err) {
        error.NoSpaceLeft => blk: {
            capped = true;
            break :blk max_wrapped_lines;
        },
        error.InvalidUtf8 => return error.InvalidUtf8,
        error.InvalidMetrics => return error.InvalidArgument,
        // Inalcançável (bounds/font validados + texto < 4 GiB na prática),
        // repassado por exaustividade do switch.
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidArgument => return error.InvalidArgument,
    };
    const res = LabelResult{
        .metrics = m,
        .truncated = capped or (bounds.h > 0 and m.height > bounds.h),
    };
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const r = ranges[i];
        if (r.len == 0) continue; // linha vazia ocupa altura, sem comando
        const slice = text[r.start..][0..r.len];
        ctx.draw.pushText(
            ctx.allocator,
            .{ .x = bounds.x, .y = bounds.y + @as(f32, @floatFromInt(i)) * font.lineHeight() },
            color,
            font,
            slice,
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
            error.InvalidUtf8 => return error.InvalidArgument,
            error.InvalidMetrics => return error.InvalidArgument,
        };
    }
    if (debug_draw) {
        ctx.draw.rectOutline(ctx.allocator, bounds, color, 1.0) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
        };
    }
    return res;
}

test "labelWrapped fatia, pula vazias e capa em 64" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const font = metrics_mod.FontMetrics.withSize(10); // advance=6, lh=10.625
    const id = id_mod.Id.fromString("test:lblw");
    const white = types.Color.rgb(255, 255, 255);

    // "aaa bbb" em largura 20 → 2 linhas = 2 comandos, empilhadas.
    ctx.beginFrame();
    const r0 = try labelWrapped(&ctx, id, types.Rect.init(0, 0, 20, 100), "aaa bbb", white, font, false);
    try stdt.testing.expect(!r0.truncated);
    try stdt.testing.expectEqual(@as(u32, 1), r0.metrics.lines);
    try stdt.testing.expectEqual(@as(usize, 2), ctx.drawCommands().len);
    try stdt.testing.expectEqualStrings("aaa", ctx.draw.textOf(ctx.drawCommands()[0]));
    try stdt.testing.expectEqualStrings("bbb", ctx.draw.textOf(ctx.drawCommands()[1]));
    const y0 = ctx.drawCommands()[0].text.pos.y;
    const y1 = ctx.drawCommands()[1].text.pos.y;
    try stdt.testing.expectEqual(y0 + font.lineHeight(), y1);
    ctx.endFrame();

    // "a\n\nb": linha vazia sem comando (2 textos).
    ctx.beginFrame();
    const r1 = try labelWrapped(&ctx, id, types.Rect.init(0, 0, 100, 100), "a\n\nb", white, font, false);
    try stdt.testing.expectEqual(@as(usize, 2), ctx.drawCommands().len);
    try stdt.testing.expect(!r1.truncated);
    ctx.endFrame();

    // 70 linhas "a": capa em 64 + truncated.
    var big: [280]u8 = undefined;
    var b: usize = 0;
    while (b < 70) : (b += 1) {
        big[b * 2] = 'a';
        big[b * 2 + 1] = '\n';
    }
    ctx.beginFrame();
    const r3 = try labelWrapped(&ctx, id, types.Rect.init(0, 0, 100, 100000), big[0 .. 70 * 2], white, font, false);
    try stdt.testing.expect(r3.truncated);
    try stdt.testing.expectEqual(@as(usize, 64), ctx.drawCommands().len);
    ctx.endFrame();

    // Contratos.
    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, labelWrapped(&ctx, id, types.Rect.init(0, 0, 0, 10), "a", white, font, false));
    try stdt.testing.expectError(error.InvalidUtf8, labelWrapped(&ctx, id, types.Rect.init(0, 0, 100, 100), "\xff", white, font, false));
    try stdt.testing.expectError(error.InvalidArgument, labelWrapped(&ctx, .null, types.Rect.init(0, 0, 100, 100), "a", white, font, false));
    ctx.endFrame();
}
