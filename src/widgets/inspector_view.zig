//! ZyntraUI — property inspector (widgets/inspector_view).
//!
//! Modelo M96 (visualização + edição) sobre o modelo puro
//! `inspector/view`. O estado (linha ativa, rolagem e arraste) pertence
//! ao chamador e é retido entre frames (`InspectorViewState`); os
//! VALORES ficam na memória do chamador (`inspector/view.Value`).
//!
//! Layout: uma linha por propriedade (`row_height`); a coluna de nomes
//! (`name_width`) à esquerda e a coluna de valores à direita.
//!
//! Interação (mouse):
//! - Press numa linha ativa-a e captura (`press_owner`); se o valor for
//!   numérico e editável, inicia o arraste horizontal (passo por pixel,
//!   com clamp na faixa) a partir do valor no clique.
//! - Boolean alterna no press (a linha inteira é a área de clique).
//! - Escolha avança uma opção no press (circula).
//! - Roda com hover: rolagem vertical (`scroll_step` por entrelinha),
//!   clampada em `[0, maxScroll]`.
//! - Teclado com foco: setas ↑/↓ movem a linha ativa (trazendo-a para a
//!   vista), ←/→ ajustam o valor (Shift = grosso, Alt = fino; inteiros
//!   arredondam), Espaço/Enter alternam boolean e avançam escolha, Tab
//!   circula o foco.
//! - Modificadores de mouse não são observáveis (o evento não os expõe):
//!   grosso/fino valem só no teclado.
//! - Desenho: fundo, linhas (alternadas/ativa), realce do editor em
//!   hover/arraste, separadores, nomes e editores (caixa de bool,
//!   número formatado, opção da escolha ou texto somente-leitura). Tudo
//!   clipado em `bounds`.
//! - `id` não-nulo obrigatório; `properties` vazio é aceito (inspector
//!   sem seleção); índices fora de faixa em `state` são descartados.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const metrics_mod = @import("../text/metrics.zig");
const inspector_mod = @import("../inspector/view.zig");
const input = @import("input.zig");

/// Estado do inspector (dono: chamador; retido entre frames).
pub const InspectorViewState = struct {
    /// Linha ativa (`null` = nenhuma).
    active: ?usize = null,
    /// Rolagem vertical em px (clampada em `[0, maxScroll]`).
    scroll: f32 = 0.0,
    /// Linha com arraste numérico em andamento. Transiente.
    dragging: ?usize = null,
    /// Valor no início do arraste. Transiente.
    drag_anchor: f32 = 0.0,
    /// X de tela no início do arraste. Transiente.
    drag_x: f32 = 0.0,
};

/// Opções de edição do inspector.
pub const InspectorViewOptions = struct {
    /// Incremento por pixel de arraste em reais (> 0).
    step: f32 = 0.01,
    /// Casas decimais padrão de reais (<= `inspector/view.max_decimals`).
    decimals: u32 = 3,
    /// Rolagem por entrelinha da roda em px (>= 0).
    scroll_step: f32 = 24.0,
    /// Fator do passo com Shift (grosso; >= 1).
    coarse_factor: f32 = 10.0,
    /// Fator do passo com Alt (fino; `0 < f <= 1`).
    fine_factor: f32 = 0.1,

    pub fn isValid(self: InspectorViewOptions) bool {
        if (!std.math.isFinite(self.step) or self.step <= 0) return false;
        if (self.decimals > inspector_mod.max_decimals) return false;
        if (!std.math.isFinite(self.scroll_step) or self.scroll_step < 0) return false;
        if (!std.math.isFinite(self.coarse_factor) or self.coarse_factor < 1) return false;
        if (!std.math.isFinite(self.fine_factor) or !(self.fine_factor > 0) or
            self.fine_factor > 1) return false;
        return true;
    }
};

/// Resultado do frame.
pub const InspectorViewResult = struct {
    /// Linha sob o cursor (dentro de `bounds`), se houver.
    hovered: ?usize = null,
    /// Linha ativa ao fim do frame.
    active: ?usize = null,
    /// A linha ativa mudou neste frame.
    active_changed: bool = false,
    /// Índice da propriedade cujo VALOR mudou neste frame.
    changed: ?usize = null,
    /// Linha com arraste numérico ativo neste frame.
    dragging: ?usize = null,
    /// Rolagem aplicada neste frame (px).
    scroll_delta: f32 = 0.0,
    /// A rolagem mudou neste frame.
    scrolled: bool = false,
};

fn fill(
    ctx: *context_mod.Context,
    r: types.Rect,
    color: types.Color,
) context_mod.ContextError!void {
    try ctx.draw.rectFilled(ctx.allocator, r, color);
}

