//! ZyntraUI — switch (toggle) (widgets/switch).
//!
//! Modelo M63: controle binário ligado/desligado, complementar ao
//! checkbox. Estado (`checked: *bool`) pertence ao chamador (padrão
//! ImGui-like); a captura de press vive no `Context` (como no botão, M7).
//! - Mouse: press captura e foca; release **dentro** alterna; release
//!   fora cancela. Múltiplos presses no mesmo frame contam como um.
//! - Teclado com foco: Espaço alterna; Tab circula o foco (Shift volta).
//! - Desenho: trilho (`track`/`track_on`, com hover) + knob deslizante
//!   à esquerda/direita + outline. Emite 3 comandos.
//! - `SwitchStyle` + `Theme.switchStyle()` — cores e geometria.
//! Contratos: `id` não-nulo; `2*knob_pad < bounds.h`; `bounds.w >= bounds.h`
//! (knob quadrado, cabe com folga na largura). Sem animação (estado
//! instantâneo, como o checkbox).

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const input = @import("input.zig");

pub const SwitchResult = struct {
    hovered: bool = false,
    toggled: bool = false,
    checked: bool = false,
    focused: bool = false,
};

/// Retângulo do knob dentro do trilho para o estado atual.
/// Knob quadrado com o lado igual à altura útil; à esquerda quando
/// desligado, à direita quando ligado (reto, sem cantos arredondados).
/// Requer `bounds.w >= bounds.h` e `2*knob_pad < bounds.h`.
pub fn switchKnobRect(bounds: types.Rect, checked: bool, style: style_mod.SwitchStyle) types.Rect {
    const pad = style.knob_pad;
    const size = @max(0, bounds.h - pad * 2);
    const x = if (checked) bounds.x + bounds.w - pad - size else bounds.x + pad;
    return types.Rect.init(x, bounds.y + pad, size, size);
}

/// Cor do trilho para o estado/hover (ligado ignora hover).
pub fn switchTrackColor(checked: bool, hovered: bool, style: style_mod.SwitchStyle) types.Color {
    if (checked) return style.track_on;
    return if (hovered) style.track_hover else style.track;
}

pub fn beginSwitch(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    checked: *bool,
    style: style_mod.SwitchStyle,
) context_mod.ContextError!SwitchResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;
    if (style.knob_pad * 2 >= bounds.h) return error.InvalidArgument;
    if (bounds.w < bounds.h) return error.InvalidArgument;

    const fm = input.FrameMouse.scan(ctx.pendingEvents());
    const hovered = if (ctx.mouse_pos) |p| bounds.contains(p) else false;
    var res = SwitchResult{ .hovered = hovered, .checked = checked.* };

    // Focável (Tab circula); click foca.
    try ctx.registerFocusable(id);
    if (fm.pressedInside(bounds)) {
        ctx.focus_owner = id;
    }
    if (ctx.press_owner == null and fm.pressedInside(bounds)) {
        ctx.press_owner = id;
    }
    if (ctx.press_owner == id and fm.released_pos != null) {
        if (hovered) {
            checked.* = !checked.*;
            res.toggled = true;
            res.checked = checked.*;
        }
        ctx.press_owner = null;
    }

    // Teclado com foco: Espaço alterna; Tab circula.
    if (ctx.hasFocus(id)) {
        for (ctx.pendingEvents()) |ev| {
            if (ev != .key) continue;
            const k = ev.key;
            if (!k.pressed or k.modifiers.ctrl) continue;
            switch (k.key) {
                .space => {
                    checked.* = !checked.*;
                    res.toggled = true;
                    res.checked = checked.*;
                },
                .tab => ctx.requestFocusAdvance(if (k.modifiers.shift) .prev else .next),
                else => {},
            }
        }
    }

    ctx.draw.rectFilled(ctx.allocator, bounds, switchTrackColor(checked.*, hovered, style)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    const knob = switchKnobRect(bounds, checked.*, style);
    ctx.draw.rectFilled(ctx.allocator, knob, style.knob) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.rectOutline(ctx.allocator, bounds, style.border, @max(1.0, style.border_width)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };

    res.checked = checked.*;
    res.focused = ctx.hasFocus(id);
    return res;
}

/// Fim do switch (M63): NO-OP — sem estado retido, sem draws.
/// Existe apenas para simetria de pareamento com outros widgets.
pub fn endSwitch(_: *context_mod.Context) void {}

