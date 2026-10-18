//! ZyntraUI — tipos C-ABI (c-abi/types).
//!
//! Representação definida para a fronteira C:
//! - Todos os structs são `extern` (layout C garantido).
//! - Tamanhos/alinhamentos travados por asserts de compilação —
//!   qualquer mudança que quebre a ABI falha o build, não o runtime.
//! - `ZyntraResult` tem tag `c_int` explícita; 0 sempre é sucesso.

const std = @import("std");
const raster_mod = @import("../software/raster.zig");
const metrics_mod = @import("../text/metrics.zig");
const style_mod = @import("../style/style.zig");

/// Código de retorno de toda função C-ABI. Sempre por valor, nunca
/// via error union (Zig) ou exceção.
pub const ZyntraResult = enum(c_int) {
    ok = 0,
    invalid_argument = 1,
    out_of_memory = 2,
    invalid_event = 3,
    invalid_command = 4,
    invalid_state = 5,
    /// Texto malformado (UTF-8 inválido em text-runs).
    invalid_text = 6,
};

pub const ZyntraVec2 = extern struct {
    x: f32 = 0,
    y: f32 = 0,
};

pub const ZyntraSize = extern struct {
    w: f32 = 0,
    h: f32 = 0,
};

pub const ZyntraRect = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,
};

pub const ZyntraColor = extern struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 255,
};

/// Estatísticas da rasterização de software, devolvidas por
/// `zyntra_framebuffer_render*`. Reexporta o struct `extern` do backend de
/// referência (mesmos campos/ordem) para não haver duas definições; a trava
/// de layout abaixo falha o build se ele mudar.
pub const ZyntraRenderStats = raster_mod.SoftwareStats;

/// Id de widget na fronteira: o mesmo `u64` opaco da API Zig
/// (`Id.fromU64`/`value`). `0` é o id nulo e os widgets o rejeitam.
pub const ZyntraId = u64;

/// Tema embutido usado pelos getters de estilo (`zyntra_style_*`) e por
/// `zyntra_theme_colors`.
pub const ZyntraThemeKind = enum(c_int) {
    dark = 0,
    light = 1,
};

/// Cores base do tema (espelha `style.Theme`; só os cinco tons base).
pub const ZyntraThemeColors = extern struct {
    bg: ZyntraColor = .{},
    surface: ZyntraColor = .{},
    text: ZyntraColor = .{},
    accent: ZyntraColor = .{},
    border: ZyntraColor = .{},
};

/// Orientação de widgets lineares (separador hoje; outros no futuro).
pub const ZyntraOrientation = enum(c_int) {
    horizontal = 0,
    vertical = 1,
};

/// Métricas de texto (reexporta o `extern struct` da API Zig).
pub const ZyntraTextMetrics = metrics_mod.TextMetrics;

// Estilos: reexportados dos `extern struct` da API Zig — uma definição só,
// com a trava de layout abaixo falhando o build se o backend mudar.
pub const ZyntraButtonStyle = style_mod.ButtonStyle;
pub const ZyntraCheckboxStyle = style_mod.CheckboxStyle;
pub const ZyntraSwitchStyle = style_mod.SwitchStyle;
pub const ZyntraSliderStyle = style_mod.SliderStyle;
pub const ZyntraProgressStyle = style_mod.ProgressStyle;
pub const ZyntraSeparatorStyle = style_mod.SeparatorStyle;

// Resultados: definidos aqui como `extern struct` (a API Zig usa structs
// comuns; a cópia campo a campo nos wrappers evita depender do layout deles).
pub const ZyntraLabelResult = extern struct {
    metrics: ZyntraTextMetrics = .{},
    truncated: bool = false,
};

pub const ZyntraButtonResult = extern struct {
    hovered: bool = false,
    pressed: bool = false,
    clicked: bool = false,
};

pub const ZyntraCheckboxResult = extern struct {
    hovered: bool = false,
    toggled: bool = false,
    checked: bool = false,
};

pub const ZyntraSwitchResult = extern struct {
    hovered: bool = false,
    toggled: bool = false,
    checked: bool = false,
    focused: bool = false,
};

pub const ZyntraSliderResult = extern struct {
    value: f32 = 0,
    changed: bool = false,
    hovered: bool = false,
    dragging: bool = false,
};

