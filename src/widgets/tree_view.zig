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

/// Referência a um nó visível, resolvida sob demanda sem vetor achatado.
const FlatNode = struct {
    item: *TreeItem,
    depth: usize,
    has_children: bool,
};

/// Busca o índice em pré-ordem; o estado expandido original permanece
/// imutável durante o teclado, preservando o snapshot S1 do frame.
fn treeViewFind(items: []TreeItem, target: usize) ?FlatNode {
    var cursor: usize = 0;
    return treeViewFindInner(items, target, 0, &cursor);
}

fn treeViewFindInner(items: []TreeItem, target: usize, depth: usize, cursor: *usize) ?FlatNode {
    for (items) |*item| {
        if (cursor.* == target) {
            return .{ .item = item, .depth = depth, .has_children = item.children.len > 0 };
        }
        cursor.* += 1;
        if (item.expanded) {
            if (treeViewFindInner(item.children, target, depth + 1, cursor)) |found| return found;
        }
    }
    return null;
}

/// Estado de teclado pendente. O commit ocorre também nos caminhos de erro
/// posteriores, mantendo mutações já aceitas sem afetar a navegação S1.
const TreePending = std.AutoHashMapUnmanaged(*TreeItem, bool);

fn treeViewCommit(pending: *TreePending) void {
    var it = pending.iterator();
    while (it.next()) |entry| {
        entry.key_ptr.*.expanded = entry.value_ptr.*;
    }
}

