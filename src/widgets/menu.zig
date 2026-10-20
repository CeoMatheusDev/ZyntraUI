//! ZyntraUI — menu dropdown (widgets/menu).
//!
//! Modelo M22 flat + M23/M24 cascata (mouse + teclado por nível):
//! - `menu(...)`: painel + clip, `active: *usize` unificando hover e
//!   teclado (setas pulam desabilitados com wrap, `Home`/`End`),
//!   click/`Enter` escolhem (one-shot), press fora/`Escape` dispensam.
//! - `menuNested(..., child)`: press dentro do filho NÃO dispensa o pai;
//!   `Right` foca o filho, `Left` no filho pede o pai (`focus_parent`).
//!   `hovered_index` + `submenuBounds`/`menuRowRect` posicionam o submenu.
//! - Itens desabilitados: texto apagado, sem hover/escolha.
//! - `MenuItem.checked`: coluna de tique à esquerda (reservada só
//!   quando algum item é marcável; `true` desenha o tique vetorial).
//! - `MenuItem.shortcut`: dica de atalho alinhada à direita, apagada
//!   (só exibição; menu é one-shot e o chamador alterna o estado).
//! `items` vazio → `InvalidArgument`. Labels UTF-8 validados no push.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const metrics_mod = @import("../text/metrics.zig");
const input = @import("input.zig");

/// Item de menu (fatia do chamador; sem ownership).
/// `separator` desenha linha divisória (sem hover/escolha); mantém a
/// altura da linha para não quebrar o mapeamento índice↔linha.
/// `checked`: `null` = item não marcável; `true` desenha o tique;
/// `false` reserva a coluna sem desenhar (alinhamento da coluna).
/// `shortcut`: dica à direita (ex.: "Ctrl+S"); apenas exibição.
pub const MenuItem = struct {
    label: []const u8,
    enabled: bool = true,
    separator: bool = false,
    checked: ?bool = null,
    shortcut: ?[]const u8 = null,
};

pub const MenuResult = struct {
    chosen: ?usize = null,
    dismissed: bool = false,
    hovered: bool = false,
    /// Linha sob o mouse (mesmo desabilitada; `null` fora do menu).
    /// Chamadores usam para abrir submenu do item focado pelo mouse.
    hovered_index: ?usize = null,
    /// `Left` pressionado com foco: pede foco ao pai. Só faz sentido em
    /// submenu aninhado (o chamador foca o id pai); menu de topo ignora.
    focus_parent: bool = false,
};

/// Filho aberto (submenu): press dentro dele não dispensa o pai.
pub const MenuChild = struct {
    id: id_mod.Id,
    bounds: types.Rect,
};

fn itemHeight(font: metrics_mod.FontMetrics) f32 {
    return font.lineHeight() + 8;
}

/// Item interagível: habilitado e não-separador.
fn selectable(it: MenuItem) bool {
    return it.enabled and !it.separator;
}

