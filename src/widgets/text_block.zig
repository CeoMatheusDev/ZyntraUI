//! ZyntraUI — bloco de texto multilinha (widgets/text_block).
//!
//! Escopo M147: texto de parágrafo (descrição, estado vazio, ajuda)
//! que quebra pela largura do rect e alinha cada linha. Duas fontes:
//! - `textBlock`: métricas de fallback (monospace) — o texto vira
//!   comandos `.text`, um por linha.
//! - `textBlockAtlas`: um `FontAtlas` (fonte real) — o texto sai em
//!   runs de glifos, com a quebra pela largura REAL dos glifos.
//!
//! Sem estado, sem alocação e sem interação: o bloco só desenha (o
//! `id` identifica o bloco para o contexto, como nos demais widgets).

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const metrics_mod = @import("../text/metrics.zig");
const wrap_mod = @import("../text/wrap.zig");
const atlas_mod = @import("../text/atlas.zig");
const layout_mod = @import("../text/layout.zig");
const image_mod = @import("../draw/image.zig");

/// Alinhamento horizontal das linhas.
pub const Align = enum {
    start,
    center,
    end,
};

/// Opções do bloco de texto.
pub const Options = struct {
    /// Alinhamento de cada linha dentro do rect.
    alignment: Align = .start,
    /// Espaço extra entre as linhas (px lógicos).
    line_spacing: f32 = 0,
};

/// Resultado do bloco de texto.
pub const TextBlockResult = struct {
    /// Linhas desenhadas.
    lines: usize = 0,
    /// True quando o texto não coube (linhas truncadas ou altura
    /// insuficiente).
    truncated: bool = false,
};

/// Máximo de linhas desenhadas (o resto trunca).
pub const max_lines: usize = 64;

fn lineAdvance(al: Align, line_w: f32, box_w: f32) f32 {
    return switch (al) {
        .start => 0,
        .center => @max(0, (box_w - line_w) / 2),
        .end => @max(0, box_w - line_w),
    };
}

/// Bloco de texto com as métricas de fallback (monospace).
pub fn textBlock(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    text: []const u8,
    color: types.Color,
    font: metrics_mod.FontMetrics,
    opts: Options,
) !TextBlockResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!font.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(opts.line_spacing) or opts.line_spacing < 0) {
        return error.InvalidArgument;
    }
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h) or
        bounds.w <= 0 or bounds.h < 0)
    {
        return error.InvalidArgument;
    }
    const line_h = font.lineHeight() + opts.line_spacing;
    var ranges: [max_lines]wrap_mod.LineRange = undefined;
    var capped = false;
    const n = wrap_mod.wrapLines(text, font, bounds.w, &ranges) catch |err| switch (err) {
        error.NoSpaceLeft => blk: {
            capped = true;
            break :blk max_lines;
        },
        error.InvalidUtf8 => return error.InvalidUtf8,
        error.InvalidMetrics => return error.InvalidArgument,
        error.InvalidArgument => return error.InvalidArgument,
        error.OutOfMemory => return error.OutOfMemory,
    };
    const used_h = @as(f32, @floatFromInt(n)) * line_h;
    const res = TextBlockResult{
        .lines = n,
        .truncated = capped or (bounds.h > 0 and used_h > bounds.h),
    };
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const r = ranges[i];
        if (r.len == 0) continue; // linha vazia ocupa altura, sem comando
        const slice = text[r.start..][0..r.len];
        const m = metrics_mod.measure(slice, font) catch return error.InvalidArgument;
        const x = bounds.x + lineAdvance(opts.alignment, m.width, bounds.w);
        const y = bounds.y + @as(f32, @floatFromInt(i)) * line_h;
        ctx.pushText(.{ .x = x, .y = y }, color, font, slice) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidCommand => error.InvalidCommand,
            error.InvalidUtf8 => return error.InvalidUtf8,
            error.InvalidMetrics => return error.InvalidArgument,
        };
    }
    return res;
}

