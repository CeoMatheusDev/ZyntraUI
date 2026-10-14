//! ZyntraUI — estilos e temas (style/style).
//!
//! Escopo M3: cores e métricas por valor, sem alocação.
//! `Theme` agrega a paleta; helpers derivam estilos de widgets.
//! Validação: espessuras/raios finitos e >= 0.

const std = @import("std");
const types = @import("../core/types.zig");

/// Estilo de botão por estado.
pub const ButtonStyle = extern struct {
    bg: types.Color,
    bg_hover: types.Color,
    bg_pressed: types.Color,
    border: types.Color,
    border_width: f32 = 1.0,
    radius: f32 = 0,

    pub fn isValid(self: ButtonStyle) bool {
        return std.math.isFinite(self.border_width) and self.border_width >= 0 and
            std.math.isFinite(self.radius) and self.radius >= 0;
    }
};

/// Estilo de checkbox.
pub const CheckboxStyle = extern struct {
    box_size: f32 = 18,
    bg: types.Color,
    bg_checked: types.Color,
    border: types.Color,
    check: types.Color,
    border_width: f32 = 1.0,

    pub fn isValid(self: CheckboxStyle) bool {
        return std.math.isFinite(self.box_size) and self.box_size > 0 and
            std.math.isFinite(self.border_width) and self.border_width >= 0;
    }
};

/// Paleta mínima do tema.
pub const Theme = extern struct {
    bg: types.Color,
    surface: types.Color,
    text: types.Color,
    accent: types.Color,
    border: types.Color,

    pub fn darkDefault() Theme {
        return .{
            .bg = types.Color.rgb(24, 24, 28),
            .surface = types.Color.rgb(50, 50, 55),
            .text = types.Color.rgb(235, 235, 240),
            .accent = types.Color.rgb(70, 110, 180),
            .border = types.Color.rgb(255, 255, 255),
        };
    }

    pub fn lightDefault() Theme {
        return .{
            .bg = types.Color.rgb(245, 245, 247),
            .surface = types.Color.rgb(255, 255, 255),
            .text = types.Color.rgb(20, 20, 25),
            .accent = types.Color.rgb(40, 90, 200),
            .border = types.Color.rgb(60, 60, 70),
        };
    }

    pub fn buttonStyle(self: Theme) ButtonStyle {
        return .{
            .bg = self.surface,
            .bg_hover = self.accent,
            .bg_pressed = types.Color.rgb(60, 140, 70),
            .border = self.border,
            .border_width = 1.0,
            .radius = 0,
        };
    }

    pub fn checkboxStyle(self: Theme) CheckboxStyle {
        return .{
            .box_size = 18,
            .bg = self.surface,
            .bg_checked = self.accent,
            .border = self.border,
            .check = types.Color.rgb(255, 255, 255),
            .border_width = 1.0,
        };
    }
};

test "Theme defaults + derivados válidos" {
    const stdt = @import("std");
    const dark = Theme.darkDefault();
    const light = Theme.lightDefault();
    try stdt.testing.expect(dark.buttonStyle().isValid());
    try stdt.testing.expect(light.buttonStyle().isValid());
    try stdt.testing.expect(dark.checkboxStyle().isValid());
    const bad_btn = ButtonStyle{
        .bg = dark.bg,
        .bg_hover = dark.bg,
        .bg_pressed = dark.bg,
        .border = dark.border,
        .border_width = -1,
    };
    try stdt.testing.expect(!bad_btn.isValid());
    const bad_chk = CheckboxStyle{
        .box_size = 0,
        .bg = dark.bg,
        .bg_checked = dark.bg,
        .border = dark.border,
        .check = dark.text,
    };
    try stdt.testing.expect(!bad_chk.isValid());
}
