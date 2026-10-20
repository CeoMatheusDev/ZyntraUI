//! ZyntraUI — combobox (widgets/combo).
//!
//! Modelo M36 (composição, estado no chamador) + M40 (teclado):
//! - Fechado: campo estilo-botão com rótulo selecionado + chevron;
//!   click abre (`open.* = true`) e foca o menu. Com foco, Espaço/Enter
//!   (via button) ou setas abrem direto no menu focado.
//! - Aberto: menu dropdown abaixo do campo (mesma largura) via
//!   `menu()` com id derivado (`id.child(1)`); escolha fecha e
//!   seleciona; press fora/`Escape` fecha sem mudar.
//! - `selected: *usize` e `open: *bool` do chamador. Reusa
//!   `ButtonStyle`/`MenuStyle` (sem struct nova).
//! - Sem clamp ao viewport (chamador posiciona); sem edição de texto.
//! `options` vazio ou `selected` fora da faixa → `InvalidArgument`.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const metrics_mod = @import("../text/metrics.zig");
const button_mod = @import("button.zig");
const menu_mod = @import("menu.zig");

pub const ComboResult = struct {
    changed: bool = false,
    open: bool = false,
};

pub fn combo(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    options: []const []const u8,
    selected: *usize,
    open: *bool,
    font: metrics_mod.FontMetrics,
    button_style: style_mod.ButtonStyle,
    menu_style: style_mod.MenuStyle,
) context_mod.ContextError!ComboResult {
    if (id.isNull()) return error.InvalidArgument;
    if (options.len == 0 or options.len > 256) return error.InvalidArgument;
    if (selected.* >= options.len) return error.InvalidArgument;
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    var res = ComboResult{ .open = open.* };

    if (!open.*) {
        const b = try button_mod.button(ctx, id, bounds, button_style);
        if (b.clicked) {
            open.* = true;
            res.open = true;
            ctx.focus_owner = id.child(1); // menu já nasce focado
        } else if (ctx.hasFocus(id)) {
            // Setas com foco abrem (Espaço/Enter já vêm do button).
            for (ctx.pendingEvents()) |ev| {
                if (ev != .key) continue;
                const k = ev.key;
                if (!k.pressed or k.modifiers.ctrl) continue;
                if (k.key == .down or k.key == .up) {
                    open.* = true;
                    res.open = true;
                    ctx.focus_owner = id.child(1);
                    break;
                }
            }
        }
        // Rótulo + chevron sobre o campo do botão.
        if (options[selected.*].len > 0) {
            ctx.pushText(
                .{ .x = bounds.x + 8, .y = bounds.y + (bounds.h - font.lineHeight()) / 2 },
                menu_style.text,
                font,
                options[selected.*],
            ) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidCommand => return error.InvalidCommand,
                error.InvalidUtf8 => return error.InvalidArgument,
                error.InvalidMetrics => return error.InvalidArgument,
            };
        }
        const cx = bounds.x + bounds.w - 16;
        const cy = bounds.y + bounds.h / 2;
        ctx.draw.line(ctx.allocator, .{ .x = cx, .y = cy - 3 }, .{ .x = cx + 6, .y = cy + 3 }, button_style.border, 2.0) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
        };
        ctx.draw.line(ctx.allocator, .{ .x = cx + 6, .y = cy + 3 }, .{ .x = cx + 12, .y = cy - 3 }, button_style.border, 2.0) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
        };
        return res;
    }

    // Aberto: menu abaixo; escolha fecha, fora/Escape fecha sem mudar.
    // Sem alloc: itens na pilha (teto 256 já validado acima).
    var buf: [256]menu_mod.MenuItem = undefined;
    const items = buf[0..options.len];
    for (options, 0..) |label, i| items[i] = .{ .label = label };
    var active: usize = selected.*;
    const mb = types.Rect{
        .x = bounds.x,
        .y = bounds.y + bounds.h,
        .w = bounds.w,
        .h = @as(f32, @floatFromInt(options.len)) * (font.lineHeight() + 8),
    };
    const m = try menu_mod.menu(ctx, id.child(1), mb, items, &active, font, menu_style);
    if (m.chosen) |c| {
        if (c != selected.*) res.changed = true;
        selected.* = c;
        open.* = false;
        res.open = false;
    } else if (m.dismissed) {
        open.* = false;
        res.open = false;
    }
    return res;
}