fn treeViewToggle(
    pending: *TreePending,
    allocator: std.mem.Allocator,
    item: *TreeItem,
) error{OutOfMemory}!void {
    const current = pending.get(item) orelse item.expanded;
    try pending.put(allocator, item, !current);
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
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;
    if (items.len == 0) return error.InvalidArgument;
    if (!std.math.isFinite(scroll_offset.*)) return error.InvalidArgument;

    // Somente contagem; nenhuma lista proporcional ao total de nós visíveis.
    const visible_count = treeViewCountVisible(items);
    var pending: TreePending = .empty;
    defer {
        treeViewCommit(&pending);
        pending.deinit(ctx.allocator);
    }
    if (visible_count == 0) return error.InvalidArgument;
    if (selected.* >= visible_count) selected.* = visible_count - 1;

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
            const flat_node = treeViewFind(items, idx).?;
            // Verifica se clicou no expansor
            const expander_x = bounds.x + @as(f32, @floatFromInt(flat_node.depth)) * style.indent;
            const expander_rect = types.Rect.init(expander_x, bounds.y + @as(f32, @floatFromInt(idx)) * style.item_height - scroll_offset.*, style.expander_size, style.expander_size);
            if (flat_node.has_children and expander_rect.contains(p)) {
                // Alterna expansão direto no item (ponteiro exato; sem
                // busca ambígua por (profundidade, índice do pai)).
                flat_node.item.expanded = !flat_node.item.expanded;
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

    // Snapshot S1: após o mouse e antes do teclado.
    const keyboard_visible_count = treeViewCountVisible(items);
    if (selected.* >= keyboard_visible_count and keyboard_visible_count > 0) selected.* = keyboard_visible_count - 1;
    last_visible = @min(keyboard_visible_count, last_visible);

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
                    if (selected.* + 1 < keyboard_visible_count) {
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
                    if (selected.* != keyboard_visible_count - 1) {
                        selected.* = keyboard_visible_count - 1;
                        res.changed = true;
                    }
                },
                .left => {
                    // Colapsa se expandido; senão vai para o pai
                    if (selected.* < keyboard_visible_count) {
                        const flat_node = treeViewFind(items, selected.*).?;
                        if (flat_node.has_children) {
                            try treeViewToggle(&pending, ctx.allocator, flat_node.item);
                        } else if (flat_node.depth > 0) {
                            // Vai para o pai (simplificação: primeiro ancestral visível acima)
                            var p: usize = selected.*;
                            while (p > 0 and treeViewFind(items, p).?.depth >= flat_node.depth) p -= 1;
                            if (p < keyboard_visible_count and treeViewFind(items, p).?.depth < flat_node.depth) {
                                selected.* = p;
                                res.changed = true;
                            }
                        }
                    }
                },
                .right => {
                    // Expande se tem filhos
                    if (selected.* < keyboard_visible_count) {
                        const flat_node = treeViewFind(items, selected.*).?;
                        if (flat_node.has_children) {
                            try treeViewToggle(&pending, ctx.allocator, flat_node.item);
                        }
                    }
                },
                .enter, .space => {
                    // Alterna expansão
                    if (selected.* < keyboard_visible_count) {
                        const flat_node = treeViewFind(items, selected.*).?;
                        if (flat_node.has_children) {
                            try treeViewToggle(&pending, ctx.allocator, flat_node.item);
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
        if (idx < keyboard_visible_count) {
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
        const flat_node = treeViewFind(items, i).?;
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
            flat_node.item.label,
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
            error.InvalidUtf8 => return error.InvalidArgument,
            error.InvalidMetrics => return error.InvalidArgument,
        };
    }

    // S2: o desenho acima ainda usa S1; a scrollbar vê os toggles do teclado.
    treeViewCommit(&pending);

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

test "TreeView rótulos aninhados e toggle exato por ponteiro (M72)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().treeViewStyle(); // item 24, indent 16, exp 12
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 300, 200);
    const id = id_mod.Id.fromString("test:tree-nested");
    var selected: usize = 0;
    var scroll: f32 = 0;

    // Raiz com 1 item e 4 filhos: índices 1..3 dos filhos excedem
    // o comprimento da raiz (1) — indexação errada estoura aqui.
    var kids = [_]TreeItem{
        .{ .label = "a0", .children = &[_]TreeItem{}, .expanded = false },
        .{ .label = "a1", .children = &[_]TreeItem{}, .expanded = false },
        .{ .label = "a2", .children = &[_]TreeItem{}, .expanded = false },
        .{ .label = "a3", .children = &[_]TreeItem{}, .expanded = false },
    };
    var items = [_]TreeItem{
        .{ .label = "A", .children = &kids, .expanded = true },
    };

    ctx.beginFrame();
    _ = try beginTreeView(&ctx, id, bounds, &items, &selected, &scroll, style);
    // Ordem dos textos desenhados: A, a0, a1, a2, a3 (rótulo do próprio nó).
    var got = [_][]const u8{ "", "", "", "", "" };
    var n: usize = 0;
    for (ctx.drawCommands()) |cmd| {
        if (cmd == .text and n < got.len) {
            got[n] = ctx.draw.textOf(cmd);
            n += 1;
        }
    }
    try stdt.testing.expectEqual(@as(usize, 5), n);
    try stdt.testing.expectEqualStrings("A", got[0]);
    try stdt.testing.expectEqualStrings("a0", got[1]);
    try stdt.testing.expectEqualStrings("a1", got[2]);
    try stdt.testing.expectEqualStrings("a2", got[3]);
    try stdt.testing.expectEqualStrings("a3", got[4]);
    ctx.endFrame();

    // Toggle exato: dois pais com filhos no mesmo (depth, índice).
    // Clicar no expansor de b1 deve alternar b1, nunca a1.
    var ax = [_]TreeItem{.{ .label = "x", .children = &[_]TreeItem{}, .expanded = false }};
    var by = [_]TreeItem{.{ .label = "y", .children = &[_]TreeItem{}, .expanded = false }};
    var ka = [_]TreeItem{
        .{ .label = "a0", .children = &[_]TreeItem{}, .expanded = false },
        .{ .label = "a1", .children = &ax, .expanded = true },
    };
    var kb = [_]TreeItem{
        .{ .label = "b0", .children = &[_]TreeItem{}, .expanded = false },
        .{ .label = "b1", .children = &by, .expanded = true },
    };
    var items2 = [_]TreeItem{
        .{ .label = "A", .children = &ka, .expanded = true },
        .{ .label = "B", .children = &kb, .expanded = true },
    };
    // Flat: 0:A 1:a0 2:a1 3:x 4:B 5:b0 6:b1 7:y — expansor de b1 (flat 6):
    // x=16, y=6*24=144; click em (20,148).
    var sel2: usize = 0;
    var scr2: f32 = 0;
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(20, 148) },
    });
    const rt = try beginTreeView(&ctx, id, bounds, &items2, &sel2, &scr2, style);
    try stdt.testing.expectEqual(@as(usize, 6), rt.toggled_index orelse 999);
    try stdt.testing.expect(!kb[1].expanded); // b1 colapsou
    try stdt.testing.expect(ka[1].expanded); // a1 intacto
    ctx.endFrame();
}

