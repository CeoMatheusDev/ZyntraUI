//! ZyntraUI — slider horizontal/vertical (widgets/slider).
//!
//! Modelo M8 (drag com captura, mouse) + M30 (teclado) + M51 (vertical):
//! - `value: *f32` pertence ao chamador; `min < max` obrigatório e
//!   `value` inicial deve ser finito (senão `InvalidArgument`).
//! - Press dentro captura (`press_owner`); enquanto dono + botão
//!   pressionado, o valor segue o mouse X (clampado — pode arrastar para
//!   fora da trilha). Release em qualquer lugar encerra o drag.
//! - Teclado com foco (click foca, Tab circula): setas ajustam em
//!   `(max-min)/20`, `Home`/`End` saltam (sempre clampado).
//! - `changed`: valor difere do da entrada nesta chamada.
//! Desenho (4 comandos): trilha, preenchimento 0..t, handle, outline.
//! `id` não-nulo obrigatório.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const input = @import("input.zig");

pub const SliderResult = struct {
    value: f32 = 0,
    changed: bool = false,
    hovered: bool = false,
    dragging: bool = false,
};

pub fn slider(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    value: *f32,
    min: f32,
    max: f32,
    style: style_mod.SliderStyle,
) context_mod.ContextError!SliderResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;
    if (!std.math.isFinite(min) or !std.math.isFinite(max) or min >= max) {
        return error.InvalidArgument;
    }
    if (!std.math.isFinite(value.*)) return error.InvalidArgument;
    value.* = std.math.clamp(value.*, min, max);

    const fm = input.FrameMouse.scan(ctx.pendingEvents());
    const hovered = if (ctx.mouse_pos) |p| bounds.contains(p) else false;
    var res = SliderResult{ .value = value.*, .hovered = hovered };
    const entry = value.*;
    const step = (max - min) / 20; // passo de teclado (M30)

    // Focável (Tab circula); click foca.
    try ctx.registerFocusable(id);
    if (fm.pressedInside(bounds)) {
        ctx.focus_owner = id;
    }

    if (ctx.press_owner == null and fm.pressedInside(bounds)) {
        ctx.press_owner = id;
    }
    if (ctx.press_owner == id) {
        if (ctx.mouse_down_left) {
            res.dragging = true;
            if (ctx.mouse_pos) |p| {
                const t = std.math.clamp((p.x - bounds.x) / bounds.w, 0, 1);
                value.* = min + t * (max - min);
            }
        }
        if (fm.released_pos != null) {
            ctx.press_owner = null;
            res.dragging = false;
        }
    }
    res.value = value.*;
    res.changed = res.value != entry;

    // Teclado com foco (M30): setas ajustam em `step`, Home/End saltam,
    // Tab circula. Sem drag pelo teclado (só mouse arrasta).
    if (ctx.hasFocus(id)) {
        for (ctx.pendingEvents()) |ev| {
            if (ev != .key) continue;
            const k = ev.key;
            if (!k.pressed or k.modifiers.ctrl) continue;
            switch (k.key) {
                .left, .down => {
                    value.* = std.math.clamp(value.* - step, min, max);
                },
                .right, .up => {
                    value.* = std.math.clamp(value.* + step, min, max);
                },
                .home => value.* = min,
                .end => value.* = max,
                .tab => ctx.requestFocusAdvance(if (k.modifiers.shift) .prev else .next),
                else => {},
            }
        }
        res.value = value.*;
        res.changed = res.value != entry;
    }

    const t = (value.* - min) / (max - min);
    const cy = bounds.y + bounds.h / 2;
    const track = types.Rect{
        .x = bounds.x,
        .y = cy - style.track_height / 2,
        .w = bounds.w,
        .h = style.track_height,
    };
    const handle = types.Rect{
        .x = bounds.x + t * bounds.w - style.handle_w / 2,
        .y = cy - style.handle_h / 2,
        .w = style.handle_w,
        .h = style.handle_h,
    };
    const filled = types.Rect{
        .x = bounds.x,
        .y = track.y,
        .w = @max(0, t * bounds.w),
        .h = track.h,
    };
    ctx.draw.rectFilled(ctx.allocator, track, style.track_bg) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.rectFilled(ctx.allocator, filled, style.fill) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.rectFilled(ctx.allocator, handle, style.handle_bg) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.rectOutline(ctx.allocator, handle, style.border, @max(1.0, style.border_width)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    return res;
}

