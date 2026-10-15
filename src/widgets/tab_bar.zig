//! ZyntraUI — barra de abas (widgets/tab_bar).
//!
//! Modelo M56: `beginTabBar`/`endTabBar` com estado no chamador.
//! - `active: *usize` — aba ativa (offset do chamador, clampado).
//! - `TabBarStyle` + `Theme.tabBarStyle()` — cores, padding, raio.
//! - Teclado: `Left`/`Right` navegam, `Home`/`End` saltam, `Tab` circula.
//! - Click na aba seleciona; `Tab` no teclado circula foco.
//! - Desenho: 1 comando por aba (fundo) + 1 outline + 1 texto = 3*N + 2.
//! `id` não-nulo obrigatório.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const input = @import("input.zig");
const metrics_mod = @import("../text/metrics.zig");

pub const TabBarResult = struct {
    active: usize = 0,
    changed: bool = false,
    focused: bool = false,
    hovered_index: ?usize = null,
};

pub const TabBarStyle = extern struct {
    bg: types.Color,
    bg_active: types.Color,
    bg_hover: types.Color,
    text: types.Color,
    text_active: types.Color,
    border: types.Color,
    border_width: f32 = 1.0,
    padding_x: f32 = 12.0,
    padding_y: f32 = 6.0,

    pub fn isValid(self: TabBarStyle) bool {
        return std.math.isFinite(self.border_width) and self.border_width >= 0 and
            std.math.isFinite(self.padding_x) and self.padding_x >= 0 and
            std.math.isFinite(self.padding_y) and self.padding_y >= 0;
    }
};

pub fn beginTabBar(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    tabs: []const []const u8,
    active: *usize,
    style: style_mod.TabBarStyle,
) context_mod.ContextError!TabBarResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid()) return error.InvalidArgument;
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;
    if (tabs.len == 0) return error.InvalidArgument;

    // Valida índice ativo
    if (active.* >= tabs.len) active.* = tabs.len - 1;

    const fm = input.FrameMouse.scan(ctx.pendingEvents());
    _ = if (ctx.mouse_pos) |p| bounds.contains(p) else false;
    var res = TabBarResult{ .active = active.*, .focused = ctx.hasFocus(id), .hovered_index = null };

    // Focável (Tab circula)
    try ctx.registerFocusable(id);
    if (fm.pressedInside(bounds)) {
        ctx.focus_owner = id;
    }

    // Layout das abas
    const font = metrics_mod.FontMetrics.withSize(10);
    var cursor_x = bounds.x;
    var tab_rects: [32]types.Rect = undefined;
    var tab_count: usize = 0;

    var i: usize = 0;
    while (i < tabs.len and tab_count < tab_rects.len) : (i += 1) {
        const label = tabs[i];
        const m = metrics_mod.measure(label, font) catch continue;
        const w = m.width + style.padding_x * 2;
        const h = bounds.h;
        tab_rects[tab_count] = types.Rect{ .x = cursor_x, .y = bounds.y, .w = w, .h = h };
        cursor_x += w;
        tab_count += 1;
    }

    // Click seleciona aba
    if (fm.pressed_pos) |p| {
        var j: usize = 0;
        while (j < tab_count) : (j += 1) {
            if (tab_rects[j].contains(p)) {
                res.changed = active.* != j;
                active.* = j;
                res.active = j;
                break;
            }
        }
    }

    // Teclado com foco
    if (ctx.hasFocus(id)) {
        for (ctx.pendingEvents()) |ev| {
            if (ev != .key) continue;
            const k = ev.key;
            if (!k.pressed or k.modifiers.ctrl) continue;
            var new_active = active.*;
            switch (k.key) {
                .left => {
                    if (active.* > 0) new_active -= 1;
                },
                .right => {
                    if (active.* + 1 < tabs.len) new_active += 1;
                },
                .home => new_active = 0,
                .end => new_active = tabs.len - 1,
                .tab => ctx.requestFocusAdvance(if (k.modifiers.shift) .prev else .next),
                else => {},
            }
            if (new_active != active.*) {
                active.* = new_active;
                res.changed = true;
                res.active = new_active;
            }
        }
    }

    // Hover index
    if (ctx.mouse_pos) |p| {
        var j: usize = 0;
        while (j < tab_count) : (j += 1) {
            if (tab_rects[j].contains(p)) {
                res.hovered_index = j;
                break;
            }
        }
    }

    // Desenho
    const active_i = active.*;
    // Fundo da barra
    ctx.draw.rectFilled(ctx.allocator, bounds, style.bg) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };

    var j: usize = 0;
    while (j < tab_count) : (j += 1) {
        const r = tab_rects[j];
        const is_active = j == active_i;
        const is_hovered = res.hovered_index == j and !is_active;

        const bg = if (is_active) style.bg_active else if (is_hovered) style.bg_hover else style.bg;
        ctx.draw.rectFilled(ctx.allocator, r, bg) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
        };

        // Texto centralizado
        const m = metrics_mod.measure(tabs[j], font) catch continue;
        const tx = r.x + (r.w - m.width) / 2;
        const ty = r.y + (r.h - font.lineHeight()) / 2;
        const text_color = if (is_active) style.text_active else style.text;
        ctx.draw.pushText(
            ctx.allocator,
            .{ .x = tx, .y = ty },
            text_color,
            font,
            tabs[j],
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
            error.InvalidUtf8 => return error.InvalidArgument,
            error.InvalidMetrics => return error.InvalidArgument,
        };
    }

    // Outline da barra
    ctx.draw.rectOutline(ctx.allocator, bounds, style.border, @max(1.0, style.border_width)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };

    return res;
}