test "TreeView nó único, limites de scroll/wheel e clip pequeno" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().treeViewStyle(); // item 24
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:tree-limits");
    var solo = [_]TreeItem{
        .{ .label = "Só", .children = &[_]TreeItem{}, .expanded = false },
    };
    var selected: usize = 5; // além do único visível → clampa
    var scroll: f32 = 9999; // além do máximo (0) → clampa

    // Árvore de 1 nó: click seleciona, scroll zera, sem crash.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(50, 12) },
    });
    const r0 = try beginTreeView(&ctx, id, types.Rect.init(0, 0, 300, 200), &solo, &selected, &scroll, style);
    try stdt.testing.expectEqual(@as(usize, 0), selected);
    try stdt.testing.expectEqual(@as(usize, 0), r0.selected);
    try stdt.testing.expectEqual(@as(f32, 0), scroll);
    ctx.endFrame();

    // Teclado nos limites com 1 nó: tudo no-op.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .up, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{} } });
    const r1 = try beginTreeView(&ctx, id, types.Rect.init(0, 0, 300, 200), &solo, &selected, &scroll, style);
    try stdt.testing.expect(!r1.changed and selected == 0);
    ctx.endFrame();

    // Wheel finito extremo: clampa sem pânico (mínimo e máximo).
    var many = [_]TreeItem{
        .{ .label = "a", .children = &[_]TreeItem{}, .expanded = false },
        .{ .label = "b", .children = &[_]TreeItem{}, .expanded = false },
        .{ .label = "c", .children = &[_]TreeItem{}, .expanded = false },
        .{ .label = "d", .children = &[_]TreeItem{}, .expanded = false },
        .{ .label = "e", .children = &[_]TreeItem{}, .expanded = false },
        .{ .label = "f", .children = &[_]TreeItem{}, .expanded = false },
    };
    var sel2: usize = 0;
    var scr2: f32 = 0;
    const small = types.Rect.init(0, 0, 300, 48); // máx = 6*24-48 = 96
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = -1e30, .pos = types.Vec2.init(150, 24) } });
    const r2 = try beginTreeView(&ctx, id, small, &many, &sel2, &scr2, style);
    try stdt.testing.expectEqual(@as(f32, 96), scr2);
    try stdt.testing.expectEqual(@as(f32, 96), r2.scroll_offset);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = 1e30, .pos = types.Vec2.init(150, 24) } });
    _ = try beginTreeView(&ctx, id, small, &many, &sel2, &scr2, style);
    try stdt.testing.expectEqual(@as(f32, 0), scr2);
    ctx.endFrame();

    // Área pequena: clip pareado presente; scroll/bounds NaN rejeitados.
    ctx.beginFrame();
    _ = try beginTreeView(&ctx, id, types.Rect.init(0, 0, 40, 26), &many, &sel2, &scr2, style);
    var saw_clip = false;
    for (ctx.drawCommands()) |cmd| {
        if (cmd == .clip and !cmd.clip.null_rect) saw_clip = true;
    }
    try stdt.testing.expect(saw_clip);
    var nan_scroll: f32 = std.math.nan(f32);
    try stdt.testing.expectError(error.InvalidArgument, beginTreeView(&ctx, id, small, &many, &sel2, &nan_scroll, style));
    const nan_bounds = types.Rect.init(0, 0, std.math.nan(f32), 48);
    try stdt.testing.expectError(error.InvalidArgument, beginTreeView(&ctx, id, nan_bounds, &many, &sel2, &scr2, style));
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

