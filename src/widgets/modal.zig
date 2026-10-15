//! ZyntraUI — janela modal (widgets/modal).
//!
//! Modelo M27 (begin/end, estado no chamador) + M39 (arrasto):
//! - `beginModal` escurece a vista inteira, desenha o painel e emite
//!   `clip(bounds)`; `endModal` limpa o clip. SEMPRE parear.
//! - Bloqueio por CONVENÇÃO (documentada, sem invasão nos widgets):
//!   com o modal aberto, o chamador NÃO sonda widgets de trás
//!   (padrão `if (open) { modal } else { fundo }`). Sem flag global.
//! - Dismiss: press fora do painel ou `Escape` → `dismissed=true`
//!   (o chamador fecha, ex. `open=false`).
//! - `beginModalDraggable`: press na faixa de título captura; o painel
//!   segue o mouse preservando o grab (`ModalDragState` do chamador),
//!   clampado ao viewport quando cabe. Release encerra.
//! `id` não-nulo; aberto/fechado/posição no chamador.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const input = @import("input.zig");

pub const ModalResult = struct {
    dismissed: bool = false,
    hovered: bool = false,
    dragging: bool = false,
};

/// Estado de arrasto do modal (chamador detém; `dx/dy` = grab menos
/// origem, preenchido na captura).
pub const ModalDragState = struct {
    dx: f32 = 0,
    dy: f32 = 0,
};

pub fn beginModal(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    style: style_mod.ModalStyle,
) context_mod.ContextError!ModalResult {
    var b = bounds;
    return beginModalInner(ctx, id, &b, null, 0, style);
}

/// Modal arrastável pela faixa de título (`title_h` px no topo).
/// `bounds` e `drag` do chamador (posição persiste entre frames).
pub fn beginModalDraggable(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: *types.Rect,
    title_h: f32,
    drag: *ModalDragState,
    style: style_mod.ModalStyle,
) context_mod.ContextError!ModalResult {
    if (!std.math.isFinite(title_h) or title_h <= 0) return error.InvalidArgument;
    return beginModalInner(ctx, id, bounds, drag, title_h, style);
}

fn beginModalInner(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: *types.Rect,
    drag: ?*ModalDragState,
    title_h: f32,
    style: style_mod.ModalStyle,
) context_mod.ContextError!ModalResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid()) return error.InvalidArgument;
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;

    const fm = input.FrameMouse.scan(ctx.pendingEvents());
    const hovered = if (ctx.mouse_pos) |p| bounds.contains(p) else false;
    var res = ModalResult{ .hovered = hovered };
    if (fm.pressed_pos) |p| {
        if (!bounds.contains(p)) {
            res.dismissed = true;
        } else if (drag) |d| {
            // Press na faixa de título captura (sem roubar dismiss:
            // dentro do painel nunca dispensa).
            const th = @min(title_h, bounds.h);
            if (p.y < bounds.y + th and ctx.press_owner == null and
                std.math.isFinite(p.x) and std.math.isFinite(p.y))
            {
                ctx.press_owner = id;
                d.dx = p.x - bounds.x;
                d.dy = p.y - bounds.y;
            }
        }
    }
    if (drag != null and ctx.press_owner == id) {
        if (ctx.mouse_down_left) {
            if (ctx.mouse_pos) |p| {
                if (std.math.isFinite(p.x) and std.math.isFinite(p.y)) {
                    const d = drag.?;
                    var nx = p.x - d.dx;
                    var ny = p.y - d.dy;
                    // Clampa ao viewport quando o painel cabe nele.
                    const vp = ctx.viewport;
                    if (vp.w > 0 and bounds.w <= vp.w) {
                        nx = std.math.clamp(nx, vp.x, vp.x + vp.w - bounds.w);
                    }
                    if (vp.h > 0 and bounds.h <= vp.h) {
                        ny = std.math.clamp(ny, vp.y, vp.y + vp.h - bounds.h);
                    }
                    bounds.x = nx;
                    bounds.y = ny;
                    res.dragging = true;
                }
            }
        }
        if (fm.released_pos != null) {
            ctx.press_owner = null;
            res.dragging = false;
        }
    }
    for (ctx.pendingEvents()) |ev| {
        if (ev != .key) continue;
        const k = ev.key;
        if (k.pressed and k.key == .escape) res.dismissed = true;
    }

    ctx.draw.rectFilled(ctx.allocator, ctx.viewport, style.dim) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.rectFilled(ctx.allocator, bounds.*, style.bg) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.rectOutline(ctx.allocator, bounds.*, style.border, @max(1.0, style.border_width)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = bounds.*, .null_rect = false } }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    return res;
}

