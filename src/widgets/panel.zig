//! ZyntraUI — painel acoplável com cabeçalho (widgets/panel).
//!
//! Modelo M74 (Docking, passo 1): o *shell* de um painel de ferramentas.
//! É a peça básica para docking (M75+): cabeçalho com título + controles
//! de colapso e fechar, devolvendo o rect de conteúdo para o chamador
//! posicionar os filhos (mesmo padrão de groupbox/toolbar/statusbar).
//!
//! - `collapsed: *bool` — estado no chamador (padrão ImGui-like).
//!   O painel NÃO redimensiona `bounds`: quando colapsado, só o
//!   cabeçalho é desenhado e `content` volta zerado, deixando a área
//!   inferior para o pai (útil para animação de colapso).
//! - Controles no cabeçalho (press captura, release dentro aciona):
//!   chevron à direita alterna `collapsed` (`toggled`); `×` (quando
//!   `closable`) apenas reporta `close_requested` — o ciclo de vida
//!   (esconder/remover) é do chamador.
//! - Teclado com foco: Espaço/Enter alternam o colapso; Tab circula.
//! - `PanelStyle` + `Theme.panelStyle()` — cores, padding, controles.
//!
//! Não é um docking completo (sem arraste nem aninhamento automático):
//! combine com `splitter`/`splitterPanes` para dividir a área.
//! `id` não-nulo obrigatório; `bounds` finito e positivo.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const metrics_mod = @import("../text/metrics.zig");
const input = @import("input.zig");

pub const PanelOptions = struct {
    title: []const u8,
    /// Desenha o chevron e permite colapsar (mouse + teclado).
    collapsible: bool = true,
    /// Desenha o `×` e reporta `close_requested`.
    closable: bool = false,
};

pub const PanelResult = struct {
    /// Área útil para o conteúdo (zerada quando colapsado).
    content: types.Rect = .{},
    collapsed: bool = false,
    /// Colapso alternado neste frame (chevron ou teclado).
    toggled: bool = false,
    /// Botão fechar acionado (o chamador decide o que fazer).
    close_requested: bool = false,
    hovered: bool = false,
};

/// Altura do cabeçalho: `lineHeight + 2*header_pad`, clampada a `bounds.h`.
/// Pura; fonte inválida ⇒ só a altura do padding.
pub fn panelHeaderHeight(bounds: types.Rect, font: metrics_mod.FontMetrics, style: style_mod.PanelStyle) f32 {
    const lh: f32 = if (font.isValid()) font.lineHeight() else 0;
    return @max(0, @min(bounds.h, lh + style.header_pad * 2));
}

/// Rect do controle `index` (0 = chevron, 1 = close), contado da direita.
/// Pura (usada para desenho e hit-test).
pub fn panelControlRect(
    bounds: types.Rect,
    header_h: f32,
    index: usize,
    style: style_mod.PanelStyle,
) types.Rect {
    const s = style.control_size;
    const right = bounds.x + bounds.w - style.padding_x - @as(f32, @floatFromInt(index)) * s;
    const y = bounds.y + @max(0, (header_h - s) / 2);
    return .{ .x = right - s, .y = y, .w = s, .h = @min(s, @max(0, bounds.h - (y - bounds.y))) };
}

/// Área útil do conteúdo: `bounds` menos o cabeçalho e o padding.
fn bodyContent(bounds: types.Rect, header_h: f32, style: style_mod.PanelStyle) types.Rect {
    const by = bounds.y + header_h;
    const bh = @max(0, bounds.h - header_h);
    return .{
        .x = bounds.x + style.padding_x,
        .y = by + style.padding_y,
        .w = @max(0, bounds.w - style.padding_x * 2),
        .h = @max(0, bh - style.padding_y * 2),
    };
}

