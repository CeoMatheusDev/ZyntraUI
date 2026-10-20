//! ZyntraUI — matemática 3D (viewport3d/math).
//!
//! Escopo M156: os tipos 3D do viewport (vetores e matrizes 4x4).
//!
//! CONVENÇÕES (documentadas, sem misturas):
//! - Mão direita: +X para a direita, +Y para cima, +Z para trás. A
//!   câmera olha para **-Z** no espaço de visão.
//! - `Mat4` é **column-major** (igual a OpenGL): `m[col][row]`, e a
//!   multiplicação compõe como `A * B` = "aplica B, depois A".
//! - Espaço de clipe: x,y ∈ [-1, 1] e z ∈ [0, 1] (o depth buffer vai
//!   de 0 (perto) a 1 (longe)).
//! - Vértices de tela têm y para CIMA (a conversão para pixels inverte
//!   o eixo y — ver `viewport3d/raster`).
//!
//! Todos os cálculos são em `f32`; as funções que produzem matrizes
//! devolvem erro quando a entrada é degenerada (NaN/Inf, matriz
//! singular).

const std = @import("std");

pub const epsilon: f32 = 1e-6;

/// Vetor 2D.
pub const Vec2 = struct {
    x: f32 = 0,
    y: f32 = 0,

    pub fn init(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }

    pub fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }

    pub fn sub(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }

    pub fn scale(a: Vec2, s: f32) Vec2 {
        return .{ .x = a.x * s, .y = a.y * s };
    }

    pub fn dot(a: Vec2, b: Vec2) f32 {
        return a.x * b.x + a.y * b.y;
    }

    pub fn length(a: Vec2) f32 {
        return @sqrt(a.dot(a));
    }

    pub fn isFinite(a: Vec2) bool {
        return std.math.isFinite(a.x) and std.math.isFinite(a.y);
    }
};

/// Vetor 3D.
pub const Vec3 = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,

    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn splat(v: f32) Vec3 {
        return .{ .x = v, .y = v, .z = v };
    }

    pub fn add(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }

    pub fn sub(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
    }

    pub fn scale(a: Vec3, s: f32) Vec3 {
        return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s };
    }

    pub fn neg(a: Vec3) Vec3 {
        return .{ .x = -a.x, .y = -a.y, .z = -a.z };
    }

    pub fn dot(a: Vec3, b: Vec3) f32 {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }

    pub fn cross(a: Vec3, b: Vec3) Vec3 {
        return .{
            .x = a.y * b.z - a.z * b.y,
            .y = a.z * b.x - a.x * b.z,
            .z = a.x * b.y - a.y * b.x,
        };
    }

    pub fn length(a: Vec3) f32 {
        return @sqrt(a.dot(a));
    }

    pub fn lengthSq(a: Vec3) f32 {
        return a.dot(a);
    }

    /// Vetor unitário (`null` se o vetor é degenerado).
    pub fn normalize(a: Vec3) ?Vec3 {
        const len = a.length();
        if (!std.math.isFinite(len) or len < epsilon) return null;
        return a.scale(1.0 / len);
    }

    pub fn lerp(a: Vec3, b: Vec3, t: f32) Vec3 {
        return a.add(b.sub(a).scale(t));
    }

    pub fn isFinite(a: Vec3) bool {
        return std.math.isFinite(a.x) and std.math.isFinite(a.y) and std.math.isFinite(a.z);
    }

    pub fn eqlApprox(a: Vec3, b: Vec3, tol: f32) bool {
        return @abs(a.x - b.x) <= tol and
            @abs(a.y - b.y) <= tol and
            @abs(a.z - b.z) <= tol;
    }
};

/// Vetor 4D (w = 1 para pontos, w = peso paradireções em espaço homogêneo).
pub const Vec4 = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    w: f32 = 0,

    pub fn init(x: f32, y: f32, z: f32, w: f32) Vec4 {
        return .{ .x = x, .y = y, .z = z, .w = w };
    }

    pub fn fromVec3(v: Vec3, w: f32) Vec4 {
        return .{ .x = v.x, .y = v.y, .z = v.z, .w = w };
    }

    pub fn toVec3(a: Vec4) Vec3 {
        return .{ .x = a.x, .y = a.y, .z = a.z };
    }

    pub fn add(a: Vec4, b: Vec4) Vec4 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z, .w = a.w + b.w };
    }

    pub fn sub(a: Vec4, b: Vec4) Vec4 {
        return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z, .w = a.w - b.w };
    }

    pub fn scale(a: Vec4, s: f32) Vec4 {
        return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s, .w = a.w * s };
    }

    pub fn isFinite(a: Vec4) bool {
        return std.math.isFinite(a.x) and std.math.isFinite(a.y) and
            std.math.isFinite(a.z) and std.math.isFinite(a.w);
    }
};

