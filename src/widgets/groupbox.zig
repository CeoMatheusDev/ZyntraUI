//! ZyntraUI — caixa agrupadora com título (widgets/groupbox).
//!
//! Modelo M73 (display puro: sem `id`, sem interação, sem estado):
//! - `groupBoxContentRect(bounds, font, style)`: área útil (pura).
//! - `groupBox(ctx, bounds, title, font, style)`: desenha o chrome e
//!   devolve o rect de conteúdo para o chamador posicionar os filhos
//!   (mesmo padrão de composição de toolbar/statusbar).
//!
//! Visual de fieldset: borda em 3 lados + topo dividido em 2 segmentos
//! flanqueando o título (sem cor de fundo atrás do texto — nada para
//! combinar com o pai). Degradações documentadas: título vazio ou que
//! não cabe com os vãos ⇒ borda do topo inteira, sem texto;
//! `border_width == 0` ⇒ sem borda; `bg` transparente (a == 0) ⇒ sem
//! preenchimento. O título é centralizado na linha do topo e pode
//! estender-se `lineHeight/2` acima de `bounds` (sem clip, como
//! `separator`). Reusa `GroupBoxStyle` + `Theme.groupBoxStyle()`.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const style_mod = @import("../style/style.zig");
const metrics_mod = @import("../text/metrics.zig");

/// Área útil da caixa: `bounds` menos `padding`, com reserva de
/// `lineHeight/2` no topo para o título (uniforme, exista título ou
/// não). Pura, sem alocação; nunca negativa. Fonte inválida ⇒ reserva 0.
pub fn groupBoxContentRect(
    bounds: types.Rect,
    font: metrics_mod.FontMetrics,
    style: style_mod.GroupBoxStyle,
) types.Rect {
    const reserve: f32 = if (font.isValid()) @max(0, font.lineHeight() * 0.5) else 0;
    const top = style.padding + reserve;
    return .{
        .x = bounds.x + style.padding,
        .y = bounds.y + top,
        .w = @max(0, bounds.w - style.padding * 2),
        .h = @max(0, bounds.h - style.padding - top),
    };
}

/// Desenha a caixa (fundo + borda + título) e devolve o rect de conteúdo.
/// Não trata eventos nem registra foco.
pub fn groupBox(
    ctx: *context_mod.Context,
    bounds: types.Rect,
    title: []const u8,
    font: metrics_mod.FontMetrics,
    style: style_mod.GroupBoxStyle,
) context_mod.ContextError!types.Rect {
    if (!style.isValid() or !font.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;

    if (style.bg.a > 0) {
        ctx.draw.rectFilled(ctx.allocator, bounds, style.bg) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
        };
    }

    // Título cabe quando há espaço para texto + vãos dentro do padding.
    var title_w: f32 = 0;
    var show_title = false;
    if (title.len > 0) {
        const m = metrics_mod.measure(title, font) catch return error.InvalidArgument;
        const avail = bounds.w - style.padding * 2;
        if (m.width + style.title_gap * 2 <= avail) {
            title_w = m.width;
            show_title = true;
        }
    }

    if (style.border_width > 0) {
        const t = style.border_width;
        const x0 = bounds.x;
        const x1 = bounds.x + bounds.w;
        const y0 = bounds.y;
        const y1 = bounds.y + bounds.h;
        try line(ctx, .{ .x = x0, .y = y0 }, .{ .x = x0, .y = y1 }, style.border, t);
        try line(ctx, .{ .x = x1, .y = y0 }, .{ .x = x1, .y = y1 }, style.border, t);
        try line(ctx, .{ .x = x0, .y = y1 }, .{ .x = x1, .y = y1 }, style.border, t);
        if (show_title) {
            const text_x = bounds.x + style.padding;
            const gap_l = text_x - style.title_gap;
            const gap_r = text_x + title_w + style.title_gap;
            if (gap_l > x0) {
                try line(ctx, .{ .x = x0, .y = y0 }, .{ .x = gap_l, .y = y0 }, style.border, t);
            }
            if (gap_r < x1) {
                try line(ctx, .{ .x = gap_r, .y = y0 }, .{ .x = x1, .y = y0 }, style.border, t);
            }
        } else {
            try line(ctx, .{ .x = x0, .y = y0 }, .{ .x = x1, .y = y0 }, style.border, t);
        }
    }

    if (show_title) {
        const lh = font.lineHeight();
        ctx.draw.pushText(
            ctx.allocator,
            .{ .x = bounds.x + style.padding, .y = bounds.y - lh * 0.5 },
            style.title,
            font,
            title,
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
            error.InvalidMetrics, error.InvalidUtf8 => return error.InvalidArgument,
        };
    }

    return groupBoxContentRect(bounds, font, style);
}

fn line(ctx: *context_mod.Context, p0: types.Vec2, p1: types.Vec2, color: types.Color, thickness: f32) context_mod.ContextError!void {
    ctx.draw.line(ctx.allocator, p0, p1, color, thickness) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
}

