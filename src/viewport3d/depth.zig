//! ZyntraUI — buffer de profundidade (viewport3d/depth).
//!
//! Escopo M156: depth buffer em `f32` no MESMO intervalo do espaço de
//! clipe ([0, 1]: 0 = perto, 1 = longe). O teste é "escreve se o novo
//! z for MENOR" (mais perto).
//!
//! Ownership: o buffer é do app (o rasterizador o aloca e o libera, ou
//! o app o fornece). Nada é alocado por triângulo.

const std = @import("std");

/// Buffer de profundidade.
pub const DepthBuffer = struct {
    /// Valores (0 = perto, 1 = longe).
    data: []f32 = &.{},
    width: u32 = 0,
    height: u32 = 0,

    pub const Error = error{ OutOfMemory, InvalidDimensions };

    /// Aloca um buffer `width`×`height` preenchido com `1.0` (fundo).
    pub fn init(gpa: std.mem.Allocator, width: u32, height: u32) !DepthBuffer {
        if (width == 0 or height == 0) return error.InvalidDimensions;
        const n = @as(usize, width) * height;
        const data = try gpa.alloc(f32, n);
        errdefer gpa.free(data);
        @memset(data, 1.0);
        return .{ .data = data, .width = width, .height = height };
    }

    /// Cria um buffer sobre memória do APP (sem cópia).
    pub fn fromSlice(data: []f32, width: u32, height: u32) Error!DepthBuffer {
        if (width == 0 or height == 0) return error.InvalidDimensions;
        if (data.len < @as(usize, width) * height) return error.InvalidDimensions;
        return .{ .data = data, .width = width, .height = height };
    }

    pub fn deinit(self: *DepthBuffer, gpa: std.mem.Allocator) void {
        if (self.data.len > 0) gpa.free(self.data);
        self.data = &.{};
        self.width = 0;
        self.height = 0;
    }

    /// Redimensiona (re-aloca; o conteúdo é perdido).
    pub fn resize(self: *DepthBuffer, gpa: std.mem.Allocator, width: u32, height: u32) !void {
        if (width == 0 or height == 0) return error.InvalidDimensions;
        if (width == self.width and height == self.height) return;
        if (self.data.len > 0) gpa.free(self.data);
        self.* = try DepthBuffer.init(gpa, width, height);
    }

    /// Limpa com um valor (1.0 = fundo).
    pub fn clear(self: *DepthBuffer, value: f32) void {
        @memset(self.data, value);
    }

    /// Profundidade em (x, y) (1.0 fora dos limites).
    pub fn get(self: *const DepthBuffer, x: u32, y: u32) f32 {
        if (x >= self.width or y >= self.height) return 1.0;
        return self.data[@as(usize, y) * self.width + x];
    }

    /// Escreve se o novo `z` for mais perto que o armazenado.
    /// `z` em [0, 1] (valores fora são ignorados).
    pub fn put(self: *DepthBuffer, x: u32, y: u32, z: f32) void {
        if (x >= self.width or y >= self.height) return;
        if (!std.math.isFinite(z) or z < 0.0 or z > 1.0) return;
        const i = @as(usize, y) * self.width + x;
        if (z < self.data[i]) self.data[i] = z;
    }
};

test "DepthBuffer: clear, put e get" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var depth = try DepthBuffer.init(gpa, 4, 3);
    defer depth.deinit(gpa);

    try stdt.testing.expectEqual(@as(f32, 1.0), depth.get(0, 0));
    depth.put(1, 1, 0.5);
    try stdt.testing.expectEqual(@as(f32, 0.5), depth.get(1, 1));
    // Mais longe: não sobrescreve.
    depth.put(1, 1, 0.8);
    try stdt.testing.expectEqual(@as(f32, 0.5), depth.get(1, 1));
    // Mais perto: sobrescreve.
    depth.put(1, 1, 0.2);
    try stdt.testing.expectEqual(@as(f32, 0.2), depth.get(1, 1));
    // Fora dos limites: ignorado.
    depth.put(9, 9, 0.1);
    try stdt.testing.expectEqual(@as(f32, 1.0), depth.get(9, 9));
    // z inválido: ignorado.
    depth.put(0, 0, std.math.nan(f32));
    try stdt.testing.expectEqual(@as(f32, 1.0), depth.get(0, 0));

    // clear e resize.
    depth.clear(0.25);
    try stdt.testing.expectEqual(@as(f32, 0.25), depth.get(2, 2));
    try depth.resize(gpa, 8, 8);
    try stdt.testing.expectEqual(@as(u32, 8), depth.width);
    try stdt.testing.expectEqual(@as(f32, 1.0), depth.get(0, 0));
}

test "DepthBuffer: fromSlice usa a memória do app" {
    const stdt = @import("std");
    var data: [16]f32 = undefined;
    @memset(&data, 1.0);
    var depth = try DepthBuffer.fromSlice(&data, 4, 4);
    try stdt.testing.expectEqual(@as(usize, 16), depth.data.len);
    depth.put(2, 2, 0.1);
    try stdt.testing.expectEqual(@as(f32, 0.1), data[2 * 4 + 2]);
    try stdt.testing.expectError(error.InvalidDimensions, DepthBuffer.fromSlice(&data, 8, 8));
}