/// Matriz 4x4 column-major: `m[col][row]`.
pub const Mat4 = struct {
    m: [4][4]f32 = .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    },

    pub fn identity() Mat4 {
        return .{};
    }

    /// Elemento por coluna e linha.
    pub fn at(a: Mat4, col: usize, row: usize) f32 {
        return a.m[col][row];
    }

    pub fn set(a: *Mat4, col: usize, row: usize, v: f32) void {
        a.m[col][row] = v;
    }

    /// Produto `a * b` (aplica `b` primeiro, depois `a`).
    pub fn mul(a: Mat4, b: Mat4) Mat4 {
        var out: Mat4 = undefined;
        for (0..4) |col| {
            for (0..4) |row| {
                var sum: f32 = 0;
                for (0..4) |k| {
                    sum += a.m[k][row] * b.m[col][k];
                }
                out.m[col][row] = sum;
            }
        }
        return out;
    }

    /// Transforma um vetor (sem divisão por w).
    ///
    /// `m` é column-major: `result_i = Σ_j m[j][i] * v_j`.
    pub fn transformVec4(a: Mat4, v: Vec4) Vec4 {
        const comps = [_]f32{ v.x, v.y, v.z, v.w };
        var out = Vec4{ .x = 0, .y = 0, .z = 0, .w = 0 };
        for (0..4) |j| {
            out.x += a.m[j][0] * comps[j];
            out.y += a.m[j][1] * comps[j];
            out.z += a.m[j][2] * comps[j];
            out.w += a.m[j][3] * comps[j];
        }
        return out;
    }

    /// Transforma um ponto (divide por w).
    pub fn transformPoint(a: Mat4, p: Vec3) ?Vec3 {
        const r = a.transformVec4(Vec4.fromVec3(p, 1));
        if (!r.isFinite() or @abs(r.w) < epsilon) return null;
        return r.toVec3().scale(1.0 / r.w);
    }

    pub fn translation(t: Vec3) Mat4 {
        var out = Mat4.identity();
        out.m[3][0] = t.x;
        out.m[3][1] = t.y;
        out.m[3][2] = t.z;
        return out;
    }

    pub fn scaling(s: Vec3) Mat4 {
        var out = Mat4.identity();
        out.m[0][0] = s.x;
        out.m[1][1] = s.y;
        out.m[2][2] = s.z;
        return out;
    }

    /// Rotação em torno de X (radianos).
    pub fn rotationX(ang: f32) Mat4 {
        const c = @cos(ang);
        const s = @sin(ang);
        var out = Mat4.identity();
        out.m[1][1] = c;
        out.m[1][2] = -s;
        out.m[2][1] = s;
        out.m[2][2] = c;
        return out;
    }

    /// Rotação em torno de Y (radianos).
    pub fn rotationY(ang: f32) Mat4 {
        const c = @cos(ang);
        const s = @sin(ang);
        var out = Mat4.identity();
        out.m[0][0] = c;
        out.m[0][2] = s;
        out.m[2][0] = -s;
        out.m[2][2] = c;
        return out;
    }

    /// Rotação em torno de Z (radianos).
    pub fn rotationZ(ang: f32) Mat4 {
        const c = @cos(ang);
        const s = @sin(ang);
        var out = Mat4.identity();
        out.m[0][0] = c;
        out.m[0][1] = -s;
        out.m[1][0] = s;
        out.m[1][1] = c;
        return out;
    }

    /// Projeção perspectiva (handedness direita, depth [0,1]).
    /// `fov_y` em radianos, `aspect` = largura/altura, `near`/`far` > 0.
    pub fn perspective(fov_y: f32, aspect: f32, near: f32, far: f32) ?Mat4 {
        if (!std.math.isFinite(fov_y) or !std.math.isFinite(aspect) or
            !std.math.isFinite(near) or !std.math.isFinite(far)) return null;
        if (fov_y <= 0 or fov_y >= std.math.pi) return null;
        if (aspect <= 0 or near <= 0 or far <= near) return null;
        const f = 1.0 / @tan(fov_y * 0.5);
        var out = Mat4.identity();
        out.m[0][0] = f / aspect;
        out.m[1][1] = f;
        out.m[2][2] = far / (near - far);
        out.m[2][3] = -1;
        out.m[3][2] = (near * far) / (near - far);
        out.m[3][3] = 0;
        return out;
    }

    /// Projeção ortográfica (handedness direita, depth [0,1]).
    pub fn orthographic(
        left: f32,
        right: f32,
        bottom: f32,
        top: f32,
        near: f32,
        far: f32,
    ) ?Mat4 {
        const vals = [_]f32{ left, right, bottom, top, near, far };
        for (vals) |v| {
            if (!std.math.isFinite(v)) return null;
        }
        if (right <= left or top <= bottom or far <= near) return null;
        var out = Mat4.identity();
        out.m[0][0] = 2.0 / (right - left);
        out.m[1][1] = 2.0 / (top - bottom);
        out.m[2][2] = 1.0 / (near - far);
        out.m[3][0] = -(right + left) / (right - left);
        out.m[3][1] = -(top + bottom) / (top - bottom);
        out.m[3][2] = near / (near - far);
        out.m[3][3] = 1;
        return out;
    }

    /// Matriz de visualização (olhar de `eye` para `target`, mão
    /// direita, -Z para frente).
    pub fn lookAt(eye: Vec3, target: Vec3, up: Vec3) ?Mat4 {
        if (!eye.isFinite() or !target.isFinite() or !up.isFinite()) return null;
        const f = target.sub(eye).normalize() orelse return null;
        const s = f.cross(up).normalize() orelse return null;
        const u = s.cross(f);
        var out = Mat4.identity();
        out.m[0][0] = s.x;
        out.m[0][1] = u.x;
        out.m[0][2] = -f.x;
        out.m[1][0] = s.y;
        out.m[1][1] = u.y;
        out.m[1][2] = -f.y;
        out.m[2][0] = s.z;
        out.m[2][1] = u.z;
        out.m[2][2] = -f.z;
        out.m[3][0] = -s.dot(eye);
        out.m[3][1] = -u.dot(eye);
        out.m[3][2] = f.dot(eye);
        return out;
    }
};