test "combo abre, escolhe e fecha; fora dispensa" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const theme = style_mod.Theme.darkDefault();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 160, 30);
    const id = id_mod.Id.fromString("test:combo");
    const opts = [_][]const u8{ "A", "B", "C" };
    var sel: usize = 0;
    var open = false;

    // Fechado: click abre (press+release no campo).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(10, 10) },
    });
    _ = try combo(&ctx, id, bounds, &opts, &sel, &open, font, theme.buttonStyle(), theme.menuStyle());
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(10, 10) },
    });
    const r0 = try combo(&ctx, id, bounds, &opts, &sel, &open, font, theme.buttonStyle(), theme.menuStyle());
    try stdt.testing.expect(r0.open and open);
    try stdt.testing.expect(ctx.hasFocus(id.child(1))); // menu já focado
    ctx.endFrame();

    // Aberto: click no item 2 (ih=18.625; y=30+2*18.625=67 → idx 2).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(10, 70) },
    });
    const r1 = try combo(&ctx, id, bounds, &opts, &sel, &open, font, theme.buttonStyle(), theme.menuStyle());
    try stdt.testing.expect(r1.changed and !r1.open and !open);
    try stdt.testing.expectEqual(@as(usize, 2), sel);
    ctx.endFrame();

    // Reabre e dispensa fora.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(10, 10) },
    });
    _ = try combo(&ctx, id, bounds, &opts, &sel, &open, font, theme.buttonStyle(), theme.menuStyle());
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(10, 10) },
    });
    _ = try combo(&ctx, id, bounds, &opts, &sel, &open, font, theme.buttonStyle(), theme.menuStyle());
    try stdt.testing.expect(open);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(500, 500) },
    });
    const r2 = try combo(&ctx, id, bounds, &opts, &sel, &open, font, theme.buttonStyle(), theme.menuStyle());
    try stdt.testing.expect(!r2.open and !open and !r2.changed);
    try stdt.testing.expectEqual(@as(usize, 2), sel);
    ctx.endFrame();

    // Contratos.
    ctx.beginFrame();
    const empty = [_][]const u8{};
    var bad: usize = 9;
    try stdt.testing.expectError(error.InvalidArgument, combo(&ctx, .null, bounds, &opts, &sel, &open, font, theme.buttonStyle(), theme.menuStyle()));
    try stdt.testing.expectError(error.InvalidArgument, combo(&ctx, id, bounds, &empty, &sel, &open, font, theme.buttonStyle(), theme.menuStyle()));
    try stdt.testing.expectError(error.InvalidArgument, combo(&ctx, id, bounds, &opts, &bad, &open, font, theme.buttonStyle(), theme.menuStyle()));
    ctx.endFrame();
}

test "combo abre com seta tendo foco" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const theme = style_mod.Theme.darkDefault();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 160, 30);
    const id = id_mod.Id.fromString("test:combo-kb");
    const opts = [_][]const u8{ "A", "B" };
    var sel: usize = 0;
    var open = false;

    // Foca com click (sem soltar: sem click ainda) e aperta Down.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(10, 10) },
    });
    _ = try combo(&ctx, id, bounds, &opts, &sel, &open, font, theme.buttonStyle(), theme.menuStyle());
    try stdt.testing.expect(ctx.hasFocus(id));
    try stdt.testing.expect(!open);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    const r = try combo(&ctx, id, bounds, &opts, &sel, &open, font, theme.buttonStyle(), theme.menuStyle());
    try stdt.testing.expect(r.open and open);
    try stdt.testing.expect(ctx.hasFocus(id.child(1)));
    ctx.endFrame();

    // Sem foco: seta ignorada.
    ctx.clearFocus();
    open = false;
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    const r2 = try combo(&ctx, id, bounds, &opts, &sel, &open, font, theme.buttonStyle(), theme.menuStyle());
    try stdt.testing.expect(!r2.open and !open);
    ctx.endFrame();
}

test "combo limites: Escape fecha, mesma escolha, teto e NaN" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10); // ih=18.625
    const theme = style_mod.Theme.darkDefault();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 160, 30);
    const id = id_mod.Id.fromString("test:combo-lim");
    const opts = [_][]const u8{ "A", "B", "C" };
    var sel: usize = 1;
    var open = false;

    // Abre com click (press+release).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(10, 10) },
    });
    _ = try combo(&ctx, id, bounds, &opts, &sel, &open, font, theme.buttonStyle(), theme.menuStyle());
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(10, 10) },
    });
    _ = try combo(&ctx, id, bounds, &opts, &sel, &open, font, theme.buttonStyle(), theme.menuStyle());
    try stdt.testing.expect(open);
    ctx.endFrame();

    // Escape com o menu focado fecha sem mudar a seleção.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .escape, .pressed = true, .modifiers = .{} } });
    const r0 = try combo(&ctx, id, bounds, &opts, &sel, &open, font, theme.buttonStyle(), theme.menuStyle());
    try stdt.testing.expect(!r0.open and !open and !r0.changed);
    try stdt.testing.expectEqual(@as(usize, 1), sel);
    ctx.endFrame();

    // Escolher o item já selecionado fecha sem marcar changed.
    // Menu abre em y=30; item 1 ocupa y 48.625..67.25 → click em y=55.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(10, 10) },
    });
    _ = try combo(&ctx, id, bounds, &opts, &sel, &open, font, theme.buttonStyle(), theme.menuStyle());
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(10, 10) },
    });
    _ = try combo(&ctx, id, bounds, &opts, &sel, &open, font, theme.buttonStyle(), theme.menuStyle());
    try stdt.testing.expect(open);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(10, 55) },
    });
    const r1 = try combo(&ctx, id, bounds, &opts, &sel, &open, font, theme.buttonStyle(), theme.menuStyle());
    try stdt.testing.expect(!r1.open and !open and !r1.changed);
    try stdt.testing.expectEqual(@as(usize, 1), sel);
    ctx.endFrame();

    // Teto de 256 opções e bounds NaN: InvalidArgument.
    ctx.beginFrame();
    var many: [257][]const u8 = undefined;
    for (&many) |*o| o.* = "x";
    try stdt.testing.expectError(error.InvalidArgument, combo(&ctx, id, bounds, &many, &sel, &open, font, theme.buttonStyle(), theme.menuStyle()));
    const nan_bounds = types.Rect.init(0, 0, std.math.nan(f32), 30);
    try stdt.testing.expectError(error.InvalidArgument, combo(&ctx, id, nan_bounds, &opts, &sel, &open, font, theme.buttonStyle(), theme.menuStyle()));
    ctx.endFrame();
}
