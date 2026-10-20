//! ZyntraUI — lista vertical (widgets/list_view).
//!
//! Modelo M58: `beginListView`/`endListView` com estado no chamador.
//! - `items: []const []const u8` — labels dos itens (chamador detém).
//! - `selected: *usize` — índice selecionado (chamador, clampado).
//! - `scroll_offset: *f32` — offset de rolagem (chamador, px).
//! - Mouse: click seleciona; wheel rola; drag no thumb rola.
//! - Teclado com foco: setas movem seleção, Home/End saltam,
//!   PageUp/PageDown saltam página.
//! - `ListViewStyle` + `Theme.listViewStyle()` — cores, padding.
//! - Desenho: fundo + N itens (fundo + texto) + scrollbar.
//! `id` não-nulo obrigatório.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const input = @import("input.zig");
const metrics_mod = @import("../text/metrics.zig");

pub const ListViewResult = struct {
    selected: usize = 0,
    changed: bool = false,
    hovered_index: ?usize = null,
    scroll_offset: f32 = 0,
};

/// Calcula a altura total de conteúdo (px).
pub fn listViewContentHeight(items: []const []const u8, style: style_mod.ListViewStyle) f32 {
    return @as(f32, @floatFromInt(items.len)) * style.item_height;
}

/// Calcula o offset máximo de rolagem.
pub fn listViewMaxScroll(items: []const []const u8, viewport_h: f32, style: style_mod.ListViewStyle) f32 {
    const content = listViewContentHeight(items, style);
    return @max(0, content - viewport_h);
}

