//! ZyntraUI — layout minimalista (layout/layout).
//!
//! Escopo M3: geometria pura, sem alocação, sem estado global.
//! - `Constraints`: clamp de tamanhos.
//! - `EdgeInsets`: padding/margem aplicado a `Rect`.
//! - `StackPlacer`: posicionamento sequencial vertical/horizontal
//!   sem alocar (cursor interno). O chamador detém `Sizes` e `Rects`.
//! Lifetime: tudo por valor; slices de entrada/saída do chamador.
//! Validação: `NaN/Inf` em tamanhos é rejeitado via `isValid`.

const std = @import("std");
const types = @import("../core/types.zig");

/// Restrições de tamanho em pixels lógicos.
pub const Constraints = struct {
    min: types.Size = .{},
    max: types.Size = .{ .w = std.math.inf(f32), .h = std.math.inf(f32) },

    pub fn fixed(w: f32, h: f32) Constraints {
        return .{ .min = .{ .w = w, .h = h }, .max = .{ .w = w, .h = h } };
    }

    pub fn isValid(self: Constraints) bool {
        return std.math.isFinite(self.min.w) and std.math.isFinite(self.min.h) and
            self.min.w >= 0 and self.min.h >= 0 and
            (std.math.isInf(self.max.w) or (std.math.isFinite(self.max.w) and self.max.w >= self.min.w)) and
            (std.math.isInf(self.max.h) or (std.math.isFinite(self.max.h) and self.max.h >= self.min.h));
    }

    pub fn constrain(self: Constraints, s: types.Size) types.Size {
        return .{
            .w = std.math.clamp(s.w, self.min.w, self.max.w),
            .h = std.math.clamp(s.h, self.min.h, self.max.h),
        };
    }
};

/// Padding/margem.
pub const EdgeInsets = extern struct {
    left: f32 = 0,
    top: f32 = 0,
    right: f32 = 0,
    bottom: f32 = 0,

    pub fn all(v: f32) EdgeInsets {
        return .{ .left = v, .top = v, .right = v, .bottom = v };
    }

    pub fn isValid(self: EdgeInsets) bool {
        return std.math.isFinite(self.left) and std.math.isFinite(self.top) and
            std.math.isFinite(self.right) and std.math.isFinite(self.bottom) and
            self.left >= 0 and self.top >= 0 and self.right >= 0 and self.bottom >= 0;
    }

    /// Aplica inset; se padding exceder o tamanho, retorna rect vazio
    /// ancorado na origem (nunca negativo).
    pub fn apply(self: EdgeInsets, r: types.Rect) types.Rect {
        const x = r.x + self.left;
        const y = r.y + self.top;
        const w = @max(0, r.w - self.left - self.right);
        const h = @max(0, r.h - self.top - self.bottom);
        return .{ .x = x, .y = y, .w = w, .h = h };
    }
};

/// Direção de empilhamento.
pub const StackDirection = enum { vertical, horizontal };

/// Posicionador sequencial sem alocação.
pub const StackPlacer = struct {
    area: types.Rect,
    direction: StackDirection,
    spacing: f32,
    cursor: f32,

    pub fn init(area: types.Rect, direction: StackDirection, spacing: f32) StackPlacer {
        std.debug.assert(spacing >= 0);
        return .{
            .area = area,
            .direction = direction,
            .spacing = spacing,
            .cursor = switch (direction) {
                .vertical => area.y,
                .horizontal => area.x,
            },
        };
    }

    /// Retorna o rect do próximo filho e avança o cursor.
    /// Largura (vertical) é limitada à área; altura respeitada.
    pub fn next(self: *StackPlacer, child: types.Size) types.Rect {
        const w = @max(0, @min(child.w, self.area.w));
        const h = @max(0, child.h);
        const r = switch (self.direction) {
            .vertical => types.Rect{
                .x = self.area.x,
                .y = self.cursor,
                .w = w,
                .h = h,
            },
            .horizontal => types.Rect{
                .x = self.cursor,
                .y = self.area.y,
                .w = @max(0, @min(child.w, self.area.w - (self.cursor - self.area.x))),
                .h = @max(0, @min(child.h, self.area.h)),
            },
        };
        self.cursor += h + self.spacing;
        if (self.direction == .horizontal) {
            // Para horizontal o avanço é pela largura, corrige:
            self.cursor -= h + self.spacing;
            self.cursor += r.w + self.spacing;
        }
        return r;
    }

    pub fn remaining(self: *const StackPlacer) f32 {
        return switch (self.direction) {
            .vertical => @max(0, (self.area.y + self.area.h) - self.cursor),
            .horizontal => @max(0, (self.area.x + self.area.w) - self.cursor),
        };
    }
};