fn firstEnabled(items: []const MenuItem) ?usize {
    for (items, 0..) |it, i| {
        if (selectable(it)) return i;
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
        if (selectable(items[i])) return i;
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

/// Menu com submenu aberto (M23+M24, aditivo): `child` suprime o
/// dismiss do pai quando o press cai dentro do filho; `Right` com foco
/// move o foco ao filho. Teclado atravessa um nível por vez.
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
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;
    if (items.len == 0) return error.InvalidArgument;
    if (items.len > 4096) return error.InvalidArgument;

    // Normaliza o índice (fora da faixa ou sobre desabilitado).
    if (active.* >= items.len or !selectable(items[active.*])) {
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
    // Hover ajusta o ativo (só interagíveis).
    if (row_at_mouse) |idx| {
        if (selectable(items[idx])) active.* = idx;
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
                                if (selectable(items[i])) {
                                    active.* = i;
                                    break;
                                }
                            }
                        },
                        .enter => {
                            if (selectable(items[active.*])) res.chosen = active.*;
                        },
                        .escape => {
                            ctx.focus_owner = null;
                            res.dismissed = true;
                        },
                        .right => {
                            // Com submenu aberto, foca o filho (teclado
                            // atravessa um nível; sem filho, no-op).
                            if (child) |ch| ctx.focus_owner = ch.id;
                        },
                        .left => {
                            // Pede foco ao pai; só aninhados usam.
                            res.focus_parent = true;
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
            if (idx < items.len and selectable(items[idx])) {
                active.* = idx;
                res.chosen = idx;
            }
        } else if (child == null or !child.?.bounds.contains(p)) {
            res.dismissed = true;
        }
    }

    // Estado de interação (M105): hover de item e navegação por teclado
    // (foco) realçam a linha ativa ⇒ alimenta o dirty rect.
    try ctx.mark_hot(id, bounds, res.hovered or focused);

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
    // Coluna de check: só reservada quando há item marcável, para não
    // alterar o layout de menus sem checks (compatível).
    var has_checks = false;
    for (items) |it| {
        if (!it.separator and it.checked != null) {
            has_checks = true;
            break;
        }
    }
    const label_x = bounds.x + 8 + (if (has_checks) @as(f32, 14) else 0);
    while (i < items.len) : (i += 1) {
        const row = types.Rect{
            .x = bounds.x,
            .y = bounds.y + @as(f32, @floatFromInt(i)) * ih,
            .w = bounds.w,
            .h = ih,
        };
        if (items[i].separator) {
            // Linha divisória centralizada (sem hover/texto).
            const cy = row.y + ih / 2;
            ctx.draw.line(
                ctx.allocator,
                .{ .x = row.x + 8, .y = cy },
                .{ .x = row.x + row.w - 8, .y = cy },
                style.border,
                1.0,
            ) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidCommand => return error.InvalidCommand,
            };
            continue;
        }
        if (i == active.* and (hovered or focused)) {
            ctx.draw.rectFilled(ctx.allocator, row, style.item_hover) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidCommand => return error.InvalidCommand,
            };
        }
        if (items[i].checked) |is_checked| {
            if (is_checked) {
                // Tique vetorial na coluna à esquerda (sem fonte/atlas).
                const cx = bounds.x + 13;
                const cy = row.y + ih / 2;
                const tick = if (selectable(items[i])) style.text else style.text_disabled;
                ctx.draw.line(
                    ctx.allocator,
                    .{ .x = cx - 4, .y = cy },
                    .{ .x = cx - 1, .y = cy + 3 },
                    tick,
                    1.5,
                ) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InvalidCommand => return error.InvalidCommand,
                };
                ctx.draw.line(
                    ctx.allocator,
                    .{ .x = cx - 1, .y = cy + 3 },
                    .{ .x = cx + 4, .y = cy - 4 },
                    tick,
                    1.5,
                ) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InvalidCommand => return error.InvalidCommand,
                };
            }
        }
        if (items[i].label.len > 0) {
            ctx.pushText(
                .{ .x = label_x, .y = row.y + 4 },
                if (selectable(items[i])) style.text else style.text_disabled,
                font,
                items[i].label,
            ) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidCommand => return error.InvalidCommand,
                error.InvalidUtf8 => return error.InvalidArgument,
                error.InvalidMetrics => return error.InvalidArgument,
            };
        }
        if (items[i].shortcut) |sc| {
            if (sc.len > 0) {
                // Dica apagada alinhada à direita; só desenha se não
                // colidir com o label.
                const sm = metrics_mod.measure(sc, font) catch return error.InvalidArgument;
                const sx = bounds.x + row.w - 8 - sm.width;
                var fits = sx > label_x;
                if (fits and items[i].label.len > 0) {
                    const lm = metrics_mod.measure(items[i].label, font) catch return error.InvalidArgument;
                    fits = sx >= label_x + lm.width + 8;
                }
                if (fits) {
                    ctx.pushText(
                        .{ .x = sx, .y = row.y + 4 },
                        style.text_disabled,
                        font,
                        sc,
                    ) catch |err| switch (err) {
                        error.OutOfMemory => return error.OutOfMemory,
                        error.InvalidCommand => return error.InvalidCommand,
                        error.InvalidUtf8 => return error.InvalidArgument,
                        error.InvalidMetrics => return error.InvalidArgument,
                    };
                }
            }
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

test "menuNested teclado atravessa um nível por vez" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().menuStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const pbounds = types.Rect.init(0, 0, 160, 50);
    const pid = id_mod.Id.fromString("test:mk-p");
    const sid = id_mod.Id.fromString("test:mk-s");
    const items = [_]MenuItem{.{ .label = "File" }};
    const sub = [_]MenuItem{.{ .label = "Only" }};
    const sb = submenuBounds(pbounds, 0, 25, sub.len, 140);
    var pactive: usize = 0;
    var sactive: usize = 0;

    // Foca o pai com click; Right move o foco ao filho.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(10, 10) },
    });
    _ = try menuNested(&ctx, pid, pbounds, &items, &pactive, font, style, .{ .id = sid, .bounds = sb });
    try stdt.testing.expect(ctx.hasFocus(pid));
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    _ = try menuNested(&ctx, pid, pbounds, &items, &pactive, font, style, .{ .id = sid, .bounds = sb });
    try stdt.testing.expect(ctx.hasFocus(sid));
    // Filho foca e recebe Enter no mesmo frame seguinte.
    _ = try menu(&ctx, sid, sb, &sub, &sactive, font, style);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .enter, .pressed = true, .modifiers = .{} } });
    _ = try menuNested(&ctx, pid, pbounds, &items, &pactive, font, style, .{ .id = sid, .bounds = sb });
    const rs = try menu(&ctx, sid, sb, &sub, &sactive, font, style);
    try stdt.testing.expectEqual(@as(?usize, 0), rs.chosen);
    ctx.endFrame();

    // Left no filho pede o pai; chamador refoca.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{} } });
    _ = try menuNested(&ctx, pid, pbounds, &items, &pactive, font, style, .{ .id = sid, .bounds = sb });
    const rl = try menu(&ctx, sid, sb, &sub, &sactive, font, style);
    try stdt.testing.expect(rl.focus_parent);
    ctx.focus_owner = pid;
    try stdt.testing.expect(ctx.hasFocus(pid));
    ctx.endFrame();

    // Right sem filho aberto é no-op (sem crash, sem roubo de foco).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    _ = try menu(&ctx, pid, pbounds, &items, &pactive, font, style);
    try stdt.testing.expect(ctx.hasFocus(pid));
    ctx.endFrame();
}

