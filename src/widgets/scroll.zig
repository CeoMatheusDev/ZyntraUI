//! ZyntraUI — container com scroll (widgets/scroll).
//!
//! Modelo M16 (begin/end imediato, estado no chamador):
//! - `beginScroll(ctx,id,bounds,scroll_y,content_h,speed,style)`:
//!   consome `mouse_wheel` com o mouse em `bounds` (`dy > 0` sobe,
//!   `speed` px por unidade, clamp em [0, max(0, content_h-bounds.h)]);
//!   emite `clip(bounds)` e retorna a área de conteúdo deslocada.
//! - Filhos desenhados entre begin/end saem clippados; `endScroll(ctx)`
//!   emite o clip-clear. SEMPRE parear (mesmo sem filhos).
//! - `scroll_y: *f32` pertence ao chamador (como slider); normalizado
//!   (clamp + NaN rejeitado com `InvalidArgument`) a cada chamada.
//! - Scrollbar (trilha + thumb proporcional) desenhada no `endScroll`
//!   quando `content_h > bounds.h`; sem conteúdo excedente, sem barra.
//! `id` não-nulo (futura captura de drag no thumb, M17+).

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");

pub const ScrollResult = struct {
    /// Área onde os filhos devem ser posicionados (origem deslocada).
    content: types.Rect = .{},
    offset: f32 = 0,
    max_offset: f32 = 0,
    hovered: bool = false,
    scrolled: bool = false,
};

pub fn beginScroll(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    scroll_y: *f32,
    content_h: f32,
    speed: f32,
    style: style_mod.ScrollStyle,
) context_mod.ContextError!ScrollResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid()) return error.InvalidArgument;
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;
    if (!std.math.isFinite(content_h) or content_h < 0) return error.InvalidArgument;
    if (!std.math.isFinite(speed) or speed <= 0) return error.InvalidArgument;
    if (!std.math.isFinite(scroll_y.*)) return error.InvalidArgument;

    const max_offset = @max(0, content_h - bounds.h);
    scroll_y.* = std.math.clamp(scroll_y.*, 0, max_offset);
    const hovered = if (ctx.mouse_pos) |p| bounds.contains(p) else false;

    var res = ScrollResult{
        .content = .{ .x = bounds.x, .y = bounds.y - scroll_y.*, .w = bounds.w, .h = @max(bounds.h, content_h) },
        .offset = scroll_y.*,
        .max_offset = max_offset,
        .hovered = hovered,
    };
    if (hovered) {
        for (ctx.pendingEvents()) |ev| {
            if (ev != .mouse_wheel) continue;
            scroll_y.* = std.math.clamp(scroll_y.* - ev.mouse_wheel.dy * speed, 0, max_offset);
            res.scrolled = true;
        }
        res.offset = scroll_y.*;
        res.content.y = bounds.y - scroll_y.*;
    }

    ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = bounds, .null_rect = false } }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    return res;
}

/// Encerra o container: limpa o clip e desenha a scrollbar (se houver
/// overflow). Guarda `bounds`, `scroll_y`, `content_h` e `style` do
/// `beginScroll` correspondente.
pub fn endScroll(
    ctx: *context_mod.Context,
    bounds: types.Rect,
    scroll_y: f32,
    content_h: f32,
    style: style_mod.ScrollStyle,
) context_mod.ContextError!void {
    ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = .{}, .null_rect = true } }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    const max_offset = @max(0, content_h - bounds.h);
    if (max_offset <= 0) return;
    const bw = @min(style.bar_width, bounds.w);
    const track = types.Rect{ .x = bounds.x + bounds.w - bw, .y = bounds.y, .w = bw, .h = bounds.h };
    const frac = bounds.h / content_h;
    const thumb_h = @max(bw, bounds.h * frac);
    const travel = bounds.h - thumb_h;
    const ty = bounds.y + (if (max_offset > 0) travel * (scroll_y / max_offset) else 0);
    ctx.draw.rectFilled(ctx.allocator, track, style.track) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.rectFilled(ctx.allocator, .{ .x = track.x, .y = ty, .w = bw, .h = thumb_h }, style.thumb) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
}

test "scroll roda, clampa e emite clip" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().scrollStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 100);
    const id = id_mod.Id.fromString("test:sc");
    var off: f32 = 0;

    // Sem hover: wheel ignorado, mas clip emitido.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = 5, .pos = types.Vec2.init(500, 500) } });
    const r0 = try beginScroll(&ctx, id, bounds, &off, 300, 24, style);
    try stdt.testing.expect(!r0.scrolled and !r0.hovered);
    try stdt.testing.expectEqual(@as(f32, 0), off);
    try stdt.testing.expectEqual(@as(f32, 200), r0.max_offset);
    try endScroll(&ctx, bounds, off, 300, style);
    try stdt.testing.expectEqual(@as(usize, 4), ctx.drawCommands().len); // clip + clip-clear + track + thumb
    try stdt.testing.expect(ctx.drawCommands()[0] == .clip);
    ctx.endFrame();

    // Hover + wheel: desce 5*24=120; segunda roda clamp no max 200.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = -5, .pos = types.Vec2.init(10, 10) } });
    const r1 = try beginScroll(&ctx, id, bounds, &off, 300, 24, style);
    try stdt.testing.expect(r1.scrolled and r1.hovered);
    try stdt.testing.expectEqual(@as(f32, 120), off);
    try stdt.testing.expectEqual(@as(f32, -120), r1.content.y);
    try endScroll(&ctx, bounds, off, 300, style);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = -99, .pos = types.Vec2.init(10, 10) } });
    _ = try beginScroll(&ctx, id, bounds, &off, 300, 24, style);
    try stdt.testing.expectEqual(@as(f32, 200), off);
    try endScroll(&ctx, bounds, off, 300, style);
    ctx.endFrame();

    // Rolar para cima além do 0 clamp; sem overflow não há barra.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = 99, .pos = types.Vec2.init(10, 10) } });
    _ = try beginScroll(&ctx, id, bounds, &off, 300, 24, style);
    try stdt.testing.expectEqual(@as(f32, 0), off);
    try endScroll(&ctx, bounds, off, 300, style);
    ctx.endFrame();
    ctx.beginFrame();
    var off2: f32 = 50; // normalizado para 0 (conteúdo menor que a vista)
    _ = try beginScroll(&ctx, id, bounds, &off2, 40, 24, style);
    try stdt.testing.expectEqual(@as(f32, 0), off2);
    try endScroll(&ctx, bounds, off2, 40, style);
    try stdt.testing.expectEqual(@as(usize, 2), ctx.drawCommands().len); // só os clips
    ctx.endFrame();

    // Contratos.
    ctx.beginFrame();
    var nan: f32 = std.math.nan(f32);
    try stdt.testing.expectError(error.InvalidArgument, beginScroll(&ctx, .null, bounds, &off, 300, 24, style));
    try stdt.testing.expectError(error.InvalidArgument, beginScroll(&ctx, id, bounds, &nan, 300, 24, style));
    try stdt.testing.expectError(error.InvalidArgument, beginScroll(&ctx, id, bounds, &off, -1, 24, style));
    try stdt.testing.expectError(error.InvalidArgument, beginScroll(&ctx, id, bounds, &off, 300, 0, style));
    ctx.endFrame();
}
