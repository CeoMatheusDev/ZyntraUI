//! ZyntraUI — fantasma do arraste (widgets/drag_ghost).
//!
//! Desenha o rótulo do payload ativo do serviço `dnd/service` junto ao
//! cursor do arraste. Não é interativo (sem `id`, sem foco nem captura)
//! e não recebe `bounds`: a caixa segue o cursor com o deslocamento do
//! estilo e é mantida dentro do `ctx.viewport` (clampada, para nunca sair
//! da janela). Chamar por ÚLTIMO, para ficar por cima dos demais widgets.
//! Sem arraste ativo nenhum comando é emitido (`drawn == false`).
//!
//! Ordem dos comandos: sombra (se opaca) → caixa → borda (se opaca e
//! espessa) → rótulo. Não emite `.clip` (a caixa já fica no viewport).
//! Erros: `style`/`font` inválidos ou rótulo não-UTF8 (`InvalidArgument`).
//! Ownership: o rótulo vem do payload (emprestado); os bytes são
//! copiados pela lista de desenho até o próximo `beginFrame`.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const style_mod = @import("../style/style.zig");
const metrics_mod = @import("../text/metrics.zig");
const dnd_mod = @import("../dnd/service.zig");

pub const DragGhostResult = struct {
    /// `true` quando a caixa foi desenhada (havia arraste ativo).
    drawn: bool = false,
    /// Retângulo de tela da caixa (vazio sem arraste).
    rect: types.Rect = .{},
    /// Métricas do rótulo medido (vazio sem arraste).
    metrics: metrics_mod.TextMetrics = .{},
};

/// Desenha o fantasma do arraste ativo sob o cursor.
pub fn dragGhost(
    ctx: *context_mod.Context,
    style: style_mod.DragGhostStyle,
    font: metrics_mod.FontMetrics,
) context_mod.ContextError!DragGhostResult {
    if (!style.isValid() or !font.isValid()) return error.InvalidArgument;
    const pay = dnd_mod.payload(ctx) orelse return .{};
    const label = pay.displayLabel();
    const text_metrics = metrics_mod.measure(label, font) catch |err| switch (err) {
        error.InvalidMetrics => return error.InvalidArgument,
        error.InvalidUtf8 => return error.InvalidArgument,
    };

    const w = @max(style.min_width, text_metrics.width + style.pad * 2);
    const h = text_metrics.height + style.pad * 2;
    const pos = dnd_mod.dragPosition(ctx);
    const vp = ctx.viewport;
    const box = types.Rect{
        .x = std.math.clamp(pos.x + style.offset.x, vp.x, vp.x + @max(0, vp.w - w)),
        .y = std.math.clamp(pos.y + style.offset.y, vp.y, vp.y + @max(0, vp.h - h)),
        .w = w,
        .h = h,
    };

    if (style.shadow.a != 0) {
        try ctx.draw.rectShadow(
            ctx.allocator,
            box,
            style.radius,
            types.Vec2.init(style.shadow_offset, style.shadow_offset),
            style.shadow_blur,
            style.shadow,
        );
    }
    if (style.radius > 0) {
        try ctx.draw.rectRounded(ctx.allocator, box, style.radius, style.bg);
    } else {
        try ctx.draw.rectFilled(ctx.allocator, box, style.bg);
    }
    if (style.border.a != 0 and style.border_width > 0) {
        try ctx.draw.rectOutline(ctx.allocator, box, style.border, style.border_width);
    }
    if (label.len > 0 and style.text.a != 0) {
        ctx.pushText(
            types.Vec2.init(box.x + style.pad, box.y + style.pad),
            style.text,
            font,
            label,
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
            error.InvalidMetrics, error.InvalidUtf8 => return error.InvalidArgument,
        };
    }

    return .{
        .drawn = true,
        .rect = box,
        .metrics = text_metrics,
    };
}

fn testStyle() style_mod.DragGhostStyle {
    return .{
        .bg = types.Color.rgb(240, 240, 240),
        .border = types.Color.rgb(20, 20, 20),
        .border_width = 1,
        .radius = 3,
        .shadow = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
        .shadow_offset = 2,
        .shadow_blur = 4,
        .text = types.Color.rgb(16, 16, 16),
        .pad = 6,
        .offset = types.Vec2.init(10, 10),
        .min_width = 48,
    };
}