test "menu separador: sem hover/escolha, teclado pula" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10); // ih=18.625
    const style = style_mod.Theme.darkDefault().menuStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 160, 80);
    const id = id_mod.Id.fromString("test:menu-sep");
    const items = [_]MenuItem{
        .{ .label = "A" },
        .{ .label = "", .separator = true },
        .{ .label = "B" },
    };
    var active: usize = 0;

    // Click no separador (linha 1, y=20): sem escolha, sem captura ativa.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(10, 20) },
    });
    const r0 = try menu(&ctx, id, bounds, &items, &active, font, style);
    try stdt.testing.expect(r0.chosen == null);
    try stdt.testing.expectEqual(@as(usize, 0), active); // hover não move p/ separador
    ctx.endFrame();

    // Down do 0 pula o separador e cai no 2.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(10, 5) },
    });
    _ = try menu(&ctx, id, bounds, &items, &active, font, style);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    _ = try menu(&ctx, id, bounds, &items, &active, font, style);
    try stdt.testing.expectEqual(@as(usize, 2), active);
    ctx.endFrame();

    // Enter no item normal escolhe; contagem inclui a linha divisória.
    // (mouse para fora: hover retido governaria o ativo.)
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(500, 500) } });
    try ctx.pushEvent(.{ .key = .{ .key = .enter, .pressed = true, .modifiers = .{} } });
    const r1 = try menu(&ctx, id, bounds, &items, &active, font, style);
    try stdt.testing.expectEqual(@as(?usize, 2), r1.chosen);
    // painel×2 + clip + 2 textos + 1 linha + highlight (focado) + clear = 8
    try stdt.testing.expectEqual(@as(usize, 8), ctx.drawCommands().len);
    ctx.endFrame();
}

test "menu todo-desabilitado nunca escolhe" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().menuStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 160, 60);
    const id = id_mod.Id.fromString("test:menu-off");
    const items = [_]MenuItem{
        .{ .label = "A", .enabled = false },
        .{ .label = "", .separator = true },
    };
    var active: usize = 0;

    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(10, 10) },
    });
    const r0 = try menu(&ctx, id, bounds, &items, &active, font, style);
    try stdt.testing.expect(r0.chosen == null and !r0.dismissed);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .enter, .pressed = true, .modifiers = .{} } });
    const r1 = try menu(&ctx, id, bounds, &items, &active, font, style);
    try stdt.testing.expect(r1.chosen == null);
    ctx.endFrame();
}