fn pushLabel(
    ctx: *context_mod.Context,
    pos: types.Vec2,
    color: types.Color,
    font: metrics_mod.FontMetrics,
    text: []const u8,
) context_mod.ContextError!void {
    ctx.draw.pushText(ctx.allocator, pos, color, font, text) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
        error.InvalidMetrics, error.InvalidUtf8 => return error.InvalidArgument,
    };
}

/// Desenha e edita uma lista de propriedades em `bounds`.
/// Ver o cabeçalho do módulo para semântica de ativação/arraste/teclado.
pub fn inspectorView(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    properties: []const inspector_mod.Property,
    state: *InspectorViewState,
    options: InspectorViewOptions,
    style: style_mod.InspectorStyle,
    font: metrics_mod.FontMetrics,
) context_mod.ContextError!InspectorViewResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid() or !font.isValid() or !options.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;
    if (!std.math.isFinite(state.scroll)) return error.InvalidArgument;
    for (properties) |p| {
        if (!p.isValid()) return error.InvalidArgument;
    }

    // Sanidade: índices de escolha dentro da faixa; linha ativa existente.
    for (properties) |p| {
        switch (p.value) {
            .choice => |ch| {
                if (ch.index.* >= ch.options.len) {
                    ch.index.* = @intCast(ch.options.len - 1);
                }
            },
            else => {},
        }
    }
    if (state.active) |a| {
        if (a >= properties.len) state.active = null;
    }
    if (state.dragging) |d| {
        if (d >= properties.len) state.dragging = null;
    }

    const row_h = style.row_height;
    const name_w = std.math.clamp(style.name_width, 0, bounds.w);
    const value_x = bounds.x + name_w;
    const value_w = bounds.w - name_w;
    const max_scroll = inspector_mod.maxScroll(properties.len, bounds.h, row_h);
    state.scroll = std.math.clamp(state.scroll, 0, max_scroll);

    var res = InspectorViewResult{ .active = state.active };
    const fm = input.FrameMouse.scan(ctx.pendingEvents());
    const inside = if (ctx.mouse_pos) |p| bounds.contains(p) else false;
    try ctx.registerFocusable(id);

    // Hover: linha sob o cursor.
    if (inside) {
        if (ctx.mouse_pos) |p| {
            const y_local = p.y - bounds.y + state.scroll;
            res.hovered = inspector_mod.rowAtY(y_local, row_h, properties.len);
        }
    }

    // Press: ativa a linha e (se numérica editável) inicia o arraste.
    if (ctx.press_owner == null and fm.pressedInside(bounds)) {
        if (ctx.mouse_pos) |p| {
            const y_local = p.y - bounds.y + state.scroll;
            if (inspector_mod.rowAtY(y_local, row_h, properties.len)) |i| {
                ctx.press_owner = id;
                ctx.focus_owner = id;
                if (state.active != i) {
                    state.active = i;
                    res.active = i;
                    res.active_changed = true;
                }
                const prop = properties[i];
                if (!prop.readonly) {
                    switch (prop.value) {
                        .boolean => |bp| {
                            bp.* = !bp.*;
                            res.changed = i;
                        },
                        .choice => |ch| {
                            if (inspector_mod.cycleIndex(ch.index.*, ch.options.len, 1)) |ni| {
                                if (ni != ch.index.*) {
                                    ch.index.* = ni;
                                    res.changed = i;
                                }
                            }
                        },
                        .integer, .real => {
                            state.dragging = i;
                            state.drag_anchor = switch (prop.value) {
                                .integer => |ip| @as(f32, @floatFromInt(ip.*)),
                                .real => |rp| rp.*,
                                else => 0,
                            };
                            state.drag_x = p.x;
                        },
                        .text => {},
                    }
                }
            }
        }
    }

    // Arraste numérico (enquanto dono da captura).
    if (ctx.press_owner == id) {
        if (ctx.mouse_down_left) {
            if (state.dragging) |i| {
                if (ctx.mouse_pos) |p| {
                    res.dragging = i;
                    const prop = properties[i];
                    const step = prop.effectiveStep(options.step);
                    const raw = inspector_mod.dragValue(state.drag_anchor, p.x - state.drag_x, step);
                    const v = inspector_mod.clampToRange(raw, prop.range);
                    switch (prop.value) {
                        .integer => |ip| {
                            const nv = inspector_mod.toInt(v);
                            if (nv != ip.*) {
                                ip.* = nv;
                                res.changed = i;
                            }
                        },
                        .real => |rp| {
                            if (v != rp.*) {
                                rp.* = v;
                                res.changed = i;
                            }
                        },
                        else => {},
                    }
                }
            }
        }
        if (fm.released_pos != null) {
            ctx.press_owner = null;
            state.dragging = null;
            res.dragging = null;
        }
    }

    // Roda com hover: rolagem vertical.
    if (inside and options.scroll_step > 0) {
        for (ctx.pendingEvents()) |ev| {
            if (ev != .mouse_wheel) continue;
            const w = ev.mouse_wheel;
            if (w.dy == 0) continue;
            const before = state.scroll;
            state.scroll = std.math.clamp(
                state.scroll - w.dy * options.scroll_step,
                0,
                max_scroll,
            );
            if (state.scroll != before) {
                res.scroll_delta = state.scroll - before;
                res.scrolled = true;
            }
        }
    }

    // Teclado com foco: navegação + edição.
    if (ctx.hasFocus(id) and properties.len > 0) {
        for (ctx.pendingEvents()) |ev| {
            if (ev != .key) continue;
            const k = ev.key;
            if (!k.pressed or k.modifiers.ctrl) continue;
            switch (k.key) {
                .up, .down => {
                    const last = properties.len - 1;
                    const next: usize = if (state.active) |a|
                        if (k.key == .up) a -| 1 else @min(a + 1, last)
                    else
                        0;
                    if (state.active == null or state.active.? != next) {
                        state.active = next;
                        res.active = next;
                        res.active_changed = true;
                    }
                    // Traz a linha ativa para a vista.
                    const top = @as(f32, @floatFromInt(next)) * row_h;
                    if (top < state.scroll) {
                        state.scroll = top;
                    } else if (top + row_h > state.scroll + bounds.h) {
                        state.scroll = top + row_h - bounds.h;
                    }
                    state.scroll = std.math.clamp(state.scroll, 0, max_scroll);
                },
                .left, .right => {
                    if (state.active) |i| {
                        const prop = properties[i];
                        if (!prop.readonly) {
                            const dir: i32 = if (k.key == .left) -1 else 1;
                            const base = prop.effectiveStep(options.step);
                            const factor: f32 = if (k.modifiers.shift)
                                options.coarse_factor
                            else if (k.modifiers.alt)
                                options.fine_factor
                            else
                                1.0;
                            switch (prop.value) {
                                .choice => |ch| {
                                    if (inspector_mod.cycleIndex(ch.index.*, ch.options.len, dir)) |ni| {
                                        if (ni != ch.index.*) {
                                            ch.index.* = ni;
                                            res.changed = i;
                                        }
                                    }
                                },
                                .integer, .real => {
                                    const anchor = switch (prop.value) {
                                        .integer => |ip| @as(f32, @floatFromInt(ip.*)),
                                        .real => |rp| rp.*,
                                        else => 0,
                                    };
                                    const v = inspector_mod.clampToRange(
                                        anchor + @as(f32, @floatFromInt(dir)) * base * factor,
                                        prop.range,
                                    );
                                    switch (prop.value) {
                                        .integer => |ip| {
                                            const nv = inspector_mod.toInt(v);
                                            if (nv != ip.*) {
                                                ip.* = nv;
                                                res.changed = i;
                                            }
                                        },
                                        .real => |rp| {
                                            if (v != rp.*) {
                                                rp.* = v;
                                                res.changed = i;
                                            }
                                        },
                                        else => {},
                                    }
                                },
                                else => {},
                            }
                        }
                    }
                },
                .space, .enter => {
                    if (state.active) |i| {
                        const prop = properties[i];
                        if (!prop.readonly) {
                            switch (prop.value) {
                                .boolean => |bp| {
                                    bp.* = !bp.*;
                                    res.changed = i;
                                },
                                .choice => |ch| {
                                    if (inspector_mod.cycleIndex(ch.index.*, ch.options.len, 1)) |ni| {
                                        if (ni != ch.index.*) {
                                            ch.index.* = ni;
                                            res.changed = i;
                                        }
                                    }
                                },
                                else => {},
                            }
                        }
                    }
                },
                .tab => ctx.requestFocusAdvance(if (k.modifiers.shift) .prev else .next),
                else => {},
            }
        }
    }
    res.active = state.active;

    // --- Desenho (clipado em `bounds`) ---
    const line_h = font.lineHeight();
    try ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = bounds, .null_rect = false } });

    if (style.bg.a != 0) try fill(ctx, bounds, style.bg);

    const hot_row: ?usize = if (state.dragging) |d|
        d
    else if (res.hovered) |h|
        h
    else
        state.active;

    var i: usize = 0;
    while (i < properties.len) : (i += 1) {
        const ry = bounds.y + @as(f32, @floatFromInt(i)) * row_h - state.scroll;
        if (ry >= bounds.y + bounds.h) break;
        const top = @max(ry, bounds.y);
        const bot = @min(ry + row_h, bounds.y + bounds.h);
        if (bot <= top) continue;
        const row = types.Rect{ .x = bounds.x, .y = top, .w = bounds.w, .h = bot - top };
        const prop = properties[i];

        const alt = style.row_alt.a != 0 and (i % 2 == 1);
        const bgc = if (alt) style.row_alt else style.row_bg;
        if (bgc.a != 0) try fill(ctx, row, bgc);
        if (style.row_active.a != 0 and state.active != null and state.active.? == i) {
            try fill(ctx, row, style.row_active);
        }
        if (style.editor_bg.a != 0 and value_w > 0 and hot_row != null and hot_row.? == i) {
            try fill(
                ctx,
                .{ .x = value_x, .y = top, .w = value_w, .h = row.h },
                style.editor_bg,
            );
        }
        if (style.separator.a != 0 and i > 0) {
            try ctx.draw.line(
                ctx.allocator,
                .{ .x = bounds.x, .y = ry },
                .{ .x = bounds.x + bounds.w, .y = ry },
                style.separator,
                1.0,
            );
        }

        const ty = ry + @max(0, (row_h - line_h) / 2);
        if (prop.name.len > 0 and style.name.a != 0) {
            try pushLabel(
                ctx,
                .{ .x = bounds.x + style.name_pad, .y = ty },
                style.name,
                font,
                prop.name,
            );
        }

        const vx = value_x + style.value_pad;
        const vcolor = if (prop.readonly) style.value_readonly else style.value;
        switch (prop.value) {
            .boolean => |bp| {
                if (style.check_size > 0) {
                    const cs = style.check_size;
                    const box = types.Rect{
                        .x = vx,
                        .y = ry + @max(0, (row_h - cs) / 2),
                        .w = cs,
                        .h = cs,
                    };
                    if (style.check_bg.a != 0) try fill(ctx, box, style.check_bg);
                    if (style.check_border.a != 0 and style.check_border_width > 0) {
                        try ctx.draw.rectOutline(
                            ctx.allocator,
                            box,
                            style.check_border,
                            style.check_border_width,
                        );
                    }
                    if (bp.* and style.check_mark.a != 0) {
                        const inset = @min(box.w, box.h) * 0.25;
                        try fill(ctx, .{
                            .x = box.x + inset,
                            .y = box.y + inset,
                            .w = @max(1, box.w - inset * 2),
                            .h = @max(1, box.h - inset * 2),
                        }, style.check_mark);
                    }
                }
            },
            .integer => |ip| {
                if (vcolor.a != 0) {
                    var buf: [32]u8 = undefined;
                    const len = inspector_mod.formatInt(&buf, ip.*);
                    if (len > 0) try pushLabel(ctx, .{ .x = vx, .y = ty }, vcolor, font, buf[0..len]);
                }
            },
            .real => |rp| {
                if (vcolor.a != 0) {
                    var buf: [32]u8 = undefined;
                    const len = inspector_mod.formatReal(
                        &buf,
                        rp.*,
                        prop.effectiveDecimals(options.decimals),
                    );
                    if (len > 0) try pushLabel(ctx, .{ .x = vx, .y = ty }, vcolor, font, buf[0..len]);
                }
            },
            .choice => |ch| {
                if (vcolor.a != 0 and ch.index.* < ch.options.len) {
                    const label = ch.options[ch.index.*];
                    if (label.len > 0) {
                        try pushLabel(ctx, .{ .x = vx, .y = ty }, vcolor, font, label);
                    }
                }
            },
            .text => |t| {
                if (vcolor.a != 0 and t.len > 0) {
                    try pushLabel(ctx, .{ .x = vx, .y = ty }, vcolor, font, t);
                }
            },
        }
    }

    try ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = .{}, .null_rect = true } });

    return res;
}