/// Bloco de texto com fonte real (atlas de glifos).
///
/// A quebra usa a largura REAL dos glifos (fonte proporcional) e cada
/// linha vira um run de glifos.
pub fn textBlockAtlas(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    text: []const u8,
    color: types.Color,
    atlas: *const atlas_mod.FontAtlas,
    opts: Options,
) !TextBlockResult {
    if (id.isNull()) return error.InvalidArgument;
    if (atlas.glyphs.len == 0) return error.InvalidArgument;
    if (!std.math.isFinite(opts.line_spacing) or opts.line_spacing < 0) {
        return error.InvalidArgument;
    }
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h) or
        bounds.w <= 0 or bounds.h < 0)
    {
        return error.InvalidArgument;
    }
    const layout = layout_mod.Layout.fromAtlas(atlas) catch return error.InvalidArgument;
    const line_h = layout.lineHeight() + opts.line_spacing;
    var ranges: [max_lines]wrap_mod.LineRange = undefined;
    var capped = false;
    const n = wrap_mod.wrapLinesLayout(text, &layout, bounds.w, &ranges) catch |err| switch (err) {
        error.NoSpaceLeft => blk: {
            capped = true;
            break :blk max_lines;
        },
        error.InvalidUtf8 => return error.InvalidUtf8,
        error.InvalidMetrics => return error.InvalidArgument,
        error.InvalidGlyph => return error.InvalidArgument,
        error.InvalidArgument => return error.InvalidArgument,
        error.InvalidCommand => return error.InvalidCommand,
        error.OutOfMemory => return error.OutOfMemory,
    };
    const used_h = @as(f32, @floatFromInt(n)) * line_h;
    const res = TextBlockResult{
        .lines = n,
        .truncated = capped or (bounds.h > 0 and used_h > bounds.h),
    };
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const r = ranges[i];
        if (r.len == 0) continue;
        const slice = text[r.start..][0..r.len];
        const w = layout.advance(slice) catch return error.InvalidArgument;
        const x = bounds.x + lineAdvance(opts.alignment, w, bounds.w);
        // A linha de base fica na ascente do atlas.
        const baseline = types.Vec2.init(x, bounds.y + @as(f32, @floatFromInt(i)) * line_h + atlas.ascent());
        atlas_mod.drawRun(&ctx.draw, ctx.allocator, atlas, slice, baseline, color) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidUtf8 => return error.InvalidUtf8,
            error.InvalidMetrics => return error.InvalidArgument,
            error.InvalidGlyph => return error.InvalidArgument,
            error.DuplicateGlyph => return error.InvalidArgument,
            error.AtlasFull => return error.InvalidArgument,
            error.InvalidCommand => return error.InvalidCommand,
        };
    }
    return res;
}