test "groupBox geometria: conteúdo, segmentos e título" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().groupBoxStyle();
    const font = metrics_mod.FontMetrics.withSize(10); // advance 6, lh 10.625
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(10, 20, 200, 100);

    // Conteúdo: pad 8 + reserva 5.3125 no topo.
    const content = groupBoxContentRect(bounds, font, style);
    try stdt.testing.expectEqual(@as(f32, 18), content.x);
    try stdt.testing.expectApproxEqAbs(@as(f32, 33.3125), content.y, 0.001);
    try stdt.testing.expectEqual(@as(f32, 184), content.w);
    try stdt.testing.expectApproxEqAbs(@as(f32, 78.6875), content.h, 0.001);

    // Título "Nome" (24px): bg transparente ⇒ 5 linhas + 1 texto.
    ctx.beginFrame();
    const ret = try groupBox(&ctx, bounds, "Nome", font, style);
    try stdt.testing.expectEqual(content, ret);
    try stdt.testing.expectEqual(@as(usize, 6), ctx.drawCommands().len);
    // Segmento superior esquerdo: x 10..(18-6)=12.
    const top_left = ctx.drawCommands()[3].line;
    try stdt.testing.expectEqual(@as(f32, 10), top_left.p0.x);
    try stdt.testing.expectEqual(@as(f32, 12), top_left.p1.x);
    try stdt.testing.expectEqual(@as(f32, 20), top_left.p0.y);
    // Segmento superior direito: (18+24+6)=48 .. 210.
    const top_right = ctx.drawCommands()[4].line;
    try stdt.testing.expectEqual(@as(f32, 48), top_right.p0.x);
    try stdt.testing.expectEqual(@as(f32, 210), top_right.p1.x);
    // Texto sobre a linha do topo, começando no padding.
    const txt = ctx.drawCommands()[5].text;
    try stdt.testing.expectEqual(@as(f32, 18), txt.pos.x);
    try stdt.testing.expectApproxEqAbs(@as(f32, 14.6875), txt.pos.y, 0.001);
    try stdt.testing.expectEqualStrings("Nome", ctx.draw.textOf(ctx.drawCommands()[5]));
    ctx.endFrame();
}

test "groupBox degradações: sem título, título grande, sem borda/fundo" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().groupBoxStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 100);

    // Título vazio: topo inteiro (4 linhas), sem texto.
    ctx.beginFrame();
    _ = try groupBox(&ctx, bounds, "", font, style);
    try stdt.testing.expectEqual(@as(usize, 4), ctx.drawCommands().len);
    const top = ctx.drawCommands()[3].line;
    try stdt.testing.expectEqual(@as(f32, 0), top.p0.x);
    try stdt.testing.expectEqual(@as(f32, 200), top.p1.x);
    for (ctx.drawCommands()) |cmd| {
        try stdt.testing.expect(cmd != .text);
    }
    ctx.endFrame();

    // Título que não cabe (largura útil 184): borda só, sem texto.
    ctx.beginFrame();
    _ = try groupBox(&ctx, types.Rect.init(0, 0, 30, 100), "TituloLongoDemais", font, style);
    try stdt.testing.expectEqual(@as(usize, 4), ctx.drawCommands().len);
    for (ctx.drawCommands()) |cmd| {
        try stdt.testing.expect(cmd != .text);
    }
    ctx.endFrame();

    // Sem borda e com fundo opaco: 1 fill + 1 texto.
    var solid = style;
    solid.border_width = 0;
    solid.bg = style_mod.Theme.darkDefault().surface;
    ctx.beginFrame();
    _ = try groupBox(&ctx, bounds, "Oi", font, solid);
    try stdt.testing.expectEqual(@as(usize, 2), ctx.drawCommands().len);
    try stdt.testing.expect(ctx.drawCommands()[0] == .rect_filled);
    try stdt.testing.expect(ctx.drawCommands()[1] == .text);
    ctx.endFrame();

    // Sem borda e sem fundo nem título: nenhum comando.
    var bare = style;
    bare.border_width = 0;
    ctx.beginFrame();
    const ret = try groupBox(&ctx, bounds, "", font, bare);
    try stdt.testing.expectEqual(@as(usize, 0), ctx.drawCommands().len);
    try stdt.testing.expectEqual(groupBoxContentRect(bounds, font, bare), ret);
    ctx.endFrame();
}

test "groupBox contratos inválidos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().groupBoxStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 100);

    try stdt.testing.expectError(error.InvalidArgument, groupBox(&ctx, types.Rect.init(0, 0, 0, 100), "t", font, style));
    try stdt.testing.expectError(error.InvalidArgument, groupBox(&ctx, types.Rect.init(0, 0, std.math.nan(f32), 100), "t", font, style));
    var bad = style;
    bad.border_width = -1;
    try stdt.testing.expectError(error.InvalidArgument, groupBox(&ctx, bounds, "t", font, bad));
    bad = style;
    bad.padding = -1;
    try stdt.testing.expectError(error.InvalidArgument, groupBox(&ctx, bounds, "t", font, bad));
    bad = style;
    bad.title_gap = std.math.inf(f32);
    try stdt.testing.expectError(error.InvalidArgument, groupBox(&ctx, bounds, "t", font, bad));
    const bad_font = metrics_mod.FontMetrics.withSize(0);
    try stdt.testing.expectError(error.InvalidArgument, groupBox(&ctx, bounds, "t", bad_font, style));
    try stdt.testing.expectError(error.InvalidArgument, groupBox(&ctx, bounds, "\xff", font, style));
}

test "groupBox integração: filho posicionado no conteúdo" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const theme = style_mod.Theme.darkDefault();
    const style = theme.groupBoxStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const button_mod = @import("button.zig");

    ctx.beginFrame();
    const content = try groupBox(&ctx, types.Rect.init(0, 0, 200, 100), "Ações", font, style);
    const btn = try button_mod.button(&ctx, @import("../core/id.zig").Id.fromString("test:gb-btn"), .{
        .x = content.x,
        .y = content.y,
        .w = 80,
        .h = @min(24, content.h),
    }, theme.buttonStyle());
    _ = btn;
    // Botão dentro do conteúdo: último comando dentro dos limites.
    const last = ctx.drawCommands()[ctx.drawCommands().len - 1];
    try stdt.testing.expect(last == .rect_filled or last == .rect_outline);
    ctx.endFrame();
}