fn testStyle() style_mod.InspectorStyle {
    return .{
        .bg = types.Color.rgb(10, 10, 10),
        .row_bg = types.Color.rgb(40, 40, 48),
        .row_alt = types.Color{ .r = 0, .g = 0, .b = 0, .a = 0 },
        .row_active = types.Color.rgb(60, 84, 120),
        .editor_bg = types.Color.rgb(24, 24, 30),
        .separator = types.Color.rgb(70, 70, 80),
        .name = types.Color.rgb(230, 230, 230),
        .name_width = 80,
        .name_pad = 6,
        .value_pad = 6,
        .row_height = 20,
        .value = types.Color.rgb(255, 255, 255),
        .value_readonly = types.Color.rgb(150, 150, 150),
        .check_size = 12,
        .check_bg = types.Color.rgb(20, 20, 20),
        .check_border = types.Color.rgb(200, 200, 200),
        .check_border_width = 1,
        .check_mark = types.Color.rgb(255, 200, 0),
    };
}

test "inspectorView: hover, ativação e bool no press" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = testStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:insp");
    const bounds = types.Rect.init(0, 0, 200, 60);
    var b0 = false;
    var iv: i64 = 3;
    const props = [_]inspector_mod.Property{
        .{ .name = "a", .value = .{ .boolean = &b0 } },
        .{ .name = "b", .value = .{ .integer = &iv } },
    };
    var st = InspectorViewState{};

    // Frame 1: hover na linha 0 (y 0..20).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(20, 10) } });
    const r0 = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(?usize, 0), r0.hovered);
    try stdt.testing.expectEqual(@as(?usize, null), r0.active);
    try stdt.testing.expectEqual(@as(?usize, null), r0.changed);
    ctx.endFrame();

    // Frame 2: press na linha 0 ⇒ ativa e alterna o bool.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(20, 10),
    } });
    const r1 = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expect(r1.active_changed);
    try stdt.testing.expectEqual(@as(?usize, 0), r1.active);
    try stdt.testing.expectEqual(@as(?usize, 0), r1.changed);
    try stdt.testing.expect(b0);
    try stdt.testing.expect(ctx.hasFocus(id));
    try stdt.testing.expectEqual(@as(?usize, null), r1.dragging);
    ctx.endFrame();

    // Frame 3: release; o bool fica ligado.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = false,
        .pos = types.Vec2.init(20, 10),
    } });
    const r2 = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(?usize, null), r2.changed);
    try stdt.testing.expect(b0);
    try stdt.testing.expect(ctx.press_owner == null);
    ctx.endFrame();

    // Frame 4: press na linha 1 (numérica) ⇒ ativa e inicia o arraste.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(120, 30),
    } });
    const r3 = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(?usize, 1), r3.active);
    try stdt.testing.expectEqual(@as(?usize, 1), r3.dragging);
    try stdt.testing.expectEqual(@as(?usize, null), r3.changed);
    try stdt.testing.expectEqual(@as(i64, 3), iv);
    ctx.endFrame();
}