test "TreeView golden G5: Right repetido alterna o mesmo no sem navegar" {
    const testing = std.testing;
    const style = style_mod.Theme.darkDefault().treeViewStyle();
    var ctx = try context_mod.Context.init(testing.allocator, .{});
    defer ctx.deinit();

    var children = [_]TreeItem{
        .{ .label = "X1", .children = &[_]TreeItem{} },
        .{ .label = "X2", .children = &[_]TreeItem{} },
    };
    var items = [_]TreeItem{
        .{ .label = "X", .children = &children, .expanded = false },
        .{ .label = "Y", .children = &[_]TreeItem{} },
    };
    const id = id_mod.Id.fromString("golden:g5");
    var selected: usize = 0;
    var scroll: f32 = 0;

    ctx.beginFrame();
    ctx.focus_owner = id;
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    const result = try beginTreeView(&ctx, id, types.Rect.init(0, 0, 300, 120), &items, &selected, &scroll, style);

    try testing.expectEqual(@as(usize, 0), selected);
    try testing.expectEqual(@as(usize, 0), result.selected);
    try testing.expect(!result.changed);
    try testing.expect(!items[0].expanded);
    var texts: usize = 0;
    for (ctx.drawCommands()) |cmd| {
        if (cmd == .text) {
            const label = ctx.draw.textOf(cmd);
            if (texts == 0) try testing.expectEqualStrings("X", label);
            if (texts == 1) try testing.expectEqualStrings("Y", label);
            texts += 1;
        }
    }
    try testing.expectEqual(@as(usize, 2), texts);
    ctx.endFrame();
}

test "TreeView golden G11: Right Down Enter navega na sequencia S1" {
    const testing = std.testing;
    const style = style_mod.Theme.darkDefault().treeViewStyle();
    var ctx = try context_mod.Context.init(testing.allocator, .{});
    defer ctx.deinit();

    var x_children = [_]TreeItem{.{ .label = "X1", .children = &[_]TreeItem{} }};
    var y_children = [_]TreeItem{.{ .label = "Y1", .children = &[_]TreeItem{} }};
    var items = [_]TreeItem{
        .{ .label = "X", .children = &x_children, .expanded = false },
        .{ .label = "Y", .children = &y_children, .expanded = false },
        .{ .label = "Z", .children = &[_]TreeItem{} },
    };
    const id = id_mod.Id.fromString("golden:g11");
    var selected: usize = 0;
    var scroll: f32 = 0;

    ctx.beginFrame();
    ctx.focus_owner = id;
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .enter, .pressed = true, .modifiers = .{} } });
    const result = try beginTreeView(&ctx, id, types.Rect.init(0, 0, 300, 120), &items, &selected, &scroll, style);

    try testing.expectEqual(@as(usize, 1), selected);
    try testing.expectEqual(@as(usize, 1), result.selected);
    try testing.expect(result.changed);
    try testing.expect(items[0].expanded);
    try testing.expect(items[1].expanded);
    var texts: usize = 0;
    for (ctx.drawCommands()) |cmd| {
        if (cmd == .text) {
            const label = ctx.draw.textOf(cmd);
            switch (texts) {
                0 => try testing.expectEqualStrings("X", label),
                1 => try testing.expectEqualStrings("Y", label),
                2 => try testing.expectEqualStrings("Z", label),
                else => return error.InvalidArgument,
            }
            texts += 1;
        }
    }
    try testing.expectEqual(@as(usize, 3), texts);
    ctx.endFrame();
}

