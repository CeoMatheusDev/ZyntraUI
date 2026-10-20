//! ZyntraUI — frustum de visão (viewport3d/frustum).
//!
//! Escopo M140: extração dos 6 planos do frustum a partir da matriz
//! view-projection (Gribb–Hartmann) para descartar triângulos fora da
//! câmera ANTES de projetar (culling, não rasterização).
//!
//! Convenção: profundidade [0,1] (near = 0, far = 1) — o plano near é
//! a própria linha z do espaço de clipe e o far é `w - z`.

const std = @import("std");
const math = @import("math.zig");

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

/// Plano (a, b, c, d): `a*x + b*y + c*z + d >= 0` ⇒ o ponto está
/// dentro (o plano normalizado).
pub const Plane = struct {
    a: f32 = 0,
    b: f32 = 0,
    c: f32 = 0,
    d: f32 = 0,

    /// Distância com sinal do ponto ao plano (positiva = dentro).
    pub fn distance(self: Plane, p: Vec3) f32 {
        return self.a * p.x + self.b * p.y + self.c * p.z + self.d;
    }

    /// Normaliza o plano (divide pela normal); `null` se degenerado.
    pub fn normalized(self: Plane) ?Plane {
        const len = @sqrt(self.a * self.a + self.b * self.b + self.c * self.c);
        if (!std.math.isFinite(len) or len < math.epsilon) return null;
        const inv = 1.0 / len;
        return .{
            .a = self.a * inv,
            .b = self.b * inv,
            .c = self.c * inv,
            .d = self.d * inv,
        };
    }
};

/// Frustum de visão (6 planos).
pub const Frustum = struct {
    /// left, right, bottom, top, near, far.
    planes: [6]Plane = .{
        .{ .a = 1, .b = 0, .c = 0, .d = 0 },
        .{ .a = -1, .b = 0, .c = 0, .d = 0 },
        .{ .a = 0, .b = 1, .c = 0, .d = 0 },
        .{ .a = 0, .b = -1, .c = 0, .d = 0 },
        .{ .a = 0, .b = 0, .c = 1, .d = 0 },
        .{ .a = 0, .b = 0, .c = -1, .d = 0 },
    },

    /// Extrai os planos da matriz view-projection (column-major).
    /// `null` se a matriz for degenerada.
    pub fn fromViewProjection(mvp: Mat4) ?Frustum {
        // As linhas da matriz (a linha i tem os elementos m[col][i]).
        var row: [4][4]f32 = undefined;
        for (0..4) |i| {
            for (0..4) |j| row[i][j] = mvp.m[j][i];
        }
        const r0 = row[0];
        const r1 = row[1];
        const r2 = row[2];
        const r3 = row[3];

        const add = struct {
            fn f(a: [4]f32, b: [4]f32) [4]f32 {
                return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2], a[3] + b[3] };
            }
        }.f;
        const sub = struct {
            fn f(a: [4]f32, b: [4]f32) [4]f32 {
                return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2], a[3] - b[3] };
            }
        }.f;

        const raw = [6][4]f32{
            add(r3, r0), // left
            sub(r3, r0), // right
            add(r3, r1), // bottom
            sub(r3, r1), // top
            r2, // near (z >= 0)
            sub(r3, r2), // far (z <= w)
        };

        var out = Frustum{};
        for (raw, 0..) |p, i| {
            const plane = Plane{ .a = p[0], .b = p[1], .c = p[2], .d = p[3] };
            out.planes[i] = plane.normalized() orelse return null;
        }
        return out;
    }

    /// O ponto está dentro do frustum?
    pub fn containsPoint(self: Frustum, p: Vec3) bool {
        if (!p.isFinite()) return false;
        for (self.planes) |plane| {
            if (plane.distance(p) < 0) return false;
        }
        return true;
    }

    /// A esfera está (totalmente) dentro do frustum? `radius` em unidades
    /// de mundo. Esferas tocam o plano (distância ≈ 0) contam como
    /// dentro.
    pub fn containsSphere(self: Frustum, center: Vec3, radius: f32) bool {
        if (!center.isFinite() or !std.math.isFinite(radius) or radius < 0) return false;
        for (self.planes) |plane| {
            if (plane.distance(center) < -radius) return false;
        }
        return true;
    }
};

test "Frustum: extrai os planos e testa pontos/esferas" {
    const stdt = @import("std");

    // Câmera olhando para -Z a partir de (0,0,5), sem rotação.
    const view = Mat4.lookAt(
        Vec3.init(0, 0, 5),
        Vec3.init(0, 0, 0),
        Vec3.init(0, 1, 0),
    ).?;
    const proj = Mat4.perspective(std.math.pi * 0.25, 1.0, 0.1, 100.0).?;
    const mvp = Mat4.mul(proj, view);

    const frustum = Frustum.fromViewProjection(mvp).?;
    // Um ponto à frente da câmera está dentro.
    try stdt.testing.expect(frustum.containsPoint(Vec3.init(0, 0, 0)));
    // Atrás da câmera, não.
    try stdt.testing.expect(!frustum.containsPoint(Vec3.init(0, 0, 10)));
    // Muito longe, não.
    try stdt.testing.expect(!frustum.containsPoint(Vec3.init(0, 0, -1000)));
    // Longe demais lateralmente, não.
    try stdt.testing.expect(!frustum.containsPoint(Vec3.init(1000, 0, 0)));
    // Uma esfera grande que atravessa o frustum é aceita (o culling é
    // conservador).
    try stdt.testing.expect(frustum.containsSphere(Vec3.init(0, 0, 0), 1000));
    try stdt.testing.expect(!frustum.containsSphere(Vec3.init(0, 0, 10), 0.1));
}

test "Frustum: matriz degenerada é recusada" {
    const stdt = @import("std");
    var zero = Mat4.identity();
    zero.m = .{
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
    };
    try stdt.testing.expect(Frustum.fromViewProjection(zero) == null);
}