pub fn beginListView(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    items: []const []const u8,
    selected: *usize,
    scroll_offset: *f32,
    style: style_mod.ListViewStyle,
) context_mod.ContextError!ListViewResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;
    if (items.len == 0) return error.InvalidArgument;
    if (!std.math.isFinite(scroll_offset.*)) return error.InvalidArgument;

    if (selected.* >= items.len) selected.* = items.len - 1;
    const max_scroll = listViewMaxScroll(items, bounds.h, style);
    scroll_offset.* = std.math.clamp(scroll_offset.*, 0, max_scroll);

    const fm = input.FrameMouse.scan(ctx.pendingEvents());
    var res = ListViewResult{ .selected = selected.*, .scroll_offset = scroll_offset.* };

    // Focável
    try ctx.registerFocusable(id);
    if (fm.pressedInside(bounds)) {
        ctx.focus_owner = id;
    }

    // Layout dos itens visíveis
    const first_visible: usize = @as(usize, @intFromFloat(@floor(scroll_offset.* / style.item_height)));
    const last_visible: usize = @min(items.len, first_visible + @as(usize, @intFromFloat(@ceil(bounds.h / style.item_height))) + 1);

    // Click seleciona
    if (fm.pressed_pos) |p| {
        const rel_y = p.y - bounds.y + scroll_offset.*;
        const idx: usize = @as(usize, @intFromFloat(@floor(rel_y / style.item_height)));
        if (idx >= first_visible and idx < last_visible) {
            res.changed = selected.* != idx;
            selected.* = idx;
            res.selected = idx;
        }
    }

    // Wheel rola (usa posição do evento, não mouse_pos retido)
    for (ctx.pendingEvents()) |ev| {
        if (ev != .mouse_wheel) continue;
        const w = ev.mouse_wheel;
        if (bounds.contains(w.pos)) {
            scroll_offset.* = std.math.clamp(scroll_offset.* - w.dy * 20, 0, max_scroll);
        }
    }

    // Teclado com foco
    if (ctx.hasFocus(id)) {
        for (ctx.pendingEvents()) |ev| {
            if (ev != .key) continue;
            const k = ev.key;
            if (!k.pressed or k.modifiers.ctrl) continue;
            switch (k.key) {
                .up => {
                    if (selected.* > 0) {
                        selected.* -= 1;
                        res.changed = true;
                    }
                },
                .down => {
                    if (selected.* + 1 < items.len) {
                        selected.* += 1;
                        res.changed = true;
                    }
                },
                .home => {
                    if (selected.* != 0) {
                        selected.* = 0;
                        res.changed = true;
                    }
                },
                .end => {
                    if (selected.* != items.len - 1) {
                        selected.* = items.len - 1;
                        res.changed = true;
                    }
                },
                .page_up => {
                    const page: usize = @intFromFloat(@floor(bounds.h / style.item_height));
                    const new_sel = if (selected.* > page) selected.* - page else 0;
                    if (new_sel != selected.*) {
                        selected.* = new_sel;
                        res.changed = true;
                    }
                },
                .page_down => {
                    const page: usize = @intFromFloat(@floor(bounds.h / style.item_height));
                    const new_sel = @min(items.len - 1, selected.* + page);
                    if (new_sel != selected.*) {
                        selected.* = new_sel;
                        res.changed = true;
                    }
                },
                .tab => ctx.requestFocusAdvance(if (k.modifiers.shift) .prev else .next),
                else => {},
            }
        }
        res.selected = selected.*;
    }

    // Auto-scroll para manter seleção visível
    if (res.changed) {
        const sel_y = @as(f32, @floatFromInt(selected.*)) * style.item_height;
        if (sel_y < scroll_offset.*) {
            scroll_offset.* = sel_y;
        } else if (sel_y + style.item_height > scroll_offset.* + bounds.h) {
            scroll_offset.* = sel_y + style.item_height - bounds.h;
        }
        scroll_offset.* = std.math.clamp(scroll_offset.*, 0, max_scroll);
    }

    // Hover (M105): só com o ponteiro DENTRO dos bounds — antes o índice
    // vinha também de fora no eixo X (realce fantasma em linhas da lista
    // quando o mouse estava ao lado dela).
    if (ctx.mouse_pos) |p| {
        if (bounds.contains(p)) {
            const rel_y = p.y - bounds.y + scroll_offset.*;
            const idx: usize = @as(usize, @intFromFloat(@floor(rel_y / style.item_height)));
            if (idx >= first_visible and idx < last_visible) {
                res.hovered_index = idx;
            }
        }
    }

    // Estado de interação (M105): hover da linha e seleção mudam o
    // fundo ⇒ alimenta o dirty rect (entrada e saída do realce). Roda a
    // roda exige o mouse dentro de `bounds`, logo o hover já cobre o
    // frame da rolagem.
    try ctx.mark_hot(id, bounds, res.hovered_index != null or res.changed);

    // Desenho: fundo
    ctx.draw.rectFilled(ctx.allocator, bounds, style.bg) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };

    // Clip para itens
    ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = bounds, .null_rect = false } }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };

    // Itens visíveis
    const font = metrics_mod.FontMetrics.withSize(10);
    var i = first_visible;
    while (i < last_visible) : (i += 1) {
        const y = bounds.y + @as(f32, @floatFromInt(i)) * style.item_height - scroll_offset.*;
        const item_rect = types.Rect.init(bounds.x, y, bounds.w, style.item_height);
        const is_selected = i == selected.*;
        const is_hovered = res.hovered_index == i and !is_selected;

        const bg = if (is_selected) style.bg_selected else if (is_hovered) style.bg_hover else style.bg;
        ctx.draw.rectFilled(ctx.allocator, item_rect, bg) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
        };

        const text_color = if (is_selected) style.text_selected else style.text;
        ctx.pushText(
            .{ .x = bounds.x + style.padding_x, .y = y + (style.item_height - font.lineHeight()) / 2 },
            text_color,
            font,
            items[i],
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
            error.InvalidUtf8 => return error.InvalidArgument,
            error.InvalidMetrics => return error.InvalidArgument,
        };
    }

    // Scrollbar
    const content_h = listViewContentHeight(items, style);
    if (content_h > bounds.h) {
        const thumb_h = @max(20, bounds.h * bounds.h / content_h);
        const thumb_y = bounds.y + (bounds.h - thumb_h) * (scroll_offset.* / max_scroll);
        const thumb = types.Rect.init(bounds.x + bounds.w - 4, thumb_y, 4, thumb_h);
        ctx.draw.rectFilled(ctx.allocator, thumb, style.border) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
        };
    }

    // Outline
    ctx.draw.rectOutline(ctx.allocator, bounds, style.border, @max(1.0, style.border_width)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };

    // Pop clip
    ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = .{}, .null_rect = true } }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };

    res.scroll_offset = scroll_offset.*;
    return res;
}

/// Fim da lista (M58): NO-OP — sem estado retido, sem draws.
/// Existe apenas para simetria de pareamento com outros widgets.
pub fn endListView(_: *context_mod.Context) void {}

