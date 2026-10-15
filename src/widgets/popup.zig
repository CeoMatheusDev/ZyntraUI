//! ZyntraUI — popup flutuante (widgets/popup).
//!
//! Modelo M18 (begin/end, estado no chamador):
//! - `beginPopup` desenha painel (fundo + borda) e emite `clip(bounds)`;
//!   conteúdo entre begin/end sai clippado; `endPopup` limpa o clip.
//!   SEMPRE parear.
//! - Dismiss: press esquerdo FORA de `bounds` neste frame →
//!   `dismissed=true` (o chamador fecha, ex. `open=false`). `Escape`
//!   NÃO dispensa (futuro; hoje é do text-input focado).
//! - `popupPlace(anchor, size, viewport)`: posiciona abaixo, vira para
//!   cima se estourar, prende na horizontal (puro, satura NaN).
//! - Eventos são broadcast: press fora dispensa mesmo com outro widget
//!   capturado (captura alheia preservada; fechar com drag ativo é
//!   decisão do app).
//! `id` não-nulo; sem estado retido (aberto/fechado é do chamador).

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const input = @import("input.zig");

pub const PopupResult = struct {
    dismissed: bool = false,
    hovered: bool = false,
};

pub fn beginPopup(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    style: style_mod.PopupStyle,
) context_mod.ContextError!PopupResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid()) return error.InvalidArgument;
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;

    const fm = input.FrameMouse.scan(ctx.pendingEvents());
    const hovered = if (ctx.mouse_pos) |p| bounds.contains(p) else false;
    var res = PopupResult{ .hovered = hovered };
    if (fm.pressed_pos) |p| {
        if (!bounds.contains(p)) res.dismissed = true;
    }

    ctx.draw.rectFilled(ctx.allocator, bounds, style.bg) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.rectOutline(ctx.allocator, bounds, style.border, @max(1.0, style.border_width)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = bounds, .null_rect = false } }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    return res;
}

/// Limpa o clip do `beginPopup` correspondente.
pub fn endPopup(ctx: *context_mod.Context) context_mod.ContextError!void {
    ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = .{}, .null_rect = true } }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
}

/// Posiciona um popup de `size` junto a `anchor`, dentro de `viewport`:
/// abre abaixo; se estourar embaixo, vira para cima; prende na
/// horizontal (se maior que a vista, ancora na origem). Puro, sem
/// alocação, sem NaN (não-finitos saturam para a origem do viewport).
pub fn popupPlace(anchor: types.Rect, size: types.Size, viewport: types.Rect) types.Rect {
    const w = @max(0, if (std.math.isFinite(size.w)) size.w else 0);
    const h = @max(0, if (std.math.isFinite(size.h)) size.h else 0);
    const ax = if (std.math.isFinite(anchor.x)) anchor.x else viewport.x;
    const ay = if (std.math.isFinite(anchor.y)) anchor.y else viewport.y;
    const ah = if (std.math.isFinite(anchor.h) and anchor.h > 0) anchor.h else 0;
    var x = ax;
    var y = ay + ah;
    if (viewport.w > 0 and viewport.h > 0) {
        if (y + h > viewport.y + viewport.h) {
            y = ay - h; // vira para cima
        }
        x = std.math.clamp(x, viewport.x, @max(viewport.x, viewport.x + viewport.w - w));
        y = @max(y, viewport.y); // topo nunca sai (base pode, se maior)
    }
    return .{ .x = x, .y = y, .w = w, .h = h };
}

test "popup dispensa fora, mantém dentro" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().popupStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(100, 100, 160, 120);
    const id = id_mod.Id.fromString("test:pop");

    // Press dentro: mantém (3 draws begin + 1 end).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(150, 150) },
    });
    const keep = try beginPopup(&ctx, id, bounds, style);
    try stdt.testing.expect(!keep.dismissed and keep.hovered);
    try endPopup(&ctx);
    try stdt.testing.expectEqual(@as(usize, 4), ctx.drawCommands().len);
    try stdt.testing.expect(ctx.drawCommands()[2] == .clip);
    ctx.endFrame();

    // Press fora: dispensa.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(10, 10) },
    });
    const out = try beginPopup(&ctx, id, bounds, style);
    try stdt.testing.expect(out.dismissed and !out.hovered);
    try endPopup(&ctx);
    ctx.endFrame();

    // Botão direito fora não dispensa (só esquerdo).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .right, .pressed = true, .pos = types.Vec2.init(10, 10) },
    });
    const rclick = try beginPopup(&ctx, id, bounds, style);
    try stdt.testing.expect(!rclick.dismissed);
    try endPopup(&ctx);
    ctx.endFrame();

    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, beginPopup(&ctx, .null, bounds, style));
    ctx.endFrame();
}

test "popupPlace abaixo, vira, prende e satura" {
    const stdt = @import("std");
    const vp = types.Rect.init(0, 0, 800, 600);

    // Normal: abaixo da âncora, mesmo x.
    try stdt.testing.expectEqual(
        types.Rect.init(100, 150, 160, 120),
        popupPlace(types.Rect.init(100, 100, 80, 50), .{ .w = 160, .h = 120 }, vp),
    );
    // Estoura embaixo: vira para cima (500-120).
    try stdt.testing.expectEqual(
        types.Rect.init(100, 380, 160, 120),
        popupPlace(types.Rect.init(100, 500, 80, 50), .{ .w = 160, .h = 120 }, vp),
    );
    // Estoura à direita: prende na borda.
    try stdt.testing.expectEqual(
        types.Rect.init(640, 100, 160, 120),
        popupPlace(types.Rect.init(700, 50, 80, 50), .{ .w = 160, .h = 120 }, vp),
    );
    // Maior que a vista: ancora na origem, sem crash.
    const big = popupPlace(types.Rect.init(700, 500, 80, 50), .{ .w = 900, .h = 700 }, vp);
    try stdt.testing.expectEqual(@as(f32, 0), big.x);
    try stdt.testing.expectEqual(@as(f32, 0), big.y);
    // NaN/negativos saturam sem crash.
    const nan = popupPlace(
        types.Rect.init(std.math.nan(f32), 0, 10, 10),
        .{ .w = std.math.inf(f32), .h = -5 },
        vp,
    );
    try stdt.testing.expect(nan.w >= 0 and nan.h >= 0);
    try stdt.testing.expect(std.math.isFinite(nan.x) and std.math.isFinite(nan.y));
}
