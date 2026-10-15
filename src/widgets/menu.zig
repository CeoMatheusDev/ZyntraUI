//! ZyntraUI — menu dropdown (widgets/menu).
//!
//! Modelo M22 flat + M23 cascata mouse-driven:
//! - `menu(...)`: painel + clip, `active: *usize` unificando hover e
//!   teclado (setas pulam desabilitados com wrap, `Home`/`End`),
//!   click/`Enter` escolhem (one-shot), press fora/`Escape` dispensam.
//! - `menuNested(..., child)`: press dentro do filho NÃO dispensa o pai.
//!   `hovered_index` + `submenuBounds`/`menuRowRect` permitem ao chamador
//!   abrir um submenu à direita do item sob o mouse.
//! - Teclado continua por nível (foco não atravessa; documentado).
//! - Itens desabilitados: texto apagado, sem hover/escolha.
//! `items` vazio → `InvalidArgument`. Labels UTF-8 validados no push.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const metrics_mod = @import("../text/metrics.zig");
const input = @import("input.zig");

/// Item de menu (fatia do chamador; sem ownership).
pub const MenuItem = struct {
    label: []const u8,
    enabled: bool = true,
};

pub const MenuResult = struct {
    chosen: ?usize = null,
    dismissed: bool = false,
    hovered: bool = false,
    /// Linha sob o mouse (mesmo desabilitada; `null` fora do menu).
    /// Chamadores usam para abrir submenu do item focado pelo mouse.
    hovered_index: ?usize = null,
};

/// Filho aberto (submenu): press dentro dele não dispensa o pai.
pub const MenuChild = struct {
    id: id_mod.Id,
    bounds: types.Rect,
};

fn itemHeight(font: metrics_mod.FontMetrics) f32 {
    return font.lineHeight() + 8;
}

fn firstEnabled(items: []const MenuItem) ?usize {
    for (items, 0..) |it, i| {
        if (it.enabled) return i;
    }
    return null;
}

fn stepActive(items: []const MenuItem, from: usize, dir: i2) ?usize {
    if (items.len == 0) return null;
    var i = from;
    var guard: usize = 0;
    while (guard < items.len) : (guard += 1) {
        if (dir >= 0) {
            i = (i + 1) % items.len;
        } else {
            i = (i + items.len - 1) % items.len;
        }
        if (items[i].enabled) return i;
    }
    return null;
}

pub fn menu(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    items: []const MenuItem,
    active: *usize,
    font: metrics_mod.FontMetrics,
    style: style_mod.MenuStyle,
) context_mod.ContextError!MenuResult {
    return menuInner(ctx, id, bounds, items, active, font, style, null);
}

/// Menu com submenu aberto (M23, aditivo): `child` suprime o dismiss do
/// pai quando o press cai dentro do filho. Teclado continua por nível
/// (foco não atravessa níveis nesta milestone — documentado).
pub fn menuNested(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    items: []const MenuItem,
    active: *usize,
    font: metrics_mod.FontMetrics,
    style: style_mod.MenuStyle,
    child: ?MenuChild,
) context_mod.ContextError!MenuResult {
    return menuInner(ctx, id, bounds, items, active, font, style, child);
}

/// Linha `index` dentro de `bounds` (mesma geometria do desenho).
pub fn menuRowRect(bounds: types.Rect, index: usize, item_h: f32) types.Rect {
    return .{
        .x = bounds.x,
        .y = bounds.y + @as(f32, @floatFromInt(index)) * item_h,
        .w = bounds.w,
        .h = item_h,
    };
}

/// Bounds do submenu ancorado à direita da linha `index`.
pub fn submenuBounds(parent: types.Rect, index: usize, item_h: f32, count: usize, width: f32) types.Rect {
    return .{
        .x = parent.x + parent.w,
        .y = parent.y + @as(f32, @floatFromInt(index)) * item_h,
        .w = width,
        .h = @as(f32, @floatFromInt(count)) * item_h,
    };
}

