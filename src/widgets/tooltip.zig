//! ZyntraUI — tooltip por hover (widgets/tooltip).
//!
//! Modelo M26 (sem relógio — 0.17.0 não expõe timer sem `Io`):
//! - `tooltip(ctx,id,anchor,text,font,style,delay_frames,state)`: conta
//!   frames consecutivos com o mouse em `anchor`; ao atingir
//!   `delay_frames`, desenha caixa + texto perto do cursor.
//! - `delay_frames = 0` mostra de imediato. Mouse fora zera e esconde.
//! - `TooltipState` do chamador (`hover_frames`); saturado em u32.
//! - Caixa clampada ao viewport. Texto UTF-8 validado no push.
//! `id` não-nulo (futura captura; hoje só identidade). `anchor` w/h > 0.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const metrics_mod = @import("../text/metrics.zig");

/// Estado retido do tooltip (chamador detém, um por tooltip).
pub const TooltipState = struct {
    hover_frames: u32 = 0,
};

pub const TooltipResult = struct {
    visible: bool = false,
    hovered: bool = false,
};

pub fn tooltip(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    anchor: types.Rect,
    text: []const u8,
    font: metrics_mod.FontMetrics,
    style: style_mod.TooltipStyle,
    delay_frames: u32,
    state: *TooltipState,
) context_mod.ContextError!TooltipResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid() or !font.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(anchor.x) or !std.math.isFinite(anchor.y) or
        !std.math.isFinite(anchor.w) or !std.math.isFinite(anchor.h))
    {
        return error.InvalidArgument;
    }
    if (anchor.w <= 0 or anchor.h <= 0) return error.InvalidArgument;

    const hovered = if (ctx.mouse_pos) |p| anchor.contains(p) else false;
    if (hovered) {
        if (state.hover_frames < std.math.maxInt(u32)) state.hover_frames += 1;
    } else {
        state.hover_frames = 0;
    }
    var res = TooltipResult{ .hovered = hovered };
    if (!hovered or state.hover_frames < delay_frames) return res;
    // delay 0: hovered no 1º frame já mostra (frames>=1 > 0). Para
    // delay>0 exige N frames consecutivos. hovered aqui implica
    // frames>=1, então delay=0 sempre mostra.
    res.visible = true;

    const m = metrics_mod.measure(text, font) catch {
        return error.InvalidArgument; // texto do chamador malformado
    };
    const pad = style.padding;
    const bw = m.width + pad * 2;
    const bh = m.height + pad * 2;
    const mp = ctx.mouse_pos.?;
    var bx = mp.x + 12;
    var by = mp.y + 16;
    // Clampa ao viewport.
    const vp = ctx.viewport;
    if (vp.w > 0 and vp.h > 0) {
        bx = @min(bx, vp.x + vp.w - bw);
        by = @min(by, vp.y + vp.h - bh);
        bx = @max(bx, vp.x);
        by = @max(by, vp.y);
    }
    const box = types.Rect{ .x = bx, .y = by, .w = @max(1, bw), .h = @max(1, bh) };
    ctx.draw.rectFilled(ctx.allocator, box, style.bg) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.rectOutline(ctx.allocator, box, style.border, @max(1.0, style.border_width)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    if (text.len > 0) {
        ctx.draw.pushText(
            ctx.allocator,
            .{ .x = box.x + pad, .y = box.y + pad },
            style.text,
            font,
            text,
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
            error.InvalidUtf8 => return error.InvalidArgument,
            error.InvalidMetrics => return error.InvalidArgument,
        };
    }
    return res;
}

test "tooltip atraso, reset e imediato" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().tooltipStyle();
    var ctx = try context_mod.Context.init(gpa, .{
        .viewport = types.Rect.init(0, 0, 800, 600),
    });
    defer ctx.deinit();
    const anchor = types.Rect.init(10, 10, 100, 40);
    const id = id_mod.Id.fromString("test:tip");
    var st = TooltipState{};

    // Frame 1-2 com hover, delay 3: invisível; frame 3: visível.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(20, 20) } });
    const r1 = try tooltip(&ctx, id, anchor, "Hi", font, style, 3, &st);
    try stdt.testing.expect(!r1.visible and r1.hovered);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(21, 21) } });
    _ = try tooltip(&ctx, id, anchor, "Hi", font, style, 3, &st);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(22, 22) } });
    const r3 = try tooltip(&ctx, id, anchor, "Hi", font, style, 3, &st);
    try stdt.testing.expect(r3.visible);
    try stdt.testing.expectEqual(@as(usize, 3), ctx.drawCommands().len); // caixa×2 + texto
    ctx.endFrame();

    // Mouse fora zera e esconde.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(500, 500) } });
    const r4 = try tooltip(&ctx, id, anchor, "Hi", font, style, 3, &st);
    try stdt.testing.expect(!r4.visible and !r4.hovered);
    try stdt.testing.expectEqual(@as(u32, 0), st.hover_frames);
    ctx.endFrame();

    // Delay 0 mostra no 1º frame com hover.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(20, 20) } });
    const r5 = try tooltip(&ctx, id, anchor, "", font, style, 0, &st);
    try stdt.testing.expect(r5.visible);
    try stdt.testing.expectEqual(@as(usize, 2), ctx.drawCommands().len); // sem texto
    ctx.endFrame();

    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, tooltip(&ctx, .null, anchor, "Hi", font, style, 0, &st));
    ctx.endFrame();
}

test "tooltip limites: âncora NaN, texto malformado, saturação" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().tooltipStyle();
    var ctx = try context_mod.Context.init(gpa, .{
        .viewport = types.Rect.init(0, 0, 800, 600),
    });
    defer ctx.deinit();
    const anchor = types.Rect.init(10, 10, 100, 40);
    const id = id_mod.Id.fromString("test:tip-lim");
    var st = TooltipState{};

    // Âncora não-finita: InvalidArgument antes de qualquer geometria.
    ctx.beginFrame();
    const nan_anchor = types.Rect.init(10, 10, std.math.nan(f32), 40);
    try stdt.testing.expectError(error.InvalidArgument, tooltip(&ctx, id, nan_anchor, "Hi", font, style, 0, &st));
    ctx.endFrame();

    // Texto malformado: InvalidArgument, sem comando parcial.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(20, 20) } });
    const before = ctx.drawCommands().len;
    try stdt.testing.expectError(error.InvalidArgument, tooltip(&ctx, id, anchor, "\xff", font, style, 0, &st));
    try stdt.testing.expectEqual(before, ctx.drawCommands().len);
    ctx.endFrame();

    // Contador pré-saturado: não dá wrap, segue visível com hover.
    st.hover_frames = std.math.maxInt(u32);
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(20, 20) } });
    const r0 = try tooltip(&ctx, id, anchor, "Hi", font, style, 3, &st);
    try stdt.testing.expect(r0.visible);
    try stdt.testing.expectEqual(std.math.maxInt(u32), st.hover_frames);
    ctx.endFrame();

    // Caixa clampada ao viewport (âncora no canto inferior direito).
    const corner = types.Rect.init(790, 590, 10, 10);
    var st2 = TooltipState{};
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(795, 595) } });
    _ = try tooltip(&ctx, id, corner, "Hi", font, style, 0, &st2);
    const box = ctx.drawCommands()[0].rect_filled.rect;
    try stdt.testing.expect(box.x + box.w <= 800);
    try stdt.testing.expect(box.y + box.h <= 600);
    ctx.endFrame();
}
