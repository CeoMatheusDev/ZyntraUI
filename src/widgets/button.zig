//! ZyntraUI — botão (widgets/button).
//!
//! Modelo M7 (release-to-activate):
//! - `hovered`: `Context.mouse_pos` (retido) dentro de `bounds`.
//! - Press dentro captura (`Context.press_owner = id`, exclusivo).
//! - `pressed`: sou o dono da captura e o botão segue pressionado.
//! - `clicked`: release esquerdo neste frame com o mouse dentro.
//!   Release fora cancela (sem click). Captura órfã: ver
//!   `Context.clearPressCapture`.
//! - Teclado (M29): focável (click foca, Tab circula); Espaço/Enter
//!   com foco clicam (sem visual de segurado).
//! Ownership: estado de captura vive no `Context`; chamador detém
//! `bounds`/`style`. `id` não-nulo obrigatório.
//! Emite 2 comandos (fill + outline). Erros: OOM ou estilo inválido.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const input = @import("input.zig");

pub const ButtonResult = struct {
    hovered: bool = false,
    pressed: bool = false,
    clicked: bool = false,
};

pub fn button(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    style: style_mod.ButtonStyle,
) context_mod.ContextError!ButtonResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;

    const fm = input.FrameMouse.scan(ctx.pendingEvents());
    const hovered = if (ctx.mouse_pos) |p| bounds.contains(p) else false;
    var res = ButtonResult{ .hovered = hovered };

    // Focável (Tab circula entre botões e inputs registrados).
    try ctx.registerFocusable(id);
    if (fm.pressedInside(bounds)) {
        ctx.focus_owner = id;
    }

    if (ctx.press_owner == null and fm.pressedInside(bounds)) {
        ctx.press_owner = id;
    }
    if (ctx.press_owner == id) {
        res.pressed = ctx.mouse_down_left;
        if (fm.released_pos != null) {
            if (hovered) res.clicked = true;
            ctx.press_owner = null;
        }
    }

    // Ativação por teclado (M29): Espaço/Enter com foco clicam;
    // Tab circula (registro completo no próximo beginFrame).
    // Sem visual de "segurado" (evento de press, sem estado retido).
    if (ctx.hasFocus(id)) {
        for (ctx.pendingEvents()) |ev| {
            if (ev != .key) continue;
            const k = ev.key;
            if (!k.pressed or k.modifiers.ctrl) continue;
            switch (k.key) {
                .space, .enter => res.clicked = true,
                .tab => ctx.requestFocusAdvance(if (k.modifiers.shift) .prev else .next),
                else => {},
            }
        }
    }

    const bg = if (res.pressed)
        style.bg_pressed
    else if (res.hovered)
        style.bg_hover
    else
        style.bg;

    // Estado de interação (M99): hover/press mudam a cor de fundo ⇒
    // alimenta o dirty rect (tanto na entrada quanto na saída do realce).
    try ctx.mark_hot(id, bounds, hovered or res.pressed);

    // Acessibilidade (M164): o botão é um nó focável; o rótulo é
    // preenchido pelo app (o widget não sabe o texto).
    try ctx.pushA11yWidget(id, .button, bounds, .{
        .focused = ctx.hasFocus(id),
        .pressed = res.pressed,
    });

    ctx.draw.rectFilled(ctx.allocator, bounds, bg) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.rectOutline(ctx.allocator, bounds, style.border, @max(1.0, style.border_width)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    return res;
}

test "button hover/press/release-to-activate + captura" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().buttonStyle();

    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(10, 10, 120, 40);
    const id = id_mod.Id.fromString("test:btn");
    const id2 = id_mod.Id.fromString("test:btn2");

    // Hover sem press: nada ativa.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(20, 20) } });
    const hover = try button(&ctx, id, bounds, style);
    try stdt.testing.expect(hover.hovered);
    try stdt.testing.expect(!hover.pressed and !hover.clicked);
    try stdt.testing.expectEqual(@as(usize, 2), ctx.drawCommands().len);
    ctx.endFrame();

    // Press dentro: captura, pressed, ainda sem click.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(20, 20) },
    });
    const down = try button(&ctx, id, bounds, style);
    try stdt.testing.expect(down.pressed);
    try stdt.testing.expect(!down.clicked);
    try stdt.testing.expect(ctx.press_owner == id);
    ctx.endFrame();

    // Release dentro no frame seguinte: click. Mouse retido dispensa move.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(20, 20) },
    });
    const click = try button(&ctx, id, bounds, style);
    try stdt.testing.expect(click.clicked);
    try stdt.testing.expect(!click.pressed);
    try stdt.testing.expect(ctx.press_owner == null);
    ctx.endFrame();

    // Press dentro + release fora: cancela, sem click.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(20, 20) },
    });
    _ = try button(&ctx, id, bounds, style);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(700, 700) },
    });
    const cancelled = try button(&ctx, id, bounds, style);
    try stdt.testing.expect(!cancelled.clicked and !cancelled.pressed);
    try stdt.testing.expect(ctx.press_owner == null);
    ctx.endFrame();

    // Captura é exclusiva: press em btn1 bloqueia btn2 sobreposto.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(20, 20) },
    });
    _ = try button(&ctx, id, bounds, style);
    const blocked = try button(&ctx, id2, bounds, style);
    try stdt.testing.expect(!blocked.pressed and !blocked.clicked);
    ctx.endFrame();

    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, button(&ctx, .null, bounds, style));
    ctx.endFrame();
}

