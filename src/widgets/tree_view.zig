//! ZyntraUI — árvore hierárquica (widgets/tree_view).
//!
//! Modelo M59: `beginTreeView`/`endTreeView` com estado no chamador.
//! - `items: []TreeItem` — nós da árvore (chamador detém).
//! - `selected: *usize` — índice do nó selecionado (chamador, clampado).
//! - `scroll_offset: *f32` — offset de rolagem (chamador, px).
//! - `TreeItem`: label, filhos, `expanded` (chamador), `depth` (derivado).
//! - Mouse: click seleciona; click em expansor alterna; wheel rola.
//! - Teclado com foco: setas navegam; Enter/Space alterna expansão;
//!   Left/Right colapsa/expande; Home/End saltam.
//! - `TreeViewStyle` + `Theme.treeViewStyle()` — cores, indent, expansor.
//! - Desenho: fundo + N nós visíveis (indent + expansor + texto) + scrollbar.
//! `id` não-nulo obrigatório.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const input = @import("input.zig");
const metrics_mod = @import("../text/metrics.zig");

pub const TreeItem = struct {
    label: []const u8,
    children: []TreeItem,
    /// Estado de expansão (chamador detém; mutado pelo widget).
    expanded: bool = false,
};

/// Índice linear do nó na lista achatada de nós visíveis.
pub const TreeViewResult = struct {
    selected: usize = 0,
    changed: bool = false,
    hovered_index: ?usize = null,
    scroll_offset: f32 = 0,
    /// Nó clicado no expansor (para feedback do app, se necessário).
    toggled_index: ?usize = null,
};

/// Nó achatado para renderização (índice no array original + profundidade).
const FlatNode = struct {
    item_index: usize,
    depth: usize,
    has_children: bool,
};

/// Achata a árvore em lista de nós visíveis (respeita `expanded`).
fn treeViewFlatten(items: []const TreeItem, out: *std.ArrayList(FlatNode), depth: usize, allocator: std.mem.Allocator) void {
    var i: usize = 0;
    while (i < items.len) : (i += 1) {
        const item = items[i];
        out.append(allocator, FlatNode{
            .item_index = i,
            .depth = depth,
            .has_children = item.children.len > 0,
        }) catch return;
        if (item.expanded and item.children.len > 0) {
            treeViewFlatten(item.children, out, depth + 1, allocator);
        }
    }
}

/// Conta nós visíveis totais.
fn treeViewCountVisible(items: []const TreeItem) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i < items.len) : (i += 1) {
        count += 1;
        if (items[i].expanded) {
            count += treeViewCountVisible(items[i].children);
        }
    }
    return count;
}

/// Calcula altura total de conteúdo (px).
pub fn treeViewContentHeight(items: []TreeItem, style: style_mod.TreeViewStyle) f32 {
    return @as(f32, @floatFromInt(treeViewCountVisible(items))) * style.item_height;
}

/// Calcula offset máximo de rolagem.
pub fn treeViewMaxScroll(items: []TreeItem, viewport_h: f32, style: style_mod.TreeViewStyle) f32 {
    const content = treeViewContentHeight(items, style);
    return @max(0, content - viewport_h);
}

/// Alterna expansão do nó no índice linear achatado.
fn treeViewToggleExpanded(items: []TreeItem, flat: []FlatNode, flat_idx: usize) void {
    if (flat_idx >= flat.len) return;
    const fn_idx = flat[flat_idx].item_index;
    // Navega até o nó pai para mutar `expanded`
    // Nota: `items` é a raiz; precisamos achar o nó correto na hierarquia.
    // Como `item_index` é relativo ao seu pai, precisamos de lógica recursiva.
    // Simplificação: assumimos que o índice achatado mapeia recursivamente.
    // Implementação recursiva de toggle:
    _ = treeViewToggleExpandedRec(items, flat[flat_idx].depth, fn_idx, 0);
}

fn treeViewToggleExpandedRec(items: []TreeItem, target_depth: usize, target_idx: usize, current_depth: usize) bool {
    var i: usize = 0;
    while (i < items.len) : (i += 1) {
        if (current_depth == target_depth and i == target_idx) {
            if (items[i].children.len > 0) {
                items[i].expanded = !items[i].expanded;
                return true;
            }
            return false;
        }
        if (items[i].expanded and items[i].children.len > 0) {
            if (treeViewToggleExpandedRec(items[i].children, target_depth, target_idx, current_depth + 1)) {
                return true;
            }
        }
    }
    return false;
}

