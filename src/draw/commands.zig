//! ZyntraUI — comandos de desenho (draw/commands).
//!
//! Contrato renderer-independente:
//! - Produtores (widgets) apenas enfileiram `DrawCommand` em pixels
//!   lógicos; nenhum backend é referenciado aqui.
//! - Consumidores (renderers externos) iteram `DrawList.items()` em
//!   ordem e executam batching próprio.
//! - Coordenadas `NaN/Inf` são rejeitadas (`InvalidCommand`).
//! Ownership: `DrawList` detém o buffer; alocador do chamador.
//! `clear` no início do frame invalida slices anteriores.
//! ABI C: payloads `extern struct`, tags `u8`; projeção plana em M5.

const std = @import("std");
const types = @import("../core/types.zig");
const metrics_mod = @import("../text/metrics.zig");

/// Comando único de desenho.
pub const DrawCommand = union(enum) {
    /// Limpa o viewport com cor sólida (normalmente primeiro).
    clear: extern struct { color: types.Color },
    rect_filled: extern struct {
        rect: types.Rect,
        color: types.Color,
    },
    rect_outline: extern struct {
        rect: types.Rect,
        color: types.Color,
        thickness: f32,
    },
    line: extern struct {
        p0: types.Vec2,
        p1: types.Vec2,
        color: types.Color,
        thickness: f32,
    },
    circle_filled: extern struct {
        center: types.Vec2,
        radius: f32,
        color: types.Color,
    },
    /// Define clip retangular (scissor) para comandos seguintes.
    /// `null_rect=true` remove o clip.
    clip: extern struct {
        rect: types.Rect,
        null_rect: bool,
    },
    /// Texto para o backend rasterizar. Os bytes vivem na arena da
    /// `DrawList` (`text_bytes`); `start/len` são offsets (estáveis
    /// mesmo se a arena realocar). `width` é a medida fallback gravada
    /// no push (backends com shaping próprio podem diferir).
    text: extern struct {
        pos: types.Vec2,
        color: types.Color,
        size: f32,
        width: f32,
        start: u32,
        len: u32,
    },

    fn finite(v: f32) bool {
        return std.math.isFinite(v);
    }

    pub fn isValid(self: DrawCommand) bool {
        switch (self) {
            .clear => return true,
            .rect_filled => |c| {
                return finite(c.rect.x) and finite(c.rect.y) and
                    finite(c.rect.w) and finite(c.rect.h) and
                    c.rect.w >= 0 and c.rect.h >= 0;
            },
            .rect_outline => |c| {
                return finite(c.rect.x) and finite(c.rect.y) and
                    finite(c.rect.w) and finite(c.rect.h) and
                    c.rect.w >= 0 and c.rect.h >= 0 and
                    finite(c.thickness) and c.thickness > 0;
            },
            .line => |c| {
                return finite(c.p0.x) and finite(c.p0.y) and
                    finite(c.p1.x) and finite(c.p1.y) and
                    finite(c.thickness) and c.thickness > 0;
            },
            .circle_filled => |c| {
                return finite(c.center.x) and finite(c.center.y) and
                    finite(c.radius) and c.radius >= 0;
            },
            .clip => |c| {
                if (c.null_rect) return true;
                return finite(c.rect.x) and finite(c.rect.y) and
                    finite(c.rect.w) and finite(c.rect.h) and
                    c.rect.w >= 0 and c.rect.h >= 0;
            },
            .text => |c| {
                return finite(c.pos.x) and finite(c.pos.y) and
                    finite(c.size) and c.size > 0 and
                    finite(c.width) and c.width >= 0;
            },
        }
    }
};

/// Lista de desenho do frame (bump por frame + retenção de capacidade).
/// `text_bytes` é a arena dos textos de comandos `.text`; comandos
/// guardam offsets, nunca slices (seguro contra realocação).
pub const DrawList = struct {
    list: std.ArrayList(DrawCommand),
    text_bytes: std.ArrayList(u8) = .empty,

    const Self = @This();

    pub fn initEmpty() Self {
        return .{ .list = .empty, .text_bytes = .empty };
    }

    pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
        self.list.deinit(gpa);
        self.text_bytes.deinit(gpa);
    }

    pub fn clearRetainingCapacity(self: *Self) void {
        self.list.clearRetainingCapacity();
        self.text_bytes.clearRetainingCapacity();
    }

    pub fn len(self: *const Self) usize {
        return self.list.items.len;
    }

    pub fn items(self: *const Self) []const DrawCommand {
        return self.list.items;
    }

    /// Resolve os bytes UTF-8 de um comando `.text`. Retorna vazio se o
    /// comando não for texto ou os offsets forem inconsistentes
    /// (defensivo para backends; nunca crasha).
    pub fn textOf(self: *const Self, cmd: DrawCommand) []const u8 {
        const t = switch (cmd) {
            .text => |p| p,
            else => return &.{},
        };
        const start: usize = t.start;
        const end: usize = start + t.len;
        const buf = self.text_bytes.items;
        if (start > end or end > buf.len) return &.{};
        return buf[start..end];
    }

    pub fn push(self: *Self, gpa: std.mem.Allocator, cmd: DrawCommand) !void {
        if (!cmd.isValid()) return error.InvalidCommand;
        try self.list.append(gpa, cmd);
    }

    pub fn clear(self: *Self, gpa: std.mem.Allocator, color: types.Color) !void {
        try self.push(gpa, .{ .clear = .{ .color = color } });
    }

    pub fn rectFilled(self: *Self, gpa: std.mem.Allocator, rect: types.Rect, color: types.Color) !void {
        try self.push(gpa, .{ .rect_filled = .{ .rect = rect, .color = color } });
    }

    pub fn rectOutline(self: *Self, gpa: std.mem.Allocator, rect: types.Rect, color: types.Color, thickness: f32) !void {
        try self.push(gpa, .{ .rect_outline = .{ .rect = rect, .color = color, .thickness = thickness } });
    }

    pub fn line(self: *Self, gpa: std.mem.Allocator, p0: types.Vec2, p1: types.Vec2, color: types.Color, thickness: f32) !void {
        try self.push(gpa, .{ .line = .{ .p0 = p0, .p1 = p1, .color = color, .thickness = thickness } });
    }

    pub fn circleFilled(self: *Self, gpa: std.mem.Allocator, center: types.Vec2, radius: f32, color: types.Color) !void {
        try self.push(gpa, .{ .circle_filled = .{ .center = center, .color = color, .radius = radius } });
    }

    /// Enfileira texto copiando os bytes para a arena interna.
    /// Valida UTF-8 no push (backend nunca recebe texto malformado).
    /// Textos que não couberem em offsets `u32` retornam `OutOfMemory`.
    pub fn pushText(
        self: *Self,
        gpa: std.mem.Allocator,
        pos: types.Vec2,
        color: types.Color,
        font: metrics_mod.FontMetrics,
        text: []const u8,
    ) !void {
        if (!font.isValid()) return error.InvalidMetrics;
        const m = try metrics_mod.measure(text, font);
        const start = self.text_bytes.items.len;
        if (start > std.math.maxInt(u32) or text.len > std.math.maxInt(u32) - start) {
            return error.OutOfMemory;
        }
        try self.text_bytes.appendSlice(gpa, text);
        try self.push(gpa, .{ .text = .{
            .pos = pos,
            .color = color,
            .size = font.size,
            .width = m.width,
            .start = @intCast(start),
            .len = @intCast(text.len),
        } });
    }
};