test "button teclado: Espaço/Enter clicam com foco" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().buttonStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(10, 10, 120, 40);
    const id = id_mod.Id.fromString("test:btn-kb");

    // Click foca (e solta); Espaço clica sem mouse.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(20, 20) },
    });
    _ = try button(&ctx, id, bounds, style);
    try stdt.testing.expect(ctx.hasFocus(id));
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(20, 20) },
    });
    _ = try button(&ctx, id, bounds, style);
    try stdt.testing.expect(!ctx.mouse_down_left);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .space, .pressed = true, .modifiers = .{} } });
    const r1 = try button(&ctx, id, bounds, style);
    try stdt.testing.expect(r1.clicked and !r1.pressed);
    ctx.endFrame();

    // Enter também; Ctrl+Espaço não; sem foco nada.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .enter, .pressed = true, .modifiers = .{} } });
    const r2 = try button(&ctx, id, bounds, style);
    try stdt.testing.expect(r2.clicked);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .space, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const r3 = try button(&ctx, id, bounds, style);
    try stdt.testing.expect(!r3.clicked);
    ctx.endFrame();
    ctx.clearFocus();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .space, .pressed = true, .modifiers = .{} } });
    const r4 = try button(&ctx, id, bounds, style);
    try stdt.testing.expect(!r4.clicked);
    ctx.endFrame();
}

test "button rejeita bounds não-finitos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().buttonStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:btn-nan");
    const nan_bounds = types.Rect.init(0, 0, std.math.nan(f32), 40);
    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, button(&ctx, id, nan_bounds, style));
    ctx.endFrame();
}

test "a11y M164: os widgets registram nós na árvore do frame" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const label_mod = @import("label.zig");
    const input_mod = @import("text_input.zig");
    const metrics_mod = @import("../text/metrics.zig");
    const theme = style_mod.Theme.darkDefault();

    var ctx = try context_mod.Context.init(gpa, .{ .viewport = types.Rect.init(0, 0, 200, 200) });
    defer ctx.deinit();
    ctx.beginFrame();

    const btn_id = id_mod.Id.fromString("a11y:btn");
    _ = try button(&ctx, btn_id, types.Rect.init(10, 10, 100, 30), theme.buttonStyle());

    const label_id = id_mod.Id.fromString("a11y:label");
    _ = try label_mod.label(
        &ctx,
        label_id,
        types.Rect.init(10, 50, 100, 20),
        "Olá",
        types.Color.rgb(255, 255, 255),
        metrics_mod.FontMetrics{},
        false,
    );

    const input_id = id_mod.Id.fromString("a11y:input");
    var buf: [32]u8 = undefined;
    // O campo tem o texto "abc" (o valor é lido no desenho).
    buf[0] = 'a';
    buf[1] = 'b';
    buf[2] = 'c';
    var len: usize = 3;
    var cursor: usize = 3;
    _ = try input_mod.textInput(
        &ctx,
        input_id,
        types.Rect.init(10, 80, 100, 24),
        &buf,
        &len,
        &cursor,
        metrics_mod.FontMetrics{},
        theme.textInputStyle(),
    );

    ctx.endFrame();

    const tree = ctx.a11y;
    try stdt.testing.expectEqual(@as(usize, 3), tree.len());

    // O botão.
    const btn = tree.at(0).?;
    try stdt.testing.expectEqual(@as(u64, btn_id.value()), btn.id);
    try stdt.testing.expectEqual(@import("../a11y/tree.zig").Role.button, btn.role);

    // O rótulo carrega o texto.
    const lab = tree.at(1).?;
    try stdt.testing.expectEqual(@import("../a11y/tree.zig").Role.label, lab.role);
    try stdt.testing.expectEqualStrings("Olá", lab.label);

    // O campo carrega o valor (o texto atual).
    const inp = tree.at(2).?;
    try stdt.testing.expectEqual(@import("../a11y/tree.zig").Role.textbox, inp.role);
    try stdt.testing.expectEqualStrings("abc", inp.value);
    try stdt.testing.expect(inp.state.editable);

    // O app completa o rótulo do botão.
    ctx.beginFrame();
    _ = try button(&ctx, btn_id, types.Rect.init(10, 10, 100, 30), theme.buttonStyle());
    ctx.setA11yLabel(btn_id, "Enviar");
    ctx.endFrame();
    try stdt.testing.expectEqualStrings("Enviar", ctx.a11y.at(0).?.label);
}