test "dragGhost: sem arraste não emite comandos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{
        .viewport = types.Rect.init(0, 0, 200, 100),
    });
    defer ctx.deinit();

    ctx.beginFrame();
    const r = try dragGhost(&ctx, testStyle(), font);
    try stdt.testing.expect(!r.drawn);
    try stdt.testing.expectEqual(types.Rect{}, r.rect);
    try stdt.testing.expectEqual(@as(usize, 0), ctx.drawCommands().len);
    ctx.endFrame();
}

test "dragGhost: caixa sob o cursor, rótulo e ordem dos comandos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{
        .viewport = types.Rect.init(0, 0, 200, 100),
    });
    defer ctx.deinit();
    const src = @import("../core/id.zig").Id.fromString("test:ghost");

    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(20, 30),
    } });
    try dnd_mod.begin(&ctx, src, .{ .kind = "chip", .label = "chip" });
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(20, 30) } });

    const r = try dragGhost(&ctx, testStyle(), font);
    try stdt.testing.expect(r.drawn);
    // Rótulo "chip": 4 glifos × avanço (0.6 × 10 = 6) = 24 ⇒ mín. 48.
    try stdt.testing.expectEqual(@as(f32, 48), r.rect.w);
    try stdt.testing.expectEqual(@as(f32, 24), r.metrics.width);
    try stdt.testing.expectEqual(@as(f32, 20 + 10), r.rect.x);
    try stdt.testing.expectEqual(@as(f32, 30 + 10), r.rect.y);
    try stdt.testing.expectEqual(font.lineHeight() + 12, r.rect.h);
    // Sem sombra: caixa + borda + texto.
    const cmds = ctx.drawCommands();
    try stdt.testing.expectEqual(@as(usize, 3), cmds.len);
    try stdt.testing.expect(cmds[0] == .rect_rounded);
    try stdt.testing.expect(cmds[1] == .rect_outline);
    try stdt.testing.expect(cmds[2] == .text);
    try stdt.testing.expectEqualStrings("chip", ctx.draw.textOf(cmds[2]));
    ctx.endFrame();
}

test "dragGhost: clamp no viewport e rótulo vazio usa o tipo" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{
        .viewport = types.Rect.init(0, 0, 200, 100),
    });
    defer ctx.deinit();
    const src = @import("../core/id.zig").Id.fromString("test:ghost2");

    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(195, 95),
    } });
    try dnd_mod.begin(&ctx, src, .{ .kind = "zone" });
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(195, 95) } });
    var style = testStyle();
    style.radius = 0;
    style.shadow = types.Color.rgb(0, 0, 0);
    const r = try dragGhost(&ctx, style, font);
    try stdt.testing.expect(r.drawn);
    // Clampada para dentro do viewport.
    try stdt.testing.expectEqual(@as(f32, 200 - r.rect.w), r.rect.x);
    try stdt.testing.expectEqual(@as(f32, 100 - r.rect.h), r.rect.y);
    try stdt.testing.expect(r.rect.x + r.rect.w <= 200);
    try stdt.testing.expect(r.rect.y + r.rect.h <= 100);
    // Rótulo vazio ⇒ desenha o `kind`; sombra opaca entra primeiro e o
    // raio 0 usa retângulo reto.
    const cmds = ctx.drawCommands();
    try stdt.testing.expectEqual(@as(usize, 4), cmds.len);
    try stdt.testing.expect(cmds[0] == .rect_shadow);
    try stdt.testing.expect(cmds[1] == .rect_filled);
    try stdt.testing.expect(cmds[2] == .rect_outline);
    try stdt.testing.expectEqualStrings("zone", ctx.draw.textOf(cmds[3]));
    ctx.endFrame();
}

test "dragGhost: contratos inválidos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{
        .viewport = types.Rect.init(0, 0, 200, 100),
    });
    defer ctx.deinit();

    ctx.beginFrame();
    var bad = testStyle();
    bad.pad = -1;
    try stdt.testing.expectError(error.InvalidArgument, dragGhost(&ctx, bad, font));
    var bad2 = testStyle();
    bad2.min_width = std.math.nan(f32);
    try stdt.testing.expectError(error.InvalidArgument, dragGhost(&ctx, bad2, font));
    try stdt.testing.expectError(
        error.InvalidArgument,
        dragGhost(&ctx, testStyle(), metrics_mod.FontMetrics{ .size = 0 }),
    );
    ctx.endFrame();
}