/// Variante vertical do `slider` (M51): valor cresce para cima
/// (topo = `max`, base = `min`); drag segue o mouse Y clampado.
/// Teclado idêntico ao horizontal (`Up`/`Right` aumentam,
/// `Down`/`Left` diminuem, `Home`/`End` saltam). Desenho em
/// 4 comandos (trilha, preenchimento da base, handle, outline).
/// Reaproveita `SliderStyle` sem mudanças.
pub fn sliderVertical(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    value: *f32,
    min: f32,
    max: f32,
    style: style_mod.SliderStyle,
) context_mod.ContextError!SliderResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;
    if (!std.math.isFinite(min) or !std.math.isFinite(max) or min >= max) {
        return error.InvalidArgument;
    }
    if (!std.math.isFinite(value.*)) return error.InvalidArgument;
    value.* = std.math.clamp(value.*, min, max);

    const fm = input.FrameMouse.scan(ctx.pendingEvents());
    const hovered = if (ctx.mouse_pos) |p| bounds.contains(p) else false;
    var res = SliderResult{ .value = value.*, .hovered = hovered };
    const entry = value.*;
    const step = (max - min) / 20; // passo de teclado (M30)

    // Focável (Tab circula); click foca.
    try ctx.registerFocusable(id);
    if (fm.pressedInside(bounds)) {
        ctx.focus_owner = id;
    }

    if (ctx.press_owner == null and fm.pressedInside(bounds)) {
        ctx.press_owner = id;
    }
    if (ctx.press_owner == id) {
        if (ctx.mouse_down_left) {
            res.dragging = true;
            if (ctx.mouse_pos) |p| {
                const t = std.math.clamp(1 - (p.y - bounds.y) / bounds.h, 0, 1);
                value.* = min + t * (max - min);
            }
        }
        if (fm.released_pos != null) {
            ctx.press_owner = null;
            res.dragging = false;
        }
    }
    res.value = value.*;
    res.changed = res.value != entry;

    // Teclado com foco (mesmo mapa do horizontal).
    if (ctx.hasFocus(id)) {
        for (ctx.pendingEvents()) |ev| {
            if (ev != .key) continue;
            const k = ev.key;
            if (!k.pressed or k.modifiers.ctrl) continue;
            switch (k.key) {
                .left, .down => {
                    value.* = std.math.clamp(value.* - step, min, max);
                },
                .right, .up => {
                    value.* = std.math.clamp(value.* + step, min, max);
                },
                .home => value.* = min,
                .end => value.* = max,
                .tab => ctx.requestFocusAdvance(if (k.modifiers.shift) .prev else .next),
                else => {},
            }
        }
        res.value = value.*;
        res.changed = res.value != entry;
    }

    const t = (value.* - min) / (max - min);
    const cx = bounds.x + bounds.w / 2;
    const ypos = bounds.y + (1 - t) * bounds.h; // centro do handle
    const track = types.Rect{
        .x = cx - style.track_height / 2,
        .y = bounds.y,
        .w = style.track_height,
        .h = bounds.h,
    };
    const handle = types.Rect{
        .x = cx - style.handle_w / 2,
        .y = ypos - style.handle_h / 2,
        .w = style.handle_w,
        .h = style.handle_h,
    };
    const filled = types.Rect{
        .x = track.x,
        .y = ypos,
        .w = track.w,
        .h = @max(0, bounds.y + bounds.h - ypos),
    };
    ctx.draw.rectFilled(ctx.allocator, track, style.track_bg) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.rectFilled(ctx.allocator, filled, style.fill) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.rectFilled(ctx.allocator, handle, style.handle_bg) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.rectOutline(ctx.allocator, handle, style.border, @max(1.0, style.border_width)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    return res;
}

test "slider arrasta entre frames, clampa e valida" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().sliderStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 30);
    const id = id_mod.Id.fromString("test:sld");
    var v: f32 = 50; // min=0 max=100

    // Press no meio (x=100 → t=0.5): captura e já posiciona.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(100, 15) },
    });
    const r0 = try slider(&ctx, id, bounds, &v, 0, 100, style);
    try stdt.testing.expect(r0.dragging);
    try stdt.testing.expectEqual(@as(f32, 50), v);
    try stdt.testing.expectEqual(@as(usize, 4), ctx.drawCommands().len);
    ctx.endFrame();

    // Move com botão pressionado (sem novo press): valor segue.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(150, 15) } });
    const r1 = try slider(&ctx, id, bounds, &v, 0, 100, style);
    try stdt.testing.expect(r1.dragging);
    try stdt.testing.expect(r1.changed);
    try stdt.testing.expectEqual(@as(f32, 75), v);
    ctx.endFrame();

    // Arrastar para fora clampa no máximo.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(9999, 15) } });
    _ = try slider(&ctx, id, bounds, &v, 0, 100, style);
    try stdt.testing.expectEqual(@as(f32, 100), v);
    ctx.endFrame();

    // Release encerra (changed reflete o último movimento).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(9999, 15) },
    });
    const r2 = try slider(&ctx, id, bounds, &v, 0, 100, style);
    try stdt.testing.expect(!r2.dragging);
    try stdt.testing.expect(ctx.press_owner == null);
    ctx.endFrame();

    // Press fora não captura; contratos inválidos rejeitados.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(500, 500) },
    });
    const r3 = try slider(&ctx, id, bounds, &v, 0, 100, style);
    try stdt.testing.expect(!r3.dragging and !r3.changed);
    try stdt.testing.expectError(error.InvalidArgument, slider(&ctx, .null, bounds, &v, 0, 100, style));
    try stdt.testing.expectError(error.InvalidArgument, slider(&ctx, id, bounds, &v, 100, 0, style));
    var nan: f32 = std.math.nan(f32);
    try stdt.testing.expectError(error.InvalidArgument, slider(&ctx, id, bounds, &nan, 0, 100, style));
    ctx.endFrame();
}