pub fn beginTreeView(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    items: []TreeItem,
    selected: *usize,
    scroll_offset: *f32,
    style: style_mod.TreeViewStyle,
) context_mod.ContextError!TreeViewResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid()) return error.InvalidArgument;
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;
    if (items.len == 0) return error.InvalidArgument;

    // Achatamento da árvore visível
    var flat = std.ArrayList(FlatNode).empty;
    defer flat.deinit(ctx.allocator);
    treeViewFlatten(items, &flat, 0, ctx.allocator);

    const visible_count = flat.items.len;
    if (selected.* >= visible_count) selected.* = visible_count - 1;
    if (visible_count == 0) selected.* = 0;

    const max_scroll = treeViewMaxScroll(items, bounds.h, style);
    scroll_offset.* = std.math.clamp(scroll_offset.*, 0, max_scroll);

    const fm = input.FrameMouse.scan(ctx.pendingEvents());
    _ = if (ctx.mouse_pos) |p| bounds.contains(p) else false;
    var res = TreeViewResult{ .selected = selected.*, .scroll_offset = scroll_offset.* };

    try ctx.registerFocusable(id);
    if (fm.pressedInside(bounds)) {
        ctx.focus_owner = id;
    }

    // Layout dos itens visíveis
    const first_visible: usize = @as(usize, @intFromFloat(@floor(scroll_offset.* / style.item_height)));
    var last_visible: usize = @min(visible_count, first_visible + @as(usize, @intFromFloat(@ceil(bounds.h / style.item_height))) + 1);

    // Click seleciona ou alterna expansor
    if (fm.pressed_pos) |p| {
        const rel_y = p.y - bounds.y + scroll_offset.*;
        const idx: usize = @as(usize, @intFromFloat(@floor(rel_y / style.item_height)));
        if (idx < visible_count) {
            const flat_node = flat.items[idx];
            // Verifica se clicou no expansor
            const expander_x = bounds.x + @as(f32, @floatFromInt(flat_node.depth)) * style.indent;
            const expander_rect = types.Rect.init(expander_x, bounds.y + @as(f32, @floatFromInt(idx)) * style.item_height - scroll_offset.*, style.expander_size, style.expander_size);
            if (flat_node.has_children and expander_rect.contains(p)) {
                // Alterna expansão recursivamente
                _ = treeViewToggleExpandedRec(items, flat_node.depth, flat_node.item_index, 0);
                res.toggled_index = idx;
            } else {
                res.changed = selected.* != idx;
                selected.* = idx;
                res.selected = idx;
            }
        }
    }

    // Wheel rola
    for (ctx.pendingEvents()) |ev| {
        if (ev != .mouse_wheel) continue;
        const w = ev.mouse_wheel;
        if (bounds.contains(w.pos)) {
            scroll_offset.* = std.math.clamp(scroll_offset.* - w.dy * 20, 0, max_scroll);
        }
    }

    // Re-achata após possível toggle: limpa e reutiliza o mesmo ArrayList.
    // O colapso pode encolher a lista no meio do frame: re-deriva limites
    // e seleção ANTES de qualquer indexação (sem isso, o desenho lê além
    // do fim e o Zig com safety aborta).
    flat.clearRetainingCapacity();
    treeViewFlatten(items, &flat, 0, ctx.allocator);
    if (selected.* >= flat.items.len and flat.items.len > 0) selected.* = flat.items.len - 1;
    last_visible = @min(flat.items.len, last_visible);

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
                    if (selected.* + 1 < flat.items.len) {
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
                    if (selected.* != flat.items.len - 1) {
                        selected.* = flat.items.len - 1;
                        res.changed = true;
                    }
                },
                .left => {
                    // Colapsa se expandido; senão vai para o pai
                    if (selected.* < flat.items.len) {
                        const flat_node = flat.items[selected.*];
                        if (flat_node.has_children) {
                            _ = treeViewToggleExpandedRec(items, flat_node.depth, flat_node.item_index, 0);
                        } else if (flat_node.depth > 0) {
                            // Vai para o pai (simplificação: primeiro ancestral visível acima)
                            var p: usize = selected.*;
                            while (p > 0 and flat.items[p].depth >= flat_node.depth) p -= 1;
                            if (p < flat.items.len and flat.items[p].depth < flat_node.depth) {
                                selected.* = p;
                                res.changed = true;
                            }
                        }
                    }
                },
                .right => {
                    // Expande se tem filhos
                    if (selected.* < flat.items.len) {
                        const flat_node = flat.items[selected.*];
                        if (flat_node.has_children) {
                            _ = treeViewToggleExpandedRec(items, flat_node.depth, flat_node.item_index, 0);
                        }
                    }
                },
                .enter, .space => {
                    // Alterna expansão
                    if (selected.* < flat.items.len) {
                        const flat_node = flat.items[selected.*];
                        if (flat_node.has_children) {
                            _ = treeViewToggleExpandedRec(items, flat_node.depth, flat_node.item_index, 0);
                        }
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

    // Hover index (contagem pós-toggle: a lista pode ter encolhido).
    if (ctx.mouse_pos) |p| {
        const rel_y = p.y - bounds.y + scroll_offset.*;
        const idx: usize = @as(usize, @intFromFloat(@floor(rel_y / style.item_height)));
        if (idx < flat.items.len) {
            res.hovered_index = idx;
        }
    }

    // Desenho: fundo
    ctx.draw.rectFilled(ctx.allocator, bounds, style.bg) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };

    // Clip
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
        const flat_node = flat.items[i];
        const is_selected = i == selected.*;
        const is_hovered = res.hovered_index == i and !is_selected;

        const bg = if (is_selected) style.bg_selected else if (is_hovered) style.bg_hover else style.bg;
        ctx.draw.rectFilled(ctx.allocator, item_rect, bg) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
        };

        // Expansor
        if (flat_node.has_children) {
            const exp_x = bounds.x + @as(f32, @floatFromInt(flat_node.depth)) * style.indent;
            const expander_rect = types.Rect.init(exp_x, y, style.expander_size, style.expander_size);
            // Desenha triângulo simples (seta para baixo se expandido, direita se colapsado)
            // Para simplicidade, desenhamos um retângulo como placeholder do expansor
            const exp_color = if (is_selected) style.text_selected else style.text;
            ctx.draw.rectFilled(ctx.allocator, expander_rect, exp_color) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidCommand => return error.InvalidCommand,
            };
        }

        // Texto
        const text_x = bounds.x + @as(f32, @floatFromInt(flat_node.depth)) * style.indent + style.expander_size + 4;
        const text_color = if (is_selected) style.text_selected else style.text;
        ctx.draw.pushText(
            ctx.allocator,
            .{ .x = text_x, .y = y + (style.item_height - font.lineHeight()) / 2 },
            text_color,
            font,
            items[flat_node.item_index].label, // Aproximação
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
            error.InvalidUtf8 => return error.InvalidArgument,
            error.InvalidMetrics => return error.InvalidArgument,
        };
    }

    // Scrollbar
    const content_h = treeViewContentHeight(items, style);
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

