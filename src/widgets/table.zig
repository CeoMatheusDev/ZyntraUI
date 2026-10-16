//! ZyntraUI — tabela com header fixo (widgets/table).
//!
//! Modelo M62: `beginTable`/`endTable` com estado no chamador.
//! - `columns: []const TableColumn` — títulos + larguras (chamador detém).
//! - `rows: []const TableRow` — linhas; cada `cells` é uma fatia (chamador).
//! - `selected: *usize` — índice da linha selecionada (chamador, clampado).
//! - `scroll_offset: *f32` — offset de rolagem do corpo (chamador, px).
//! - Header fixo; só o corpo rola. Mouse: click seleciona; wheel rola.
//! - Teclado com foco: setas/Home/End/PageUp/PageDown movem; Tab avança.
//! - `TableStyle` + `Theme.tableStyle()` — cores, alturas, padding.
//! - Desenho: fundo + header (títulos + separadores) + N linhas
//!   (fundo zebrado/seleção/hover + células) + scrollbar + outline.
//! `id` não-nulo obrigatório.
//!
//! Colunas com largura finita positiva; a soma pode exceder a largura
//! visível (o clip contém) ou ser menor (sobra à direita, sem desenho).

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const input = @import("input.zig");
const metrics_mod = @import("../text/metrics.zig");

pub const TableColumn = struct {
    title: []const u8,
    width: f32,
};

pub const TableRow = struct {
    cells: []const []const u8,
};

pub const TableResult = struct {
    selected: usize = 0,
    changed: bool = false,
    hovered_index: ?usize = null,
    scroll_offset: f32 = 0,
};

/// Retângulo do corpo (abaixo do header fixo).
pub fn tableBodyRect(bounds: types.Rect, style: style_mod.TableStyle) types.Rect {
    return types.Rect.init(
        bounds.x,
        bounds.y + style.header_height,
        bounds.w,
        @max(0, bounds.h - style.header_height),
    );
}

/// Altura total do conteúdo (linhas), em px.
pub fn tableContentHeight(rows: []const TableRow, style: style_mod.TableStyle) f32 {
    return @as(f32, @floatFromInt(rows.len)) * style.row_height;
}

/// Offset máximo de rolagem do corpo.
pub fn tableMaxScroll(rows: []const TableRow, body_h: f32, style: style_mod.TableStyle) f32 {
    return @max(0, tableContentHeight(rows, style) - body_h);
}

/// Largura total das colunas (px).
pub fn tableColumnsWidth(columns: []const TableColumn) f32 {
    var total: f32 = 0;
    for (columns) |c| total += c.width;
    return total;
}

fn columnsValid(columns: []const TableColumn) bool {
    if (columns.len == 0) return false;
    for (columns) |c| {
        if (!std.math.isFinite(c.width) or c.width <= 0) return false;
    }
    return true;
}

