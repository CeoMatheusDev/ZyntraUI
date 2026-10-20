//! ZyntraUI — rótulo de texto rico (widgets/rich_label).
//!
//! Escopo M165: um rótulo com TRECHOS DE ESTILOS DIFERENTES (cor,
//! negrito, itálico, tag) — o caso do texto com ênfase, do link
//! embutido ou do erro em destaque.
//! - `richLabel`: métricas de fallback (monospace) — o texto vira
//!   comandos `.text`, um por trecho.
//! - `richLabelAtlas`: um `FontAtlas` (fonte real) — cada trecho sai em
//!   runs de glifos.
//!
//! O cálculo dos trechos é do módulo `text/rich` (que quebra o texto
//! pela largura e aplica as spans); o widget só desenha.
//!
//! Sem estado, sem alocação (os trechos vão para um buffer do
//! chamador) e sem interação.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const metrics_mod = @import("../text/metrics.zig");
const atlas_mod = @import("../text/atlas.zig");
const layout_mod = @import("../text/layout.zig");
const rich_mod = @import("../text/rich.zig");

/// Alinhamento horizontal das linhas.
pub const Align = rich_mod.Align;

/// Opções do rótulo rico.
pub const Options = struct {
    /// Alinhamento de cada linha dentro do rect.
    alignment: Align = .start,
    /// Espaço extra entre as linhas (px lógicos).
    line_spacing: f32 = 0,
};

/// Máximo de trechos por rótulo (o buffer é do chamador).
pub const max_runs: usize = 256;

/// Rótulo rico com as métricas de fallback (monospace).
pub fn richLabel(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    text: []const u8,
    spans: []const rich_mod.Span,
    color: types.Color,
    font: metrics_mod.FontMetrics,
    opts: Options,
) !void {
    const layout = layout_mod.Layout.fromMetrics(font) catch return error.InvalidArgument;
    try draw(ctx, id, bounds, text, spans, layout, color, opts, 0);
}

/// Rótulo rico com um atlas de glifos (fonte real).
pub fn richLabelAtlas(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    text: []const u8,
    spans: []const rich_mod.Span,
    atlas: *const atlas_mod.FontAtlas,
    opts: Options,
) !void {
    if (atlas.glyphs.len == 0) return error.InvalidArgument;
    const layout = layout_mod.Layout.fromAtlas(atlas) catch return error.InvalidArgument;
    try draw(ctx, id, bounds, text, spans, layout, .{ .r = 255, .g = 255, .b = 255, .a = 255 }, opts, atlas.ascent());
}

/// Desenha comum (as duas fontes).
fn draw(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    text: []const u8,
    spans: []const rich_mod.Span,
    layout: layout_mod.Layout,
    default_color: types.Color,
    opts: Options,
    ascent: f32,
) !void {
    if (id.isNull()) return error.InvalidArgument;
    if (!std.math.isFinite(opts.line_spacing) or opts.line_spacing < 0) {
        return error.InvalidArgument;
    }
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h) or
        bounds.w <= 0 or bounds.h < 0)
    {
        return error.InvalidArgument;
    }

    // Os trechos (o texto é quebrado pela largura do rect).
    var run_buf: [max_runs]rich_mod.Run = undefined;
    const n = rich_mod.layoutRuns(
        layout,
        text,
        spans,
        bounds.w,
        types.Vec2.init(bounds.x, bounds.y),
        opts.alignment,
        run_buf[0..],
    ) catch |err| return switch (err) {
        error.InvalidUtf8 => error.InvalidUtf8,
        error.InvalidMetrics => error.InvalidArgument,
        error.InvalidArgument => error.InvalidArgument,
        error.NoSpaceLeft => error.InvalidArgument,
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidCommand => error.InvalidCommand,
    };

    // Acessibilidade (M164): o rótulo é lido como um texto só.
    try ctx.pushA11yWidget(id, .label, bounds, .{});
    ctx.setA11yLabel(id, text);

    // A linha de base: a altura da linha + o espaçamento extra.
    const line_h = layout.lineHeight() + opts.line_spacing;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const r = run_buf[i];
        const y = bounds.y + @as(f32, @floatFromInt(i)) * line_h;
        const color = if (r.style.color.a == 0 and r.style.color.r == 0 and
            r.style.color.g == 0 and r.style.color.b == 0)
            default_color
        else
            r.style.color;
        const slice = text[r.start..][0..r.len];
        // Com o atlas, a linha de base fica na ascente; com as métricas
        // de fallback, o topo já é o topo do texto.
        const pos = types.Vec2.init(r.x, y + ascent);
        layout.draw(&ctx.draw, ctx.allocator, slice, pos, color) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidCommand => error.InvalidCommand,
            error.InvalidUtf8 => error.InvalidUtf8,
            error.InvalidMetrics => error.InvalidArgument,
            error.InvalidGlyph => error.InvalidArgument,
            error.InvalidArgument => error.InvalidArgument,
        };
    }
}

