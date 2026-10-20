//! ZyntraUI — seleção de objetos (viewport3d/pick).
//!
//! Escopo M141: *picking* por ray casting — o clique do mouse vira um
//! raio no espaço do mundo e o objeto mais próximo é identificado.
//! Isolado do widget: o app guarda o raio/resultado e decide o que
//! desenhar (highlight, gizmo, seleção).
//!
//! Convenções: as mesmas do pipeline (mão direita, -Z para frente,
//! depth [0,1], y da tela para baixo).

const std = @import("std");
const math = @import("math.zig");
const mesh_mod = @import("mesh.zig");

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

/// Identificador de um objeto (definido pelo app).
pub const ObjectId = u32;

/// Raio no espaço do mundo.
pub const Ray = struct {
    origin: Vec3 = .{},
    /// Direção unitária.
    direction: Vec3 = .{ .x = 0, .y = 0, .z = -1 },

    pub fn isValid(self: Ray) bool {
        if (!self.origin.isFinite() or !self.direction.isFinite()) return false;
        const len = self.direction.length();
        return len > math.epsilon;
    }
};

/// Resultado de um picking.
pub const Hit = struct {
    /// Objeto atingido.
    id: ObjectId = 0,
    /// Distância do início do raio até o impacto.
    distance: f32 = 0,
    /// Ponto de impacto (espaço do mundo).
    point: Vec3 = .{},
    /// Índice do triângulo atingido dentro da malha.
    triangle: usize = 0,
};

/// Constrói o raio a partir de uma posição de tela (pixels, y para
/// baixo) e da matriz view-projection. `null` se a matriz for singular
/// ou a posição inválida.
pub fn screenRay(
    mvp: Mat4,
    screen_x: f32,
    screen_y: f32,
    width: u32,
    height: u32,
) ?Ray {
    if (!std.math.isFinite(screen_x) or !std.math.isFinite(screen_y)) return null;
    if (width == 0 or height == 0) return null;
    const inv = mvp.inverse() orelse return null;
    const ndc_x = 2.0 * screen_x / @as(f32, @floatFromInt(width)) - 1.0;
    const ndc_y = 1.0 - 2.0 * screen_y / @as(f32, @floatFromInt(height));
    const near = inv.transformPoint(Vec3.init(ndc_x, ndc_y, 0)) orelse return null;
    const far = inv.transformPoint(Vec3.init(ndc_x, ndc_y, 1)) orelse return null;
    const dir = far.sub(near).normalize() orelse return null;
    return .{ .origin = near, .direction = dir };
}

/// Interseção raio × triângulo (Möller–Trumbore). Devolve a distância
/// ao impacto ou `null` (sem interseção / triângulo degenerado).
/// `cull_backface` descarta as faces com o winding invertido.
pub fn rayTriangle(
    ray: Ray,
    v0: Vec3,
    v1: Vec3,
    v2: Vec3,
    cull_backface: bool,
) ?f32 {
    if (!ray.isValid()) return null;
    const e1 = v1.sub(v0);
    const e2 = v2.sub(v0);
    const p = ray.direction.cross(e2);
    const det = e1.dot(p);
    if (!std.math.isFinite(det) or @abs(det) < math.epsilon) return null;
    if (cull_backface and det < 0) return null;
    const inv_det = 1.0 / det;
    const tv = ray.origin.sub(v0);
    const u = tv.dot(p) * inv_det;
    if (u < 0 or u > 1) return null;
    const q = tv.cross(e1);
    const v = ray.direction.dot(q) * inv_det;
    if (v < 0 or u + v > 1) return null;
    const t = e2.dot(q) * inv_det;
    if (!std.math.isFinite(t) or t < 0) return null;
    return t;
}

/// Interseção raio × esfera (centro + raio). Devolve a distância ao
/// impacto (a raiz mais próxima à frente) ou `null`.
pub fn raySphere(ray: Ray, center: Vec3, radius: f32) ?f32 {
    if (!ray.isValid() or !center.isFinite()) return null;
    if (!std.math.isFinite(radius) or radius < 0) return null;
    const oc = ray.origin.sub(center);
    const b = oc.dot(ray.direction);
    const c = oc.dot(oc) - radius * radius;
    const disc = b * b - c;
    if (!std.math.isFinite(disc) or disc < 0) return null;
    const sq = @sqrt(disc);
    var t = -b - sq;
    if (t < 0) t = -b + sq;
    if (t < 0) return null;
    return t;
}

/// Pica o objeto na malha: percorre os triângulos (transformados pelo
/// modelo) e devolve o impacto mais próximo. `object_id` identifica a
/// malha (o app define).
pub fn pickMesh(
    ray: Ray,
    mesh: mesh_mod.Mesh,
    model: Mat4,
    object_id: ObjectId,
    cull_backface: bool,
) ?Hit {
    if (!ray.isValid() or !mesh.isValid()) return null;
    var best: ?Hit = null;
    var ti: usize = 0;
    while (ti < mesh.triangleCount()) : (ti += 1) {
        const tri = mesh.triangle(ti) orelse continue;
        const a = model.transformPoint(tri[0]) orelse continue;
        const b = model.transformPoint(tri[1]) orelse continue;
        const c = model.transformPoint(tri[2]) orelse continue;
        const t = rayTriangle(ray, a, b, c, cull_backface) orelse continue;
        if (best) |bt| {
            if (t >= bt.distance) continue;
        }
        best = .{
            .id = object_id,
            .distance = t,
            .point = ray.origin.add(ray.direction.scale(t)),
            .triangle = ti,
        };
    }
    return best;
}