pub fn beginTable(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    columns: []const TableColumn,
    rows: []const TableRow,
    selected: *usize,
    scroll_offset: *f32,
    style: style_mod.TableStyle,
) context_mod.ContextError!TableResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    if (bounds.w <= 0 or bounds.h <= style.header_height) return error.InvalidArgument;
    if (!columnsValid(columns)) return error.InvalidArgument;
    if (rows.len == 0) return error.InvalidArgument;
    if (!std.math.isFinite(scroll_offset.*)) return error.InvalidArgument;

    const body = tableBodyRect(bounds, style);
    if (selected.* >= rows.len) selected.* = rows.len - 1;
    const max_scroll = tableMaxScroll(rows, body.h, style);
    scroll_offset.* = std.math.clamp(scroll_offset.*, 0, max_scroll);

    const fm = input.FrameMouse.scan(ctx.pendingEvents());
    var res = TableResult{ .selected = selected.*, .scroll_offset = scroll_offset.* };

    // Focável
    try ctx.registerFocusable(id);
    if (fm.pressedInside(bounds)) {
        ctx.focus_owner = id;
    }

    // Layout das linhas visíveis no corpo
    const first_visible: usize = @as(usize, @intFromFloat(@floor(scroll_offset.* / style.row_height)));
    const last_visible: usize = @min(rows.len, first_visible + @as(usize, @intFromFloat(@ceil(body.h / style.row_height))) + 1);

    // Click no corpo seleciona
    if (fm.pressed_pos) |p| {
        if (body.contains(p)) {
            const rel_y = p.y - body.y + scroll_offset.*;
            const idx: usize = @as(usize, @intFromFloat(@floor(rel_y / style.row_height)));
            if (idx >= first_visible and idx < last_visible) {
                res.changed = selected.* != idx;
                selected.* = idx;
                res.selected = idx;
            }
        }
    }

    // Wheel rola o corpo
    for (ctx.pendingEvents()) |ev| {
        if (ev != .mouse_wheel) continue;
        const w = ev.mouse_wheel;
        if (body.contains(w.pos)) {
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
                    if (selected.* + 1 < rows.len) {
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
                    if (selected.* != rows.len - 1) {
                        selected.* = rows.len - 1;
                        res.changed = true;
                    }
                },
                .page_up => {
                    const page: usize = @intFromFloat(@floor(body.h / style.row_height));
                    const new_sel = if (selected.* > page) selected.* - page else 0;
                    if (new_sel != selected.*) {
                        selected.* = new_sel;
                        res.changed = true;
                    }
                },
                .page_down => {
                    const page: usize = @intFromFloat(@floor(body.h / style.row_height));
                    const new_sel = @min(rows.len - 1, selected.* + page);
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

    // Auto-scroll para manter seleção visível no corpo
    if (res.changed) {
        const sel_y = @as(f32, @floatFromInt(selected.*)) * style.row_height;
        if (sel_y < scroll_offset.*) {
            scroll_offset.* = sel_y;
        } else if (sel_y + style.row_height > scroll_offset.* + body.h) {
            scroll_offset.* = sel_y + style.row_height - body.h;
        }
        scroll_offset.* = std.math.clamp(scroll_offset.*, 0, max_scroll);
    }

    // Hover (só no corpo)
    if (ctx.mouse_pos) |p| {
        if (body.contains(p)) {
            const rel_y = p.y - body.y + scroll_offset.*;
            const idx: usize = @as(usize, @intFromFloat(@floor(rel_y / style.row_height)));
            if (idx >= first_visible and idx < last_visible) {
                res.hovered_index = idx;
            }
        }
    }

    // Desenho: fundo
    ctx.draw.rectFilled(ctx.allocator, bounds, style.bg) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };

    const font = metrics_mod.FontMetrics.withSize(10);
    const header_rect = types.Rect.init(bounds.x, bounds.y, bounds.w, style.header_height);

    // Header: títulos + separadores verticais
    var cx: f32 = bounds.x;
    for (columns, 0..) |col, j| {
        if (col.title.len > 0) {
            ctx.draw.pushText(
                ctx.allocator,
                .{ .x = cx + style.padding_x, .y = header_rect.y + (style.header_height - font.lineHeight()) / 2 },
                style.text_header,
                font,
                col.title,
            ) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidCommand => return error.InvalidCommand,
                error.InvalidUtf8 => return error.InvalidArgument,
                error.InvalidMetrics => return error.InvalidArgument,
            };
        }
        cx += col.width;
        if (j + 1 < columns.len) {
            ctx.draw.rectFilled(ctx.allocator, types.Rect.init(cx - 1, header_rect.y, 1, style.header_height), style.border) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidCommand => return error.InvalidCommand,
            };
        }
    }

    // Clip do corpo
    ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = body, .null_rect = false } }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };

    // Linhas visíveis
    var i = first_visible;
    while (i < last_visible) : (i += 1) {
        const y = body.y + @as(f32, @floatFromInt(i)) * style.row_height - scroll_offset.*;
        const row_rect = types.Rect.init(bounds.x, y, bounds.w, style.row_height);
        const is_selected = i == selected.*;
        const is_hovered = res.hovered_index == i and !is_selected;

        const bg = if (is_selected)
            style.bg_selected
        else if (is_hovered)
            style.bg_hover
        else if (i % 2 == 0)
            style.bg
        else
            style.bg_alt;
        ctx.draw.rectFilled(ctx.allocator, row_rect, bg) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
        };

        const text_color = if (is_selected) style.text_selected else style.text;
        const row = rows[i];
        var cx2: f32 = bounds.x;
        for (columns, 0..) |col, j| {
            if (j < row.cells.len and row.cells[j].len > 0) {
                ctx.draw.pushText(
                    ctx.allocator,
                    .{ .x = cx2 + style.padding_x, .y = y + (style.row_height - font.lineHeight()) / 2 },
                    text_color,
                    font,
                    row.cells[j],
                ) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InvalidCommand => return error.InvalidCommand,
                    error.InvalidUtf8 => return error.InvalidArgument,
                    error.InvalidMetrics => return error.InvalidArgument,
                };
            }
            cx2 += col.width;
            if (j + 1 < columns.len) {
                ctx.draw.rectFilled(ctx.allocator, types.Rect.init(cx2 - 1, y, 1, style.row_height), style.border) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InvalidCommand => return error.InvalidCommand,
                };
            }
        }
    }

    // Pop clip (volta antes do scrollbar/outline)
    ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = .{}, .null_rect = true } }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };

    // Scrollbar no corpo
    const content_h = tableContentHeight(rows, style);
    if (content_h > body.h) {
        const thumb_h = @max(20, body.h * body.h / content_h);
        const thumb_y = body.y + (body.h - thumb_h) * (scroll_offset.* / max_scroll);
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

    res.scroll_offset = scroll_offset.*;
    return res;
}

