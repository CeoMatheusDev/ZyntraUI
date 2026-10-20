//! ZyntraUI — imagens RGBA8 (draw/image).
//!
//! Escopo M123: representação e validação de uma imagem de pixels
//! fornecida pelo chamador, sem decodificação e sem alocação própria.
//! - `Image`: pixels RGBA8 não-premultiplicados, row-major, com `stride`
//!   em bytes. O chamador detém os bytes; eles precisam viver até o
//!   backend consumir o comando (a `DrawList` não copia pixels).
//! - `Region`: sub-retângulo inteiro da imagem, usado por sprites/atlas.
//! Lifetime: `Image` empresta `pixels`; não há posse transferida.
//! Validação: largura/altura > 0, `stride` suficiente e pixels presentes.

const std = @import("std");
const types = @import("../core/types.zig");

/// Bytes por pixel do formato suportado (RGBA8).
pub const bytes_per_pixel: u32 = 4;

/// Sub-retângulo inteiro em pixels de uma imagem (origem no topo-esquerdo).
pub const Region = extern struct {
    x: u32 = 0,
    y: u32 = 0,
    w: u32 = 0,
    h: u32 = 0,

    pub fn init(x: u32, y: u32, w: u32, h: u32) Region {
        return .{ .x = x, .y = y, .w = w, .h = h };
    }

    /// Região preenchida e contida em `width`×`height`.
    pub fn isValidFor(self: Region, width: u32, height: u32) bool {
        if (self.w == 0 or self.h == 0) return false;
        const x1 = @as(u64, self.x) + self.w;
        const y1 = @as(u64, self.y) + self.h;
        return x1 <= width and y1 <= height;
    }
};

/// Imagem RGBA8 não-premultiplicada, row-major.
///
/// O buffer é emprestado: a imagem não copia nem libera `pixels`.
pub const Image = struct {
    width: u32 = 0,
    height: u32 = 0,
    /// Distância em bytes entre o início de duas linhas.
    stride: u32 = 0,
    pixels: []const u8 = &.{},

    const Self = @This();

    pub const Error = error{InvalidImage};

    /// Cria uma imagem compacta (`stride = width * 4`).
    /// `pixels` precisa conter ao menos `width * height * 4` bytes.
    pub fn init(width: u32, height: u32, pixels: []const u8) Error!Self {
        const row_bytes = @as(u64, width) * bytes_per_pixel;
        if (row_bytes > std.math.maxInt(u32)) return error.InvalidImage;
        return initStrided(width, height, @intCast(row_bytes), pixels);
    }

    /// Cria uma imagem com `stride` explícito (padding entre linhas).
    pub fn initStrided(width: u32, height: u32, stride: u32, pixels: []const u8) Error!Self {
        const img = Self{
            .width = width,
            .height = height,
            .stride = stride,
            .pixels = pixels,
        };
        if (!img.isValid()) return error.InvalidImage;
        return img;
    }

    pub fn isValid(self: Self) bool {
        if (self.width == 0 or self.height == 0) return false;
        const row_bytes = @as(u64, self.width) * bytes_per_pixel;
        if (row_bytes > std.math.maxInt(u32)) return false;
        if (@as(u64, self.stride) < row_bytes) return false;
        const needed = @as(u64, self.stride) * self.height;
        if (needed > std.math.maxInt(usize)) return false;
        return self.pixels.len >= needed;
    }

    pub fn size(self: Self) types.Size {
        return .{
            .w = @floatFromInt(self.width),
            .h = @floatFromInt(self.height),
        };
    }

    /// Região que cobre a imagem inteira.
    pub fn fullRegion(self: Self) Region {
        return .{ .x = 0, .y = 0, .w = self.width, .h = self.height };
    }

    /// Lê um pixel validado (bounds em `width`/`height`).
    pub fn pixel(self: Self, x: u32, y: u32) [4]u8 {
        std.debug.assert(x < self.width and y < self.height);
        const i = @as(usize, y) * self.stride + @as(usize, x) * bytes_per_pixel;
        return self.pixels[i..][0..4].*;
    }
};

test "Image valida layout compacto e stride" {
    const stdt = @import("std");
    var bytes: [16]u8 = undefined;
    for (&bytes, 0..) |*b, i| b.* = @intCast(i);

    const img = try Image.init(2, 2, &bytes);
    try stdt.testing.expect(img.isValid());
    try stdt.testing.expectEqual(@as(u32, 8), img.stride);
    try stdt.testing.expectEqual([4]u8{ 0, 1, 2, 3 }, img.pixel(0, 0));
    try stdt.testing.expectEqual([4]u8{ 12, 13, 14, 15 }, img.pixel(1, 1));
    try stdt.testing.expectEqual(types.Size{ .w = 2, .h = 2 }, img.size());

    // Stride maior que o necessário é aceito; bytes curtos não.
    var pad_bytes: [24]u8 = undefined;
    @memset(&pad_bytes, 0);
    const padded = try Image.initStrided(2, 2, 12, &pad_bytes);
    try stdt.testing.expect(padded.isValid());
    try stdt.testing.expectError(error.InvalidImage, Image.initStrided(2, 2, 7, &bytes));
    var short_bytes: [15]u8 = undefined;
    @memset(&short_bytes, 0);
    try stdt.testing.expectError(error.InvalidImage, Image.init(2, 2, &short_bytes));
    try stdt.testing.expectError(error.InvalidImage, Image.init(0, 1, &bytes));
}

test "Region valida limites sem overflow" {
    const stdt = @import("std");
    try stdt.testing.expect((Region.init(0, 0, 2, 2)).isValidFor(2, 2));
    try stdt.testing.expect((Region.init(1, 1, 1, 1)).isValidFor(2, 2));
    try stdt.testing.expect(!(Region.init(1, 1, 2, 1)).isValidFor(2, 2));
    try stdt.testing.expect(!(Region.init(0, 0, 0, 1)).isValidFor(2, 2));
    try stdt.testing.expect((Region.init(0, 0, 1, 1)).isValidFor(1, 1));
}