test "inspectorView: arraste numérico com passo, faixa e teclado" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = testStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:insp-drag");
    const bounds = types.Rect.init(0, 0, 200, 60);
    var f: f32 = 1.0;
    var i: i64 = 2;
    const props = [_]inspector_mod.Property{
        .{
            .name = "f",
            .value = .{ .real = &f },
            .step = 0.5,
            .decimals = 1,
            .range = .{ .min = 0, .max = 3 },
        },
        .{ .name = "i", .value = .{ .integer = &i }, .range = .{ .min = 0, .max = 5 } },
    };
    var st = InspectorViewState{};

    // Press na linha 0 em x=100 ⇒ âncora 1.0.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(100, 10),
    } });
    _ = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(f32, 1.0), st.drag_anchor);
    ctx.endFrame();

    // +2 px com passo 0.5 ⇒ 2.0.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(102, 10) } });
    const r0 = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(f32, 2.0), f);
    try stdt.testing.expectEqual(@as(?usize, 0), r0.changed);
    try stdt.testing.expectEqual(@as(?usize, 0), r0.dragging);
    ctx.endFrame();

    // Longe à direita ⇒ clampa no máximo da faixa (3.0).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(400, 10) } });
    const r1 = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(f32, 3.0), f);
    try stdt.testing.expectEqual(@as(?usize, 0), r1.changed);
    ctx.endFrame();

    // Longe à esquerda ⇒ clampa no mínimo (0.0).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(-400, 10) } });
    _ = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(f32, 0.0), f);
    ctx.endFrame();

    // Release encerra o arraste.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = false,
        .pos = types.Vec2.init(-400, 10),
    } });
    const r2 = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(?usize, null), r2.dragging);
    try stdt.testing.expect(st.dragging == null);
    ctx.endFrame();

    // Teclado: → ajusta o real pelo passo (0.5); Shift ⇒ grosso (x10).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    const r3 = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(f32, 0.5), f);
    try stdt.testing.expectEqual(@as(?usize, 0), r3.changed);
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{ .shift = true } } });
    const r4 = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(f32, 3.0), f); // 0.5 + 5.0 ⇒ clampa em 3
    try stdt.testing.expectEqual(@as(?usize, 0), r4.changed);
    ctx.endFrame();

    // Alt ⇒ fino (x0.1); ← volta.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{ .alt = true } } });
    _ = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(f32, 2.95), f);
    ctx.endFrame();

    // ↓ move a ativa para a linha 1; → ajusta o inteiro (passo padrão 1).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    const r5 = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expect(r5.active_changed);
    try stdt.testing.expectEqual(@as(?usize, 1), r5.active);
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    const r6 = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(i64, 3), i);
    try stdt.testing.expectEqual(@as(?usize, 1), r6.changed);
    ctx.endFrame();

    // ↑/↓ clampam nos extremos; Ctrl+seta é ignorado.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    const r7 = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(?usize, 1), r7.active);
    try stdt.testing.expect(!r7.active_changed);
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const r8 = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(?usize, null), r8.changed);
    try stdt.testing.expectEqual(@as(i64, 3), i);
    ctx.endFrame();
}