test "textBlock quebra e alinha com as métricas de fallback" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10); // advance 6
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:tb");

    // "aaa bbb" em largura 20 => 2 linhas ("aaa" e "bbb").
    ctx.beginFrame();
    const r = try textBlock(&ctx, id, types.Rect.init(0, 0, 20, 100), "aaa bbb", types.Color.rgb(255, 255, 255), font, .{});
    try stdt.testing.expectEqual(@as(usize, 2), r.lines);
    try stdt.testing.expect(!r.truncated);
    try stdt.testing.expectEqual(@as(usize, 2), ctx.drawCommands().len);
    try stdt.testing.expectEqualStrings("aaa", ctx.draw.textOf(ctx.drawCommands()[0]));
    try stdt.testing.expectEqualStrings("bbb", ctx.draw.textOf(ctx.drawCommands()[1]));
    // A segunda linha fica uma altura abaixo.
    const y0 = ctx.drawCommands()[0].text.pos.y;
    const y1 = ctx.drawCommands()[1].text.pos.y;
    try stdt.testing.expectEqual(y0 + font.lineHeight(), y1);
    ctx.endFrame();

    // Centralizado: a linha de 18 px numa caixa de 40 => x = 11.
    ctx.beginFrame();
    _ = try textBlock(&ctx, id, types.Rect.init(0, 0, 40, 100), "aaa", types.Color.rgb(255, 255, 255), font, .{ .alignment = .center });
    try stdt.testing.expectEqual(@as(f32, 11), ctx.drawCommands()[0].text.pos.x);
    ctx.endFrame();

    // Altura insuficiente => truncado.
    ctx.beginFrame();
    const r3 = try textBlock(&ctx, id, types.Rect.init(0, 0, 20, 5), "aaa bbb", types.Color.rgb(255, 255, 255), font, .{});
    try stdt.testing.expect(r3.truncated);
    ctx.endFrame();

    // Contratos.
    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, textBlock(&ctx, .null, types.Rect.init(0, 0, 20, 20), "a", types.Color.rgb(0, 0, 0), font, .{}));
    try stdt.testing.expectError(error.InvalidArgument, textBlock(&ctx, id, types.Rect.init(0, 0, 0, 20), "a", types.Color.rgb(0, 0, 0), font, .{}));
    try stdt.testing.expectError(error.InvalidUtf8, textBlock(&ctx, id, types.Rect.init(0, 0, 20, 20), "\xff", types.Color.rgb(0, 0, 0), font, .{}));
    try stdt.testing.expectError(error.InvalidArgument, textBlock(&ctx, id, types.Rect.init(0, 0, 20, 20), "a", types.Color.rgb(0, 0, 0), font, .{ .line_spacing = -1 }));
    ctx.endFrame();
}

test "textBlockAtlas quebra pela largura real e alinha" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:tba");

    // 'A' = 5, 'B' = 3, espaço = 2 ⇒ "AB AB" mede 18.
    var b = atlas_mod.Builder.init(32, 32, 1);
    defer b.deinit(gpa);
    _ = try b.addGlyph(gpa, 'A', 4, 8, .{ .advance = 5, .bearing_y = -8, .height = 8 });
    _ = try b.addGlyph(gpa, 'B', 4, 8, .{ .advance = 3, .bearing_y = -8, .height = 8 });
    _ = try b.addGlyph(gpa, ' ', 1, 1, .{ .advance = 2 });
    var bytes: [32 * 32 * 4]u8 = undefined;
    for (&bytes, 0..) |*p, i| p.* = @truncate(i);
    const img = try image_mod.Image.init(32, 32, &bytes);
    var atlas = try b.finish(gpa, img);
    defer atlas.deinit(gpa);

    // Largura 11 ⇒ 2 linhas (um run por linha).
    ctx.beginFrame();
    const r = try textBlockAtlas(&ctx, id, types.Rect.init(0, 0, 11, 40), "AB AB", types.Color.rgb(255, 255, 255), &atlas, .{});
    try stdt.testing.expectEqual(@as(usize, 2), r.lines);
    try stdt.testing.expect(!r.truncated);
    try stdt.testing.expectEqual(@as(usize, 2), ctx.drawCommands().len);
    try stdt.testing.expect(ctx.drawCommands()[0] == .glyph_run);
    try stdt.testing.expectEqual(@as(usize, 2), ctx.draw.glyphsOf(ctx.drawCommands()[0]).len);
    ctx.endFrame();

    // Centralizado: a linha de 8 px numa caixa de 20 => x = 6.
    ctx.beginFrame();
    _ = try textBlockAtlas(&ctx, id, types.Rect.init(0, 0, 20, 40), "AB", types.Color.rgb(255, 255, 255), &atlas, .{ .alignment = .center });
    try stdt.testing.expectEqual(@as(f32, 6), ctx.drawCommands()[0].glyph_run.bounds.x);
    ctx.endFrame();

    // Contratos.
    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, textBlockAtlas(&ctx, id, types.Rect.init(0, 0, 20, 20), "A", types.Color.rgb(0, 0, 0), &atlas, .{ .line_spacing = -1 }));
    try stdt.testing.expectError(error.InvalidUtf8, textBlockAtlas(&ctx, id, types.Rect.init(0, 0, 20, 20), "\xff", types.Color.rgb(0, 0, 0), &atlas, .{}));
    ctx.endFrame();
}
