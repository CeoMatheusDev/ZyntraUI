//! ZyntraUI — contrato de renderer externo (draw/renderer).
//!
//! A ZyntraUI NÃO implementa renderer GPU próprio. Este módulo define:
//! - Como backends externos consomem `DrawCommand` em ordem.
//! - `cull`: estatísticas puras de visibilidade (sem alocação),
//!   para backends pularem submissões fora do viewport.
//! - `NullRenderer`: test-double que valida comandos e conta envios.
//! - `Backend`: interface mínima (vtable) que backends reais
//!   implementam (software, OpenGL, Vulkan, etc.).
//! Ownership: a ZyntraUI empresta `cmds` apenas durante `submit`;
//! o backend não retém o slice. Recursos GPU pertencem ao backend.
//! Coordenadas inválidas nunca chegam aqui (`DrawList` já valida),
//! mas `submit` revalida defensivamente.

const std = @import("std");
const types = @import("../core/types.zig");
const commands = @import("commands.zig");

/// Estatísticas de um frame submetido.
pub const FrameStats = extern struct {
    submitted: u32 = 0,
    visible: u32 = 0,
    culled: u32 = 0,
};

fn intersects(a: types.Rect, b: types.Rect) bool {
    if (a.w <= 0 or a.h <= 0 or b.w <= 0 or b.h <= 0) return false;
    return a.x < b.x + b.w and b.x < a.x + a.w and
        a.y < b.y + b.h and b.y < a.y + a.h;
}

/// Bounds conservadores de um comando para culling. `clear` cobre o
/// viewport inteiro (sempre visível) → retorna `null` como "global".
pub fn commandBounds(cmd: commands.DrawCommand) ?types.Rect {
    switch (cmd) {
        .clear => return null,
        // Alfa global: não tem geometria (vale para os comandos seguintes).
        .alpha => return null,
        .rect_filled => |c| return c.rect,
        .rect_outline => |c| return c.rect,
        .line => |c| {
            const x = @min(c.p0.x, c.p1.x);
            const y = @min(c.p0.y, c.p1.y);
            const w = @abs(c.p1.x - c.p0.x) + c.thickness;
            const h = @abs(c.p1.y - c.p0.y) + c.thickness;
            return .{ .x = x - c.thickness / 2, .y = y - c.thickness / 2, .w = w, .h = h };
        },
        .circle_filled => |c| {
            return .{
                .x = c.center.x - c.radius,
                .y = c.center.y - c.radius,
                .w = c.radius * 2,
                .h = c.radius * 2,
            };
        },
        .circle_outline => |c| {
            const r = c.radius + c.thickness / 2;
            return .{
                .x = c.center.x - r,
                .y = c.center.y - r,
                .w = r * 2,
                .h = r * 2,
            };
        },
        .circle_dashed => |c| {
            const r = c.radius + c.thickness / 2;
            return .{
                .x = c.center.x - r,
                .y = c.center.y - r,
                .w = r * 2,
                .h = r * 2,
            };
        },
        .rect_gradient_radial => |c| return c.rect,
        .rect_gradient_conic => |c| return c.rect,
        .line_dashed => |c| {
            const x = @min(c.p0.x, c.p1.x);
            const y = @min(c.p0.y, c.p1.y);
            const w = @abs(c.p1.x - c.p0.x) + c.thickness;
            const h = @abs(c.p1.y - c.p0.y) + c.thickness;
            return .{ .x = x - c.thickness / 2, .y = y - c.thickness / 2, .w = w, .h = h };
        },
        .clip => |c| {
            if (c.null_rect) return null;
            return c.rect;
        },
        .text => |c| {
            // Bounds fallback (largura medida no push, altura ~= size).
            return .{ .x = c.pos.x, .y = c.pos.y, .w = c.width, .h = c.size };
        },
        .rect_rounded => |c| return c.rect,
        .image => |c| return c.rect,
        .glyph_run => |c| return c.bounds,
        .rect_gradient => |c| return c.rect,
        .rect_shadow => |c| {
            // União da silhueta e da silhueta deslocada, expandida pelo
            // raio de atenuação (+1px de margem de amostragem).
            const sr = types.Rect{
                .x = c.rect.x + c.offset.x,
                .y = c.rect.y + c.offset.y,
                .w = c.rect.w,
                .h = c.rect.h,
            };
            const pad = c.blur / 2 + 1;
            const x = @min(c.rect.x, sr.x) - pad;
            const y = @min(c.rect.y, sr.y) - pad;
            const x2 = @max(c.rect.x + c.rect.w, sr.x + sr.w) + pad;
            const y2 = @max(c.rect.y + c.rect.h, sr.y + sr.h) + pad;
            return .{ .x = x, .y = y, .w = x2 - x, .h = y2 - y };
        },
        .blur => |c| return c.rect,
        .path => |c| return c.bounds,
    }
}