test "inspectorView: escolha circula (press, setas e Espaço)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = testStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:insp-choice");
    const bounds = types.Rect.init(0, 0, 200, 60);
    var idx: u32 = 0;
    const options = [_][]const u8{ "A", "B", "C" };
    const props = [_]inspector_mod.Property{
        .{ .name = "m", .value = .{ .choice = .{ .index = &idx, .options = &options } } },
        .{ .name = "r", .value = .{ .text = "ro" }, .readonly = true },
    };
    var st = InspectorViewState{};

    // Press na linha 0 ⇒ avança para a opção 1.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(100, 10),
    } });
    const r0 = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(u32, 1), idx);
    try stdt.testing.expectEqual(@as(?usize, 0), r0.changed);
    ctx.endFrame();

    // Release + press de novo ⇒ 2 (e depois circula para 0).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = false,
        .pos = types.Vec2.init(100, 10),
    } });
    _ = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(100, 10),
    } });
    _ = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(u32, 2), idx);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = false,
        .pos = types.Vec2.init(100, 10),
    } });
    _ = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(100, 10),
    } });
    _ = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(u32, 0), idx); // circulou
    ctx.endFrame();

    // Setas ←/→ e Espaço circulam pelo teclado.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    _ = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(u32, 1), idx);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{} } });
    _ = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(u32, 0), idx);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .space, .pressed = true, .modifiers = .{} } });
    const r1 = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(u32, 1), idx);
    try stdt.testing.expectEqual(@as(?usize, 0), r1.changed);
    ctx.endFrame();

    // Linha somente-leitura: teclado e press não mudam nada.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    _ = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(?usize, 1), st.active);
    try ctx.pushEvent(.{ .key = .{ .key = .space, .pressed = true, .modifiers = .{} } });
    const r2 = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(?usize, null), r2.changed);
    try stdt.testing.expectEqual(@as(u32, 1), idx);
    ctx.endFrame();
}

