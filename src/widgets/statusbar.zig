//! ZyntraUI — barra de status (widgets/statusbar).
//!
//! Modelo M68 (composição leve, sem `id`, sem interação própria):
//! a StatusBar desenha o chrome e oferece **posicionamento
//! determinístico** dos segmentos, delegando desenho/interação a
//! widgets existentes (`label`, `button`, `separator`, ...).
//! - `statusBarContentRect(bounds, style)`: área útil (padding), puro.
//! - `statusBar(ctx, bounds, style)`: 1..2 comandos (fundo + borda) e
//!   devolve `StatusBar` (estado no CHAMADOR, por valor).
//! - `StatusBar.nextItem(width)`: próximo segmento à esquerda.
//! - `StatusBar.nextRight(width)`: próximo segmento ancorado à direita
//!   (ex.: "Ln 1, Col 1"). Lados nunca se sobrepõem.
//! - `StatusBar.remaining()`: espaço livre entre os cursores.
//! - `statusBarText(...)`: segmento de texto (1 linha) à esquerda,
//!   medido via `text/metrics` e emitido com `pushText` direto
//!   (sem `id` por item, como `separatorLabeled`).
//! - `statusBarSeparator(...)`: divisor vertical entre segmentos
//!   (reusa `widgets/separator`).
//!
//! Reusa `layout.StackPlacer` (lado esquerdo) + escalares espelhados
//! no lado direito — **sem** sistema de layout paralelo e sem alterar
//! contratos da Toolbar. Falta de espaço: a largura é **clampada** ao
//! livre e `StatusBar.overflowed` é marcado (determinístico).

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const style_mod = @import("../style/style.zig");
const layout = @import("../layout/layout.zig");
const metrics_mod = @import("../text/metrics.zig");
const separator_mod = @import("separator.zig");

/// Área útil da barra (bounds menos padding), nunca negativa.
pub fn statusBarContentRect(bounds: types.Rect, style: style_mod.StatusBarStyle) types.Rect {
    return .{
        .x = bounds.x + style.padding_x,
        .y = bounds.y + style.padding_y,
        .w = @max(0, bounds.w - style.padding_x * 2),
        .h = @max(0, bounds.h - style.padding_y * 2),
    };
}

/// Estado de posicionamento da barra (detido pelo chamador).
pub const StatusBar = struct {
    /// Área útil (dentro do padding).
    content: types.Rect,
    /// Altura uniforme dos segmentos (clampada ao conteúdo).
    item_h: f32,
    /// Espaçamento horizontal entre segmentos.
    spacing: f32,
    /// Posicionador do lado esquerdo (faixa centralizada).
    left: layout.StackPlacer,
    /// Borda direita ainda livre (recua a cada `nextRight`).
    right_x: f32,
    /// `true` se algum segmento não coube com a largura pedida.
    overflowed: bool = false,

    /// Espaço livre entre o cursor esquerdo e a borda direita livre.
    fn avail(self: *const StatusBar) f32 {
        return @max(0, self.right_x - self.left.cursor);
    }

    /// Próximo segmento à esquerda com `width` pedida. A largura é
    /// clampada ao espaço livre (inclui a reserva do lado direito);
    /// se menor que a pedida (ou inválida), marca `overflowed`.
    pub fn nextItem(self: *StatusBar, width: f32) types.Rect {
        const valid = std.math.isFinite(width) and width >= 0;
        const want: f32 = if (valid) width else 0;
        const w = @min(want, self.avail());
        const r = self.left.next(.{ .w = w, .h = self.item_h });
        if (!valid or w + 0.001 < want) self.overflowed = true;
        return r;
    }

    /// Próximo segmento ancorado à direita. Mesma regra de clamp e
    /// `overflowed` de `nextItem`; nunca invade o lado esquerdo.
    pub fn nextRight(self: *StatusBar, width: f32) types.Rect {
        const valid = std.math.isFinite(width) and width >= 0;
        const want: f32 = if (valid) width else 0;
        const w = @min(want, self.avail());
        const x = self.right_x - w;
        self.right_x = x - self.spacing;
        if (!valid or w + 0.001 < want) self.overflowed = true;
        return .{ .x = x, .y = self.left.area.y, .w = w, .h = self.item_h };
    }

    /// Espaço horizontal livre entre os dois lados.
    pub fn remaining(self: *const StatusBar) f32 {
        return self.avail();
    }
};