pub fn endTabBar(_: *context_mod.Context) void {
    // Sem estado retido; existe para simetria com outros widgets
}

test "TabBar click seleciona, teclado navega, clamp ativo" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().tabBarStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 400, 30);
    const id = id_mod.Id.fromString("test:tab");
    var active: usize = 0;
    const tabs = [_][]const u8{ "A", "BBB", "CC" };

    // Click na 2ª aba (x=50 dentro da aba "BBB": largura ~30..72)
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(50, 15) },
    });
    const r0 = try beginTabBar(&ctx, id, bounds, &tabs, &active, style);
    try stdt.testing.expect(r0.changed);
    try stdt.testing.expectEqual(@as(usize, 1), active);
    ctx.endFrame();

    // Left volta para 0
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{} } });
    const r1 = try beginTabBar(&ctx, id, bounds, &tabs, &active, style);
    try stdt.testing.expect(r1.changed);
    try stdt.testing.expectEqual(@as(usize, 0), active);
    ctx.endFrame();

    // Right avança para 1
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    const r2 = try beginTabBar(&ctx, id, bounds, &tabs, &active, style);
    try stdt.testing.expect(r2.changed);
    try stdt.testing.expectEqual(@as(usize, 1), active);
    ctx.endFrame();

    // Home/End
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{} } });
    _ = try beginTabBar(&ctx, id, bounds, &tabs, &active, style);
    try stdt.testing.expectEqual(@as(usize, 2), active);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    _ = try beginTabBar(&ctx, id, bounds, &tabs, &active, style);
    try stdt.testing.expectEqual(@as(usize, 0), active);
    ctx.endFrame();

    // Click fora não muda; ativo clampado
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(500, 500) },
    });
    const r3 = try beginTabBar(&ctx, id, bounds, &tabs, &active, style);
    try stdt.testing.expect(!r3.changed);
    try stdt.testing.expectEqual(@as(usize, 0), active);
    ctx.endFrame();

    // Índice inválido clampado
    active = 999;
    ctx.beginFrame();
    _ = try beginTabBar(&ctx, id, bounds, &tabs, &active, style);
    try stdt.testing.expectEqual(@as(usize, 2), active);
    ctx.endFrame();

    // Contratos inválidos
    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, beginTabBar(&ctx, .null, bounds, &tabs, &active, style));
    try stdt.testing.expectError(error.InvalidArgument, beginTabBar(&ctx, id, types.Rect.init(0, 0, 0, 0), &tabs, &active, style));
    try stdt.testing.expectError(error.InvalidArgument, beginTabBar(&ctx, id, bounds, &[_][]const u8{}, &active, style));
    const bad_style = style_mod.TabBarStyle{ .border_width = -1, .bg = .{}, .bg_active = .{}, .bg_hover = .{}, .text = .{}, .text_active = .{}, .border = .{}, .padding_x = 0, .padding_y = 0 };
    try stdt.testing.expectError(error.InvalidArgument, beginTabBar(&ctx, id, bounds, &tabs, &active, bad_style));
    ctx.endFrame();
}
