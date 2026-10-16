//! ZyntraUI — barra de ferramentas (widgets/toolbar).
//!
//! Modelo M67 (composição leve, sem `id`, sem interação própria):
//! a Toolbar desenha o chrome e oferece **posicionamento
//! determinístico** dos itens, delegando desenho/interação a widgets
//! existentes (`button`, `label`, `separator`, ...).
//! - `toolbarContentRect(bounds, style)`: área útil (padding), puro.
//! - `toolbar(ctx, bounds, style)`: 1..2 comandos (fundo + borda) e
//!   devolve `Toolbar` (estado no CHAMADOR, por valor).
//! - `Toolbar.nextItem(width)`: próximo rect (altura uniforme
//!   `item_height`, centralizada verticalmente no conteúdo).
//! - `Toolbar.remaining()`: espaço horizontal restante.
//! - `toolbarSeparator(ctx, tb, style)`: divisor vertical entre grupos
//!   (reusa `widgets/separator`).
//!
//! Reusa `layout.StackPlacer` (horizontal) — **sem** sistema de layout
//! paralelo — e não trata eventos: a interação fica nos widgets dos
//! itens. Falta de espaço: a largura de cada item é **clampada** ao
//! restante e `Toolbar.overflowed` é marcado (determinístico).

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const style_mod = @import("../style/style.zig");
const layout = @import("../layout/layout.zig");
const separator_mod = @import("separator.zig");

/// Área útil da toolbar (bounds menos padding), nunca negativa.
pub fn toolbarContentRect(bounds: types.Rect, style: style_mod.ToolbarStyle) types.Rect {
    return .{
        .x = bounds.x + style.padding_x,
        .y = bounds.y + style.padding_y,
        .w = @max(0, bounds.w - style.padding_x * 2),
        .h = @max(0, bounds.h - style.padding_y * 2),
    };
}

/// Estado de posicionamento da toolbar (detido pelo chamador).
pub const Toolbar = struct {
    /// Área útil (dentro do padding).
    content: types.Rect,
    /// Altura uniforme dos itens (clampada ao conteúdo).
    item_h: f32,
    /// Faixa horizontal onde os itens são posicionados.
    placer: layout.StackPlacer,
    /// `true` se algum item não coube com a largura pedida.
    overflowed: bool = false,

    /// Próximo item com `width` pedida e altura `item_h`. A largura é
    /// clampada ao espaço restante; se menor que a pedida (ou inválida),
    /// marca `overflowed`.
    pub fn nextItem(self: *Toolbar, width: f32) types.Rect {
        const valid = std.math.isFinite(width) and width >= 0;
        const want: f32 = if (valid) width else 0;
        const r = self.placer.next(.{ .w = want, .h = self.item_h });
        if (!valid or r.w + 0.001 < want) self.overflowed = true;
        return r;
    }

    /// Espaço horizontal restante na faixa de itens.
    pub fn remaining(self: *const Toolbar) f32 {
        return self.placer.remaining();
    }
};

/// Desenha o chrome (fundo + borda quando `border_width > 0`) e devolve
/// o posicionador. Não trata eventos nem registra foco.
pub fn toolbar(
    ctx: *context_mod.Context,
    bounds: types.Rect,
    style: style_mod.ToolbarStyle,
) context_mod.ContextError!Toolbar {
    if (!style.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
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

    const content = toolbarContentRect(bounds, style);
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
        .placer = layout.StackPlacer.init(strip, .horizontal, style.spacing),
    };
}

/// Posiciona e desenha um divisor vertical entre grupos de itens,
/// reusando `widgets/separator`.
pub fn toolbarSeparator(
    ctx: *context_mod.Context,
    tb: *Toolbar,
    style: style_mod.SeparatorStyle,
) context_mod.ContextError!void {
    if (!style.isValid()) return error.InvalidArgument;
    const r = tb.nextItem(@max(style.thickness, 1.0));
    try separator_mod.separator(ctx, r, .vertical, style);
}

test "toolbar geometria: conteúdo, itens e centralização" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().toolbarStyle(); // pad 8/6, spacing 6, item 28
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();

    const bounds = types.Rect.init(0, 0, 200, 40); // content h = 28 → item_h = 28
    ctx.beginFrame();
    var tb = try toolbar(&ctx, bounds, style);
    try stdt.testing.expectEqual(@as(usize, 2), ctx.drawCommands().len); // fundo + borda
    try stdt.testing.expectEqual(types.Rect.init(8, 6, 184, 28), tb.content);
    try stdt.testing.expectEqual(@as(f32, 28), tb.item_h);

    const a = tb.nextItem(50);
    const b = tb.nextItem(30);
    try stdt.testing.expectEqual(types.Rect.init(8, 6, 50, 28), a);
    try stdt.testing.expectEqual(types.Rect.init(64, 6, 30, 28), b); // 8 + 50 + 6
    try stdt.testing.expectEqual(@as(f32, 92), tb.remaining()); // 192 - 100
    try stdt.testing.expect(!tb.overflowed);
    ctx.endFrame();

    // Conteúdo mais alto que o item: faixa verticalmente centrada.
    ctx.beginFrame();
    var tb2 = try toolbar(&ctx, types.Rect.init(0, 0, 200, 60), style); // content h = 48
    try stdt.testing.expectEqual(@as(f32, 28), tb2.item_h);
    const it = tb2.nextItem(10);
    try stdt.testing.expectEqual(@as(f32, 16), it.y); // 6 + (48-28)/2
    ctx.endFrame();
}

