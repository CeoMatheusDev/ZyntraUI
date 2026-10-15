//! ZyntraUI — animações (anim/anim).
//!
//! Extensão OPCIONAL: easing puro + tween + timer, sem alocação,
//! sem estado global, sem thread. O chamador avança o tempo (`tick`)
//! e lê `valueAt`/`progress` para dirigir widgets/estilos.
//! - `Ease.apply`: satura entradas (NaN → 0, resto clampado em 0..1);
//!   sempre retorna finito em [0,1] para easings conhecidos.
//! - `Tween.init` valida `duration` (`InvalidArgument` se <= 0 ou
//!   não-finito). `valueAt` satura o tempo.
//! - `AnimTimer.tick` ignora `dt` negativo/não-finito (saturação
//!   documentada, sem erro na hot path).

const std = @import("std");
const types = @import("../core/types.zig");

/// Curvas de easing (todas com f(0)=0, f(1)=1).
pub const Ease = enum {
    linear,
    quad_in,
    quad_out,
    quad_in_out,
    cubic_in,
    cubic_out,
    cubic_in_out,

    pub fn apply(self: Ease, t: f32) f32 {
        var x = t;
        if (!std.math.isFinite(x)) x = 0;
        x = std.math.clamp(x, 0, 1);
        return switch (self) {
            .linear => x,
            .quad_in => x * x,
            .quad_out => 1 - (1 - x) * (1 - x),
            .quad_in_out => if (x < 0.5) 2 * x * x else 1 - (-2 * x + 2) * (-2 * x + 2) / 2,
            .cubic_in => x * x * x,
            .cubic_out => 1 - (1 - x) * (1 - x) * (1 - x),
            .cubic_in_out => if (x < 0.5)
                4 * x * x * x
            else
                1 - (-2 * x + 2) * (-2 * x + 2) * (-2 * x + 2) / 2,
        };
    }
};

/// Interpolação linear `from → to` ao longo de `duration` segundos.
pub const Tween = struct {
    from: f32,
    to: f32,
    duration: f32,
    ease: Ease = .linear,

    pub fn init(from: f32, to: f32, duration: f32, ease: Ease) !Tween {
        if (!std.math.isFinite(from) or !std.math.isFinite(to)) return error.InvalidArgument;
        if (!std.math.isFinite(duration) or duration <= 0) return error.InvalidArgument;
        return .{ .from = from, .to = to, .duration = duration, .ease = ease };
    }

    /// Valor em `elapsed` segundos (saturado em [from,to]).
    pub fn valueAt(self: Tween, elapsed: f32) f32 {
        var t = elapsed / self.duration;
        if (!std.math.isFinite(t)) t = if (elapsed >= 0) 1 else 0;
        return self.from + (self.to - self.from) * self.ease.apply(t);
    }

    pub fn doneAt(self: Tween, elapsed: f32) bool {
        return elapsed >= self.duration;
    }
};

/// Cronômetro de animação; o chamador dita `dt` por frame.
pub const AnimTimer = struct {
    duration: f32,
    elapsed: f32 = 0,
    looping: bool = false,

    pub fn init(duration: f32, looping: bool) !AnimTimer {
        if (!std.math.isFinite(duration) or duration <= 0) return error.InvalidArgument;
        return .{ .duration = duration, .looping = looping };
    }

    pub fn reset(self: *AnimTimer) void {
        self.elapsed = 0;
    }

    pub fn tick(self: *AnimTimer, dt: f32) void {
        if (!std.math.isFinite(dt) or dt < 0) return;
        self.elapsed += dt;
        if (self.looping and self.duration > 0) {
            self.elapsed = @mod(self.elapsed, self.duration);
        }
    }

    /// Progresso 0..1 (saturado quando não-looping).
    pub fn progress(self: *const AnimTimer) f32 {
        const t = self.elapsed / self.duration;
        if (!std.math.isFinite(t)) return 1;
        return std.math.clamp(t, 0, 1);
    }

    pub fn done(self: *const AnimTimer) bool {
        return !self.looping and self.elapsed >= self.duration;
    }
};

/// Interpola dois `Color` por canal (t saturado). Arredonda para o u8
/// mais próximo; alfa incluído.
pub fn lerpColor(a: types.Color, b: types.Color, t: f32) types.Color {
    const x = Ease.linear.apply(t);
    return .{
        .r = lerpChannel(a.r, b.r, x),
        .g = lerpChannel(a.g, b.g, x),
        .b = lerpChannel(a.b, b.b, x),
        .a = lerpChannel(a.a, b.a, x),
    };
}