test "switch alterna no release dentro, cancela fora" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().switchStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 44, 22);
    const id = id_mod.Id.fromString("test:sw");
    var checked = false;

    // Press captura e foca, mas não alterna ainda (3 draws).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 11) },
    });
    const r0 = try beginSwitch(&ctx, id, bounds, &checked, style);
    try stdt.testing.expect(!r0.toggled);
    try stdt.testing.expect(!checked);
    try stdt.testing.expect(r0.focused);
    try stdt.testing.expectEqual(@as(usize, 3), ctx.drawCommands().len);
    ctx.endFrame();

    // Release dentro: alterna.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(5, 11) },
    });
    const r1 = try beginSwitch(&ctx, id, bounds, &checked, style);
    try stdt.testing.expect(r1.toggled);
    try stdt.testing.expect(checked);
    ctx.endFrame();

    // Press dentro + release fora: cancela, mantém estado.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 11) },
    });
    _ = try beginSwitch(&ctx, id, bounds, &checked, style);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(500, 500) },
    });
    const r2 = try beginSwitch(&ctx, id, bounds, &checked, style);
    try stdt.testing.expect(!r2.toggled);
    try stdt.testing.expect(checked);
    ctx.endFrame();
}

test "switch teclado: Espaço alterna, Enter ignora" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().switchStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 44, 22);
    const id = id_mod.Id.fromString("test:sw-kb");
    var checked = false;

    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 11) },
    });
    _ = try beginSwitch(&ctx, id, bounds, &checked, style);
    try stdt.testing.expect(ctx.hasFocus(id));
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .space, .pressed = true, .modifiers = .{} } });
    const r1 = try beginSwitch(&ctx, id, bounds, &checked, style);
    try stdt.testing.expect(r1.toggled and checked and r1.focused);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .enter, .pressed = true, .modifiers = .{} } });
    const r2 = try beginSwitch(&ctx, id, bounds, &checked, style);
    try stdt.testing.expect(!r2.toggled and checked);
    ctx.endFrame();
}

test "switch knob desliza + contratos inválidos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().switchStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(10, 10, 44, 22);
    const id = id_mod.Id.fromString("test:sw-geom");
    var checked = false;

    // Knob à esquerda (off) e à direita (on), mesmo tamanho quadrado.
    const off = switchKnobRect(bounds, false, style);
    const on = switchKnobRect(bounds, true, style);
    try stdt.testing.expectEqual(off.w, off.h);
    try stdt.testing.expect(on.x > off.x);
    try stdt.testing.expectEqual(bounds.y + bounds.h, on.y + on.h + style.knob_pad);
    try stdt.testing.expectEqual(bounds.x + style.knob_pad, off.x);
    try stdt.testing.expectEqual(bounds.x + bounds.w - style.knob_pad, on.x + on.w);

    // Contratos inválidos.
    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, beginSwitch(&ctx, .null, bounds, &checked, style));
    try stdt.testing.expectError(error.InvalidArgument, beginSwitch(&ctx, id, types.Rect.init(0, 0, 0, 0), &checked, style));
    // Largura menor que altura: knob não caberia.
    try stdt.testing.expectError(error.InvalidArgument, beginSwitch(&ctx, id, types.Rect.init(0, 0, 10, 22), &checked, style));
    const bad_pad = style_mod.SwitchStyle{
        .track = .{},
        .track_on = .{},
        .track_hover = .{},
        .knob = .{},
        .border = .{},
        .border_width = 1.0,
        .knob_pad = 11.0,
    };
    try stdt.testing.expectError(error.InvalidArgument, beginSwitch(&ctx, id, bounds, &checked, bad_pad));
    const bad_style = style_mod.SwitchStyle{
        .track = .{},
        .track_on = .{},
        .track_hover = .{},
        .knob = .{},
        .border = .{},
        .knob_pad = -1.0,
    };
    try stdt.testing.expectError(error.InvalidArgument, beginSwitch(&ctx, id, bounds, &checked, bad_style));
    ctx.endFrame();
}

test "switch rejeita bounds não-finitos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().switchStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:sw-nan");
    var checked = false;
    const nan_bounds = types.Rect.init(std.math.nan(f32), 0, 44, 22);
    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, beginSwitch(&ctx, id, nan_bounds, &checked, style));
    try stdt.testing.expect(!checked);
    ctx.endFrame();
}
