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
        .clip => |c| {
            if (c.null_rect) return null;
            return c.rect;
        },
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
