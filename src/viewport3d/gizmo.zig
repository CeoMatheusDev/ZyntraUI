//! ZyntraUI — gizmos de transformação (viewport3d/gizmo).
//!
//! Escopo M142: gizmos de translação, rotação e escala para o objeto
//! selecionado. O gizmo é DADO + GEOMETRIA: o app informa o transform do
//! objeto e recebe o delta pedido (translação, ângulo ou fator), aplicando
//! no seu próprio estado. Nada é desenhado aqui (o app desenha as
//! alças com o rasterizador).
//!
//! Convenções: o gizmo vive no ESPAÇO DO OBJETO (o `model` do objeto);
//! o raio do picking vem do espaço do mundo.

const std = @import("std");
const math = @import("math.zig");
const pick_mod = @import("pick.zig");

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Ray = pick_mod.Ray;

/// Tipo de gizmo.
pub const Kind = enum {
    translate,
    rotate,
    scale,
};

/// Eixo/alça do gizmo.
pub const Handle = enum {
    x,
    y,
    z,
};

/// Resultado de um arraste de gizmo.
pub const Drag = union(enum) {
    /// Nova translação (espaço do mundo).
    translate: Vec3,
    /// Ângulo em radianos (no sentido positivo do eixo).
    rotate: f32,
    /// Fator de escala (>= 0).
    scale: f32,
};

/// Gizmo de transformação.
pub const Gizmo = struct {
    /// Transform do objeto (o gizmo vive nele).
    model: Mat4 = Mat4.identity(),
    /// Tamanho do gizmo (unidades de mundo).
    size: f32 = 1.0,
    /// Tipo de gizmo ativo.
    kind: Kind = .translate,
    /// Raio de captura das alças (espaço do objeto).
    pick_radius: f32 = 0.12,

    pub fn isValid(self: Gizmo) bool {
        if (!std.math.isFinite(self.size) or self.size <= 0) return false;
        if (!std.math.isFinite(self.pick_radius) or self.pick_radius < 0) return false;
        return true;
    }

    /// Direção do eixo no espaço do objeto.
    pub fn axisDirection(self: Gizmo, axis: Handle) Vec3 {
        _ = self;
        return switch (axis) {
            .x => .{ .x = 1, .y = 0, .z = 0 },
            .y => .{ .x = 0, .y = 1, .z = 0 },
            .z => .{ .x = 0, .y = 0, .z = 1 },
        };
    }

    /// Posição da alça no espaço do objeto (a ponta do eixo).
    pub fn handlePosition(self: Gizmo, axis: Handle) Vec3 {
        return self.axisDirection(axis).scale(self.size);
    }

    /// Posição da alça no espaço do mundo.
    pub fn handleWorld(self: Gizmo, axis: Handle) ?Vec3 {
        return self.model.transformPoint(self.handlePosition(axis));
    }

    /// Qual alça o raio acerta? (a mais próxima em ordem X, Y, Z)
    pub fn pickHandle(self: Gizmo, ray: Ray) ?Handle {
        if (!self.isValid() or !ray.isValid()) return null;
        var best: ?Handle = null;
        var best_dist: f32 = std.math.inf(f32);
        for ([_]Handle{ .x, .y, .z }) |axis| {
            const center = self.handleWorld(axis) orelse continue;
            const t = pick_mod.raySphere(ray, center, self.pick_radius * self.size) orelse continue;
            if (t < best_dist) {
                best_dist = t;
                best = axis;
            }
        }
        return best;
    }

    /// Calcula o delta pedido ao arrastar a alça.
    ///
    /// - Translação: o raio é projetado no eixo; o resultado é o novo
    ///   deslocamento (espaço do mundo) a partir da origem do objeto.
    /// - Rotação: o raio é projetado no plano do eixo; o resultado é o
    ///   ângulo (rad) em torno do eixo.
    /// - Escala: o raio é projetado no eixo; o resultado é o fator
    ///   (distância nova / tamanho).
    pub fn drag(self: Gizmo, axis: Handle, ray: Ray) ?Drag {
        if (!self.isValid() or !ray.isValid()) return null;
        const origin = self.model.transformPoint(Vec3.splat(0)) orelse return null;
        const dir_world = self.model.transformVec4(math.Vec4.fromVec3(self.axisDirection(axis), 0));
        const axis_world = Vec3.init(dir_world.x, dir_world.y, dir_world.z).normalize() orelse return null;

        return switch (self.kind) {
            .translate => blk: {
                const p = projectOnAxis(ray, origin, axis_world) orelse break :blk null;
                break :blk Drag{ .translate = p };
            },
            .rotate => blk: {
                // Ângulo ABSOLUTO em torno do eixo (o app subtrai o
                // ângulo inicial do arraste).
                const ang = angleInPlane(ray, origin, axis_world, self.angleReference(axis)) orelse break :blk null;
                break :blk Drag{ .rotate = ang };
            },
            .scale => blk: {
                const p = projectOnAxis(ray, origin, axis_world) orelse break :blk null;
                const along = p.sub(origin).dot(axis_world);
                const factor = along / self.size;
                if (!std.math.isFinite(factor) or factor < 0) break :blk null;
                break :blk Drag{ .scale = factor };
            },
        };
    }

    /// Vetor de referência do plano de rotação (qualquer vetor não
    /// paralelo ao eixo).
    fn angleReference(self: Gizmo, axis: Handle) Vec3 {
        _ = self;
        return switch (axis) {
            .x => Vec3.init(0, 1, 0),
            .y => Vec3.init(0, 0, 1),
            .z => Vec3.init(1, 0, 0),
        };
    }
};