/// Fim da tabela (M62): NO-OP — sem estado retido, sem draws.
/// Existe apenas para simetria de pareamento com outros widgets.
pub fn endTable(_: *context_mod.Context) void {}

test "Table seleciona, navega, rola e valida contratos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().tableStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 150); // header 26 → corpo 124
    const id = id_mod.Id.fromString("test:table");
    var selected: usize = 0;
    var scroll: f32 = 0;

    const columns = [_]TableColumn{
        .{ .title = "Nome", .width = 120 },
        .{ .title = "Idade", .width = 60 },
    };
    const r0cells = [_][]const u8{ "Ana", "30" };
    const r1cells = [_][]const u8{ "Bia", "25" };
    const r2cells = [_][]const u8{ "Caio", "41" };
    const rows = [_]TableRow{
        .{ .cells = &r0cells },
        .{ .cells = &r1cells },
        .{ .cells = &r2cells },
        .{ .cells = &r1cells },
        .{ .cells = &r2cells },
        .{ .cells = &r0cells },
        .{ .cells = &r1cells },
        .{ .cells = &r2cells },
    };

    // Helpers puros.
    try stdt.testing.expectEqual(@as(f32, 192), tableContentHeight(&rows, style));
    try stdt.testing.expectEqual(@as(f32, 68), tableMaxScroll(&rows, 124, style));
    try stdt.testing.expectEqual(@as(f32, 180), tableColumnsWidth(&columns));
    try stdt.testing.expectEqual(@as(f32, 26), tableBodyRect(bounds, style).y);

    // Click na 2ª linha (y=60 → corpo rel 34 → índice 1) foca + seleciona.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(100, 60) },
    });
    const c0 = try beginTable(&ctx, id, bounds, &columns, &rows, &selected, &scroll, style);
    try stdt.testing.expect(c0.changed);
    try stdt.testing.expectEqual(@as(usize, 1), selected);
    try stdt.testing.expect(ctx.hasFocus(id));
    ctx.endFrame();

    // Down → 2.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    const c1 = try beginTable(&ctx, id, bounds, &columns, &rows, &selected, &scroll, style);
    try stdt.testing.expect(c1.changed);
    try stdt.testing.expectEqual(@as(usize, 2), selected);
    ctx.endFrame();

    // End → último.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{} } });
    _ = try beginTable(&ctx, id, bounds, &columns, &rows, &selected, &scroll, style);
    try stdt.testing.expectEqual(@as(usize, 7), selected);
    ctx.endFrame();

    // Home → primeiro.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    _ = try beginTable(&ctx, id, bounds, &columns, &rows, &selected, &scroll, style);
    try stdt.testing.expectEqual(@as(usize, 0), selected);
    ctx.endFrame();

    // Wheel no corpo rola (dy negativo = para baixo).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = -3, .pos = types.Vec2.init(100, 100) } });
    const c2 = try beginTable(&ctx, id, bounds, &columns, &rows, &selected, &scroll, style);
    try stdt.testing.expect(c2.scroll_offset > 0);
    ctx.endFrame();

    // Contratos inválidos.
    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, beginTable(&ctx, .null, bounds, &columns, &rows, &selected, &scroll, style));
    try stdt.testing.expectError(error.InvalidArgument, beginTable(&ctx, id, types.Rect.init(0, 0, 0, 0), &columns, &rows, &selected, &scroll, style));
    // Corpo degenerado: h <= header_height.
    try stdt.testing.expectError(error.InvalidArgument, beginTable(&ctx, id, types.Rect.init(0, 0, 200, 26), &columns, &rows, &selected, &scroll, style));
    try stdt.testing.expectError(error.InvalidArgument, beginTable(&ctx, id, bounds, &[_]TableColumn{}, &rows, &selected, &scroll, style));
    try stdt.testing.expectError(error.InvalidArgument, beginTable(&ctx, id, bounds, &rows_bad_cols, &rows, &selected, &scroll, style));
    try stdt.testing.expectError(error.InvalidArgument, beginTable(&ctx, id, bounds, &columns, &[_]TableRow{}, &selected, &scroll, style));
    const bad_style = style_mod.TableStyle{
        .bg = .{},
        .bg_alt = .{},
        .bg_selected = .{},
        .bg_hover = .{},
        .text = .{},
        .text_header = .{},
        .text_selected = .{},
        .border = .{},
        .border_width = 1,
        .row_height = 0,
        .header_height = 26,
        .padding_x = 8,
    };
    try stdt.testing.expectError(error.InvalidArgument, beginTable(&ctx, id, bounds, &columns, &rows, &selected, &scroll, bad_style));
    ctx.endFrame();
}