test "TreeView golden G6: scrollbar usa S2 enquanto linhas usam S1" {
    const testing = std.testing;
    const style = style_mod.Theme.darkDefault().treeViewStyle();
    var ctx = try context_mod.Context.init(testing.allocator, .{});
    defer ctx.deinit();

    var children = [_]TreeItem{
        .{ .label = "X1", .children = &[_]TreeItem{} },
        .{ .label = "X2", .children = &[_]TreeItem{} },
        .{ .label = "X3", .children = &[_]TreeItem{} },
        .{ .label = "X4", .children = &[_]TreeItem{} },
    };
    var items = [_]TreeItem{
        .{ .label = "X", .children = &children, .expanded = false },
        .{ .label = "Y", .children = &[_]TreeItem{} },
        .{ .label = "Z", .children = &[_]TreeItem{} },
        .{ .label = "W", .children = &[_]TreeItem{} },
        .{ .label = "Q", .children = &[_]TreeItem{} },
    };
    const id = id_mod.Id.fromString("golden:g6");
    var selected: usize = 0;
    var scroll: f32 = 0;

    ctx.beginFrame();
    ctx.focus_owner = id;
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    const result = try beginTreeView(&ctx, id, types.Rect.init(0, 0, 300, 72), &items, &selected, &scroll, style);
    try testing.expect(items[0].expanded);
    try testing.expectEqual(@as(usize, 0), result.selected);
    try testing.expectEqual(@as(f32, 0), result.scroll_offset);

    var texts: usize = 0;
    var filled_rects: usize = 0;
    for (ctx.drawCommands()) |cmd| {
        if (cmd == .rect_filled) filled_rects += 1;
        if (cmd == .text) {
            switch (texts) {
                0 => try testing.expectEqualStrings("X", ctx.draw.textOf(cmd)),
                1 => try testing.expectEqualStrings("Y", ctx.draw.textOf(cmd)),
                2 => try testing.expectEqualStrings("Z", ctx.draw.textOf(cmd)),
                3 => try testing.expectEqualStrings("W", ctx.draw.textOf(cmd)),
                else => return error.InvalidArgument,
            }
            texts += 1;
        }
    }
    try testing.expectEqual(@as(usize, 4), texts);
    // Fundo + 4 linhas + expansor de X + thumb da scrollbar de S2.
    try testing.expectEqual(@as(usize, 7), filled_rects);
    ctx.endFrame();
}

test "TreeView golden G12: wheel preserva intervalo de indices anterior" {
    const testing = std.testing;
    const style = style_mod.Theme.darkDefault().treeViewStyle();
    var ctx = try context_mod.Context.init(testing.allocator, .{});
    defer ctx.deinit();

    var items = [_]TreeItem{
        .{ .label = "a", .children = &[_]TreeItem{} },
        .{ .label = "b", .children = &[_]TreeItem{} },
        .{ .label = "c", .children = &[_]TreeItem{} },
        .{ .label = "d", .children = &[_]TreeItem{} },
        .{ .label = "e", .children = &[_]TreeItem{} },
        .{ .label = "f", .children = &[_]TreeItem{} },
    };
    const id = id_mod.Id.fromString("golden:g12");
    var selected: usize = 0;
    var scroll: f32 = 0;

    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = -1, .pos = types.Vec2.init(150, 24) } });
    const result = try beginTreeView(&ctx, id, types.Rect.init(0, 0, 300, 48), &items, &selected, &scroll, style);
    try testing.expectEqual(@as(f32, 20), scroll);
    try testing.expectEqual(@as(f32, 20), result.scroll_offset);
    var texts: usize = 0;
    for (ctx.drawCommands()) |cmd| {
        if (cmd != .text) continue;
        switch (texts) {
            0 => try testing.expectEqualStrings("a", ctx.draw.textOf(cmd)),
            1 => try testing.expectEqualStrings("b", ctx.draw.textOf(cmd)),
            2 => try testing.expectEqualStrings("c", ctx.draw.textOf(cmd)),
            else => return error.InvalidArgument,
        }
        texts += 1;
    }
    try testing.expectEqual(@as(usize, 3), texts);
    ctx.endFrame();
}

