//! ZyntraUI — câmera 3D (viewport3d/camera).
//!
//! Escopo M156: a câmera é um DADO independente do widget: o app
//! guarda, ajusta e renderiza. Os helpers de órbita/pan/zoom são
//! opcionais (o app pode implementar os seus).
//!
//! Convenção: mão direita, a câmera olha para o alvo a partir da
//! posição derivada de (yaw, pitch, distance); `up` é a referência
//! vertical. Projeção perspectiva ou ortográfica, com o depth em
//! [0, 1] (ver `viewport3d/math`).

const std = @import("std");
const math = @import("math.zig");

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

/// Tipo de projeção.
pub const Projection = enum {
    perspective,
    orthographic,
};

/// Erros da câmera.
pub const Error = error{
    /// Parâmetros degenerados (fov, near/far, aspect, distância).
    InvalidCamera,
};

/// Câmera 3D (dados + helpers).
pub const Camera = struct {
    /// Alvo: o ponto que a câmera olha.
    target: Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    /// Referência vertical.
    up: Vec3 = .{ .x = 0, .y = 1, .z = 0 },
    /// Campo de visão vertical (radianos, projeção perspectiva).
    fov_y: f32 = 60 * (std.math.pi * (1.0 / 180.0)),
    /// Plano near e far (positivo, near < far).
    near: f32 = 0.1,
    far: f32 = 100.0,
    /// Distância do alvo (zoom).
    distance: f32 = 5.0,
    /// Ângulo de órbita em torno de Y (radianos).
    yaw: f32 = 0.6,
    /// Ângulo de órbita em torno de X (radianos, limitado a ±89°).
    pitch: f32 = 0.4,
    /// Projeção ativa.
    projection: Projection = .perspective,
    /// Altura da área visível (projeção ortográfica).
    ortho_height: f32 = 2.0,

    /// Posição da câmera no espaço do mundo.
    pub fn position(self: Camera) Vec3 {
        const cp = @cos(self.pitch);
        const sp = @sin(self.pitch);
        const cy = @cos(self.yaw);
        const sy = @sin(self.yaw);
        return self.target.add(Vec3.init(cp * sy, sp, cp * cy).scale(self.distance));
    }

    /// Matriz de visualização (olhar do alvo).
    pub fn view(self: Camera) ?Mat4 {
        return Mat4.lookAt(self.position(), self.target, self.up);
    }

    /// Matriz de projeção (`aspect` = largura/altura da área visível).
    pub fn projectionMatrix(self: Camera, aspect: f32) ?Mat4 {
        return switch (self.projection) {
            .perspective => Mat4.perspective(self.fov_y, aspect, self.near, self.far),
            .orthographic => blk: {
                const h = self.ortho_height * 0.5;
                const w = h * aspect;
                break :blk Mat4.orthographic(-w, w, -h, h, self.near, self.far);
            },
        };
    }

    /// Projeção combined (view * projection).
    pub fn viewProjection(self: Camera, aspect: f32) ?Mat4 {
        const v = self.view() orelse return null;
        const p = self.projectionMatrix(aspect) orelse return null;
        return Mat4.mul(p, v);
    }

    /// Orbita: gira em torno do alvo (yaw em Y, pitch em X, limitado a
    /// ±89° para não inverter o eixo vertical).
    pub fn orbit(self: *Camera, d_yaw: f32, d_pitch: f32) void {
        if (!std.math.isFinite(d_yaw) or !std.math.isFinite(d_pitch)) return;
        self.yaw += d_yaw;
        const limit = 89.0 * (std.math.pi * (1.0 / 180.0));
        self.pitch = std.math.clamp(self.pitch + d_pitch, -limit, limit);
    }

    /// Move o alvo no plano da câmera (pan): `dx`/`dy` em unidades de
    /// mundo por pixel de arrasto.
    pub fn pan(self: *Camera, dx: f32, dy: f32, aspect: f32) void {
        if (!std.math.isFinite(dx) or !std.math.isFinite(dy)) return;
        const v = self.view() orelse return;
        // Eixos da câmera em espaço do mundo (linhas da matriz de
        // visão: right = linha 0, up = linha 1).
        const right = Vec3.init(v.at(0, 0), v.at(0, 1), v.at(0, 2));
        const up = Vec3.init(v.at(1, 0), v.at(1, 1), v.at(1, 2));
        const scale = self.distance * 0.002;
        _ = aspect;
        self.target = self.target
            .add(right.scale(-dx * scale))
            .add(up.scale(dy * scale));
    }

    /// Zoom: `delta > 0` afasta, `delta < 0` aproxima (multiplicativo,
    /// com limite para não atravessar o alvo).
    pub fn zoom(self: *Camera, delta: f32) void {
        if (!std.math.isFinite(delta) or delta <= 0) return;
        const factor = 1.0 - delta;
        if (factor <= 0.01) return;
        self.distance = std.math.clamp(self.distance * factor, 0.01, 1.0e6);
    }

    /// Sanidade dos parâmetros.
    pub fn isValid(self: Camera) bool {
        if (!self.target.isFinite() or !self.up.isFinite()) return false;
        if (!std.math.isFinite(self.fov_y) or self.fov_y <= 0 or self.fov_y >= std.math.pi) return false;
        if (!std.math.isFinite(self.near) or !std.math.isFinite(self.far)) return false;
        if (self.near <= 0 or self.far <= self.near) return false;
        if (!std.math.isFinite(self.distance) or self.distance <= 0) return false;
        if (!std.math.isFinite(self.yaw) or !std.math.isFinite(self.pitch)) return false;
        if (!std.math.isFinite(self.ortho_height) or self.ortho_height <= 0) return false;
        return true;
    }
};

test "Camera: posição, vista e projeção" {
    const stdt = @import("std");
    var cam = Camera{};
    try stdt.testing.expect(cam.isValid());

    // A posição está na distância certa do alvo.
    const p = cam.position();
    try stdt.testing.expectApproxEqAbs(@as(f32, 5.0), p.sub(cam.target).length(), 1e-4);

    // A projeção perspectiva é válida e a view olha para -Z.
    const vp = cam.viewProjection(1.5).?;
    try stdt.testing.expect(vp.at(2, 3) != 0 or vp.at(3, 2) != 0);

    // Câmera degenerada: near >= far.
    var bad = cam;
    bad.far = bad.near;
    try stdt.testing.expect(!bad.isValid());
    try stdt.testing.expect(bad.viewProjection(1.0) == null);
}

test "Camera: órbita, pan e zoom" {
    const stdt = @import("std");
    var cam = Camera{ .distance = 4.0 };

    // Órbita: o yaw muda e o pitch é limitado.
    cam.orbit(0.5, 0.2);
    try stdt.testing.expectApproxEqAbs(@as(f32, 1.1), cam.yaw, 1e-5);
    cam.orbit(0, 10.0);
    try stdt.testing.expect(cam.pitch <= 89.0 * (std.math.pi * (1.0 / 180.0)) + 1e-6);

    // Pan: o alvo se move.
    const before = cam.target;
    cam.pan(10, 0, 1.0);
    try stdt.testing.expect(cam.target.x != before.x or cam.target.z != before.z);

    // Zoom: a distância diminui com delta positivo e é limitada.
    const d0 = cam.distance;
    cam.zoom(0.1);
    try stdt.testing.expect(cam.distance < d0);
    cam.zoom(100.0);
    try stdt.testing.expect(cam.distance > 0.0);
}
