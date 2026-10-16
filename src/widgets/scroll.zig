//! ZyntraUI — container com scroll (widgets/scroll).
//!
//! Modelo M16+M17 (begin/end imediato, estado no chamador) + M31 teclado:
//! - `beginScroll(ctx,id,bounds,scroll_y,content_h,speed,style)`:
//!   `mouse_wheel` com hover (`dy > 0` sobe, `speed` px/unidade);
//!   press no thumb captura e o arrasto posiciona absoluto;
//!   tudo clampado em [0, max(0, content_h-bounds.h)].
//! - Focável (click foca, Tab circula; filhos clicados refocam depois):
//!   `PageUp`/`PageDown` = ±vista, `Home`/`End` = extremos.
//! - Emite `clip(bounds)`; filhos entre begin/end saem clippados;
//!   `endScroll` limpa o clip e desenha a scrollbar (só com overflow).
//!   SEMPRE parear (mesmo sem filhos).
//! - `scroll_y: *f32` do chamador, normalizado a cada chamada
//!   (NaN rejeitado). Geometria do thumb partilhada hit-test/desenho.
//! `id` não-nulo (dono da captura de drag).

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const input = @import("input.zig");

pub const ScrollResult = struct {
    /// Área onde os filhos devem ser posicionados (origem deslocada).
    content: types.Rect = .{},
    offset: f32 = 0,
    max_offset: f32 = 0,
    hovered: bool = false,
    scrolled: bool = false,
    dragging: bool = false,
};

/// Geometria do thumb (`null` sem overflow). Partilhada entre hit-test
/// (begin) e desenho (end) para nunca divergirem.
fn thumbRect(bounds: types.Rect, scroll_y: f32, content_h: f32, style: style_mod.ScrollStyle) ?types.Rect {
    const max_offset = @max(0, content_h - bounds.h);
    if (max_offset <= 0) return null;
    const bw = @min(style.bar_width, bounds.w);
    const frac = bounds.h / content_h;
    const thumb_h = @max(bw, bounds.h * frac);
    const travel = bounds.h - thumb_h;
    const ty = bounds.y + (if (max_offset > 0) travel * (scroll_y / max_offset) else 0);
    return .{ .x = bounds.x + bounds.w - bw, .y = ty, .w = bw, .h = thumb_h };
}

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
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;
    if (!std.math.isFinite(content_h) or content_h < 0) return error.InvalidArgument;
    if (!std.math.isFinite(speed) or speed <= 0) return error.InvalidArgument;
    if (!std.math.isFinite(scroll_y.*)) return error.InvalidArgument;

    const max_offset = @max(0, content_h - bounds.h);
    scroll_y.* = std.math.clamp(scroll_y.*, 0, max_offset);
    const hovered = if (ctx.mouse_pos) |p| bounds.contains(p) else false;
    const fm = input.FrameMouse.scan(ctx.pendingEvents());

    // Focável (Tab circula); click foca (filhos clicados refocam depois,
    // na ordem de sondagem).
    try ctx.registerFocusable(id);
    if (fm.pressedInside(bounds)) {
        ctx.focus_owner = id;
    }

    var res = ScrollResult{
        .content = .{ .x = bounds.x, .y = bounds.y - scroll_y.*, .w = bounds.w, .h = @max(bounds.h, content_h) },
        .offset = scroll_y.*,
        .max_offset = max_offset,
        .hovered = hovered,
    };

    // Drag no thumb: press captura; posição absoluta do mouse dita o
    // offset (pulo direto, não relativo ao grab). Release encerra.
    const thumb = thumbRect(bounds, scroll_y.*, content_h, style);
    if (thumb) |tr| {
        if (ctx.press_owner == null and fm.pressed_pos != null and tr.contains(fm.pressed_pos.?)) {
            ctx.press_owner = id;
        }
    }
    if (ctx.press_owner == id) {
        res.dragging = ctx.mouse_down_left;
        if (thumbRect(bounds, scroll_y.*, content_h, style)) |tr| {
            // Recomputa a cada chamada (thumb move com o offset).
            const travel = bounds.h - tr.h;
            if (travel > 0) {
                if (ctx.mouse_pos) |p| {
                    const t = std.math.clamp((p.y - bounds.y - tr.h / 2) / travel, 0, 1);
                    scroll_y.* = t * max_offset;
                }
            }
        }
        if (fm.released_pos != null) {
            ctx.press_owner = null;
            res.dragging = false;
        }
        res.offset = scroll_y.*;
        res.content.y = bounds.y - scroll_y.*;
    } else if (hovered) {
        for (ctx.pendingEvents()) |ev| {
            if (ev != .mouse_wheel) continue;
            scroll_y.* = std.math.clamp(scroll_y.* - ev.mouse_wheel.dy * speed, 0, max_offset);
            res.scrolled = true;
        }
        res.offset = scroll_y.*;
        res.content.y = bounds.y - scroll_y.*;
    }

    // Teclado com foco (M31): PageUp/Down = ±vista, Home/End = extremos.
    if (ctx.hasFocus(id)) {
        for (ctx.pendingEvents()) |ev| {
            if (ev != .key) continue;
            const k = ev.key;
            if (!k.pressed or k.modifiers.ctrl) continue;
            switch (k.key) {
                .page_up => {
                    scroll_y.* = std.math.clamp(scroll_y.* - bounds.h, 0, max_offset);
                    res.scrolled = true;
                },
                .page_down => {
                    scroll_y.* = std.math.clamp(scroll_y.* + bounds.h, 0, max_offset);
                    res.scrolled = true;
                },
                .home => {
                    scroll_y.* = 0;
                    res.scrolled = true;
                },
                .end => {
                    scroll_y.* = max_offset;
                    res.scrolled = true;
                },
                .tab => ctx.requestFocusAdvance(if (k.modifiers.shift) .prev else .next),
                else => {},
            }
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
    const tr = thumbRect(bounds, scroll_y, content_h, style) orelse return;
    const bw = tr.w;
    const track = types.Rect{ .x = bounds.x + bounds.w - bw, .y = bounds.y, .w = bw, .h = bounds.h };
    ctx.draw.rectFilled(ctx.allocator, track, style.track) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.rectFilled(ctx.allocator, tr, style.thumb) catch |err| switch (err) {
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

test "scroll drag no thumb posiciona absoluto" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().scrollStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    // bounds 200×100, conteúdo 300: thumb h=33.33 em y=0..33.33, x=192..200.
    const bounds = types.Rect.init(0, 0, 200, 100);
    const id = id_mod.Id.fromString("test:sc-drag");
    var off: f32 = 0;

    // Press no thumb captura (sem mover ainda).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(196, 10) },
    });
    const r0 = try beginScroll(&ctx, id, bounds, &off, 300, 24, style);
    try stdt.testing.expect(r0.dragging);
    try stdt.testing.expect(ctx.press_owner == id);
    try endScroll(&ctx, bounds, off, 300, style);
    ctx.endFrame();

    // Move com botão pressionado: y=60 → t=(60-16.67)/66.67=0.65 → 130.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(196, 60) } });
    const r1 = try beginScroll(&ctx, id, bounds, &off, 300, 24, style);
    try stdt.testing.expect(r1.dragging);
    try stdt.testing.expectApproxEqAbs(@as(f32, 130), off, 0.01);
    try endScroll(&ctx, bounds, off, 300, style);
    ctx.endFrame();

    // Release encerra a captura.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(196, 60) },
    });
    const r2 = try beginScroll(&ctx, id, bounds, &off, 300, 24, style);
    try stdt.testing.expect(!r2.dragging);
    try stdt.testing.expect(ctx.press_owner == null);
    try endScroll(&ctx, bounds, off, 300, style);
    ctx.endFrame();

    // Press na trilha fora do thumb não captura.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(196, 95) },
    });
    const r3 = try beginScroll(&ctx, id, bounds, &off, 300, 24, style);
    try stdt.testing.expect(!r3.dragging);
    try stdt.testing.expect(ctx.press_owner == null);
    try endScroll(&ctx, bounds, off, 300, style);
    ctx.endFrame();
}