/// Desenha o chrome (fundo + borda quando `border_width > 0`) e devolve
/// o posicionador. Não trata eventos nem registra foco.
pub fn statusBar(
    ctx: *context_mod.Context,
    bounds: types.Rect,
    style: style_mod.StatusBarStyle,
) context_mod.ContextError!StatusBar {
    if (!style.isValid()) return error.InvalidArgument;
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;

    ctx.draw.rectFilled(ctx.allocator, bounds, style.bg) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    if (style.border_width > 0) {
        ctx.draw.rectOutline(ctx.allocator, bounds, style.border, style.border_width) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
        };
    }

    const content = statusBarContentRect(bounds, style);
    const item_h = @min(style.item_height, content.h);
    const strip = types.Rect{
        .x = content.x,
        .y = content.y + @max(0, (content.h - item_h) * 0.5),
        .w = content.w,
        .h = item_h,
    };
    return .{
        .content = content,
        .item_h = item_h,
        .spacing = style.spacing,
        .left = layout.StackPlacer.init(strip, .horizontal, style.spacing),
        .right_x = strip.x + strip.w,
    };
}

/// Segmento de texto (1 linha) à esquerda: mede, posiciona e emite
/// 1 comando `.text`. Devolve o rect ocupado.
pub fn statusBarText(
    ctx: *context_mod.Context,
    sb: *StatusBar,
    text: []const u8,
    font: metrics_mod.FontMetrics,
    color: types.Color,
) context_mod.ContextError!types.Rect {
    if (!font.isValid()) return error.InvalidArgument;
    const m = metrics_mod.measure(text, font) catch return error.InvalidArgument;
    const r = sb.nextItem(m.width);
    ctx.draw.pushText(
        ctx.allocator,
        .{ .x = r.x, .y = sb.left.area.y + @max(0, (sb.item_h - font.lineHeight()) * 0.5) },
        color,
        font,
        text,
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
        error.InvalidMetrics, error.InvalidUtf8 => return error.InvalidArgument,
    };
    return r;
}

/// Posiciona e desenha um divisor vertical entre segmentos (lado
/// esquerdo), reusando `widgets/separator`.
pub fn statusBarSeparator(
    ctx: *context_mod.Context,
    sb: *StatusBar,
    style: style_mod.SeparatorStyle,
) context_mod.ContextError!void {
    if (!style.isValid()) return error.InvalidArgument;
    const r = sb.nextItem(@max(style.thickness, 1.0));
    try separator_mod.separator(ctx, r, .vertical, style);
}

test "statusbar geometria: conteúdo, esquerda e direita ancorada" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().statusBarStyle(); // pad 8/4, spacing 6, item 20
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();

    const bounds = types.Rect.init(0, 0, 200, 28); // content h = 20 → item_h = 20
    ctx.beginFrame();
    var sb = try statusBar(&ctx, bounds, style);
    try stdt.testing.expectEqual(@as(usize, 2), ctx.drawCommands().len); // fundo + borda
    try stdt.testing.expectEqual(types.Rect.init(8, 4, 184, 20), sb.content);
    try stdt.testing.expectEqual(@as(f32, 20), sb.item_h);

    const a = sb.nextItem(50);
    try stdt.testing.expectEqual(types.Rect.init(8, 4, 50, 20), a);
    const r = sb.nextRight(30);
    try stdt.testing.expectEqual(types.Rect.init(162, 4, 30, 20), r); // 8+184-30
    try stdt.testing.expectEqual(@as(f32, 92), sb.remaining()); // (162-6) - (8+50+6)
    try stdt.testing.expect(!sb.overflowed);
    ctx.endFrame();
}

test "statusbar falta de espaço: lados clampam sem sobrepor" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().statusBarStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();

    ctx.beginFrame();
    var sb = try statusBar(&ctx, types.Rect.init(0, 0, 100, 28), style); // content w = 84
    const a = sb.nextItem(60);
    try stdt.testing.expectEqual(@as(f32, 60), a.w);
    try stdt.testing.expect(!sb.overflowed);

    // Direita pede 60 mas só há 18 livres → clampa e sinaliza.
    const r = sb.nextRight(60);
    try stdt.testing.expectEqual(@as(f32, 18), r.w);
    try stdt.testing.expectEqual(@as(f32, 74), r.x); // 8+84-18
    try stdt.testing.expect(sb.overflowed);
    try stdt.testing.expectEqual(@as(f32, 0), sb.remaining());

    // Esgotado: esquerda e direita seguintes têm largura 0, sem sobrepor.
    const b = sb.nextItem(5);
    try stdt.testing.expectEqual(@as(f32, 0), b.w);
    try stdt.testing.expectEqual(@as(f32, 0), sb.nextRight(5).w);
    try stdt.testing.expect(sb.overflowed);
    ctx.endFrame();
}