test "menu limites: End, normalização, item único, área pequena" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10); // ih=18.625
    const style = style_mod.Theme.darkDefault().menuStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:menu-lim");

    // active fora da faixa/sobre desabilitado normaliza no primeiro válido.
    const items = [_]MenuItem{
        .{ .label = "A", .enabled = false },
        .{ .label = "B" },
        .{ .label = "C", .enabled = false },
    };
    var active: usize = 999;
    ctx.beginFrame();
    _ = try menu(&ctx, id, types.Rect.init(0, 0, 160, 75), &items, &active, font, style);
    try stdt.testing.expectEqual(@as(usize, 1), active);
    ctx.endFrame();

    // End cai no último habilitado; Home no primeiro (pulando bordas off).
    const items2 = [_]MenuItem{
        .{ .label = "A" },
        .{ .label = "B", .enabled = false },
        .{ .label = "C" },
    };
    var active2: usize = 0;
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    _ = try menu(&ctx, id, types.Rect.init(0, 0, 160, 75), &items2, &active2, font, style);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{} } });
    _ = try menu(&ctx, id, types.Rect.init(0, 0, 160, 75), &items2, &active2, font, style);
    try stdt.testing.expectEqual(@as(usize, 2), active2);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    _ = try menu(&ctx, id, types.Rect.init(0, 0, 160, 75), &items2, &active2, font, style);
    try stdt.testing.expectEqual(@as(usize, 0), active2);
    ctx.endFrame();

    // Item único: down/up circulam nele, Enter escolhe.
    const items3 = [_]MenuItem{.{ .label = "Only" }};
    var active3: usize = 0;
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    _ = try menu(&ctx, id, types.Rect.init(0, 0, 160, 30), &items3, &active3, font, style);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .up, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .enter, .pressed = true, .modifiers = .{} } });
    const r3 = try menu(&ctx, id, types.Rect.init(0, 0, 160, 30), &items3, &active3, font, style);
    try stdt.testing.expectEqual(@as(usize, 0), active3);
    try stdt.testing.expectEqual(@as(?usize, 0), r3.chosen);
    ctx.endFrame();

    // Área menor que uma linha: clip pareado, click mapeia, sem crash.
    var active4: usize = 0;
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    const r4 = try menu(&ctx, id, types.Rect.init(0, 0, 160, 10), &items2, &active4, font, style);
    try stdt.testing.expectEqual(@as(?usize, 0), r4.chosen);
    var saw_clip = false;
    for (ctx.drawCommands()) |cmd| {
        if (cmd == .clip and !cmd.clip.null_rect) saw_clip = true;
    }
    try stdt.testing.expect(saw_clip);
    ctx.endFrame();

    // Bounds NaN e lista acima do teto: InvalidArgument, sem draws novos.
    ctx.beginFrame();
    const before = ctx.drawCommands().len;
    const nan_bounds = types.Rect.init(0, 0, std.math.nan(f32), 75);
    try stdt.testing.expectError(error.InvalidArgument, menu(&ctx, id, nan_bounds, &items2, &active2, font, style));
    var big: [4097]MenuItem = undefined;
    for (&big) |*it| it.* = .{ .label = "x" };
    try stdt.testing.expectError(error.InvalidArgument, menu(&ctx, id, types.Rect.init(0, 0, 160, 75), &big, &active2, font, style));
    try stdt.testing.expectEqual(before, ctx.drawCommands().len);
    ctx.endFrame();
}