/// Limpa o clip do `beginModal` correspondente.
pub fn endModal(ctx: *context_mod.Context) context_mod.ContextError!void {
    ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = .{}, .null_rect = true } }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
}

test "modal dim, painel, dispensa fora e com Escape" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().modalStyle();
    var ctx = try context_mod.Context.init(gpa, .{
        .viewport = types.Rect.init(0, 0, 800, 600),
    });
    defer ctx.deinit();
    const bounds = types.Rect.init(300, 200, 200, 150);
    const id = id_mod.Id.fromString("test:modal");

    // Press dentro: mantém (dim + painel×2 + clip + clear = 5).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(400, 250) },
    });
    const keep = try beginModal(&ctx, id, bounds, style);
    try stdt.testing.expect(!keep.dismissed and keep.hovered);
    try endModal(&ctx);
    try stdt.testing.expectEqual(@as(usize, 5), ctx.drawCommands().len);
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 800, 600), ctx.drawCommands()[0].rect_filled.rect);
    ctx.endFrame();

    // Press fora e Escape dispensam.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(10, 10) },
    });
    const out = try beginModal(&ctx, id, bounds, style);
    try stdt.testing.expect(out.dismissed);
    try endModal(&ctx);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .escape, .pressed = true, .modifiers = .{} } });
    const esc = try beginModal(&ctx, id, bounds, style);
    try stdt.testing.expect(esc.dismissed);
    try endModal(&ctx);
    ctx.endFrame();

    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, beginModal(&ctx, .null, bounds, style));
    ctx.endFrame();
}

test "modalDraggable arrasta pela barra, clamp e solta" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().modalStyle();
    var ctx = try context_mod.Context.init(gpa, .{
        .viewport = types.Rect.init(0, 0, 800, 600),
    });
    defer ctx.deinit();
    var bounds = types.Rect.init(100, 100, 200, 150);
    const id = id_mod.Id.fromString("test:modal-drag");
    var drag = ModalDragState{};

    // Press na barra (y=110 < 100+24) captura com grab (10,10).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(110, 110) },
    });
    const r0 = try beginModalDraggable(&ctx, id, &bounds, 24, &drag, style);
    try stdt.testing.expect(r0.dragging and !r0.dismissed);
    try stdt.testing.expect(ctx.press_owner == id);
    try endModal(&ctx);
    ctx.endFrame();

    // Move mantém o grab: (200,200)-(10,10) = (190,190).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(200, 200) } });
    const r1 = try beginModalDraggable(&ctx, id, &bounds, 24, &drag, style);
    try stdt.testing.expect(r1.dragging);
    try stdt.testing.expectEqual(types.Rect.init(190, 190, 200, 150), bounds);
    try endModal(&ctx);
    ctx.endFrame();

    // Arrastar além da borda clampa ao viewport (600-150=450 em y).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(900, 900) } });
    _ = try beginModalDraggable(&ctx, id, &bounds, 24, &drag, style);
    try stdt.testing.expectEqual(@as(f32, 600), bounds.x);
    try stdt.testing.expectEqual(@as(f32, 450), bounds.y);
    try endModal(&ctx);
    ctx.endFrame();

    // Release encerra; press no corpo (fora da barra) não arrasta.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(900, 900) },
    });
    const r2 = try beginModalDraggable(&ctx, id, &bounds, 24, &drag, style);
    try stdt.testing.expect(!r2.dragging and ctx.press_owner == null);
    try endModal(&ctx);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(610, 500) },
    });
    const r3 = try beginModalDraggable(&ctx, id, &bounds, 24, &drag, style);
    try stdt.testing.expect(!r3.dragging and !r3.dismissed);
    try stdt.testing.expect(ctx.press_owner == null);
    try endModal(&ctx);
    ctx.endFrame();

    // title_h inválido rejeitado.
    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, beginModalDraggable(&ctx, id, &bounds, 0, &drag, style));
    ctx.endFrame();
}
