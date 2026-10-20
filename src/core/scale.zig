//! ZyntraUI — escala DPI (core/scale).
//!
//! Escopo M125: a biblioteca trabalha em pixels LÓGICOS; o host
//! (janela/renderer) trabalha em pixels de DISPOSITIVO. Este módulo é
//! a ponte entre os dois espaços.
//! - `DpiScale.factor` = pixels de dispositivo por pixel lógico
//!   (1 = 100%, 2 = 200%).
//! - Conversões de ponto/tamanho/rect e `snapDevice` (alinha o rect
//!   lógico à grade de pixels de dispositivo, para bordas nítidas).
//! Ownership: valor puro, sem alocação e sem estado global.
//! Validação: fator finito e > 0.

const std = @import("std");
const types = @import("types.zig");

/// Fator de escala entre pixels lógicos e pixels de dispositivo.
pub const DpiScale = struct {
    /// Pixels de dispositivo por pixel lógico.
    factor: f32 = 1.0,

    pub const Self = @This();

    pub fn isValid(self: Self) bool {
        return std.math.isFinite(self.factor) and self.factor > 0;
    }

    /// Constrói a escala a partir de DPI (96 DPI = 100%).
    /// `null` para DPI não-finito ou ≤ 0.
    pub fn fromDpi(dpi: f32) ?Self {
        if (!std.math.isFinite(dpi) or dpi <= 0) return null;
        return .{ .factor = dpi / 96.0 };
    }

    /// Converte um valor lógico para pixels de dispositivo.
    pub fn toDevice(self: Self, logical: f32) f32 {
        return logical * self.factor;
    }

    /// Converte um valor de dispositivo para pixels lógicos.
    pub fn toLogical(self: Self, device: f32) f32 {
        return device / self.factor;
    }

    pub fn vec(self: Self, v: types.Vec2) types.Vec2 {
        return .{ .x = v.x * self.factor, .y = v.y * self.factor };
    }

    /// Converte um ponto de dispositivo para pixels lógicos.
    pub fn vecToLogical(self: Self, v: types.Vec2) types.Vec2 {
        return .{ .x = v.x / self.factor, .y = v.y / self.factor };
    }

    pub fn size(self: Self, s: types.Size) types.Size {
        return .{ .w = s.w * self.factor, .h = s.h * self.factor };
    }

    pub fn rect(self: Self, r: types.Rect) types.Rect {
        return .{
            .x = r.x * self.factor,
            .y = r.y * self.factor,
            .w = r.w * self.factor,
            .h = r.h * self.factor,
        };
    }

    /// Converte um rect de dispositivo para pixels lógicos.
    pub fn rectToLogical(self: Self, r: types.Rect) types.Rect {
        return .{
            .x = r.x / self.factor,
            .y = r.y / self.factor,
            .w = r.w / self.factor,
            .h = r.h / self.factor,
        };
    }

    /// Converte um tamanho de dispositivo para pixels lógicos.
    pub fn sizeToLogical(self: Self, s: types.Size) types.Size {
        return .{ .w = s.w / self.factor, .h = s.h / self.factor };
    }

    /// Alinha o rect lógico à grade de pixels de dispositivo: o lado
    /// esquerdo/superior arredonda para dentro e o direito/inferior para
    /// fora, de modo que a borda caia exatamente num pixel físico.
    /// O resultado volta em pixels lógicos.
    pub fn snapDevice(self: Self, r: types.Rect) types.Rect {
        const x0 = @floor(r.x * self.factor);
        const y0 = @floor(r.y * self.factor);
        const x1 = @ceil((r.x + r.w) * self.factor);
        const y1 = @ceil((r.y + r.h) * self.factor);
        return .{
            .x = x0 / self.factor,
            .y = y0 / self.factor,
            .w = @max(0, (x1 - x0) / self.factor),
            .h = @max(0, (y1 - y0) / self.factor),
        };
    }
};

test "DpiScale converte e valida" {
    const stdt = @import("std");
    const s = DpiScale{ .factor = 2.0 };
    try stdt.testing.expect(s.isValid());
    try stdt.testing.expectEqual(@as(f32, 40), s.toDevice(20));
    try stdt.testing.expectEqual(@as(f32, 20), s.toLogical(40));
    try stdt.testing.expectEqual(types.Vec2.init(20, 10), s.vec(types.Vec2.init(10, 5)));
    try stdt.testing.expectEqual(types.Size{ .w = 20, .h = 10 }, s.size(types.Size{ .w = 10, .h = 5 }));
    try stdt.testing.expectEqual(
        types.Rect.init(20, 10, 40, 20),
        s.rect(types.Rect.init(10, 5, 20, 10)),
    );

    try stdt.testing.expect(!(DpiScale{ .factor = 0 }).isValid());
    try stdt.testing.expect(!(DpiScale{ .factor = -1 }).isValid());
    try stdt.testing.expect(!(DpiScale{ .factor = std.math.nan(f32) }).isValid());
    try stdt.testing.expect(!(DpiScale{ .factor = std.math.inf(f32) }).isValid());

    // 96 DPI = 100%; 144 DPI = 150%.
    try stdt.testing.expectEqual(@as(f32, 1), DpiScale.fromDpi(96).?.factor);
    try stdt.testing.expectEqual(@as(f32, 1.5), DpiScale.fromDpi(144).?.factor);
    try stdt.testing.expect(DpiScale.fromDpi(0) == null);
    try stdt.testing.expect(DpiScale.fromDpi(std.math.nan(f32)) == null);
}

test "DpiScale.snapDevice alinha na grade física" {
    const stdt = @import("std");
    const s = DpiScale{ .factor = 2.0 };
    // 10.3..20.7 lógico => 20.6..41.4 device => 20..42 device
    // => 10..21 lógico (largura 11). Vertical: 5.1..20.7 => 10..42
    // device => 5..21 lógico (altura 16).
    const snapped = s.snapDevice(types.Rect.init(10.3, 5.1, 10.4, 15.6));
    try stdt.testing.expectEqual(@as(f32, 10), snapped.x);
    try stdt.testing.expectEqual(@as(f32, 5), snapped.y);
    try stdt.testing.expectEqual(@as(f32, 11), snapped.w);
    try stdt.testing.expectEqual(@as(f32, 16), snapped.h);

    // Escala 1:1 não muda nada além do arredondamento.
    const one = DpiScale{};
    const r = types.Rect.init(1, 2, 3, 4);
    try stdt.testing.expectEqual(r, one.snapDevice(r));
}