const rows_bad_cols = [_]TableColumn{
    .{ .title = "X", .width = 50 },
    .{ .title = "Y", .width = -1 },
};

test "Table uma linha: click, teclado nos limites, scroll zerado" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().tableStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 50); // corpo h = 24
    const id = id_mod.Id.fromString("test:table-one");
    const columns = [_]TableColumn{.{ .title = "Nome", .width = 120 }};
    const c0 = [_][]const u8{"só"};
    const rows = [_]TableRow{.{ .cells = &c0 }};
    var selected: usize = 0;
    var scroll: f32 = 9999; // além do máximo (0) → clampa

    // Click na única linha seleciona (já era 0) e foca; scroll clampa.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(100, 30) },
    });
    const r0 = try beginTable(&ctx, id, bounds, &columns, &rows, &selected, &scroll, style);
    try stdt.testing.expectEqual(@as(usize, 0), selected);
    try stdt.testing.expectEqual(@as(f32, 0), scroll);
    try stdt.testing.expectEqual(@as(f32, 0), r0.scroll_offset);
    try stdt.testing.expect(ctx.hasFocus(id));
    ctx.endFrame();

    // Teclado nos limites: Up/Down/PageUp/PageDown não saem da linha 0.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .up, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .page_up, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .page_down, .pressed = true, .modifiers = .{} } });
    const r1 = try beginTable(&ctx, id, bounds, &columns, &rows, &selected, &scroll, style);
    try stdt.testing.expect(!r1.changed);
    try stdt.testing.expectEqual(@as(usize, 0), selected);
    ctx.endFrame();
}