/// Conta visíveis vs. fora do viewport. Pura, sem alocação.
pub fn cull(cmds: []const commands.DrawCommand, viewport: types.Rect) FrameStats {
    var out = FrameStats{ .submitted = @intCast(cmds.len) };
    for (cmds) |cmd| {
        const b = commandBounds(cmd);
        if (b == null) {
            out.visible += 1;
        } else if (intersects(b.?, viewport)) {
            out.visible += 1;
        } else {
            out.culled += 1;
        }
    }
    return out;
}

/// Test-double: valida e conta, sem desenhar.
pub const NullRenderer = struct {
    submitted_total: usize = 0,
    visible_total: usize = 0,
    frames: u32 = 0,

    pub fn submit(self: *NullRenderer, cmds: []const commands.DrawCommand, viewport: types.Rect) !FrameStats {
        for (cmds) |cmd| {
            if (!cmd.isValid()) return error.InvalidCommand;
        }
        const stats = cull(cmds, viewport);
        self.submitted_total += stats.submitted;
        self.visible_total += stats.visible;
        self.frames += 1;
        return stats;
    }
};

/// Vtable que backends reais implementam.
pub const BackendVTable = struct {
    submit: *const fn (
        ctx: *anyopaque,
        cmds: []const commands.DrawCommand,
        viewport: types.Rect,
    ) anyerror!FrameStats,
    name: *const fn (ctx: *anyopaque) []const u8,
};

/// Handle opaco para um backend externo.
pub const Backend = struct {
    ptr: *anyopaque,
    vtable: *const BackendVTable,

    pub fn submit(self: Backend, cmds: []const commands.DrawCommand, viewport: types.Rect) !FrameStats {
        return try self.vtable.submit(self.ptr, cmds, viewport);
    }

    pub fn name(self: Backend) []const u8 {
        return self.vtable.name(self.ptr);
    }
};

test "cull separa visível de fora" {
    const stdt = @import("std");
    const vp = types.Rect.init(0, 0, 100, 100);
    const cmds = [_]commands.DrawCommand{
        .{ .clear = .{ .color = types.Color.rgb(0, 0, 0) } },
        .{ .rect_filled = .{ .rect = types.Rect.init(10, 10, 20, 20), .color = types.Color.rgb(255, 0, 0) } },
        .{ .rect_filled = .{ .rect = types.Rect.init(500, 500, 20, 20), .color = types.Color.rgb(0, 255, 0) } },
        .{ .line = .{
            .p0 = types.Vec2.init(1000, 1000),
            .p1 = types.Vec2.init(1010, 1010),
            .color = types.Color.rgb(0, 0, 255),
            .thickness = 1,
        } },
    };
    const s = cull(&cmds, vp);
    try stdt.testing.expectEqual(@as(u32, 4), s.submitted);
    try stdt.testing.expectEqual(@as(u32, 2), s.visible); // clear + rect dentro
    try stdt.testing.expectEqual(@as(u32, 2), s.culled);
}

test "NullRenderer valida e acumula" {
    const stdt = @import("std");
    var r = NullRenderer{};
    const vp = types.Rect.init(0, 0, 100, 100);
    const cmds = [_]commands.DrawCommand{
        .{ .rect_filled = .{ .rect = types.Rect.init(0, 0, 10, 10), .color = types.Color.rgb(1, 2, 3) } },
    };
    const s = try r.submit(&cmds, vp);
    try stdt.testing.expectEqual(@as(u32, 1), s.visible);
    try stdt.testing.expectEqual(@as(usize, 1), r.submitted_total);
    try stdt.testing.expectEqual(@as(u32, 1), r.frames);
    const bad = [_]commands.DrawCommand{
        .{ .rect_filled = .{ .rect = types.Rect.init(0, 0, -5, 5), .color = types.Color.rgb(0, 0, 0) } },
    };
    try stdt.testing.expectError(error.InvalidCommand, r.submit(&bad, vp));
}