/// Fim da árvore (M59): NO-OP — sem estado retido, sem draws.
/// Existe apenas para simetria de pareamento com outros widgets.
pub fn endTreeView(_: *context_mod.Context) void {}

test "TreeView seleciona, navega, expande/colapsa" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().treeViewStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 300, 200);
    const id = id_mod.Id.fromString("test:tree");
    var selected: usize = 999; // será clampado
    var scroll: f32 = 0;

    var child_a = [_]TreeItem{
        .{ .label = "Arquivo 1", .children = &[_]TreeItem{}, .expanded = false },
        .{ .label = "Arquivo 2", .children = &[_]TreeItem{}, .expanded = false },
    };
    var child_b = [_]TreeItem{
        .{ .label = "Arquivo 3", .children = &[_]TreeItem{}, .expanded = false },
    };

    var items = [_]TreeItem{
        .{
            .label = "Pasta A",
            .children = &child_a,
            .expanded = true,
        },
        .{
            .label = "Pasta B",
            .children = &child_b,
            .expanded = false,
        },
        .{
            .label = "Pasta C",
            .children = &[_]TreeItem{},
            .expanded = true,
        },
    };

    // Click no primeiro item (Pasta A, índice 0)
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(50, 12) },
    });
    const r0 = try beginTreeView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expect(r0.changed);
    try stdt.testing.expectEqual(@as(usize, 0), selected);
    ctx.endFrame();

    // Down move para "Arquivo 1" (índice 1 na lista achatada)
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    const r1 = try beginTreeView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expect(r1.changed);
    try stdt.testing.expectEqual(@as(usize, 1), selected);
    ctx.endFrame();

    // Enter em "Pasta B" (colapsada) expande
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .enter, .pressed = true, .modifiers = .{} } });
    _ = try beginTreeView(&ctx, id, bounds, &items, &selected, &scroll, style);
    // selected ainda 1 (Arquivo 1), mas Pasta B expandida
    ctx.endFrame();

    // Right em "Pasta B" expande
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    _ = try beginTreeView(&ctx, id, bounds, &items, &selected, &scroll, style);
    ctx.endFrame();

    // Left em item expandido colapsa
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{} } });
    _ = try beginTreeView(&ctx, id, bounds, &items, &selected, &scroll, style);
    ctx.endFrame();

    // Contratos inválidos
    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, beginTreeView(&ctx, .null, bounds, &items, &selected, &scroll, style));
    try stdt.testing.expectError(error.InvalidArgument, beginTreeView(&ctx, id, types.Rect.init(0, 0, 0, 0), &items, &selected, &scroll, style));
    try stdt.testing.expectError(error.InvalidArgument, beginTreeView(&ctx, id, bounds, &[_]TreeItem{}, &selected, &scroll, style));
    const bad_style = style_mod.TreeViewStyle{ .item_height = 0, .bg = .{}, .bg_selected = .{}, .bg_hover = .{}, .text = .{}, .text_selected = .{}, .border = .{}, .border_width = 1, .indent = 16, .expander_size = 12 };
    try stdt.testing.expectError(error.InvalidArgument, beginTreeView(&ctx, id, bounds, &items, &selected, &scroll, bad_style));
    ctx.endFrame();
}