test "Vec3: operaç��es básicas e normalização" {
    const stdt = @import("std");
    const a = Vec3.init(1, 2, 3);
    const b = Vec3.init(4, 5, 6);
    try stdt.testing.expectEqual(Vec3.init(5, 7, 9), a.add(b));
    try stdt.testing.expectEqual(Vec3.init(-3, -3, -3), a.sub(b));
    try stdt.testing.expectEqual(@as(f32, 32), a.dot(b));
    try stdt.testing.expectEqual(Vec3.init(-3, 6, -3), a.cross(b));
    try stdt.testing.expect(a.normalize() != null);
    const n = a.normalize().?;
    try stdt.testing.expectApproxEqAbs(@as(f32, 1), n.length(), 1e-5);
    // Vetor degenerado: sem normalização.
    try stdt.testing.expect(Vec3.splat(0).normalize() == null);
}

test "Mat4: identidade, translação e composição" {
    const stdt = @import("std");
    const id = Mat4.identity();
    try stdt.testing.expectEqual(@as(f32, 1), id.at(0, 0));
    try stdt.testing.expectEqual(@as(f32, 0), id.at(3, 0));

    const t = Mat4.translation(Vec3.init(1, 2, 3));
    const p = t.transformPoint(Vec3.init(10, 20, 30)).?;
    try stdt.testing.expectApproxEqAbs(@as(f32, 11), p.x, 1e-5);
    try stdt.testing.expectApproxEqAbs(@as(f32, 22), p.y, 1e-5);
    try stdt.testing.expectApproxEqAbs(@as(f32, 33), p.z, 1e-5);

    // Composição `t * s`: a escala entra primeiro, a translação depois
    // ⇒ (1,1,1) → escala (2,2,2) → translação (3,4,5).
    const s = Mat4.scaling(Vec3.init(2, 2, 2));
    const p2 = Mat4.mul(t, s).transformPoint(Vec3.init(1, 1, 1)).?;
    try stdt.testing.expectApproxEqAbs(@as(f32, 3), p2.x, 1e-5);
    try stdt.testing.expectApproxEqAbs(@as(f32, 4), p2.y, 1e-5);
    try stdt.testing.expectApproxEqAbs(@as(f32, 5), p2.z, 1e-5);
}