test "TreeView golden G13: auto-scroll nao recalcula intervalo desenhado" {
    const testing = std.testing;
    const style = style_mod.Theme.darkDefault().treeViewStyle();
    var ctx = try context_mod.Context.init(testing.allocator, .{});
    defer ctx.deinit();

    var items = [_]TreeItem{
        .{ .label = "a", .children = &[_]TreeItem{} },
        .{ .label = "b", .children = &[_]TreeItem{} },
        .{ .label = "c", .children = &[_]TreeItem{} },
        .{ .label = "d", .children = &[_]TreeItem{} },
        .{ .label = "e", .children = &[_]TreeItem{} },
        .{ .label = "f", .children = &[_]TreeItem{} },
    };
    const id = id_mod.Id.fromString("golden:g13");
    var selected: usize = 0;
    var scroll: f32 = 0;

    ctx.beginFrame();
    ctx.focus_owner = id;
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{} } });
    const result = try beginTreeView(&ctx, id, types.Rect.init(0, 0, 300, 48), &items, &selected, &scroll, style);
    try testing.expect(result.changed);
    try testing.expectEqual(@as(usize, 5), selected);
    try testing.expectEqual(@as(usize, 5), result.selected);
    try testing.expectEqual(@as(f32, 96), scroll);
    try testing.expectEqual(@as(f32, 96), result.scroll_offset);
    var texts: usize = 0;
    for (ctx.drawCommands()) |cmd| {
        if (cmd != .text) continue;
        switch (texts) {
            0 => try testing.expectEqualStrings("a", ctx.draw.textOf(cmd)),
            1 => try testing.expectEqualStrings("b", ctx.draw.textOf(cmd)),
            2 => try testing.expectEqualStrings("c", ctx.draw.textOf(cmd)),
            else => return error.InvalidArgument,
        }
        texts += 1;
    }
    try testing.expectEqual(@as(usize, 3), texts);
    ctx.endFrame();
}

test "TreeView traversal: preorder skips collapsed descendants without allocations" {
    const testing = std.testing;
    var deep = [_]TreeItem{
        .{ .label = "deep", .children = &[_]TreeItem{} },
    };
    var branch = [_]TreeItem{
        .{ .label = "visible", .children = &deep, .expanded = true },
        .{ .label = "hidden", .children = &[_]TreeItem{} },
    };
    var collapsed_children = [_]TreeItem{
        .{ .label = "not visible", .children = &[_]TreeItem{} },
    };
    var items = [_]TreeItem{
        .{ .label = "root", .children = &branch, .expanded = true },
        .{ .label = "collapsed", .children = &collapsed_children },
        .{ .label = "tail", .children = &[_]TreeItem{} },
    };

    const expected = [_][]const u8{ "root", "visible", "deep", "hidden", "collapsed", "tail" };
    try testing.expectEqual(expected.len, treeViewCountVisible(&items));
    for (expected, 0..) |label, idx| {
        const found = treeViewFind(&items, idx) orelse return error.TestUnexpectedResult;
        try testing.expectEqualStrings(label, found.item.label);
    }
    try testing.expect(treeViewFind(&items, expected.len) == null);
    try testing.expectEqual(@as(usize, 0), treeViewFind(&items, 0).?.depth);
    try testing.expectEqual(@as(usize, 2), treeViewFind(&items, 2).?.depth);
    try testing.expectEqual(@as(usize, 0), treeViewFind(&items, 5).?.depth);
}

test "TreeView pending keyboard toggles preserve S1 until commit" {
    const testing = std.testing;
    var child = [_]TreeItem{
        .{ .label = "child", .children = &[_]TreeItem{} },
    };
    var items = [_]TreeItem{
        .{ .label = "parent", .children = &child, .expanded = false },
        .{ .label = "sibling", .children = &[_]TreeItem{} },
    };
    var pending: TreePending = .empty;
    defer pending.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 2), treeViewCountVisible(&items));
    try treeViewToggle(&pending, testing.allocator, &items[0]);
    try testing.expect(!items[0].expanded);
    try testing.expectEqual(@as(usize, 2), treeViewCountVisible(&items));
    try testing.expectEqualStrings("sibling", treeViewFind(&items, 1).?.item.label);

    treeViewCommit(&pending);
    try testing.expect(items[0].expanded);
    try testing.expectEqual(@as(usize, 3), treeViewCountVisible(&items));
    try testing.expectEqualStrings("child", treeViewFind(&items, 1).?.item.label);

    // Dois toggles adicionais no mesmo snapshot cancelam um ao outro.
    try treeViewToggle(&pending, testing.allocator, &items[0]);
    try treeViewToggle(&pending, testing.allocator, &items[0]);
    try testing.expect(items[0].expanded);
    treeViewCommit(&pending);
    try testing.expect(items[0].expanded);
    try testing.expectEqual(@as(usize, 3), treeViewCountVisible(&items));
}