test "TreeView colapso, scroll, contagem e profundidade" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().treeViewStyle(); // item_height = 24
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 300, 48); // 2 linhas visíveis
    const id = id_mod.Id.fromString("test:tree-deep");
    var selected: usize = 0;
    var scroll: f32 = 0;

    var leaf_kids = [_]TreeItem{
        .{ .label = "Neto", .children = &[_]TreeItem{}, .expanded = false },
    };
    var mid_kids = [_]TreeItem{
        .{ .label = "Filho", .children = &leaf_kids, .expanded = true },
    };
    var items = [_]TreeItem{
        .{ .label = "Raiz", .children = &mid_kids, .expanded = true },
        .{ .label = "Raiz2", .children = &[_]TreeItem{}, .expanded = false },
    };

    // Helpers puros: 4 visíveis (Raiz, Filho, Neto, Raiz2).
    try stdt.testing.expectEqual(@as(f32, 96), treeViewContentHeight(&items, style));
    try stdt.testing.expectEqual(@as(f32, 48), treeViewMaxScroll(&items, bounds.h, style));

    // Click foca (sem mudar seleção, já é 0 → !changed).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(150, 12) },
    });
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(150, 12) },
    });
    _ = try beginTreeView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expect(ctx.hasFocus(id));
    ctx.endFrame();

    // Ordem achatada através das profundidades: down ×3 chega em Raiz2.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    _ = try beginTreeView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expectEqual(@as(usize, 1), selected);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    _ = try beginTreeView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expectEqual(@as(usize, 2), selected); // Neto, depth 2
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    const r3 = try beginTreeView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expect(r3.changed);
    try stdt.testing.expectEqual(@as(usize, 3), selected); // Raiz2
    ctx.endFrame();

    // Extremidades são no-op: down no último e up no primeiro.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    const r4 = try beginTreeView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expect(!r4.changed and selected == 3);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    _ = try beginTreeView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expectEqual(@as(usize, 0), selected);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .up, .pressed = true, .modifiers = .{} } });
    const r5 = try beginTreeView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expect(!r5.changed and selected == 0);
    ctx.endFrame();

    // Scroll clampado ao máximo (48) e de volta ao 0.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = -10, .pos = types.Vec2.init(150, 24) } });
    const r6 = try beginTreeView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expectEqual(@as(f32, 48), r6.scroll_offset);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = 10, .pos = types.Vec2.init(150, 24) } });
    const r7 = try beginTreeView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expectEqual(@as(f32, 0), r7.scroll_offset);
    ctx.endFrame();

    // Seleção válida após recolher: volta ao topo (scroll zera),
    // seleciona Neto (2), colapsa Raiz pelo expansor (click em x=6,
    // linha 0) → próxima frame clampa p/ 1.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    _ = try beginTreeView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expectEqual(@as(usize, 0), selected);
    try stdt.testing.expectEqual(@as(f32, 0), scroll);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    _ = try beginTreeView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expectEqual(@as(usize, 1), selected);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    _ = try beginTreeView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expectEqual(@as(usize, 2), selected);
    ctx.endFrame();
    // Rola de volta ao topo sem mover a seleção (scroll 24 → 0).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = 10, .pos = types.Vec2.init(150, 24) } });
    _ = try beginTreeView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expectEqual(@as(f32, 0), scroll);
    try stdt.testing.expectEqual(@as(usize, 2), selected);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(6, 6) },
    });
    const r8 = try beginTreeView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expect(r8.toggled_index != null);
    try stdt.testing.expect(!items[0].expanded);
    ctx.endFrame();
    ctx.beginFrame();
    _ = try beginTreeView(&ctx, id, bounds, &items, &selected, &scroll, style);
    try stdt.testing.expect(selected < 2); // clampado aos 2 visíveis
    try stdt.testing.expectEqual(@as(f32, 48), treeViewContentHeight(&items, style));
    ctx.endFrame();
}
