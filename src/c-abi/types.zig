//! ZyntraUI — tipos C-ABI (c-abi/types).
//!
//! Representação definida para a fronteira C:
//! - Todos os structs são `extern` (layout C garantido).
//! - Tamanhos/alinhamentos travados por asserts de compilação —
//!   qualquer mudança que quebre a ABI falha o build, não o runtime.
//! - `ZyntraResult` tem tag `c_int` explícita; 0 sempre é sucesso.

const std = @import("std");
const raster_mod = @import("../software/raster.zig");

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

// Trava de ABI: falhe o build se o layout mudar.
comptime {
    if (@sizeOf(ZyntraResult) != @sizeOf(c_int)) @compileError("ZyntraResult ABI drift");
    if (@sizeOf(ZyntraRenderStats) != 16 or @alignOf(ZyntraRenderStats) != 4) @compileError("ZyntraRenderStats ABI drift");
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
    try stdt.testing.expectEqual(@as(c_int, 0), @backingInt(ZyntraResult.ok));
}