fn lerpChannel(u: u8, v: u8, x: f32) u8 {
    const r = @as(f32, @floatFromInt(u)) + (@as(f32, @floatFromInt(v)) - @as(f32, @floatFromInt(u))) * x;
    return @intFromFloat(std.math.clamp(r + 0.5, 0, 255));
}

test "Ease endpoints e valores conhecidos" {
    const stdt = @import("std");
    const easings = [_]Ease{ .linear, .quad_in, .quad_out, .quad_in_out, .cubic_in, .cubic_out, .cubic_in_out };
    for (easings) |e| {
        try stdt.testing.expectEqual(@as(f32, 0), e.apply(0));
        try stdt.testing.expectEqual(@as(f32, 1), e.apply(1));
        try stdt.testing.expectEqual(@as(f32, 0), e.apply(-5));
        try stdt.testing.expectEqual(@as(f32, 1), e.apply(99));
        try stdt.testing.expectEqual(@as(f32, 0), e.apply(std.math.nan(f32)));
    }
    try stdt.testing.expectApproxEqAbs(@as(f32, 0.5), Ease.linear.apply(0.5), 1e-6);
    try stdt.testing.expectApproxEqAbs(@as(f32, 0.75), Ease.quad_out.apply(0.5), 1e-6);
    try stdt.testing.expectApproxEqAbs(@as(f32, 0.25), Ease.quad_in.apply(0.5), 1e-6);
    try stdt.testing.expectApproxEqAbs(@as(f32, 0.5), Ease.quad_in_out.apply(0.5), 1e-6);
}

test "Tween valueAt e validação" {
    const stdt = @import("std");
    const tw = try Tween.init(0, 100, 2.0, .linear);
    try stdt.testing.expectEqual(@as(f32, 0), tw.valueAt(0));
    try stdt.testing.expectEqual(@as(f32, 50), tw.valueAt(1.0));
    try stdt.testing.expectEqual(@as(f32, 100), tw.valueAt(2.0));
    try stdt.testing.expectEqual(@as(f32, 100), tw.valueAt(99));
    try stdt.testing.expectEqual(@as(f32, 0), tw.valueAt(-1));
    try stdt.testing.expect(!tw.doneAt(1.9));
    try stdt.testing.expect(tw.doneAt(2.0));
    try stdt.testing.expectError(error.InvalidArgument, Tween.init(0, 1, 0, .linear));
    try stdt.testing.expectError(error.InvalidArgument, Tween.init(0, 1, -1, .linear));
    try stdt.testing.expectError(error.InvalidArgument, Tween.init(std.math.nan(f32), 1, 1, .linear));
}

test "AnimTimer progresso, loop e done" {
    const stdt = @import("std");
    var tm = try AnimTimer.init(1.0, false);
    try stdt.testing.expectEqual(@as(f32, 0), tm.progress());
    tm.tick(0.5);
    try stdt.testing.expectEqual(@as(f32, 0.5), tm.progress());
    try stdt.testing.expect(!tm.done());
    tm.tick(-1); // ignorado
    try stdt.testing.expectEqual(@as(f32, 0.5), tm.progress());
    tm.tick(std.math.nan(f32)); // ignorado
    try stdt.testing.expectEqual(@as(f32, 0.5), tm.progress());
    tm.tick(0.7);
    try stdt.testing.expectEqual(@as(f32, 1), tm.progress());
    try stdt.testing.expect(tm.done());
    tm.reset();
    try stdt.testing.expect(!tm.done());

    var loop = try AnimTimer.init(1.0, true);
    loop.tick(2.5);
    try stdt.testing.expectApproxEqAbs(@as(f32, 0.5), loop.progress(), 1e-6);
    try stdt.testing.expect(!loop.done());
    try stdt.testing.expectError(error.InvalidArgument, AnimTimer.init(0, false));
}

test "lerpColor ponto médio" {
    const stdt = @import("std");
    const C = @import("../core/types.zig").Color;
    const mid = lerpColor(C.rgb(0, 0, 0), C.rgb(255, 255, 255), 0.5);
    try stdt.testing.expectEqual(C.rgb(128, 128, 128), mid);
    try stdt.testing.expectEqual(C.rgb(0, 0, 0), lerpColor(C.rgb(0, 0, 0), C.rgb(255, 0, 0), 0));
    try stdt.testing.expectEqual(C.rgb(255, 0, 0), lerpColor(C.rgb(0, 0, 0), C.rgb(255, 0, 0), 1));
}