test "Mat4: projeções perspectiva e ortográfica" {
    const stdt = @import("std");
    const proj = Mat4.perspective(std.math.pi * 0.25, 1.0, 0.1, 100.0).?;
    // Um ponto no plano near vai para z ≈ 0; no far, z ≈ 1.
    const near_p = proj.transformVec4(Vec4.init(0, 0, -0.1, 1));
    try stdt.testing.expectApproxEqAbs(@as(f32, 0), near_p.z / near_p.w, 1e-4);
    const far_p = proj.transformVec4(Vec4.init(0, 0, -100.0, 1));
    try stdt.testing.expectApproxEqAbs(@as(f32, 1), far_p.z / far_p.w, 1e-4);
    // A borda do frustum (x = tan(fov/2) a 1 de distância) dá x_ndc = 1.
    const half = @tan(std.math.pi * 0.25 * 0.5);
    const edge = proj.transformVec4(Vec4.init(half, 0, -1, 1));
    try stdt.testing.expectApproxEqAbs(@as(f32, 1), edge.x / edge.w, 1e-4);

    // Entradas degeneradas são recusadas.
    try stdt.testing.expect(Mat4.perspective(0, 1, 0.1, 100) == null);
    try stdt.testing.expect(Mat4.perspective(std.math.pi * 0.25, 0, 0.1, 100) == null);
    try stdt.testing.expect(Mat4.perspective(std.math.pi * 0.25, 1, 0, 100) == null);
    try stdt.testing.expect(Mat4.perspective(std.math.pi * 0.25, 1, 1, 1) == null);

    const ortho = Mat4.orthographic(-1, 1, -1, 1, 0, 10).?;
    const o = ortho.transformPoint(Vec3.init(0, 0, -5)).?;
    try stdt.testing.expectApproxEqAbs(@as(f32, 0.5), o.z, 1e-4);
}

test "Mat4: lookAt com a câmera olhando para -Z" {
    const stdt = @import("std");
    const view = Mat4.lookAt(
        Vec3.init(0, 0, 5),
        Vec3.init(0, 0, 0),
        Vec3.init(0, 1, 0),
    ).?;
    // Um ponto na frente da câmera (z = 0) fica em z = -5 no espaço de visão.
    const p = view.transformPoint(Vec3.init(0, 0, 0)).?;
    try stdt.testing.expectApproxEqAbs(@as(f32, -5), p.z, 1e-4);
    // eye == target (degenerate) é recusado.
    try stdt.testing.expect(Mat4.lookAt(Vec3.splat(0), Vec3.splat(0), Vec3.init(0, 1, 0)) == null);
}

test "fuzz math: operações finitas não geram NaN/Inf" {
    try std.testing.fuzz({}, fuzzMath, .{});
}

fn fuzzMath(_: void, smith: *std.testing.Smith) !void {
    var bytes: [96]u8 = undefined;
    smith.bytes(&bytes);
    const f = struct {
        fn at(b: []const u8, i: usize) f32 {
            const v: i32 = @as(i32, b[i % b.len]) - 128;
            // Valores "interessantes" (0, ±1, grandes, NaN) sem gerar
            // infinitos no meio.
            return switch (@as(u8, @truncate(@as(u32, @bitCast(v)))) % 8) {
                0 => 0,
                1 => 1,
                2 => -1,
                3 => 3.5,
                4 => -2.25,
                5 => 1.0e6,
                6 => -1.0e-6,
                else => @as(f32, @floatFromInt(@rem(v, 1000))) * 0.25,
            };
        }
    };

    const a = Vec3.init(f.at(&bytes, 0), f.at(&bytes, 4), f.at(&bytes, 8));
    const b = Vec3.init(f.at(&bytes, 12), f.at(&bytes, 16), f.at(&bytes, 20));

    // As operações de vetor nunca dividem por zero.
    _ = a.add(b);
    _ = a.sub(b);
    _ = a.scale(f.at(&bytes, 24));
    _ = a.dot(b);
    _ = a.cross(b);
    if (a.normalize()) |n| {
        try std.testing.expect(std.math.isFinite(n.x));
        try std.testing.expect(std.math.isFinite(n.y));
        try std.testing.expect(std.math.isFinite(n.z));
    }

    // Matrizes: as projeções com entrada válida são finitas.
    const proj = Mat4.perspective(
        @abs(f.at(&bytes, 28)) * 0.5 + 0.01,
        @abs(f.at(&bytes, 32)) + 0.01,
        @abs(f.at(&bytes, 36)) * 0.01 + 0.001,
        @abs(f.at(&bytes, 40)) + 1.0,
    );
    if (proj) |p| {
        const r = p.transformVec4(Vec4.init(1, 2, 3, 1));
        try std.testing.expect(r.isFinite());
    }
    const view = Mat4.lookAt(a, b, Vec3.init(0, 1, 0));
    if (view) |v| {
        const r = v.transformVec4(Vec4.init(1, 2, 3, 1));
        try std.testing.expect(r.isFinite());
    }
    // Multiplicação e translação nunca produzem NaN com entrada finita.
    const t = Mat4.translation(a);
    const m = Mat4.mul(t, Mat4.scaling(Vec3.splat(2)));
    const r = m.transformVec4(Vec4.init(1, 2, 3, 1));
    try std.testing.expect(r.isFinite());
}