/// Centraliza `child` dentro de `container` (clampa em zero).
pub fn centered(container: types.Rect, child: types.Size) types.Rect {
    return .{
        .x = container.x + @max(0, (container.w - child.w) / 2),
        .y = container.y + @max(0, (container.h - child.h) / 2),
        .w = @max(0, @min(child.w, container.w)),
        .h = @max(0, @min(child.h, container.h)),
    };
}

test "Constraints.constrain clampa" {
    const stdt = @import("std");
    const c = Constraints{ .min = .{ .w = 10, .h = 10 }, .max = .{ .w = 100, .h = 50 } };
    try stdt.testing.expect(c.isValid());
    try stdt.testing.expectEqual(types.Size{ .w = 10, .h = 50 }, c.constrain(.{ .w = 0, .h = 99 }));
    try stdt.testing.expectEqual(types.Size{ .w = 50, .h = 20 }, c.constrain(.{ .w = 50, .h = 20 }));
    const bad = Constraints{ .min = .{ .w = 10, .h = 0 }, .max = .{ .w = 5, .h = 5 } };
    try stdt.testing.expect(!bad.isValid());
}

test "EdgeInsets.apply nunca negativo" {
    const stdt = @import("std");
    const r = EdgeInsets.all(10).apply(types.Rect.init(0, 0, 100, 50));
    try stdt.testing.expectEqual(types.Rect.init(10, 10, 80, 30), r);
    const empty = EdgeInsets.all(100).apply(types.Rect.init(0, 0, 50, 50));
    try stdt.testing.expectEqual(@as(f32, 0), empty.w);
    try stdt.testing.expectEqual(@as(f32, 0), empty.h);
}

test "StackPlacer vertical empilha com spacing" {
    const stdt = @import("std");
    var p = StackPlacer.init(types.Rect.init(0, 0, 200, 200), .vertical, 8);
    const a = p.next(.{ .w = 200, .h = 40 });
    const b = p.next(.{ .w = 200, .h = 30 });
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 200, 40), a);
    try stdt.testing.expectEqual(types.Rect.init(0, 48, 200, 30), b);
    try stdt.testing.expectEqual(@as(f32, 114), p.remaining());
}

test "centered centraliza e clampa" {
    const stdt = @import("std");
    try stdt.testing.expectEqual(
        types.Rect.init(40, 45, 20, 10),
        centered(types.Rect.init(0, 0, 100, 100), .{ .w = 20, .h = 10 }),
    );
}

test "fuzz layout: sem crash, invariantes em entradas finitas" {
    try std.testing.fuzz({}, fuzzLayout, .{});
}

fn fuzzLayout(_: void, smith: *std.testing.Smith) !void {
    var fb: [32]u8 = undefined;
    smith.bytes(&fb);
    const bits: [8]f32 = @bitCast(fb);
    // bits[0..2] = área, bits[2..4] = filho, bits[4..6] = constraints, bits[6..8] = insets
    const area = types.Rect.init(bits[0], bits[1], @abs(bits[2]), @abs(bits[3]));
    const child = types.Size{ .w = @abs(bits[2]), .h = @abs(bits[3]) };
    const insets = EdgeInsets{
        .left = @abs(bits[6]),
        .top = @abs(bits[7]),
        .right = @abs(bits[6]),
        .bottom = @abs(bits[7]),
    };

    // Sem crash nunca (só matemática f32, sem conversão p/ int).
    const applied = insets.apply(area);
    var placer = StackPlacer.init(area, .vertical, @abs(bits[4]));
    const r0 = placer.next(child);
    const r1 = placer.next(child);
    const cc = centered(area, child);
    const cons = Constraints{
        .min = .{ .w = 0, .h = 0 },
        .max = .{ .w = @abs(bits[4]) + 1, .h = @abs(bits[5]) + 1 },
    };
    const cs = cons.constrain(child);

    // Invariantes quando tudo é finito.
    const all_finite = std.math.isFinite(bits[0]) and std.math.isFinite(bits[1]) and
        std.math.isFinite(bits[2]) and std.math.isFinite(bits[3]) and
        std.math.isFinite(bits[4]) and std.math.isFinite(bits[5]) and
        std.math.isFinite(bits[6]) and std.math.isFinite(bits[7]);
    if (!all_finite) return;
    try std.testing.expect(applied.w >= 0 and applied.h >= 0);
    try std.testing.expect(r0.x == area.x and r1.x == area.x);
    try std.testing.expect(r1.y >= r0.y); // cursor avança
    try std.testing.expect(r0.w <= @max(0, area.w) + 0.001);
    try std.testing.expect(cc.x >= @min(area.x, area.x + area.w));
    try std.testing.expect(cs.w >= 0 and cs.w <= cons.max.w);
    try std.testing.expect(cs.h >= 0 and cs.h <= cons.max.h);
}