fn menuInner(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    items: []const MenuItem,
    active: *usize,
    font: metrics_mod.FontMetrics,
    style: style_mod.MenuStyle,
    child: ?MenuChild,
) context_mod.ContextError!MenuResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid() or !font.isValid()) return error.InvalidArgument;
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;
    if (items.len == 0) return error.InvalidArgument;
    if (items.len > 4096) return error.InvalidArgument;

    // Normaliza o índice (fora da faixa ou sobre desabilitado).
    if (active.* >= items.len or !items[active.*].enabled) {
        active.* = firstEnabled(items) orelse 0;
    }

    const fm = input.FrameMouse.scan(ctx.pendingEvents());
    if (fm.pressedInside(bounds)) {
        ctx.focus_owner = id;
    }
    const focused = ctx.hasFocus(id);
    const hovered = if (ctx.mouse_pos) |p| bounds.contains(p) else false;
    var res = MenuResult{ .hovered = hovered };

    const ih = itemHeight(font);
    // Linha sob o mouse (qualquer uma, p/ hovered_index + submenu).
    const row_at_mouse: ?usize = if (ctx.mouse_pos) |p| blk: {
        if (!bounds.contains(p)) break :blk null;
        const idx: usize = @intFromFloat(@min(@floor((p.y - bounds.y) / ih), @as(f32, @floatFromInt(items.len - 1))));
        break :blk if (idx < items.len) idx else null;
    } else null;
    res.hovered_index = row_at_mouse;
    // Hover ajusta o ativo (só habilitados).
    if (row_at_mouse) |idx| {
        if (items[idx].enabled) active.* = idx;
    }

    if (focused) {
        for (ctx.pendingEvents()) |ev| {
            switch (ev) {
                .key => |k| {
                    if (!k.pressed) continue;
                    switch (k.key) {
                        .up => {
                            if (stepActive(items, active.*, -1)) |n| active.* = n;
                        },
                        .down => {
                            if (stepActive(items, active.*, 1)) |n| active.* = n;
                        },
                        .home => {
                            if (firstEnabled(items)) |n| active.* = n;
                        },
                        .end => {
                            var i: usize = items.len;
                            while (i > 0) {
                                i -= 1;
                                if (items[i].enabled) {
                                    active.* = i;
                                    break;
                                }
                            }
                        },
                        .enter => {
                            if (items[active.*].enabled) res.chosen = active.*;
                        },
                        .escape => {
                            ctx.focus_owner = null;
                            res.dismissed = true;
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }
    }
    // Click em item habilitado escolhe (one-shot); fora dispensa,
    // exceto dentro do filho aberto (cascata).
    if (fm.pressed_pos) |p| {
        if (bounds.contains(p)) {
            const idx: usize = @intFromFloat(@min(@floor((p.y - bounds.y) / ih), @as(f32, @floatFromInt(items.len - 1))));
            if (idx < items.len and items[idx].enabled) {
                active.* = idx;
                res.chosen = idx;
            }
        } else if (child == null or !child.?.bounds.contains(p)) {
            res.dismissed = true;
        }
    }

    // Painel + itens.
    ctx.draw.rectFilled(ctx.allocator, bounds, style.bg) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.rectOutline(ctx.allocator, bounds, style.border, @max(1.0, style.border_width)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    // Clip do conteúdo (limpo ao fim; pareado como popup/scroll).
    ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = bounds, .null_rect = false } }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    var i: usize = 0;
    while (i < items.len) : (i += 1) {
        const row = types.Rect{
            .x = bounds.x,
            .y = bounds.y + @as(f32, @floatFromInt(i)) * ih,
            .w = bounds.w,
            .h = ih,
        };
        if (i == active.* and (hovered or focused)) {
            ctx.draw.rectFilled(ctx.allocator, row, style.item_hover) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidCommand => return error.InvalidCommand,
            };
        }
        if (items[i].label.len > 0) {
            ctx.draw.pushText(
                ctx.allocator,
                .{ .x = bounds.x + 8, .y = row.y + 4 },
                if (items[i].enabled) style.text else style.text_disabled,
                font,
                items[i].label,
            ) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidCommand => return error.InvalidCommand,
                error.InvalidUtf8 => return error.InvalidArgument,
                error.InvalidMetrics => return error.InvalidArgument,
            };
        }
    }
    ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = .{}, .null_rect = true } }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    return res;
}

test "menu hover escolhe, fora dispensa, vazio rejeita" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10); // lh=17, ih=25
    const style = style_mod.Theme.darkDefault().menuStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 160, 75);
    const id = id_mod.Id.fromString("test:menu");
    const items = [_]MenuItem{
        .{ .label = "Open" },
        .{ .label = "Save" },
        .{ .label = "Quit", .enabled = false },
    };
    var active: usize = 0;

    // Click no item 1 (y=30, ih=25 → idx 1).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(10, 30) },
    });
    const r0 = try menu(&ctx, id, bounds, &items, &active, font, style);
    try stdt.testing.expectEqual(@as(?usize, 1), r0.chosen);
    try stdt.testing.expectEqual(@as(usize, 1), active);
    ctx.endFrame();

    // Click no desabilitado (y=60 → idx 2): sem escolha.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(10, 60) },
    });
    const r1 = try menu(&ctx, id, bounds, &items, &active, font, style);
    try stdt.testing.expect(r1.chosen == null);
    ctx.endFrame();

    // Press fora dispensa.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(500, 500) },
    });
    const r2 = try menu(&ctx, id, bounds, &items, &active, font, style);
    try stdt.testing.expect(r2.dismissed);
    ctx.endFrame();

    ctx.beginFrame();
    const empty = [_]MenuItem{};
    try stdt.testing.expectError(error.InvalidArgument, menu(&ctx, .null, bounds, &items, &active, font, style));
    try stdt.testing.expectError(error.InvalidArgument, menu(&ctx, id, bounds, &empty, &active, font, style));
    ctx.endFrame();
}