test "toolbar falta de espaço: clampa largura e sinaliza overflow" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().toolbarStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();

    ctx.beginFrame();
    var tb = try toolbar(&ctx, types.Rect.init(0, 0, 100, 40), style); // content w = 84
    const a = tb.nextItem(60);
    try stdt.testing.expectEqual(@as(f32, 60), a.w);
    try stdt.testing.expect(!tb.overflowed);

    // Pede 60 mas só restam 18 → clampa e sinaliza.
    const b = tb.nextItem(60);
    try stdt.testing.expectEqual(@as(f32, 18), b.w);
    try stdt.testing.expect(tb.overflowed);
    try stdt.testing.expectEqual(@as(f32, 0), tb.remaining());

    // Espaço esgotado: itens seguintes têm largura 0 e continuam sinalizando.
    const c = tb.nextItem(5);
    try stdt.testing.expectEqual(@as(f32, 0), c.w);
    try stdt.testing.expect(tb.overflowed);
    ctx.endFrame();
}

test "toolbar limites e entradas inválidas" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const base = style_mod.Theme.darkDefault().toolbarStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();

    // Bounds degenerados.
    try stdt.testing.expectError(error.InvalidArgument, toolbar(&ctx, types.Rect.init(0, 0, 0, 10), base));
    // Estilos inválidos.
    const bad_pad = style_mod.ToolbarStyle{ .bg = base.bg, .border = base.border, .padding_x = -1 };
    try stdt.testing.expectError(error.InvalidArgument, toolbar(&ctx, types.Rect.init(0, 0, 10, 10), bad_pad));
    const bad_sp = style_mod.ToolbarStyle{ .bg = base.bg, .border = base.border, .spacing = std.math.nan(f32) };
    try stdt.testing.expectError(error.InvalidArgument, toolbar(&ctx, types.Rect.init(0, 0, 10, 10), bad_sp));

    // Padding maior que o bounds: conteúdo vazio, item_h 0 (não negativos).
    ctx.beginFrame();
    var tb = try toolbar(&ctx, types.Rect.init(0, 0, 10, 10), base);
    try stdt.testing.expectEqual(@as(f32, 0), tb.content.w);
    try stdt.testing.expectEqual(@as(f32, 0), tb.item_h);
    const r = tb.nextItem(5);
    try stdt.testing.expectEqual(@as(f32, 0), r.w);
    try stdt.testing.expect(tb.overflowed);
    ctx.endFrame();

    // Largura de item não-finita/negativa: vira 0 e sinaliza.
    ctx.beginFrame();
    var tb2 = try toolbar(&ctx, types.Rect.init(0, 0, 200, 40), base);
    try stdt.testing.expectEqual(@as(f32, 0), tb2.nextItem(std.math.nan(f32)).w);
    try stdt.testing.expect(tb2.overflowed);
    ctx.endFrame();
    ctx.beginFrame();
    var tb3 = try toolbar(&ctx, types.Rect.init(0, 0, 200, 40), base);
    try stdt.testing.expectEqual(@as(f32, 0), tb3.nextItem(-4).w);
    try stdt.testing.expect(tb3.overflowed);
    ctx.endFrame();

    // Separador com estilo inválido.
    ctx.beginFrame();
    var tb4 = try toolbar(&ctx, types.Rect.init(0, 0, 200, 40), base);
    const bad_sep = style_mod.SeparatorStyle{ .color = base.border, .thickness = 0 };
    try stdt.testing.expectError(error.InvalidArgument, toolbarSeparator(&ctx, &tb4, bad_sep));
    ctx.endFrame();
}

test "toolbar integração: separador vertical dentro do conteúdo" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const theme = style_mod.Theme.darkDefault();
    const style = theme.toolbarStyle();
    const sep_style = theme.separatorStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();

    const bounds = types.Rect.init(0, 0, 200, 40);
    ctx.beginFrame();
    var tb = try toolbar(&ctx, bounds, style); // 2 comandos (fundo + borda)
    _ = tb.nextItem(40); // botão à esquerda
    try toolbarSeparator(&ctx, &tb, sep_style); // + 1 comando (linha)
    const cmds = ctx.drawCommands();
    try stdt.testing.expectEqual(@as(usize, 3), cmds.len);
    const line = cmds[2].rect_filled.rect;
    try stdt.testing.expect(line.x >= tb.content.x and line.x + line.w <= tb.content.x + tb.content.w);
    try stdt.testing.expectEqual(@as(f32, sep_style.thickness), line.w);
    try stdt.testing.expectEqual(tb.item_h, line.h);
    ctx.endFrame();
}

test "toolbar rejeita bounds não-finitos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().toolbarStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const nan_bounds = types.Rect.init(0, std.math.inf(f32), 200, 40);
    ctx.beginFrame();
    const before = ctx.drawCommands().len;
    try stdt.testing.expectError(error.InvalidArgument, toolbar(&ctx, nan_bounds, style));
    try stdt.testing.expectEqual(before, ctx.drawCommands().len);
    ctx.endFrame();
}
