//! ZyntraUI — malhas 3D simples (viewport3d/mesh).
//!
//! Escopo M156: malhas mínima para o viewport 3D — vértices
//! posicionados + índices de triângulos. Sem normais, sem texturas, sem
//! alocação: o app fornece os slices (emprestados) ou usa o cubo
//! pronto (`CubeMesh`).
//!
//! Convenção: o winding padrão é anti-horário quando visto de fora
//! (frente) — o rasterizador pode descartar faces traseiras.

const std = @import("std");
const math = @import("math.zig");

const Vec3 = math.Vec3;

/// Malha: posições + índices (3 por triângulo).
pub const Mesh = struct {
    /// Posições dos vértices (espaço do modelo).
    positions: []const Vec3 = &.{},
    /// Índices dos triângulos (3 por triângulo).
    indices: []const u32 = &.{},

    /// Número de triângulos (índice/3).
    pub fn triangleCount(self: Mesh) usize {
        return self.indices.len / 3;
    }

    /// Vértice por índice (null se o índice é inválido).
    pub fn vertex(self: Mesh, index: u32) ?Vec3 {
        if (index >= self.positions.len) return null;
        return self.positions[index];
    }

    /// Triângulo por índice (null se algum índice é inválido).
    pub fn triangle(self: Mesh, index: usize) ?[3]Vec3 {
        const base = index * 3;
        if (base + 2 >= self.indices.len) return null;
        const a = self.vertex(self.indices[base]) orelse return null;
        const b = self.vertex(self.indices[base + 1]) orelse return null;
        const c = self.vertex(self.indices[base + 2]) orelse return null;
        return .{ a, b, c };
    }

    /// Sanidade: índices dentro dos vértices.
    pub fn isValid(self: Mesh) bool {
        for (self.positions) |p| {
            if (!p.isFinite()) return false;
        }
        for (self.indices) |i| {
            if (i >= self.positions.len) return false;
        }
        return self.indices.len % 3 == 0;
    }
};

/// Cubo unitário (centrado na origem), com lados de `size`.
/// Sem alocação: os dados são do app.
pub const CubeMesh = struct {
    positions: [8]Vec3 = undefined,
    indices: [36]u32 = undefined,

    pub fn init(size: f32) CubeMesh {
        const h = size * 0.5;
        var out = CubeMesh{};
        out.positions = .{
            .{ .x = -h, .y = -h, .z = -h }, // 0
            .{ .x = h, .y = -h, .z = -h }, // 1
            .{ .x = h, .y = h, .z = -h }, // 2
            .{ .x = -h, .y = h, .z = -h }, // 3
            .{ .x = -h, .y = -h, .z = h }, // 4
            .{ .x = h, .y = -h, .z = h }, // 5
            .{ .x = h, .y = h, .z = h }, // 6
            .{ .x = -h, .y = h, .z = h }, // 7
        };
        // Face frontal (-Z), traseira (+Z), direita (+X), esquerda (-X),
        // topo (+Y), base (-Y) — anti-horário visto de fora.
        out.indices = .{
            0, 2, 1, 0, 3, 2, // frente
            4, 5, 6, 4, 6, 7, // traseira
            1, 2, 6, 1, 6, 5, // direita
            0, 4, 7, 0, 7, 3, // esquerda
            3, 7, 6, 3, 6, 2, // topo
            0, 1, 5, 0, 5, 4, // base
        };
        return out;
    }

    pub fn mesh(self: *const CubeMesh) Mesh {
        return .{ .positions = &self.positions, .indices = &self.indices };
    }
};

test "Mesh: triângulos e validação" {
    const stdt = @import("std");
    const cube = CubeMesh.init(2.0);
    const m = cube.mesh();
    try stdt.testing.expect(m.isValid());
    try stdt.testing.expectEqual(@as(usize, 12), m.triangleCount());
    const t = m.triangle(0).?;
    try stdt.testing.expect(t[0].eqlApprox(Vec3.init(-1, -1, -1), 1e-5));
    // Índice fora do vértice: triângulo inválido.
    const bad = Mesh{ .positions = &.{Vec3.splat(0)}, .indices = &.{ 0, 1, 2 } };
    try stdt.testing.expect(!bad.isValid());
    try stdt.testing.expect(bad.triangle(0) == null);
}

test "CubeMesh: vértices e volume" {
    const stdt = @import("std");
    const cube = CubeMesh.init(2.0);
    try stdt.testing.expectEqual(@as(f32, 1.0), cube.positions[0].x * -1.0);
    try stdt.testing.expectEqual(@as(f32, -1.0), cube.positions[0].z);
    try stdt.testing.expectEqual(@as(f32, 1.0), cube.positions[6].z);
    // Cada face tem 2 triângulos (36 índices = 12 triângulos).
    try stdt.testing.expectEqual(@as(usize, 36), cube.indices.len);
}