test "menuNested cascata: hovered_index, filho não dispensa, escolhe" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10); // ih=25
    const style = style_mod.Theme.darkDefault().menuStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const pbounds = types.Rect.init(0, 0, 160, 50);
    const pid = id_mod.Id.fromString("test:menu-p");
    const sid = id_mod.Id.fromString("test:menu-s");
    const items = [_]MenuItem{.{ .label = "File" }};
    const sub = [_]MenuItem{ .{ .label = "New" }, .{ .label = "Open" } };
    var pactive: usize = 0;
    var sactive: usize = 0;

    // Geometria partilhada: linha 0 + submenu à direita (item_h=25 aqui).
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 160, 25), menuRowRect(pbounds, 0, 25));
    const sb = submenuBounds(pbounds, 0, 25, sub.len, 140);
    try stdt.testing.expectEqual(types.Rect.init(160, 0, 140, 50), sb);

    // Hover no pai expõe hovered_index; submenu abre e recebe click
    // sem dispensar o pai (menuNested com child).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(10, 10) } });
    const rp = try menuNested(
        &ctx,
        pid,
        pbounds,
        &items,
        &pactive,
        font,
        style,
        .{ .id = sid, .bounds = sb },
    );
    try stdt.testing.expectEqual(@as(?usize, 0), rp.hovered_index);
    try stdt.testing.expect(!rp.dismissed);
    const rs = try menu(&ctx, sid, sb, &sub, &sactive, font, style);
    try stdt.testing.expect(!rs.dismissed);
    ctx.endFrame();

    // Click no filho ("Open", y=30 → idx 1): escolhe sem dispensar o pai.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(170, 30) },
    });
    const rp2 = try menuNested(&ctx, pid, pbounds, &items, &pactive, font, style, .{ .id = sid, .bounds = sb });
    const rs2 = try menu(&ctx, sid, sb, &sub, &sactive, font, style);
    try stdt.testing.expectEqual(@as(?usize, 1), rs2.chosen);
    try stdt.testing.expect(!rp2.dismissed);
    ctx.endFrame();

    // Press longe de ambos dispensa os dois.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(500, 500) },
    });
    const rp3 = try menuNested(&ctx, pid, pbounds, &items, &pactive, font, style, .{ .id = sid, .bounds = sb });
    const rs3 = try menu(&ctx, sid, sb, &sub, &sactive, font, style);
    try stdt.testing.expect(rp3.dismissed and rs3.dismissed);
    ctx.endFrame();
}

test "menu teclado circula, pula desabilitado, Enter escolhe" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().menuStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 160, 75);
    const id = id_mod.Id.fromString("test:menu-kb");
    const items = [_]MenuItem{
        .{ .label = "A" },
        .{ .label = "B", .enabled = false },
        .{ .label = "C" },
    };
    var active: usize = 0;

    // Foca com click e anda: down pula o desabilitado (0→2), down dá wrap (2→0).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    _ = try menu(&ctx, id, bounds, &items, &active, font, style);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(500, 500) } });
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    _ = try menu(&ctx, id, bounds, &items, &active, font, style);
    try stdt.testing.expectEqual(@as(usize, 2), active);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    _ = try menu(&ctx, id, bounds, &items, &active, font, style);
    try stdt.testing.expectEqual(@as(usize, 0), active);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .up, .pressed = true, .modifiers = .{} } });
    _ = try menu(&ctx, id, bounds, &items, &active, font, style);
    try stdt.testing.expectEqual(@as(usize, 2), active);
    ctx.endFrame();

    // Enter escolhe; Escape dispensa e desfoca.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .enter, .pressed = true, .modifiers = .{} } });
    const rc = try menu(&ctx, id, bounds, &items, &active, font, style);
    try stdt.testing.expectEqual(@as(?usize, 2), rc.chosen);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .escape, .pressed = true, .modifiers = .{} } });
    const re = try menu(&ctx, id, bounds, &items, &active, font, style);
    try stdt.testing.expect(re.dismissed and !ctx.hasFocus(id));
    ctx.endFrame();
}