// Trava de ABI: falhe o build se o layout mudar.
comptime {
    if (@sizeOf(ZyntraResult) != @sizeOf(c_int)) @compileError("ZyntraResult ABI drift");
    if (@sizeOf(ZyntraRenderStats) != 16 or @alignOf(ZyntraRenderStats) != 4) @compileError("ZyntraRenderStats ABI drift");
    if (@sizeOf(ZyntraId) != 8 or @alignOf(ZyntraId) != 8) @compileError("ZyntraId ABI drift");
    if (@sizeOf(ZyntraThemeColors) != 20 or @alignOf(ZyntraThemeColors) != 1) @compileError("ZyntraThemeColors ABI drift");
    if (@sizeOf(ZyntraTextMetrics) != 16 or @alignOf(ZyntraTextMetrics) != 4) @compileError("ZyntraTextMetrics ABI drift");
    if (@sizeOf(ZyntraButtonStyle) != 24 or @alignOf(ZyntraButtonStyle) != 4) @compileError("ZyntraButtonStyle ABI drift");
    if (@sizeOf(ZyntraCheckboxStyle) != 24 or @alignOf(ZyntraCheckboxStyle) != 4) @compileError("ZyntraCheckboxStyle ABI drift");
    if (@sizeOf(ZyntraSwitchStyle) != 28 or @alignOf(ZyntraSwitchStyle) != 4) @compileError("ZyntraSwitchStyle ABI drift");
    if (@sizeOf(ZyntraSliderStyle) != 32 or @alignOf(ZyntraSliderStyle) != 4) @compileError("ZyntraSliderStyle ABI drift");
    if (@sizeOf(ZyntraProgressStyle) != 16 or @alignOf(ZyntraProgressStyle) != 4) @compileError("ZyntraProgressStyle ABI drift");
    if (@sizeOf(ZyntraSeparatorStyle) != 12 or @alignOf(ZyntraSeparatorStyle) != 4) @compileError("ZyntraSeparatorStyle ABI drift");
    if (@sizeOf(ZyntraLabelResult) != 20 or @alignOf(ZyntraLabelResult) != 4) @compileError("ZyntraLabelResult ABI drift");
    if (@sizeOf(ZyntraButtonResult) != 3 or @alignOf(ZyntraButtonResult) != 1) @compileError("ZyntraButtonResult ABI drift");
    if (@sizeOf(ZyntraCheckboxResult) != 3 or @alignOf(ZyntraCheckboxResult) != 1) @compileError("ZyntraCheckboxResult ABI drift");
    if (@sizeOf(ZyntraSwitchResult) != 4 or @alignOf(ZyntraSwitchResult) != 1) @compileError("ZyntraSwitchResult ABI drift");
    if (@sizeOf(ZyntraSliderResult) != 8 or @alignOf(ZyntraSliderResult) != 4) @compileError("ZyntraSliderResult ABI drift");
    if (@sizeOf(ZyntraVec2) != 8 or @alignOf(ZyntraVec2) != 4) @compileError("ZyntraVec2 ABI drift");
    if (@sizeOf(ZyntraSize) != 8 or @alignOf(ZyntraSize) != 4) @compileError("ZyntraSize ABI drift");
    if (@sizeOf(ZyntraRect) != 16 or @alignOf(ZyntraRect) != 4) @compileError("ZyntraRect ABI drift");
    if (@sizeOf(ZyntraColor) != 4 or @alignOf(ZyntraColor) != 1) @compileError("ZyntraColor ABI drift");
    std.debug.assert(@backingInt(ZyntraResult.ok) == 0);
}

test "C-ABI tipos: tamanhos e ok==0" {
    const stdt = @import("std");
    try stdt.testing.expectEqual(@as(usize, 8), @sizeOf(ZyntraVec2));
    try stdt.testing.expectEqual(@as(usize, 16), @sizeOf(ZyntraRect));
    try stdt.testing.expectEqual(@as(usize, 4), @sizeOf(ZyntraColor));
    try stdt.testing.expectEqual(@as(usize, 16), @sizeOf(ZyntraRenderStats));
    try stdt.testing.expectEqual(@as(usize, 8), @sizeOf(ZyntraId));
    try stdt.testing.expectEqual(@as(usize, 24), @sizeOf(ZyntraButtonStyle));
    try stdt.testing.expectEqual(@as(usize, 3), @sizeOf(ZyntraButtonResult));
    try stdt.testing.expectEqual(@as(usize, 20), @sizeOf(ZyntraLabelResult));
    try stdt.testing.expectEqual(@as(c_int, 0), @backingInt(ZyntraResult.ok));
    try stdt.testing.expectEqual(@as(i32, 0), @backingInt(ZyntraThemeKind.dark));
    try stdt.testing.expectEqual(@as(i32, 1), @backingInt(ZyntraThemeKind.light));
}
