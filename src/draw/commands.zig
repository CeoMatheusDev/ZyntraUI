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
        }
    }
};

/// Lista de desenho do frame (bump por frame + retenção de capacidade).
pub const DrawList = struct {
    list: std.ArrayList(DrawCommand),

    const Self = @This();

    pub fn initEmpty() Self {
        return .{ .list = .empty };
    }

    pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
        self.list.deinit(gpa);
    }

    pub fn clearRetainingCapacity(self: *Self) void {
        self.list.clearRetainingCapacity();
    }

    pub fn len(self: *const Self) usize {
        return self.list.items.len;
    }

    pub fn items(self: *const Self) []const DrawCommand {
        return self.list.items;
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