test "inspectorView: rolagem pela roda e clamp" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = testStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:insp-scroll");
    // 5 linhas de 20 px num viewport de 60 ⇒ maxScroll = 40.
    const bounds = types.Rect.init(0, 0, 200, 60);
    var v0: i64 = 0;
    var v1: i64 = 1;
    var v2: i64 = 2;
    var v3: i64 = 3;
    var v4: i64 = 4;
    const props = [_]inspector_mod.Property{
        .{ .name = "0", .value = .{ .integer = &v0 } },
        .{ .name = "1", .value = .{ .integer = &v1 } },
        .{ .name = "2", .value = .{ .integer = &v2 } },
        .{ .name = "3", .value = .{ .integer = &v3 } },
        .{ .name = "4", .value = .{ .integer = &v4 } },
    };
    var st = InspectorViewState{};
    const opts = InspectorViewOptions{ .scroll_step = 20 };

    // Roda "para baixo" (dy < 0: afasta) ⇒ rola 20 px.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = -1, .pos = types.Vec2.init(100, 30) } });
    const r0 = try inspectorView(&ctx, id, bounds, &props, &st, opts, style, font);
    try stdt.testing.expect(r0.scrolled);
    try stdt.testing.expectEqual(@as(f32, 20), st.scroll);
    try stdt.testing.expectEqual(@as(f32, 20), r0.scroll_delta);
    ctx.endFrame();

    // Mais roda ⇒ clampa em maxScroll (40).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = -5, .pos = types.Vec2.init(100, 30) } });
    const r1 = try inspectorView(&ctx, id, bounds, &props, &st, opts, style, font);
    try stdt.testing.expectEqual(@as(f32, 40), st.scroll);
    try stdt.testing.expectEqual(@as(f32, 20), r1.scroll_delta);
    ctx.endFrame();

    // Roda para cima (dy > 0) ⇒ volta e clampa em 0.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = 9, .pos = types.Vec2.init(100, 30) } });
    _ = try inspectorView(&ctx, id, bounds, &props, &st, opts, style, font);
    try stdt.testing.expectEqual(@as(f32, 0), st.scroll);
    ctx.endFrame();

    // Fora do hover a roda é ignorada.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = -1, .pos = types.Vec2.init(500, 500) } });
    const r2 = try inspectorView(&ctx, id, bounds, &props, &st, opts, style, font);
    try stdt.testing.expect(!r2.scrolled);
    try stdt.testing.expectEqual(@as(f32, 0), st.scroll);
    ctx.endFrame();

    // O hit-test considera o deslocamento: com scroll=40, y=10 ⇒ conteúdo 50 ⇒ linha 2.
    st.scroll = 40;
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(100, 10) } });
    const r3 = try inspectorView(&ctx, id, bounds, &props, &st, opts, style, font);
    try stdt.testing.expectEqual(@as(?usize, 2), r3.hovered);
    ctx.endFrame();

    // ↓ da linha 3 (não visível) traz a linha 4 para a vista (scroll = 40).
    // Primeiro foca o widget (press+release).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(100, 10),
    } });
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = false,
        .pos = types.Vec2.init(100, 10),
    } });
    _ = try inspectorView(&ctx, id, bounds, &props, &st, opts, style, font);
    try stdt.testing.expect(ctx.hasFocus(id));
    ctx.endFrame();

    st.active = 3;
    st.scroll = 0;
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    const r4 = try inspectorView(&ctx, id, bounds, &props, &st, opts, style, font);
    try stdt.testing.expectEqual(@as(?usize, 4), r4.active);
    // Linha 4 (topo 80, base 100) num viewport de 60 ⇒ scroll = 40.
    try stdt.testing.expectEqual(@as(f32, 40), st.scroll);
    ctx.endFrame();

    // Já na última: nada muda.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    const r5 = try inspectorView(&ctx, id, bounds, &props, &st, opts, style, font);
    try stdt.testing.expectEqual(@as(?usize, 4), r5.active);
    try stdt.testing.expect(!r5.active_changed);
    try stdt.testing.expectEqual(@as(?usize, null), r5.changed);
    ctx.endFrame();
}