// ---------------------------------------------------------------------------
// Testes
// ---------------------------------------------------------------------------

test "richLabel: divide o texto em trechos coloridos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{ .viewport = types.Rect.init(0, 0, 200, 200) });
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:rich");

    const red = types.Color.rgb(255, 0, 0);
    const spans = [_]rich_mod.Span{.{ .start = 2, .len = 2, .style = .{ .color = red } }};

    ctx.beginFrame();
    try richLabel(
        &ctx,
        id,
        types.Rect.init(0, 0, 200, 40),
        "abcdef",
        &spans,
        types.Color.rgb(255, 255, 255),
        font,
        .{},
    );
    const cmds = ctx.drawCommands();
    // Três trechos (o estilo volta ao padrão depois da span).
    try stdt.testing.expectEqual(@as(usize, 3), cmds.len);
    try stdt.testing.expectEqualStrings("ab", ctx.draw.textOf(cmds[0]));
    try stdt.testing.expectEqualStrings("cd", ctx.draw.textOf(cmds[1]));
    try stdt.testing.expectEqual(red, cmds[1].text.color);
    try stdt.testing.expectEqualStrings("ef", ctx.draw.textOf(cmds[2]));
    ctx.endFrame();
}

test "richLabel: quebra pela largura e alinha" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10); // avanço 6
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:rich2");

    ctx.beginFrame();
    // "aaa bbb" (24 px) numa caixa de 18 ⇒ 2 linhas.
    try richLabel(
        &ctx,
        id,
        types.Rect.init(0, 0, 18, 40),
        "aaa bbb",
        &.{},
        types.Color.rgb(255, 255, 255),
        font,
        .{},
    );
    const cmds = ctx.drawCommands();
    try stdt.testing.expectEqual(@as(usize, 2), cmds.len);
    try stdt.testing.expectEqualStrings("aaa", ctx.draw.textOf(cmds[0]));
    try stdt.testing.expectEqualStrings("bbb", ctx.draw.textOf(cmds[1]));
    // A segunda linha fica uma altura abaixo.
    try stdt.testing.expectApproxEqAbs(
        cmds[0].text.pos.y + font.lineHeight(),
        cmds[1].text.pos.y,
        0.001,
    );
    ctx.endFrame();
}

test "richLabel: argumentos inválidos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, richLabel(
        &ctx,
        id_mod.Id.null,
        types.Rect.init(0, 0, 10, 10),
        "x",
        &.{},
        types.Color.rgb(255, 255, 255),
        font,
        .{},
    ));
    try stdt.testing.expectError(error.InvalidArgument, richLabel(
        &ctx,
        id_mod.Id.fromString("x"),
        types.Rect.init(0, 0, 0, 10),
        "x",
        &.{},
        types.Color.rgb(255, 255, 255),
        font,
        .{},
    ));
    try stdt.testing.expectError(error.InvalidArgument, richLabel(
        &ctx,
        id_mod.Id.fromString("x"),
        types.Rect.init(0, 0, 10, 10),
        "x",
        &.{},
        types.Color.rgb(255, 255, 255),
        font,
        .{ .line_spacing = -1 },
    ));
    ctx.endFrame();
}