pub fn panel(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    collapsed: *bool,
    opts: PanelOptions,
    font: metrics_mod.FontMetrics,
    style: style_mod.PanelStyle,
) context_mod.ContextError!PanelResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid() or !font.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;

    const header_h = panelHeaderHeight(bounds, font, style);
    const header = types.Rect{ .x = bounds.x, .y = bounds.y, .w = bounds.w, .h = header_h };
    // Controle 0 = chevron (sempre visível); 1 = close (se closable).
    const chev = panelControlRect(bounds, header_h, 0, style);
    const close = if (opts.closable) panelControlRect(bounds, header_h, 1, style) else null;

    // Título medido/truncado ANTES de desenhar: reporta UTF-8 inválido sem
    // deixar um clip desemparelhado e impede o texto de invadir os controles.
    var title_slice: []const u8 = &.{};
    if (opts.title.len > 0 and header_h > 0) {
        const cols: f32 = if (opts.closable) 2 else 1;
        const avail = @max(0, bounds.w - style.padding_x * 2 - cols * (style.control_size + 4));
        const n = metrics_mod.truncateToWidth(opts.title, font, avail) catch |err| switch (err) {
            error.InvalidMetrics, error.InvalidArgument, error.InvalidUtf8 => return error.InvalidArgument,
        };
        title_slice = opts.title[0..n];
    }

    const fm = input.FrameMouse.scan(ctx.pendingEvents());
    const hovered = if (ctx.mouse_pos) |p| bounds.contains(p) else false;
    var res = PanelResult{ .hovered = hovered, .collapsed = collapsed.* };

    try ctx.registerFocusable(id);
    if (fm.pressedInside(header)) ctx.focus_owner = id;

    const on_chev = opts.collapsible and fm.pressedInside(chev);
    const on_close = if (close) |c| fm.pressedInside(c) else false;
    if (ctx.press_owner == null and (on_chev or on_close)) {
        ctx.press_owner = id;
    }
    if (ctx.press_owner == id) {
        if (fm.released_pos) |p| {
            if (opts.collapsible and chev.contains(p)) {
                collapsed.* = !collapsed.*;
                res.toggled = true;
            } else if (close) |c| {
                if (c.contains(p)) res.close_requested = true;
            }
            ctx.press_owner = null;
        }
    }

    if (ctx.hasFocus(id)) {
        for (ctx.pendingEvents()) |ev| {
            if (ev != .key) continue;
            const k = ev.key;
            if (!k.pressed or k.modifiers.ctrl) continue;
            switch (k.key) {
                .space, .enter => {
                    if (opts.collapsible) {
                        collapsed.* = !collapsed.*;
                        res.toggled = true;
                    }
                },
                .tab => ctx.requestFocusAdvance(if (k.modifiers.shift) .prev else .next),
                else => {},
            }
        }
    }
    res.collapsed = collapsed.*;

    // Painel enquadrado: só o cabeçalho quando colapsado.
    const frame = if (collapsed.*) header else bounds;

    // Clip local (pareado como menu/popup) para o título não invadir
    // os controles.
    try ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = bounds, .null_rect = false } });

    if (!collapsed.* and style.bg.a > 0) {
        try fill(ctx, types.Rect{ .x = bounds.x, .y = bounds.y + header_h, .w = bounds.w, .h = @max(0, bounds.h - header_h) }, style.bg);
    }
    if (style.header_bg.a > 0) try fill(ctx, header, style.header_bg);
    if (style.border_width > 0) {
        try outline(ctx, frame, style.border, style.border_width);
    }
    if (!collapsed.* and style.separator.a > 0 and header_h > 0) {
        const sy = bounds.y + header_h;
        try line(ctx, types.Vec2.init(bounds.x, sy), types.Vec2.init(bounds.x + bounds.w, sy), style.separator, 1.0);
    }
    if (title_slice.len > 0) {
        const lh = font.lineHeight();
        const ty = bounds.y + @max(0, (header_h - lh) / 2);
        ctx.pushText(
            .{ .x = bounds.x + style.padding_x, .y = ty },
            style.title,
            font,
            title_slice,
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
            error.InvalidMetrics, error.InvalidUtf8 => return error.InvalidArgument,
        };
    }
    if (opts.collapsible) {
        if (ctx.mouse_pos) |mp| {
            if (chev.contains(mp) and style.control_hover.a > 0) try fill(ctx, chev, style.control_hover);
        }
        try chevronGlyph(ctx, chev, collapsed.*, style.control);
    }
    if (close) |c| {
        if (ctx.mouse_pos) |mp| {
            if (c.contains(mp) and style.control_hover.a > 0) try fill(ctx, c, style.control_hover);
        }
        try closeGlyph(ctx, c, style.control);
    }

    try ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = .{}, .null_rect = true } });

    res.content = if (collapsed.*) .{} else bodyContent(bounds, header_h, style);
    return res;
}