test "Table wheel extremo clampa; scroll/bounds NaN rejeitados" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().tableStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 150); // corpo 124, máx 68
    const id = id_mod.Id.fromString("test:table-wheel");
    const columns = [_]TableColumn{.{ .title = "N", .width = 120 }};
    const ca = [_][]const u8{"a"};
    const rows = [_]TableRow{ .{ .cells = &ca }, .{ .cells = &ca }, .{ .cells = &ca }, .{ .cells = &ca }, .{ .cells = &ca }, .{ .cells = &ca }, .{ .cells = &ca }, .{ .cells = &ca } };
    var selected: usize = 0;
    var scroll: f32 = 0;

    // Wheel finito extremo para baixo: sem pânico, clampa no máximo.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = -1e30, .pos = types.Vec2.init(100, 100) } });
    const r0 = try beginTable(&ctx, id, bounds, &columns, &rows, &selected, &scroll, style);
    try stdt.testing.expectEqual(@as(f32, 68), scroll);
    try stdt.testing.expectEqual(@as(f32, 68), r0.scroll_offset);
    ctx.endFrame();

    // Wheel finito extremo para cima: clampa no zero.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = 1e30, .pos = types.Vec2.init(100, 100) } });
    _ = try beginTable(&ctx, id, bounds, &columns, &rows, &selected, &scroll, style);
    try stdt.testing.expectEqual(@as(f32, 0), scroll);
    ctx.endFrame();

    // Scroll do chamador não-finito e bounds não-finitos: InvalidArgument.
    var nan_scroll: f32 = std.math.nan(f32);
    try stdt.testing.expectError(error.InvalidArgument, beginTable(&ctx, id, bounds, &columns, &rows, &selected, &nan_scroll, style));
    const nan_bounds = types.Rect.init(0, 0, std.math.nan(f32), 150);
    try stdt.testing.expectError(error.InvalidArgument, beginTable(&ctx, id, nan_bounds, &columns, &rows, &selected, &scroll, style));
}

test "Table encolhe linhas, área pequena e última linha por click" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().tableStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:table-shrink");
    const columns = [_]TableColumn{.{ .title = "N", .width = 120 }};
    const ca = [_][]const u8{"a"};
    const cb = [_][]const u8{"b"};
    const rows8 = [_]TableRow{ .{ .cells = &ca }, .{ .cells = &cb }, .{ .cells = &ca }, .{ .cells = &cb }, .{ .cells = &ca }, .{ .cells = &cb }, .{ .cells = &ca }, .{ .cells = &cb } };
    const rows2 = [_]TableRow{ .{ .cells = &ca }, .{ .cells = &cb } };
    var selected: usize = 7;
    var scroll: f32 = 0;

    // Seleção além do novo tamanho é clampada (sem estado corrompido).
    ctx.beginFrame();
    const r0 = try beginTable(&ctx, id, types.Rect.init(0, 0, 200, 150), &columns, rows8[0..8], &selected, &scroll, style);
    try stdt.testing.expectEqual(@as(usize, 7), r0.selected);
    ctx.endFrame();
    ctx.beginFrame();
    const r1 = try beginTable(&ctx, id, types.Rect.init(0, 0, 200, 150), &columns, rows2[0..2], &selected, &scroll, style);
    try stdt.testing.expectEqual(@as(usize, 1), selected);
    try stdt.testing.expectEqual(@as(usize, 1), r1.selected);
    ctx.endFrame();

    // Área pequena (corpo h=1): desenha com clip pareado, sem crash.
    selected = 0;
    scroll = 0;
    ctx.beginFrame();
    _ = try beginTable(&ctx, id, types.Rect.init(0, 0, 200, 27), &columns, rows8[0..8], &selected, &scroll, style);
    var saw_clip = false;
    for (ctx.drawCommands()) |cmd| {
        if (cmd == .clip and !cmd.clip.null_rect) saw_clip = true;
    }
    try stdt.testing.expect(saw_clip);
    ctx.endFrame();

    // Última linha por click com scroll no máximo (linha 7 em y=138).
    selected = 0;
    scroll = 68;
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(100, 138) },
    });
    _ = try beginTable(&ctx, id, types.Rect.init(0, 0, 200, 150), &columns, rows8[0..8], &selected, &scroll, style);
    try stdt.testing.expectEqual(@as(usize, 7), selected);
    ctx.endFrame();
}