test "slider teclado: setas, Home/End, Tab" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().sliderStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 30);
    const id = id_mod.Id.fromString("test:sld-kb");
    var v: f32 = 50; // step = 5

    // Click foca; Right soma um passo.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(100, 15) },
    });
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(100, 15) },
    });
    _ = try slider(&ctx, id, bounds, &v, 0, 100, style);
    try stdt.testing.expect(ctx.hasFocus(id));
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    const r1 = try slider(&ctx, id, bounds, &v, 0, 100, style);
    try stdt.testing.expect(r1.changed and !r1.dragging);
    try stdt.testing.expectEqual(@as(f32, 55), v);
    ctx.endFrame();

    // Left volta; Home/End saltam (clampados).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{} } });
    _ = try slider(&ctx, id, bounds, &v, 0, 100, style);
    try stdt.testing.expectEqual(@as(f32, 50), v);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{} } });
    _ = try slider(&ctx, id, bounds, &v, 0, 100, style);
    try stdt.testing.expectEqual(@as(f32, 100), v);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    const r2 = try slider(&ctx, id, bounds, &v, 0, 100, style);
    try stdt.testing.expect(!r2.changed); // já no máximo
    try stdt.testing.expectEqual(@as(f32, 100), v);
    ctx.endFrame();

    // Sem foco: setas ignoradas.
    ctx.clearFocus();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{} } });
    const r3 = try slider(&ctx, id, bounds, &v, 0, 100, style);
    try stdt.testing.expect(!r3.changed);
    try stdt.testing.expectEqual(@as(f32, 100), v);
    ctx.endFrame();
}

test "sliderVertical arrasta no eixo Y, topo é máximo" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().sliderStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 30, 200);
    const id = id_mod.Id.fromString("test:sld-v");
    var v: f32 = 50; // min=0 max=100

    // Press no meio (y=100 → t=0.5): captura e posiciona.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(15, 100) },
    });
    const r0 = try sliderVertical(&ctx, id, bounds, &v, 0, 100, style);
    try stdt.testing.expect(r0.dragging);
    try stdt.testing.expectEqual(@as(f32, 50), v);
    try stdt.testing.expectEqual(@as(usize, 4), ctx.drawCommands().len);
    ctx.endFrame();

    // Move para cima com botão pressionado: valor sobe.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(15, 50) } });
    const r1 = try sliderVertical(&ctx, id, bounds, &v, 0, 100, style);
    try stdt.testing.expect(r1.dragging);
    try stdt.testing.expect(r1.changed);
    try stdt.testing.expectEqual(@as(f32, 75), v);
    ctx.endFrame();

    // Arrastar acima do topo clampa no máximo.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(15, -9999) } });
    _ = try sliderVertical(&ctx, id, bounds, &v, 0, 100, style);
    try stdt.testing.expectEqual(@as(f32, 100), v);
    ctx.endFrame();

    // Arrastar abaixo da base clampa no mínimo; release encerra.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(15, 9999) } });
    _ = try sliderVertical(&ctx, id, bounds, &v, 0, 100, style);
    try stdt.testing.expectEqual(@as(f32, 0), v);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(15, 9999) },
    });
    const r2 = try sliderVertical(&ctx, id, bounds, &v, 0, 100, style);
    try stdt.testing.expect(!r2.dragging);
    try stdt.testing.expect(ctx.press_owner == null);
    ctx.endFrame();

    // Press fora não captura; contratos inválidos rejeitados.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(500, 500) },
    });
    const r3 = try sliderVertical(&ctx, id, bounds, &v, 0, 100, style);
    try stdt.testing.expect(!r3.dragging and !r3.changed);
    try stdt.testing.expectError(error.InvalidArgument, sliderVertical(&ctx, .null, bounds, &v, 0, 100, style));
    try stdt.testing.expectError(error.InvalidArgument, sliderVertical(&ctx, id, bounds, &v, 100, 0, style));
    var nan: f32 = std.math.nan(f32);
    try stdt.testing.expectError(error.InvalidArgument, sliderVertical(&ctx, id, bounds, &nan, 0, 100, style));
    ctx.endFrame();
    // Solta o press fora (higiene de captura p/ próximos testes).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(500, 500) },
    });
    _ = try sliderVertical(&ctx, id, bounds, &v, 0, 100, style);
    ctx.endFrame();
}