fn fill(ctx: *context_mod.Context, r: types.Rect, color: types.Color) context_mod.ContextError!void {
    ctx.draw.rectFilled(ctx.allocator, r, color) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
}

fn outline(ctx: *context_mod.Context, r: types.Rect, color: types.Color, w: f32) context_mod.ContextError!void {
    ctx.draw.rectOutline(ctx.allocator, r, color, @max(1.0, w)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
}

fn line(ctx: *context_mod.Context, p0: types.Vec2, p1: types.Vec2, color: types.Color, t: f32) context_mod.ContextError!void {
    ctx.draw.line(ctx.allocator, p0, p1, color, t) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
}

/// Chevron: 2 segmentos formando `⌄` (expandido) ou `›` (colapsado).
fn chevronGlyph(ctx: *context_mod.Context, r: types.Rect, collapsed: bool, color: types.Color) context_mod.ContextError!void {
    const cx = r.x + r.w / 2;
    const cy = r.y + r.h / 2;
    const s: f32 = @min(r.w, r.h) * 0.22;
    if (collapsed) {
        try line(ctx, types.Vec2.init(cx - s * 0.5, cy - s), types.Vec2.init(cx + s * 0.5, cy), color, 1.5);
        try line(ctx, types.Vec2.init(cx + s * 0.5, cy), types.Vec2.init(cx - s * 0.5, cy + s), color, 1.5);
    } else {
        try line(ctx, types.Vec2.init(cx - s, cy - s * 0.5), types.Vec2.init(cx, cy + s * 0.5), color, 1.5);
        try line(ctx, types.Vec2.init(cx, cy + s * 0.5), types.Vec2.init(cx + s, cy - s * 0.5), color, 1.5);
    }
}

/// Cruz `×`: 2 segmentos diagonais.
fn closeGlyph(ctx: *context_mod.Context, r: types.Rect, color: types.Color) context_mod.ContextError!void {
    const cx = r.x + r.w / 2;
    const cy = r.y + r.h / 2;
    const s: f32 = @min(r.w, r.h) * 0.24;
    try line(ctx, types.Vec2.init(cx - s, cy - s), types.Vec2.init(cx + s, cy + s), color, 1.5);
    try line(ctx, types.Vec2.init(cx + s, cy - s), types.Vec2.init(cx - s, cy + s), color, 1.5);
}

test "panel: geometria, conteúdo e hit-test dos controles" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().panelStyle();
    const font = metrics_mod.FontMetrics.withSize(10); // lh=10.625
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(10, 20, 200, 120);
    const id = id_mod.Id.fromString("test:panel");
    var collapsed = false;

    // Altura do cabeçalho: lh + 12 = 22.625.
    const hh = panelHeaderHeight(bounds, font, style);
    try stdt.testing.expectApproxEqAbs(@as(f32, 22.625), hh, 0.001);
    // Conteúdo: y = 20 + 22.625 + 8; w = 200 - 16.
    const content = bodyContent(bounds, hh, style);
    try stdt.testing.expectApproxEqAbs(@as(f32, 50.625), content.y, 0.001);
    try stdt.testing.expectEqual(@as(f32, 184), content.w);

    // Chevron é o controle 0, encostado à direita (padding_x=8).
    const chev = panelControlRect(bounds, hh, 0, style);
    try stdt.testing.expectEqual(@as(f32, 10 + 200 - 8 - 18), chev.x);
    try stdt.testing.expectEqual(@as(f32, 18), chev.w);

    // Release no chevron após press: alterna o colapso.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(chev.x + 4, chev.y + 4) },
    });
    _ = try panel(&ctx, id, bounds, &collapsed, .{ .title = "Camadas" }, font, style);
    try stdt.testing.expect(!collapsed);
    try stdt.testing.expectEqual(@as(?id_mod.Id, id), ctx.press_owner);
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(chev.x + 4, chev.y + 4) },
    });
    const r1 = try panel(&ctx, id, bounds, &collapsed, .{ .title = "Camadas" }, font, style);
    try stdt.testing.expect(r1.toggled and collapsed);
    try stdt.testing.expectEqual(types.Rect{}, r1.content);
    try stdt.testing.expect(ctx.press_owner == null);
    ctx.endFrame();

    // Colapsado: só o cabeçalho é enquadrado (borda sobre `header`).
    const cmd = ctx.drawCommands();
    var frames: usize = 0;
    for (cmd) |c| {
        if (c == .rect_outline) {
            frames += 1;
            try stdt.testing.expectEqual(hh, c.rect_outline.rect.h);
        }
    }
    try stdt.testing.expectEqual(@as(usize, 1), frames);

    // Sem `closable`, o `×` não é desenhado (só chevron = 2 segmentos).
    var lines: usize = 0;
    for (cmd) |c| {
        if (c == .line) lines += 1;
    }
    // separador (1) não existe colapsado; chevron = 2.
    try stdt.testing.expectEqual(@as(usize, 2), lines);
}