test "ListView click seleciona, teclado navega, scroll" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().listViewStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 100);
    const id = id_mod.Id.fromString("test:list");
    var selected: usize = 0;
    var scroll: f32 = 0;
    const items = [_][]const u8{ "A", "B", "C", "D", "E", "F", "G", "H" };

    // Click no 3º item (y=56+2=58 dentro de "C")
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(100, 58) },
    });
    const r0 = try beginListView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expect(r0.changed);
    try stdt.testing.expectEqual(@as(usize, 2), selected);
    ctx.endFrame();

    // Down move para 3
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    const r1 = try beginListView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expect(r1.changed);
    try stdt.testing.expectEqual(@as(usize, 3), selected);
    ctx.endFrame();

    // End salta para o último
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{} } });
    const r2 = try beginListView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expect(r2.changed);
    try stdt.testing.expectEqual(@as(usize, 7), selected);
    ctx.endFrame();

    // Home salta para o primeiro
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    const r3 = try beginListView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expect(r3.changed);
    try stdt.testing.expectEqual(@as(usize, 0), selected);
    ctx.endFrame();

    // Wheel rola (dy negativo = rolar para baixo)
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = -3, .pos = types.Vec2.init(100, 50) } });
    const r4 = try beginListView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expect(r4.scroll_offset > 0);
    ctx.endFrame();

    // Contratos inválidos
    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, beginListView(&ctx, .null, bounds, &items, &selected, &scroll, style));
    try stdt.testing.expectError(error.InvalidArgument, beginListView(&ctx, id, types.Rect.init(0, 0, 0, 0), &items, &selected, &scroll, style));
    try stdt.testing.expectError(error.InvalidArgument, beginListView(&ctx, id, bounds, &[_][]const u8{}, &selected, &scroll, style));
    const bad_style = style_mod.ListViewStyle{ .item_height = 0, .bg = .{}, .bg_selected = .{}, .bg_hover = .{}, .text = .{}, .text_selected = .{}, .border = .{}, .border_width = 1, .padding_x = 8 };
    try stdt.testing.expectError(error.InvalidArgument, beginListView(&ctx, id, bounds, &items, &selected, &scroll, bad_style));
    ctx.endFrame();
}

test "listView limites: bounds/scroll não-finitos, scroll e wheel extremos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().listViewStyle(); // item 28
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:list-lim");
    const items = [_][]const u8{ "A", "B", "C", "D", "E", "F", "G", "H" };
    var selected: usize = 0;
    var scroll: f32 = 0;
    // Corpo 100px, conteúdo 224px → scroll máximo 124.
    const bounds = types.Rect.init(0, 0, 200, 100);

    // Scroll do chamador além do máximo clampa na entrada.
    scroll = 9999;
    ctx.beginFrame();
    const r0 = try beginListView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expectEqual(@as(f32, 124), scroll);
    try stdt.testing.expectEqual(@as(f32, 124), r0.scroll_offset);
    ctx.endFrame();

    // Wheel finito extremo: clampa sem pânico (mínimo e máximo).
    scroll = 0;
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = -1e30, .pos = types.Vec2.init(100, 50) } });
    _ = try beginListView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expectEqual(@as(f32, 124), scroll);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = 1e30, .pos = types.Vec2.init(100, 50) } });
    _ = try beginListView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expectEqual(@as(f32, 0), scroll);
    ctx.endFrame();

    // Geometria não-finita: InvalidArgument em vez de pânico na
    // conversão float→int do layout (bounds.h=+inf estourava usize).
    ctx.beginFrame();
    var nan_scroll: f32 = std.math.nan(f32);
    try stdt.testing.expectError(error.InvalidArgument, beginListView(&ctx, id, bounds, &items, &selected, &nan_scroll, style));
    const nan_bounds = types.Rect.init(0, 0, 200, std.math.nan(f32));
    try stdt.testing.expectError(error.InvalidArgument, beginListView(&ctx, id, nan_bounds, &items, &selected, &scroll, style));
    const inf_bounds = types.Rect.init(0, 0, 200, std.math.inf(f32));
    try stdt.testing.expectError(error.InvalidArgument, beginListView(&ctx, id, inf_bounds, &items, &selected, &scroll, style));
    ctx.endFrame();
}

test "list_view alimenta o dirty rect (M105): hover marca só os bounds" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().listViewStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(10, 10, 120, 60);
    const id = id_mod.Id.fromString("test:lv:hot");
    const items = [_][]const u8{ "A", "B", "C" };
    var selected: usize = 0;
    var scroll: f32 = 0;
    const away = types.Vec2.init(500, 500);
    const inside = types.Vec2.init(20, 20);

    // Frio: nada sujo (a aplicação não marcou nada).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = away } });
    _ = try beginListView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expect(ctx.dirty_rect.isEmpty());
    ctx.endFrame();

    // Hover: exatamente os bounds do widget entram na região suja.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = inside } });
    _ = try beginListView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expectEqual(bounds, ctx.dirty_rect);
    ctx.endFrame();

    // Saída do hover: o realce que ficou no framebuffer é repintado.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = away } });
    _ = try beginListView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expectEqual(bounds, ctx.dirty_rect);
    ctx.endFrame();

    // Frio de novo: nada a repintar.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = away } });
    _ = try beginListView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expect(ctx.dirty_rect.isEmpty());
    ctx.endFrame();
}