test "statusbar limites e entradas inválidas" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const base = style_mod.Theme.darkDefault().statusBarStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();

    // Bounds degenerados e estilos inválidos.
    try stdt.testing.expectError(error.InvalidArgument, statusBar(&ctx, types.Rect.init(0, 0, 0, 10), base));
    const bad_pad = style_mod.StatusBarStyle{ .bg = base.bg, .border = base.border, .padding_y = -1 };
    try stdt.testing.expectError(error.InvalidArgument, statusBar(&ctx, types.Rect.init(0, 0, 10, 10), bad_pad));
    const bad_sp = style_mod.StatusBarStyle{ .bg = base.bg, .border = base.border, .spacing = std.math.nan(f32) };
    try stdt.testing.expectError(error.InvalidArgument, statusBar(&ctx, types.Rect.init(0, 0, 10, 10), bad_sp));

    // Larguras inválidas viram 0 e sinalizam (ambos os lados).
    ctx.beginFrame();
    var sb = try statusBar(&ctx, types.Rect.init(0, 0, 200, 28), base);
    try stdt.testing.expectEqual(@as(f32, 0), sb.nextItem(std.math.nan(f32)).w);
    try stdt.testing.expect(sb.overflowed);
    ctx.endFrame();
    ctx.beginFrame();
    var sb2 = try statusBar(&ctx, types.Rect.init(0, 0, 200, 28), base);
    try stdt.testing.expectEqual(@as(f32, 0), sb2.nextRight(-4).w);
    try stdt.testing.expect(sb2.overflowed);
    ctx.endFrame();

    // Fonte inválida e separador com estilo inválido.
    ctx.beginFrame();
    var sb3 = try statusBar(&ctx, types.Rect.init(0, 0, 200, 28), base);
    const bad_font = metrics_mod.FontMetrics.withSize(0);
    try stdt.testing.expectError(error.InvalidArgument, statusBarText(&ctx, &sb3, "x", bad_font, base.border));
    const bad_sep = style_mod.SeparatorStyle{ .color = base.border, .thickness = 0 };
    try stdt.testing.expectError(error.InvalidArgument, statusBarSeparator(&ctx, &sb3, bad_sep));
    ctx.endFrame();
}

test "statusbar texto mede e posiciona; integração com button" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const theme = style_mod.Theme.darkDefault();
    const style = theme.statusBarStyle();
    const font = metrics_mod.FontMetrics.withSize(10); // advance = 6
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const button_mod = @import("button.zig");

    const bounds = types.Rect.init(0, 0, 200, 28);
    ctx.beginFrame();
    var sb = try statusBar(&ctx, bounds, style); // 2 comandos
    const rt = try statusBarText(&ctx, &sb, "OK", font, theme.text); // +1 texto
    try stdt.testing.expectEqual(@as(f32, 12), rt.w); // 2 glifos × 6
    try stdt.testing.expectEqual(@as(f32, 8), rt.x);
    try stdt.testing.expectEqual(@as(usize, 3), ctx.drawCommands().len);
    try stdt.testing.expectEqualStrings("OK", ctx.draw.textOf(ctx.drawCommands()[2]));
    try stdt.testing.expect(!sb.overflowed);

    // Integração: um button cabe no rect retornado e desenha dentro da barra.
    const rb = sb.nextRight(48);
    const btn = try button_mod.button(&ctx, @import("../core/id.zig").Id.fromString("test:sb-btn"), rb, theme.buttonStyle());
    _ = btn;
    try stdt.testing.expect(ctx.drawCommands().len > 3);
    const last = ctx.drawCommands()[ctx.drawCommands().len - 1];
    try stdt.testing.expect(last == .rect_filled or last == .rect_outline);
    ctx.endFrame();
}