test "DrawList helpers + validação" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var dl = DrawList.initEmpty();
    defer dl.deinit(gpa);

    try dl.clear(gpa, types.Color.rgb(10, 20, 30));
    try dl.rectFilled(gpa, types.Rect.init(0, 0, 10, 10), types.Color.rgb(255, 0, 0));
    try dl.rectOutline(gpa, types.Rect.init(0, 0, 10, 10), types.Color.rgb(0, 255, 0), 1.0);
    try dl.line(gpa, types.Vec2.init(0, 0), types.Vec2.init(5, 5), types.Color.rgb(0, 0, 255), 2.0);
    try dl.circleFilled(gpa, types.Vec2.init(3, 3), 4.0, types.Color.rgb(255, 255, 0));
    try stdt.testing.expectEqual(@as(usize, 5), dl.len());

    // Inválidos:
    try stdt.testing.expectError(error.InvalidCommand, dl.rectFilled(
        gpa,
        types.Rect.init(0, 0, -1, 5),
        types.Color.rgb(0, 0, 0),
    ));
    try stdt.testing.expectError(error.InvalidCommand, dl.line(
        gpa,
        types.Vec2.init(std.math.nan(f32), 0),
        types.Vec2.init(0, 0),
        types.Color.rgb(0, 0, 0),
        1.0,
    ));
    const cap = dl.list.capacity;
    dl.clearRetainingCapacity();
    try stdt.testing.expectEqual(@as(usize, 0), dl.len());
    try stdt.testing.expect(dl.list.capacity >= cap);
}

test "DrawList pushText copia, resolve e valida" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var dl = DrawList.initEmpty();
    defer dl.deinit(gpa);
    const font = metrics_mod.FontMetrics.withSize(10); // advance=6

    // Buffer mutável do chamador pode morrer após o push: a lista copiou.
    var owned = try gpa.dupe(u8, "AB€");
    defer gpa.free(owned);
    try dl.pushText(gpa, types.Vec2.init(1, 2), types.Color.rgb(1, 2, 3), font, owned);
    owned[0] = 'X';
    try stdt.testing.expectEqual(@as(usize, 1), dl.len());
    const cmd = dl.items()[0];
    try stdt.testing.expectEqualStrings("AB€", dl.textOf(cmd));
    try stdt.testing.expectEqual(@as(f32, 18), cmd.text.width);

    // Segundo push acumula offsets; texto vazio é no-op válido.
    try dl.pushText(gpa, types.Vec2.init(0, 0), types.Color.rgb(0, 0, 0), font, "");
    try dl.pushText(gpa, types.Vec2.init(0, 0), types.Color.rgb(0, 0, 0), font, "C");
    try stdt.testing.expectEqualStrings("C", dl.textOf(dl.items()[2]));
    try stdt.testing.expectEqualStrings("", dl.textOf(dl.items()[1]));

    // Não-texto e offsets absurdos retornam vazio sem crashar.
    const not_text: DrawCommand = .{ .clear = .{ .color = types.Color.rgb(0, 0, 0) } };
    try stdt.testing.expectEqualStrings("", dl.textOf(not_text));
    var forged = dl.items()[2];
    forged.text.len = std.math.maxInt(u32);
    try stdt.testing.expectEqualStrings("", dl.textOf(forged));

    // UTF-8 inválido e fonte inválida rejeitados sem enfileirar.
    const before = dl.len();
    try stdt.testing.expectError(error.InvalidUtf8, dl.pushText(gpa, types.Vec2.init(0, 0), types.Color.rgb(0, 0, 0), font, "\xff"));
    try stdt.testing.expectError(error.InvalidMetrics, dl.pushText(gpa, types.Vec2.init(0, 0), types.Color.rgb(0, 0, 0), .{ .size = 0 }, "A"));
    try stdt.testing.expectEqual(before, dl.len());
}
