//! ZyntraUI — recorte de triângulos (viewport3d/clipping).
//!
//! Escopo M156: recorte contra o plano near, feito no ESPAÇO DE VISÃO
//! (antes da divisão perspectiva — o passo que evita a projeção
//! invertida dos vértices atrás da câmera).
//!
//! Convenção: no espaço de visão a câmera olha para -Z; a região
//! visível é `z <= -near`. O recorte é o de Sutherland–Hodgman contra
//! esse único plano: o resultado tem 3 ou 4 vértices (1 ou 2
//! triângulos).

const std = @import("std");
const math = @import("math.zig");

const Vec3 = math.Vec3;

/// Distância ao plano near (positivo = dentro da região visível).
fn signedDistance(v: Vec3, near: f32) f32 {
    return -near - v.z;
}

/// Recorta o triângulo `v` contra o plano near (espaço de visão).
/// Devolve o número de triângulos escritos em `out` (0, 1 ou 2).
pub fn clipTriangleNear(v: [3]Vec3, near: f32, out: *[2][3]Vec3) usize {
    if (!std.math.isFinite(near) or near <= 0) return 0;
    for (v) |p| {
        if (!p.isFinite()) return 0;
    }

    // Polígono recortado (máximo: 4 vértices com um plano).
    var poly: [4]Vec3 = undefined;
    var n: usize = 0;
    var prev = v[0];
    var prev_in = signedDistance(prev, near) >= 0;
    for (v[0..3]) |cur| {
        const cur_in = signedDistance(cur, near) >= 0;
        if (prev_in != cur_in) {
            const dp = signedDistance(prev, near);
            const dc = signedDistance(cur, near);
            const denom = dp - dc;
            if (@abs(denom) > math.epsilon) {
                const t = dp / denom;
                poly[n] = prev.lerp(cur, t);
                n += 1;
            }
        }
        if (cur_in) {
            poly[n] = cur;
            n += 1;
        }
        prev = cur;
        prev_in = cur_in;
    }
    if (n < 3) return 0;

    // Fan triangulation a partir do primeiro vértice.
    var tris: usize = 0;
    var i: usize = 1;
    while (i + 1 < n) : (i += 1) {
        if (tris >= out.len) break;
        out[tris] = .{ poly[0], poly[i], poly[i + 1] };
        tris += 1;
    }
    return tris;
}

test "clipping: triângulo inteiro, parcialmente e totalmente fora" {
    const stdt = @import("std");
    var out: [2][3]Vec3 = undefined;

    // Todo dentro: 1 triângulo, sem alteração.
    const inside = [_]Vec3{
        Vec3.init(-1, -1, -2),
        Vec3.init(1, -1, -2),
        Vec3.init(0, 1, -2),
    };
    try stdt.testing.expectEqual(@as(usize, 1), clipTriangleNear(inside, 0.1, &out));
    try stdt.testing.expect(out[0][0].eqlApprox(inside[0], 1e-5));

    // Parcialmente: 2 triângulos (o plano corta o triângulo).
    const partial = [_]Vec3{
        Vec3.init(-1, -1, -0.05), // atrás do near
        Vec3.init(1, -1, -2),
        Vec3.init(0, 1, -2),
    };
    const n = clipTriangleNear(partial, 0.1, &out);
    try stdt.testing.expect(n == 1 or n == 2);
    // Os vértices recortados ficam no plano (z = -near).
    for (out[0]) |p| {
        try stdt.testing.expect(p.z <= -0.1 + 1e-4);
    }

    // Todo atrás: nada.
    const behind = [_]Vec3{
        Vec3.init(-1, -1, -0.01),
        Vec3.init(1, -1, -0.02),
        Vec3.init(0, 1, -0.03),
    };
    try stdt.testing.expectEqual(@as(usize, 0), clipTriangleNear(behind, 0.1, &out));

    // Degenerado: nada.
    try stdt.testing.expectEqual(@as(usize, 0), clipTriangleNear(inside, 0.0, &out));
    const nan_tri = [_]Vec3{ Vec3.init(std.math.nan(f32), 0, -1), inside[1], inside[2] };
    try stdt.testing.expectEqual(@as(usize, 0), clipTriangleNear(nan_tri, 0.1, &out));
}

test "fuzz clipping: triângulos aleatórios não crasham" {
    try std.testing.fuzz({}, fuzzClipping, .{});
}

fn fuzzClipping(_: void, smith: *std.testing.Smith) !void {
    var bytes: [48]u8 = undefined;
    smith.bytes(&bytes);
    const f = struct {
        fn at(b: []const u8, i: usize) f32 {
            const v: i32 = @as(i32, b[i % b.len]) - 128;
            return @as(f32, @floatFromInt(@rem(v, 2000))) * 0.01 - 10.0;
        }
    };
    const near: f32 = @abs(f.at(&bytes, 40)) * 0.1 + 0.01;
    const tri = [3]Vec3{
        Vec3.init(f.at(&bytes, 0), f.at(&bytes, 4), f.at(&bytes, 8)),
        Vec3.init(f.at(&bytes, 12), f.at(&bytes, 16), f.at(&bytes, 20)),
        Vec3.init(f.at(&bytes, 24), f.at(&bytes, 28), f.at(&bytes, 32)),
    };
    var out: [2][3]Vec3 = undefined;
    const n = clipTriangleNear(tri, near, &out);
    try std.testing.expect(n <= 2);
    for (out[0..n]) |t| {
        for (t) |p| try std.testing.expect(p.isFinite());
    }
}