test "inspectorView: desenho (clip, linhas, bool, valores)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var style = testStyle();
    style.row_alt = types.Color.rgb(30, 30, 36);
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:insp-draw");
    const bounds = types.Rect.init(0, 0, 200, 60);
    var on = true;
    var scale: f32 = 1.5;
    var idx: u32 = 1;
    const options = [_][]const u8{ "A", "B" };
    const props = [_]inspector_mod.Property{
        .{ .name = "on", .value = .{ .boolean = &on } },
        .{ .name = "scale", .value = .{ .real = &scale }, .decimals = 1 },
        .{ .name = "mode", .value = .{ .choice = .{ .index = &idx, .options = &options } } },
    };
    var st = InspectorViewState{ .active = 2 };

    ctx.beginFrame();
    const r = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(?usize, null), r.changed);
    try stdt.testing.expectEqual(@as(?usize, 2), r.active);

    const cmds = ctx.drawCommands();
    try stdt.testing.expect(cmds[0] == .clip);
    try stdt.testing.expect(!cmds[0].clip.null_rect);
    try stdt.testing.expect(cmds[cmds.len - 1] == .clip);
    try stdt.testing.expect(cmds[cmds.len - 1].clip.null_rect);

    var fills: usize = 0;
    var outlines: usize = 0;
    var texts: usize = 0;
    var lines: usize = 0;
    var text_slices: [8][]const u8 = undefined;
    var text_count: usize = 0;
    for (cmds) |c| {
        switch (c) {
            .rect_filled => fills += 1,
            .rect_outline => outlines += 1,
            .line => lines += 1,
            .text => {
                if (text_count < text_slices.len) {
                    text_slices[text_count] = ctx.draw.textOf(c);
                    text_count += 1;
                }
                texts += 1;
            },
            else => {},
        }
    }
    // Fundo + 3 linhas + realce da ativa + realce do editor (ativa) +
    // caixa do bool + marca = 8.
    try stdt.testing.expectEqual(@as(usize, 8), fills);
    // Borda da caixa do bool.
    try stdt.testing.expectEqual(@as(usize, 1), outlines);
    // 2 separadores (linhas 1 e 2).
    try stdt.testing.expectEqual(@as(usize, 2), lines);
    // 3 nomes + "1.5" + "B" (o bool não emite texto).
    try stdt.testing.expectEqual(@as(usize, 5), texts);
    try stdt.testing.expectEqualStrings("on", text_slices[0]);
    try stdt.testing.expectEqualStrings("scale", text_slices[1]);
    try stdt.testing.expectEqualStrings("1.5", text_slices[2]);
    try stdt.testing.expectEqualStrings("mode", text_slices[3]);
    try stdt.testing.expectEqualStrings("B", text_slices[4]);
    // 3 clips + 7 fills + 1 outline + 2 linhas + 5 textos = 18.
    try stdt.testing.expectEqual(@as(usize, 18), cmds.len);
    ctx.endFrame();
}