test "cull usa bounds de texto" {
    const stdt = @import("std");
    const vp = types.Rect.init(0, 0, 100, 100);
    const inside = [_]commands.DrawCommand{
        .{ .text = .{
            .pos = types.Vec2.init(10, 10),
            .color = types.Color.rgb(255, 255, 255),
            .size = 16,
            .width = 50,
            .start = 0,
            .len = 0,
        } },
    };
    try stdt.testing.expectEqual(@as(u32, 1), cull(&inside, vp).visible);
    const outside = [_]commands.DrawCommand{
        .{ .text = .{
            .pos = types.Vec2.init(500, 500),
            .color = types.Color.rgb(255, 255, 255),
            .size = 16,
            .width = 50,
            .start = 0,
            .len = 0,
        } },
    };
    const s = cull(&outside, vp);
    try stdt.testing.expectEqual(@as(u32, 0), s.visible);
    try stdt.testing.expectEqual(@as(u32, 1), s.culled);
}

test "cull usa bounds do comando de imagem (M123)" {
    const stdt = @import("std");
    const vp = types.Rect.init(0, 0, 100, 100);
    var bytes: [16]u8 = undefined;
    for (&bytes, 0..) |*b, i| b.* = @intCast(i);
    const img = try @import("image.zig").Image.init(2, 2, &bytes);

    var dl = commands.DrawList.initEmpty();
    defer dl.deinit(stdt.testing.allocator);
    try dl.image(stdt.testing.allocator, types.Rect.init(10, 10, 20, 20), img, types.Color.rgb(255, 255, 255));
    try dl.image(stdt.testing.allocator, types.Rect.init(500, 500, 20, 20), img, types.Color.rgb(255, 255, 255));

    try stdt.testing.expectEqual(types.Rect.init(10, 10, 20, 20), commandBounds(dl.items()[0]).?);
    const s = cull(dl.items(), vp);
    try stdt.testing.expectEqual(@as(u32, 1), s.visible);
    try stdt.testing.expectEqual(@as(u32, 1), s.culled);
}

test "cull usa bounds do retângulo arredondado" {
    const stdt = @import("std");
    const vp = types.Rect.init(0, 0, 100, 100);
    try stdt.testing.expectEqual(
        types.Rect.init(10, 10, 20, 20),
        commandBounds(.{ .rect_rounded = .{
            .rect = types.Rect.init(10, 10, 20, 20),
            .radius = 4,
            .color = types.Color.rgb(1, 2, 3),
        } }).?,
    );
    try stdt.testing.expectEqual(
        types.Rect.init(2, 3, 8, 9),
        commandBounds(.{ .rect_gradient = .{
            .rect = types.Rect.init(2, 3, 8, 9),
            .p0 = types.Vec2.init(0, 0),
            .p1 = types.Vec2.init(0, 10),
            .color0 = types.Color.rgb(0, 0, 0),
            .color1 = types.Color.rgb(255, 255, 255),
        } }).?,
    );
    // Sombra: união da silhueta e da silhueta deslocada + pad (blur/2 + 1).
    try stdt.testing.expectEqual(
        types.Rect.init(6, 6, 30, 31),
        commandBounds(.{ .rect_shadow = .{
            .rect = types.Rect.init(10, 10, 20, 20),
            .radius = 4,
            .offset = types.Vec2.init(2, 3),
            .blur = 6,
            .color = .{ .r = 0, .g = 0, .b = 0, .a = 128 },
        } }).?,
    );
    // Blur: bounds é o próprio rect.
    try stdt.testing.expectEqual(
        types.Rect.init(5, 6, 7, 8),
        commandBounds(.{ .blur = .{ .rect = types.Rect.init(5, 6, 7, 8), .radius = 3 } }).?,
    );
    const cmds = [_]commands.DrawCommand{
        .{ .rect_rounded = .{ .rect = types.Rect.init(10, 10, 20, 20), .radius = 4, .color = types.Color.rgb(1, 2, 3) } },
        .{ .rect_rounded = .{ .rect = types.Rect.init(500, 500, 20, 20), .radius = 4, .color = types.Color.rgb(1, 2, 3) } },
    };
    const s = cull(&cmds, vp);
    try stdt.testing.expectEqual(@as(u32, 1), s.visible);
    try stdt.testing.expectEqual(@as(u32, 1), s.culled);
}