test "screenRay: o raio sai da câmera na direção da tela" {
    const stdt = @import("std");
    const cam = @import("camera.zig");
    const view = Mat4.lookAt(
        Vec3.init(0, 0, 5),
        Vec3.init(0, 0, 0),
        Vec3.init(0, 1, 0),
    ).?;
    const proj = Mat4.perspective(std.math.pi * 0.25, 1.0, 0.1, 100.0).?;
    const mvp = Mat4.mul(proj, view);

    // O centro da tela: o raio aponta para -Z (a frente da câmera).
    const ray = screenRay(mvp, 50, 50, 100, 100).?;
    try stdt.testing.expect(ray.isValid());
    try stdt.testing.expect(ray.direction.z < -0.9);

    // Um ponto acima do centro: o raio sobe (o ângulo depende do fov).
    const ray2 = screenRay(mvp, 50, 10, 100, 100).?;
    try stdt.testing.expect(ray2.direction.y > 0.2);
    try stdt.testing.expect(ray2.direction.z < -0.9);
    // E abaixo do centro, desce.
    const ray3 = screenRay(mvp, 50, 90, 100, 100).?;
    try stdt.testing.expect(ray3.direction.y < -0.2);

    // Casos inválidos.
    try stdt.testing.expect(screenRay(mvp, 50, 50, 0, 100) == null);
    try stdt.testing.expect(screenRay(mvp, std.math.nan(f32), 50, 100, 100) == null);
    _ = cam;
}

test "rayTriangle: acerta o triângulo e ignora o resto" {
    const stdt = @import("std");
    // Triângulo no plano z = 0, olhando de z = +5 para -Z.
    const v0 = Vec3.init(-1, -1, 0);
    const v1 = Vec3.init(1, -1, 0);
    const v2 = Vec3.init(0, 1, 0);
    const ray = Ray{ .origin = Vec3.init(0, 0, 5), .direction = Vec3.init(0, 0, -1) };
    const t = rayTriangle(ray, v0, v1, v2, false).?;
    try stdt.testing.expectApproxEqAbs(@as(f32, 5), t, 1e-4);

    // Fora do triângulo: nada.
    const miss = Ray{ .origin = Vec3.init(5, 5, 5), .direction = Vec3.init(0, 0, -1) };
    try stdt.testing.expect(rayTriangle(miss, v0, v1, v2, false) == null);
    // Atrás da câmera: nada.
    const behind = Ray{ .origin = Vec3.init(0, 0, 5), .direction = Vec3.init(0, 0, 1) };
    try stdt.testing.expect(rayTriangle(behind, v0, v1, v2, false) == null);
    // Triângulo degenerado: nada.
    try stdt.testing.expect(rayTriangle(ray, v0, v0, v2, false) == null);
}

test "pickMesh: acha o cubo e devolve o objeto mais próximo" {
    const stdt = @import("std");
    var cube = mesh_mod.CubeMesh.init(2.0);
    const mesh = cube.mesh();
    const ray = Ray{ .origin = Vec3.init(0, 0, 5), .direction = Vec3.init(0, 0, -1) };
    const hit = pickMesh(ray, mesh, Mat4.identity(), 7, false).?;
    try stdt.testing.expectEqual(@as(ObjectId, 7), hit.id);
    // A face da frente está em z = 1 ⇒ distância 4.
    try stdt.testing.expectApproxEqAbs(@as(f32, 4), hit.distance, 1e-3);
    try stdt.testing.expectApproxEqAbs(@as(f32, 1), hit.point.z, 1e-3);

    // Um raio que passa ao lado não acerta.
    const miss = Ray{ .origin = Vec3.init(10, 10, 5), .direction = Vec3.init(0, 0, -1) };
    try stdt.testing.expect(pickMesh(miss, mesh, Mat4.identity(), 7, false) == null);

    // A transformação do modelo é respeitada (o cubo desloca).
    const moved = pickMesh(ray, mesh, Mat4.translation(Vec3.init(0, 0, 3)), 9, false).?;
    try stdt.testing.expectApproxEqAbs(@as(f32, 1), moved.distance, 1e-3);
}

test "raySphere: acerta a esfera e ignora o resto" {
    const stdt = @import("std");
    const ray = Ray{ .origin = Vec3.init(0, 0, 5), .direction = Vec3.init(0, 0, -1) };
    const t = raySphere(ray, Vec3.init(0, 0, 0), 1.0).?;
    try stdt.testing.expectApproxEqAbs(@as(f32, 4), t, 1e-4);
    // Fora da esfera: nada.
    try stdt.testing.expect(raySphere(ray, Vec3.init(5, 5, 0), 1.0) == null);
}