/// Projeta o raio na reta (origem, direção) e devolve o ponto mais
/// próximo (ou `null` se degenerado).
pub fn projectOnAxis(ray: Ray, origin: Vec3, axis: Vec3) ?Vec3 {
    const a = axis.normalize() orelse return null;
    const w0 = origin.sub(ray.origin);
    const a_dot_a = a.dot(a);
    const b_dot_a = ray.direction.dot(a);
    const d = ray.direction.dot(ray.direction);
    const e = ray.direction.dot(w0);
    const denom = a_dot_a * d - b_dot_a * b_dot_a;
    if (@abs(denom) < math.epsilon) return null;
    const tc = (a_dot_a * e - b_dot_a * w0.dot(a)) / denom;
    if (tc < 0) return null; // atrás da câmera
    return ray.origin.add(ray.direction.scale(tc));
}

/// Ângulo (rad) do raio em torno do eixo, medido no plano que contém
/// `reference`.
pub fn angleInPlane(ray: Ray, origin: Vec3, axis: Vec3, reference: Vec3) ?f32 {
    const a = axis.normalize() orelse return null;
    // Base do plano: a referência projetada no plano perpendicular.
    var u = reference.sub(a.scale(reference.dot(a)));
    u = u.normalize() orelse return null;
    const v = a.cross(u);
    const w = ray.origin.sub(origin);
    const x = w.dot(u);
    const y = w.dot(v);
    if (@abs(x) < math.epsilon and @abs(y) < math.epsilon) return null;
    return std.math.atan2(y, x);
}

test "Gizmo: as alças ficam nas pontas dos eixos" {
    const stdt = @import("std");
    const g = Gizmo{ .size = 2.0 };
    try stdt.testing.expect(g.isValid());
    try stdt.testing.expect(g.handlePosition(.x).eqlApprox(Vec3.init(2, 0, 0), 1e-5));
    try stdt.testing.expect(g.handlePosition(.y).eqlApprox(Vec3.init(0, 2, 0), 1e-5));
    try stdt.testing.expect(g.handlePosition(.z).eqlApprox(Vec3.init(0, 0, 2), 1e-5));
    // Com translação, as alças vão junto.
    const t = Gizmo{ .model = Mat4.translation(Vec3.init(1, 0, 0)), .size = 1.0 };
    try stdt.testing.expect(t.handleWorld(.x).?.eqlApprox(Vec3.init(2, 0, 0), 1e-5));
}

test "Gizmo: o picking acha a alça mais próxima" {
    const stdt = @import("std");
    const g = Gizmo{ .size = 1.0, .pick_radius = 0.2 };
    // Um raio apontando para a alça X (em (1,0,0)).
    const ray_x = Ray{ .origin = Vec3.init(1, 0, 5), .direction = Vec3.init(0, 0, -1) };
    try stdt.testing.expectEqual(Handle.x, g.pickHandle(ray_x).?);
    // Fora de alcance: nada.
    const miss = Ray{ .origin = Vec3.init(5, 5, 5), .direction = Vec3.init(0, 0, -1) };
    try stdt.testing.expect(g.pickHandle(miss) == null);
}

test "Gizmo: arraste de translação ao longo do eixo" {
    const stdt = @import("std");
    const g = Gizmo{ .size = 1.0, .kind = .translate };
    // O raio passa por (2, 0, 0) ⇒ a translação pedida é (2,0,0).
    const ray = Ray{ .origin = Vec3.init(2, 0, 5), .direction = Vec3.init(0, 0, -1) };
    const d = g.drag(.x, ray).?;
    switch (d) {
        .translate => |t| try stdt.testing.expect(t.eqlApprox(Vec3.init(2, 0, 0), 1e-3)),
        else => return error.TestUnexpectedResult,
    }
    // Um raio fora do eixo não produz translação (nada a projetar).
    const miss = Ray{ .origin = Vec3.init(5, 5, 5), .direction = Vec3.init(0, 1, 0) };
    try stdt.testing.expect(g.drag(.x, miss) == null);
}

test "Gizmo: arraste de rotação e de escala" {
    const stdt = @import("std");
    const g = Gizmo{ .size = 1.0, .kind = .rotate };
    // Um raio no plano XY, com um ângulo de ~45° em torno de Z.
    const ray = Ray{ .origin = Vec3.init(1, 1, 0), .direction = Vec3.init(0, 0, 1) };
    const d = g.drag(.z, ray).?;
    switch (d) {
        .rotate => |ang| try stdt.testing.expectApproxEqAbs(std.math.pi * 0.25, ang, 1e-3),
        else => return error.TestUnexpectedResult,
    }

    const gs = Gizmo{ .size = 1.0, .kind = .scale };
    const ray2 = Ray{ .origin = Vec3.init(3, 0, 5), .direction = Vec3.init(0, 0, -1) };
    const d2 = gs.drag(.x, ray2).?;
    switch (d2) {
        .scale => |f| try stdt.testing.expectApproxEqAbs(@as(f32, 3), f, 1e-3),
        else => return error.TestUnexpectedResult,
    }
}