test "panel: close reporta sem alternar colapso" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().panelStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 120);
    const id = id_mod.Id.fromString("test:panel-close");
    var collapsed = false;

    const hh = panelHeaderHeight(bounds, font, style);
    const close = panelControlRect(bounds, hh, 1, style);

    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(close.x + 4, close.y + 4) },
    });
    _ = try panel(&ctx, id, bounds, &collapsed, .{ .title = "T", .closable = true }, font, style);
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(close.x + 4, close.y + 4) },
    });
    const r = try panel(&ctx, id, bounds, &collapsed, .{ .title = "T", .closable = true }, font, style);
    try stdt.testing.expect(r.close_requested);
    try stdt.testing.expect(!r.toggled and !collapsed);
    // Expande: separador + borda sobre `bounds`.
    var sep = false;
    for (ctx.drawCommands()) |c| {
        if (c == .line and c.line.p0.y == hh) sep = true;
    }
    try stdt.testing.expect(sep);
    ctx.endFrame();
}

test "panel: teclado alterna e casos inválidos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().panelStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 120);
    const id = id_mod.Id.fromString("test:panel-kb");
    var collapsed = false;

    // Foca clicando no título (fora dos controles) e alterna com Espaço.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(30, 10) },
    });
    _ = try panel(&ctx, id, bounds, &collapsed, .{ .title = "T" }, font, style);
    try stdt.testing.expect(ctx.hasFocus(id));
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .space, .pressed = true, .modifiers = .{} } });
    const r1 = try panel(&ctx, id, bounds, &collapsed, .{ .title = "T" }, font, style);
    try stdt.testing.expect(r1.toggled and collapsed);
    ctx.endFrame();

    ctx.beginFrame();
    const nan_b = types.Rect.init(0, 0, std.math.nan(f32), 120);
    try stdt.testing.expectError(error.InvalidArgument, panel(&ctx, id, nan_b, &collapsed, .{ .title = "T" }, font, style));
    try stdt.testing.expectError(error.InvalidArgument, panel(&ctx, .null, bounds, &collapsed, .{ .title = "T" }, font, style));
    var bad = style;
    bad.control_size = 0;
    try stdt.testing.expectError(error.InvalidArgument, panel(&ctx, id, bounds, &collapsed, .{ .title = "T" }, font, bad));
    try stdt.testing.expectError(error.InvalidArgument, panel(&ctx, id, bounds, &collapsed, .{ .title = "\xff" }, font, style));
    ctx.endFrame();
}

test "panel: colapsável falso ignora chevron e teclado" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().panelStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 120);
    const id = id_mod.Id.fromString("test:panel-nocollapse");
    var collapsed = false;
    const hh = panelHeaderHeight(bounds, font, style);
    const chev = panelControlRect(bounds, hh, 0, style);

    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(chev.x + 4, chev.y + 4) },
    });
    _ = try panel(&ctx, id, bounds, &collapsed, .{ .title = "T", .collapsible = false }, font, style);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(chev.x + 4, chev.y + 4) },
    });
    const r = try panel(&ctx, id, bounds, &collapsed, .{ .title = "T", .collapsible = false }, font, style);
    try stdt.testing.expect(!r.toggled and !collapsed);
    // Sem chevron desenhado: nenhuma linha de glifo (só separador).
    var glyphs: usize = 0;
    for (ctx.drawCommands()) |c| {
        if (c == .line and c.line.p0.y != hh) glyphs += 1;
    }
    try stdt.testing.expectEqual(@as(usize, 0), glyphs);
    ctx.endFrame();
}