test "menu checkmarks e atalhos: tique só no marcado, atalho à direita" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().menuStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 220, 75);
    const id = id_mod.Id.fromString("test:menu-check");
    const items = [_]MenuItem{
        .{ .label = "Grade", .checked = true, .shortcut = "Ctrl+G" },
        .{ .label = "Snap", .checked = false, .shortcut = "Ctrl+Shift+S" },
        .{ .label = "Somente" },
    };
    var active: usize = 0;

    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(5, 5) } });
    const r = try menu(&ctx, id, bounds, &items, &active, font, style);
    try stdt.testing.expectEqual(@as(?usize, 0), r.hovered_index);

    var ticks: usize = 0;
    var saw_grade = false;
    var saw_ctrl_g = false;
    var saw_snap = false;
    var saw_ctrl_shift_s = false;
    var saw_somente = false;
    const tb = ctx.draw.text_bytes.items;
    for (ctx.drawCommands()) |cmd| {
        switch (cmd) {
            .line => ticks += 1,
            .text => |t| {
                const s = tb[t.start .. t.start + t.len];
                if (std.mem.eql(u8, s, "Grade")) {
                    saw_grade = true;
                    // check reservado: label deslocado p/ a direita (x=22).
                    try stdt.testing.expectEqual(@as(f32, 22), t.pos.x);
                } else if (std.mem.eql(u8, s, "Ctrl+G")) {
                    saw_ctrl_g = true;
                    try stdt.testing.expect(t.pos.x > 22);
                } else if (std.mem.eql(u8, s, "Snap")) {
                    saw_snap = true;
                } else if (std.mem.eql(u8, s, "Ctrl+Shift+S")) {
                    saw_ctrl_shift_s = true;
                } else if (std.mem.eql(u8, s, "Somente")) {
                    saw_somente = true;
                }
            },
            else => {},
        }
    }
    // Só "Grade" (checked=true) desenha tique (2 segmentos).
    try stdt.testing.expectEqual(@as(usize, 2), ticks);
    try stdt.testing.expect(saw_grade and saw_snap and saw_somente);
    try stdt.testing.expect(saw_ctrl_g and saw_ctrl_shift_s);

    // Escolher um item marcável apenas reporta o índice (one-shot);
    // o chamador alterna o estado.
    var active2: usize = 0;
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(30, 5) },
    });
    const r2 = try menu(&ctx, id, bounds, &items, &active2, font, style);
    try stdt.testing.expectEqual(@as(?usize, 0), r2.chosen);
    ctx.endFrame();

    // Menu sem checks mantém o label em x=8 (layout preservado).
    const plain = [_]MenuItem{.{ .label = "Open" }};
    var active3: usize = 0;
    ctx.beginFrame();
    _ = try menu(&ctx, id, bounds, &plain, &active3, font, style);
    var saw_open = false;
    const tb2 = ctx.draw.text_bytes.items;
    for (ctx.drawCommands()) |cmd| {
        switch (cmd) {
            .text => |t| {
                const s = tb2[t.start .. t.start + t.len];
                if (std.mem.eql(u8, s, "Open")) {
                    saw_open = true;
                    try stdt.testing.expectEqual(@as(f32, 8), t.pos.x);
                }
            },
            else => {},
        }
    }
    try stdt.testing.expect(saw_open);
    ctx.endFrame();
}

test "menu alimenta o dirty rect (M105): hover e foco marcam os bounds" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10); // lh=17, ih=25
    const style = style_mod.Theme.darkDefault().menuStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 160, 75);
    const id = id_mod.Id.fromString("test:menu:hot");
    const items = [_]MenuItem{ .{ .label = "Open" }, .{ .label = "Save" }, .{ .label = "Quit" } };
    var active: usize = 0;
    const away = types.Vec2.init(500, 500);
    const inside = types.Vec2.init(10, 30);

    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = away } });
    _ = try menu(&ctx, id, bounds, &items, &active, font, style);
    try stdt.testing.expect(ctx.dirty_rect.isEmpty());
    ctx.endFrame();

    // Hover de item: linha ativa realçada ⇒ bounds sujos.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = inside } });
    const hover = try menu(&ctx, id, bounds, &items, &active, font, style);
    try stdt.testing.expect(hover.hovered);
    try stdt.testing.expectEqual(bounds, ctx.dirty_rect);
    ctx.endFrame();

    // Mouse fora mas foco no menu: navegação por teclado também realça.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{ .button = .left, .pressed = true, .pos = inside } });
    _ = try menu(&ctx, id, bounds, &items, &active, font, style);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = away } });
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    _ = try menu(&ctx, id, bounds, &items, &active, font, style);
    try stdt.testing.expectEqual(bounds, ctx.dirty_rect);
    ctx.endFrame();

    ctx.beginFrame();
    ctx.focus_owner = null; // o host devolve o foco
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = away } });
    _ = try menu(&ctx, id, bounds, &items, &active, font, style);
    try stdt.testing.expectEqual(bounds, ctx.dirty_rect); // sai do estado
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = away } });
    _ = try menu(&ctx, id, bounds, &items, &active, font, style);
    try stdt.testing.expect(ctx.dirty_rect.isEmpty());
    ctx.endFrame();
}