test "inspectorView: contratos inválidos e índices fora de faixa" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = testStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:insp-bad");
    const bounds = types.Rect.init(0, 0, 200, 60);
    var b0 = false;
    var idx: u32 = 9;
    const options = [_][]const u8{ "A", "B" };
    const props = [_]inspector_mod.Property{
        .{ .name = "a", .value = .{ .boolean = &b0 } },
        .{ .name = "m", .value = .{ .choice = .{ .index = &idx, .options = &options } } },
    };
    var st = InspectorViewState{};

    ctx.beginFrame();
    // id nulo
    try stdt.testing.expectError(error.InvalidArgument, inspectorView(&ctx, .null, bounds, &props, &st, .{}, style, font));
    // bounds inválidos
    try stdt.testing.expectError(error.InvalidArgument, inspectorView(&ctx, id, types.Rect.init(0, 0, 0, 10), &props, &st, .{}, style, font));
    try stdt.testing.expectError(error.InvalidArgument, inspectorView(&ctx, id, types.Rect.init(0, 0, 10, std.math.inf(f32)), &props, &st, .{}, style, font));
    // estilo / fonte / opções
    var bad_style = style;
    bad_style.row_height = 0;
    try stdt.testing.expectError(error.InvalidArgument, inspectorView(&ctx, id, bounds, &props, &st, .{}, bad_style, font));
    var bad_style2 = style;
    bad_style2.name_width = -1;
    try stdt.testing.expectError(error.InvalidArgument, inspectorView(&ctx, id, bounds, &props, &st, .{}, bad_style2, font));
    try stdt.testing.expectError(error.InvalidArgument, inspectorView(&ctx, id, bounds, &props, &st, .{ .step = 0 }, style, font));
    try stdt.testing.expectError(error.InvalidArgument, inspectorView(&ctx, id, bounds, &props, &st, .{ .decimals = 9 }, style, font));
    try stdt.testing.expectError(error.InvalidArgument, inspectorView(&ctx, id, bounds, &props, &st, .{ .fine_factor = 2 }, style, font));
    try stdt.testing.expectError(error.InvalidArgument, inspectorView(&ctx, id, bounds, &props, &st, .{}, style, metrics_mod.FontMetrics{ .size = 0 }));
    // rolagem não-finita
    var bad_st = InspectorViewState{ .scroll = std.math.nan(f32) };
    try stdt.testing.expectError(error.InvalidArgument, inspectorView(&ctx, id, bounds, &props, &bad_st, .{}, style, font));
    // escolha com índice fora de faixa é clampada (memória do chamador).
    idx = 9;
    _ = try inspectorView(&ctx, id, bounds, &props, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(u32, 1), idx);
    // índice de escolha inválido (sem opções) é rejeitado.
    const empty = [_]inspector_mod.Property{.{ .value = .{ .choice = .{
        .index = &idx,
        .options = &.{},
    } } }};
    try stdt.testing.expectError(error.InvalidArgument, inspectorView(&ctx, id, bounds, &empty, &st, .{}, style, font));
    // property com passo inválido é rejeitada.
    var r: f32 = 0;
    const bad_props = [_]inspector_mod.Property{.{ .value = .{ .real = &r }, .step = -1 }};
    try stdt.testing.expectError(error.InvalidArgument, inspectorView(&ctx, id, bounds, &bad_props, &st, .{}, style, font));
    // propriedades vazias são aceitas (inspector sem seleção).
    const none: [0]inspector_mod.Property = .{};
    const r0 = try inspectorView(&ctx, id, bounds, &none, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(?usize, null), r0.active);
    // Linha ativa/arraste fora de faixa são descartados.
    var st2 = InspectorViewState{ .active = 7, .dragging = 9, .scroll = 1000 };
    _ = try inspectorView(&ctx, id, bounds, &props, &st2, .{}, style, font);
    try stdt.testing.expectEqual(@as(?usize, null), st2.active);
    try stdt.testing.expectEqual(@as(?usize, null), st2.dragging);
    try stdt.testing.expectEqual(@as(f32, 0), st2.scroll); // 2 linhas cabem
    ctx.endFrame();
}