test "scroll teclado: PageUp/Down, Home/End com foco" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().scrollStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 100);
    const id = id_mod.Id.fromString("test:sc-kb");
    var off: f32 = 0;

    // Click foca; PageDown desce uma vista (100); PageUp volta.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(10, 10) },
    });
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(10, 10) },
    });
    _ = try beginScroll(&ctx, id, bounds, &off, 300, 24, style);
    try stdt.testing.expect(ctx.hasFocus(id));
    try endScroll(&ctx, bounds, off, 300, style);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .page_down, .pressed = true, .modifiers = .{} } });
    const r1 = try beginScroll(&ctx, id, bounds, &off, 300, 24, style);
    try stdt.testing.expect(r1.scrolled);
    try stdt.testing.expectEqual(@as(f32, 100), off);
    try endScroll(&ctx, bounds, off, 300, style);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .page_down, .pressed = true, .modifiers = .{} } });
    _ = try beginScroll(&ctx, id, bounds, &off, 300, 24, style);
    try stdt.testing.expectEqual(@as(f32, 200), off); // clamp no max
    try endScroll(&ctx, bounds, off, 300, style);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .page_up, .pressed = true, .modifiers = .{} } });
    _ = try beginScroll(&ctx, id, bounds, &off, 300, 24, style);
    try stdt.testing.expectEqual(@as(f32, 100), off);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    _ = try beginScroll(&ctx, id, bounds, &off, 300, 24, style);
    try stdt.testing.expectEqual(@as(f32, 0), off);
    ctx.endFrame();

    // Sem foco: teclas ignoradas.
    ctx.clearFocus();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{} } });
    const r2 = try beginScroll(&ctx, id, bounds, &off, 300, 24, style);
    try stdt.testing.expect(!r2.scrolled);
    try stdt.testing.expectEqual(@as(f32, 0), off);
    try endScroll(&ctx, bounds, off, 300, style);
    ctx.endFrame();
}

test "scroll rejeita bounds não-finitos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().scrollStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:scr-nan");
    var off: f32 = 0;
    const nan_bounds = types.Rect.init(0, 0, 200, std.math.nan(f32));
    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, beginScroll(&ctx, id, nan_bounds, &off, 300, 24, style));
    try stdt.testing.expectEqual(@as(f32, 0), off);
    ctx.endFrame();
}