test "sliderVertical teclado: Up/Down, Home/End" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().sliderStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 30, 200);
    const id = id_mod.Id.fromString("test:sld-v-kb");
    var v: f32 = 50; // step = 5

    // Click foca; Up soma um passo.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(15, 100) },
    });
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(15, 100) },
    });
    _ = try sliderVertical(&ctx, id, bounds, &v, 0, 100, style);
    try stdt.testing.expect(ctx.hasFocus(id));
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .up, .pressed = true, .modifiers = .{} } });
    const r1 = try sliderVertical(&ctx, id, bounds, &v, 0, 100, style);
    try stdt.testing.expect(r1.changed and !r1.dragging);
    try stdt.testing.expectEqual(@as(f32, 55), v);
    ctx.endFrame();

    // Down volta; Home/End saltam.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    _ = try sliderVertical(&ctx, id, bounds, &v, 0, 100, style);
    try stdt.testing.expectEqual(@as(f32, 50), v);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    _ = try sliderVertical(&ctx, id, bounds, &v, 0, 100, style);
    try stdt.testing.expectEqual(@as(f32, 0), v);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{} } });
    const r2 = try sliderVertical(&ctx, id, bounds, &v, 0, 100, style);
    try stdt.testing.expect(r2.changed);
    try stdt.testing.expectEqual(@as(f32, 100), v);
    ctx.endFrame();
}

test "slider limites: bounds NaN, valor inicial fora, drag extremo" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().sliderStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:sld-lim");
    const vid = id_mod.Id.fromString("test:sld-lim-v");

    // Bounds não-finitos: InvalidArgument nas duas orientações.
    var v: f32 = 50;
    const nan_bounds = types.Rect.init(0, 0, std.math.nan(f32), 30);
    try stdt.testing.expectError(error.InvalidArgument, slider(&ctx, id, nan_bounds, &v, 0, 100, style));
    try stdt.testing.expectError(error.InvalidArgument, sliderVertical(&ctx, vid, nan_bounds, &v, 0, 100, style));

    // Valor inicial fora da faixa clampa na entrada (sem changed).
    var hi: f32 = 999;
    ctx.beginFrame();
    const r0 = try slider(&ctx, id, types.Rect.init(0, 0, 200, 30), &hi, 0, 100, style);
    try stdt.testing.expectEqual(@as(f32, 100), hi);
    try stdt.testing.expect(!r0.changed);
    ctx.endFrame();
    var lo: f32 = -999;
    ctx.beginFrame();
    _ = try sliderVertical(&ctx, vid, types.Rect.init(0, 0, 30, 200), &lo, 0, 100, style);
    try stdt.testing.expectEqual(@as(f32, 0), lo);
    ctx.endFrame();

    // Drag em posição finita extrema: clampa, sem pânico nem NaN.
    var d: f32 = 50;
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(100, 15) },
    });
    _ = try slider(&ctx, id, types.Rect.init(0, 0, 200, 30), &d, 0, 100, style);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(1e30, 15) } });
    _ = try slider(&ctx, id, types.Rect.init(0, 0, 200, 30), &d, 0, 100, style);
    try stdt.testing.expectEqual(@as(f32, 100), d);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(-1e30, 15) } });
    _ = try slider(&ctx, id, types.Rect.init(0, 0, 200, 30), &d, 0, 100, style);
    try stdt.testing.expectEqual(@as(f32, 0), d);
    ctx.endFrame();

    // Faixa minúscula continua válida (sem divisão por zero: min < max).
    // Solta o drag anterior e foca com click antes da tecla.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(-1e30, 15) },
    });
    ctx.endFrame();
    var tiny: f32 = 0;
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(100, 15) },
    });
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(100, 15) },
    });
    _ = try slider(&ctx, id, types.Rect.init(0, 0, 200, 30), &tiny, 0, 1e-30, style);
    try stdt.testing.expect(ctx.hasFocus(id));
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    const rt = try slider(&ctx, id, types.Rect.init(0, 0, 200, 30), &tiny, 0, 1e-30, style);
    try stdt.testing.expect(rt.changed);
    try stdt.testing.expect(tiny >= 0 and tiny <= 1e-30);
    ctx.endFrame();

    // Estilo inválido rejeitado.
    var bad = style;
    bad.track_height = 0;
    try stdt.testing.expectError(error.InvalidArgument, slider(&ctx, id, types.Rect.init(0, 0, 200, 30), &d, 0, 100, bad));
}
