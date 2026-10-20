//! ZyntraUI — rasterizador 3D em software (viewport3d/raster).
//!
//! Escopo M156: rasterização de triângulos SEM GPU e sem dependências
//! externas. Pipeline: vértices do modelo → transformação → espaço de
//! visão → RECORTE no plano near → projeção → tela → rasterização com
//! teste de profundidade.
//!
//! Convenções (ver `viewport3d/math`):
//! - Mão direita, a câmera olha para -Z.
//! - Espaço de clipe: x,y ∈ [-1,1], z ∈ [0,1] (near = 0, far = 1).
//! - Tela: x para a direita, y para BAIXO (0 = topo), z = profundidade
//!   em [0,1] (menor = mais perto).
//!
//! Determinismo: sem aleatoriedade, sem alocação por triângulo, com
//! os buffers do chamador.

const std = @import("std");
const types = @import("../core/types.zig");
const math = @import("math.zig");
const camera_mod = @import("camera.zig");
const clipping = @import("clipping.zig");
const depth_mod = @import("depth.zig");
const mesh_mod = @import("mesh.zig");
const frustum_mod = @import("frustum.zig");

const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;
const Color = types.Color;

/// Alvo de rasterização: pixels RGBA8 (mesmo formato do
/// `software/raster`).
pub const Target = struct {
    pixels: []u8 = &.{},
    width: u32 = 0,
    height: u32 = 0,
    /// Bytes por linha (pode ser > width*4).
    stride: u32 = 0,

    pub fn isValid(self: Target) bool {
        if (self.width == 0 or self.height == 0) return false;
        const need = @as(usize, self.stride) * self.height;
        return self.stride >= self.width * 4 and self.pixels.len >= need;
    }

    /// Escreve um pixel (RGBA), respeitando o stride.
    pub fn put(self: *Target, x: u32, y: u32, c: Color) void {
        if (x >= self.width or y >= self.height) return;
        const o = @as(usize, y) * self.stride + @as(usize, x) * 4;
        self.pixels[o] = c.r;
        self.pixels[o + 1] = c.g;
        self.pixels[o + 2] = c.b;
        self.pixels[o + 3] = c.a;
    }

    /// Limpa com uma cor.
    pub fn clear(self: *Target, c: Color) void {
        var y: u32 = 0;
        while (y < self.height) : (y += 1) {
            var o = @as(usize, y) * self.stride;
            const end = o + @as(usize, self.width) * 4;
            while (o < end) : (o += 4) {
                self.pixels[o] = c.r;
                self.pixels[o + 1] = c.g;
                self.pixels[o + 2] = c.b;
                self.pixels[o + 3] = c.a;
            }
        }
    }
};

/// Vértice em espaço de tela (x, y em pixels; z = profundidade [0,1]).
pub const ScreenVertex = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
};

/// Opções de desenho.
pub const Options = struct {
    /// Descarta faces traseiras (o cálculo usa o espaço de visão).
    backface_culling: bool = false,
    /// Cor sólida dos triângulos.
    color: Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
};

/// Rasterizador: alvo + depth + pipeline.
pub const Rasterizer = struct {
    gpa: std.mem.Allocator,
    target: Target = .{},
    depth: depth_mod.DepthBuffer = .{},
    width: u32 = 0,
    height: u32 = 0,

    const Self = @This();

    pub fn init(gpa: std.mem.Allocator, width: u32, height: u32) !Self {
        var self = Self{ .gpa = gpa };
        try self.resize(gpa, width, height);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.depth.deinit(self.gpa);
        self.target = .{};
        self.width = 0;
        self.height = 0;
    }

    /// Redimensiona o alvo lógico (o framebuffer é do app: o
    /// rasterizador só escreve nele).
    pub fn resize(self: *Self, gpa: std.mem.Allocator, width: u32, height: u32) !void {
        if (width == 0 or height == 0) return error.InvalidDimensions;
        self.gpa = gpa;
        try self.depth.resize(gpa, width, height);
        self.width = width;
        self.height = height;
    }

    /// Define o alvo (o framebuffer do app, emprestado).
    pub fn setTarget(self: *Self, target: Target) !void {
        if (!target.isValid()) return error.InvalidTarget;
        self.target = target;
    }

    /// Limpa a cor de fundo e o depth.
    pub fn clear(self: *Self, color: Color) void {
        self.target.clear(color);
        self.depth.clear(1.0);
    }

    /// Desenha um triângulo JÁ em espaço de tela (com o depth test).
    pub fn drawTriangleScreen(self: *Self, v: [3]ScreenVertex, color: Color) void {
        const area = edge(v[0], v[1], v[2]);
        if (!std.math.isFinite(area) or @abs(area) < 1e-9) return; // degenerado
        const inv_area = 1.0 / area;

        // Caixa envolvente (pixels inteiros, clampada ao alvo).
        const min_x: f32 = @min(v[0].x, @min(v[1].x, v[2].x));
        const max_x: f32 = @max(v[0].x, @max(v[1].x, v[2].x));
        const min_y: f32 = @min(v[0].y, @min(v[1].y, v[2].y));
        const max_y: f32 = @max(v[0].y, @max(v[1].y, v[2].y));
        if (!std.math.isFinite(min_x) or !std.math.isFinite(max_x) or
            !std.math.isFinite(min_y) or !std.math.isFinite(max_y)) return;
        const x0: i64 = @intFromFloat(@floor(@max(0.0, min_x)));
        const x1: i64 = @intFromFloat(@ceil(@min(@as(f32, @floatFromInt(self.width)), max_x)));
        const y0: i64 = @intFromFloat(@floor(@max(0.0, min_y)));
        const y1: i64 = @intFromFloat(@ceil(@min(@as(f32, @floatFromInt(self.height)), max_y)));
        if (x1 <= x0 or y1 <= y0) return;

        var py: i64 = y0;
        while (py < y1) : (py += 1) {
            var px: i64 = x0;
            while (px < x1) : (px += 1) {
                const p = ScreenVertex{
                    .x = @as(f32, @floatFromInt(px)) + 0.5,
                    .y = @as(f32, @floatFromInt(py)) + 0.5,
                };
                const w0 = edge(v[1], v[2], p) * inv_area;
                const w1 = edge(v[2], v[0], p) * inv_area;
                const w2 = 1.0 - w0 - w1;
                // Dentro: os três pesos barycêntricos com o mesmo sinal
                // (o winding pode ser invertido).
                const inside = (w0 >= 0 and w1 >= 0 and w2 >= 0) or
                    (w0 <= 0 and w1 <= 0 and w2 <= 0);
                if (!inside) continue;
                const z = w0 * v[0].z + w1 * v[1].z + w2 * v[2].z;
                if (!std.math.isFinite(z) or z < 0.0 or z > 1.0) continue;
                const ux: u32 = @intCast(px);
                const uy: u32 = @intCast(py);
                if (z >= self.depth.get(ux, uy)) continue;
                self.depth.put(ux, uy, z);
                self.target.put(ux, uy, color);
            }
        }
    }

    /// Desenha uma malha: modelo → visão → recorte → projeção → tela.
    ///
    /// `aspect` = largura/altura da área visível. Sem alocação por
    /// triângulo (buffers locais de tamanho fixo).
    pub fn drawMesh(
        self: *Self,
        mesh: mesh_mod.Mesh,
        model: Mat4,
        cam: camera_mod.Camera,
        aspect: f32,
        opts: Options,
    ) void {
        if (!mesh.isValid()) return;
        const view = cam.view() orelse return;
        const proj = cam.projectionMatrix(aspect) orelse return;
        const mvp = Mat4.mul(proj, Mat4.mul(view, model));
        const view_model = Mat4.mul(view, model);
        // Culling de frustum (M140): triângulos fora da câmera são
        // descartados ANTES da projeção.
        const frustum = frustum_mod.Frustum.fromViewProjection(mvp);

        var ti: usize = 0;
        while (ti < mesh.triangleCount()) : (ti += 1) {
            const tri = mesh.triangle(ti) orelse continue;
            if (frustum) |f| {
                const sphere = mesh_mod.triangleSphere(tri) orelse continue;
                if (!f.containsSphere(sphere.center, sphere.radius)) continue;
            }
            self.drawTriangleWorld(tri, view_model, mvp, cam, opts);
        }
    }

    /// Pipeline de UM triângulo (espaço de mundo → tela).
    fn drawTriangleWorld(
        self: *Self,
        tri: [3]Vec3,
        view_model: Mat4,
        mvp: Mat4,
        cam: camera_mod.Camera,
        opts: Options,
    ) void {
        // Espaço de visão (para o recorte e o culling).
        var view_tri: [3]Vec3 = undefined;
        for (tri, 0..) |p, i| {
            const v = view_model.transformPoint(p) orelse return;
            view_tri[i] = v;
        }

        // Culling de face traseira (normal × direção da câmera).
        if (opts.backface_culling) {
            const n = view_tri[1].sub(view_tri[0]).cross(view_tri[2].sub(view_tri[0]));
            // A câmera está na origem do espaço de visão: a direção do
            // triângulo para a câmera é -view_tri[0].
            if (n.dot(view_tri[0].neg()) <= 0) return;
        }

        // Recorte no plano near (antes da projeção).
        var clipped: [2][3]Vec3 = undefined;
        const n_clipped = clipping.clipTriangleNear(view_tri, cam.near, &clipped);
        var ci: usize = 0;
        while (ci < n_clipped) : (ci += 1) {
            var screen: [3]ScreenVertex = undefined;
            var proj_ok = true;
            for (clipped[ci], 0..) |p, i| {
                const s = projectToScreen(mvp, p, self.width, self.height) orelse {
                    proj_ok = false;
                    break;
                };
                screen[i] = s;
            }
            if (!proj_ok) continue;
            self.drawTriangleScreen(screen, opts.color);
        }
    }

    /// Desenha um segmento 3D como um quadrilátero fino (2
    /// triângulos). A largura é em unidades de mundo.
    pub fn drawSegment(
        self: *Self,
        p0: Vec3,
        p1: Vec3,
        width: f32,
        color: Color,
        model: Mat4,
        cam: camera_mod.Camera,
        aspect: f32,
    ) void {
        if (!std.math.isFinite(width) or width <= 0) return;
        const dir = p1.sub(p0);
        if (dir.lengthSq() < math.epsilon * math.epsilon) return;
        // Perpendicular: cruza com o eixo Y; se o segmento é vertical,
        // cruza com o eixo X.
        var perp = dir.cross(Vec3.init(0, 1, 0));
        if (perp.lengthSq() < math.epsilon * math.epsilon) {
            perp = dir.cross(Vec3.init(1, 0, 0));
        }
        perp = perp.normalize() orelse return;
        const half = perp.scale(width * 0.5);
        const quad = [4]Vec3{ p0.sub(half), p1.sub(half), p1.add(half), p0.add(half) };
        const tris = [2][3]Vec3{
            .{ quad[0], quad[1], quad[2] },
            .{ quad[0], quad[2], quad[3] },
        };
        const view = cam.view() orelse return;
        const proj = cam.projectionMatrix(aspect) orelse return;
        const mvp = Mat4.mul(proj, Mat4.mul(view, model));
        const view_model = Mat4.mul(view, model);
        for (tris) |t| {
            self.drawTriangleWorld(t, view_model, mvp, cam, .{ .color = color });
        }
    }
};

/// Função de aresta (2D): o sinal dá o lado do ponto.
fn edge(a: ScreenVertex, b: ScreenVertex, p: ScreenVertex) f32 {
    return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
}

/// Projeta um ponto do espaço de visão para a tela (x, y em pixels, z em
/// [0,1]). `null` se estiver atrás da câmera ou degenerado.
pub fn projectToScreen(mvp: Mat4, p: Vec3, width: u32, height: u32) ?ScreenVertex {
    const clip = mvp.transformVec4(Vec4.fromVec3(p, 1));
    if (!clip.isFinite()) return null;
    if (clip.w <= math.epsilon) return null; // atrás da câmera
    const inv_w = 1.0 / clip.w;
    const ndc_x = clip.x * inv_w;
    const ndc_y = clip.y * inv_w;
    const ndc_z = clip.z * inv_w;
    if (!std.math.isFinite(ndc_x) or !std.math.isFinite(ndc_y) or
        !std.math.isFinite(ndc_z)) return null;
    return .{
        .x = (ndc_x * 0.5 + 0.5) * @as(f32, @floatFromInt(width)),
        .y = (1.0 - (ndc_y * 0.5 + 0.5)) * @as(f32, @floatFromInt(height)),
        .z = ndc_z,
    };
}

test "Target: escrita com stride e clear" {
    const stdt = @import("std");
    var buf: [24 * 2]u8 = undefined;
    @memset(&buf, 0);
    var target = Target{ .pixels = &buf, .width = 4, .height = 2, .stride = 4 * 4 + 8 };
    try stdt.testing.expect(target.isValid());
    target.put(1, 0, .{ .r = 10, .g = 20, .b = 30, .a = 255 });
    try stdt.testing.expectEqual(@as(u8, 10), buf[4]);
    try stdt.testing.expectEqual(@as(u8, 255), buf[7]);
    target.clear(.{ .r = 1, .g = 2, .b = 3, .a = 4 });
    try stdt.testing.expectEqual(@as(u8, 1), buf[0]);
    // Fora dos limites: ignorado.
    target.put(9, 9, .{ .r = 9, .g = 9, .b = 9, .a = 9 });
    try stdt.testing.expectEqual(@as(u8, 1), buf[0]);
}

test "Rasterizer: triângulo na tela preenche o interior" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var buf: [16 * 16 * 4]u8 = undefined;
    @memset(&buf, 0);
    const target = Target{ .pixels = &buf, .width = 16, .height = 16, .stride = 16 * 4 };

    var r = try Rasterizer.init(gpa, 16, 16);
    defer r.deinit();
    try r.setTarget(target);
    r.clear(.{ .r = 0, .g = 0, .b = 0, .a = 255 });

    r.drawTriangleScreen(
        .{ .{ .x = 4, .y = 4, .z = 0.5 }, .{ .x = 12, .y = 4, .z = 0.5 }, .{ .x = 4, .y = 12, .z = 0.5 } },
        .{ .r = 255, .g = 0, .b = 0, .a = 255 },
    );
    // O interior foi pintado; o fundo ficou intacto.
    try stdt.testing.expectEqual(@as(u8, 255), buf[(6 * 16 + 6) * 4]);
    try stdt.testing.expectEqual(@as(u8, 0), buf[(0 * 16 + 0) * 4]);
    // O depth foi gravado.
    try stdt.testing.expectApproxEqAbs(@as(f32, 0.5), r.depth.get(6, 6), 1e-4);
}

test "Rasterizer: depth test esconde o triângulo mais distante" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var buf: [16 * 16 * 4]u8 = undefined;
    @memset(&buf, 0);
    const target = Target{ .pixels = &buf, .width = 16, .height = 16, .stride = 16 * 4 };

    var r = try Rasterizer.init(gpa, 16, 16);
    defer r.deinit();
    try r.setTarget(target);
    r.clear(.{ .r = 0, .g = 0, .b = 0, .a = 255 });

    // Longe (z = 0.8) primeiro, depois perto (z = 0.2): o perto vence.
    r.drawTriangleScreen(
        .{ .{ .x = 2, .y = 2, .z = 0.8 }, .{ .x = 14, .y = 2, .z = 0.8 }, .{ .x = 2, .y = 14, .z = 0.8 } },
        .{ .r = 255, .g = 0, .b = 0, .a = 255 },
    );
    r.drawTriangleScreen(
        .{ .{ .x = 2, .y = 2, .z = 0.2 }, .{ .x = 14, .y = 2, .z = 0.2 }, .{ .x = 2, .y = 14, .z = 0.2 } },
        .{ .r = 0, .g = 255, .b = 0, .a = 255 },
    );
    try stdt.testing.expectEqual(@as(u8, 0), buf[(6 * 16 + 6) * 4]); // vermelho
    try stdt.testing.expectEqual(@as(u8, 255), buf[(6 * 16 + 6) * 4 + 1]); // verde
    try stdt.testing.expectApproxEqAbs(@as(f32, 0.2), r.depth.get(6, 6), 1e-4);
}

test "Rasterizer: cubo 3D com depth buffer" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var buf: [64 * 64 * 4]u8 = undefined;
    @memset(&buf, 0);
    const target = Target{ .pixels = &buf, .width = 64, .height = 64, .stride = 64 * 4 };

    var r = try Rasterizer.init(gpa, 64, 64);
    defer r.deinit();
    try r.setTarget(target);
    r.clear(.{ .r = 0, .g = 0, .b = 0, .a = 255 });

    var cube = mesh_mod.CubeMesh.init(2.0);
    const cam = camera_mod.Camera{ .distance = 6.0, .yaw = 0.6, .pitch = 0.4 };
    r.drawMesh(cube.mesh(), Mat4.identity(), cam, 1.0, .{ .color = .{ .r = 200, .g = 200, .b = 255, .a = 255 } });

    // Algo foi desenhado (o cubo ocupa a tela).
    var lit: u32 = 0;
    var y: u32 = 0;
    while (y < 64) : (y += 1) {
        var x: u32 = 0;
        while (x < 64) : (x += 1) {
            if (buf[(y * 64 + x) * 4] > 0) lit += 1;
        }
    }
    try stdt.testing.expect(lit > 100);
    // O fundo continua preto.
    try stdt.testing.expectEqual(@as(u8, 0), buf[0]);
}

test "projectToScreen: ponto à frente vira pixel, atrás não" {
    const stdt = @import("std");
    const proj = Mat4.perspective(std.math.pi * 0.5, 1.0, 0.1, 100.0).?;
    const s = projectToScreen(proj, Vec3.init(0, 0, -1), 100, 100).?;
    try stdt.testing.expectApproxEqAbs(@as(f32, 50), s.x, 0.01);
    try stdt.testing.expectApproxEqAbs(@as(f32, 50), s.y, 0.01);
    // Atrás da câmera: nada.
    try stdt.testing.expect(projectToScreen(proj, Vec3.init(0, 0, 1), 100, 100) == null);
}

test "fuzz raster: triângulos aleatórios não escreve fora do alvo" {
    try std.testing.fuzz({}, fuzzRaster, .{});
}

fn fuzzRaster(_: void, smith: *std.testing.Smith) !void {
    var bytes: [64]u8 = undefined;
    smith.bytes(&bytes);
    const gpa = std.testing.allocator;

    // Alvo com uma faixa de canário DEPOIS da última linha: qualquer
    // escrita fora da área é detectada.
    const w: u32 = 16;
    const h: u32 = 8;
    const guard: usize = 64;
    var buf: [w * h * 4 + guard]u8 = undefined;
    @memset(&buf, 0xAA);
    const target = Target{ .pixels = &buf, .width = w, .height = h, .stride = w * 4 };

    var r = try Rasterizer.init(gpa, w, h);
    defer r.deinit();
    try r.setTarget(target);
    r.clear(.{ .r = 0, .g = 0, .b = 0, .a = 255 });

    const f = struct {
        fn at(b: []const u8, i: usize) f32 {
            const v: i32 = @as(i32, b[i % b.len]) - 128;
            return @as(f32, @floatFromInt(v)) * 0.5;
        }
    };
    const tri = [3]ScreenVertex{
        .{ .x = f.at(&bytes, 0), .y = f.at(&bytes, 4), .z = f.at(&bytes, 8) },
        .{ .x = f.at(&bytes, 12), .y = f.at(&bytes, 16), .z = f.at(&bytes, 20) },
        .{ .x = f.at(&bytes, 24), .y = f.at(&bytes, 28), .z = f.at(&bytes, 32) },
    };
    r.drawTriangleScreen(tri, .{ .r = 255, .g = 255, .b = 255, .a = 255 });

    // O canário está intacto.
    var i: usize = w * h * 4;
    while (i < buf.len) : (i += 1) {
        try std.testing.expectEqual(@as(u8, 0xAA), buf[i]);
    }
}

test "Rasterizer: o culling de frustum descarta triângulos fora da câmera" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var buf: [64 * 64 * 4]u8 = undefined;
    @memset(&buf, 0);
    const target = Target{ .pixels = &buf, .width = 64, .height = 64, .stride = 64 * 4 };

    var r = try Rasterizer.init(gpa, 64, 64);
    defer r.deinit();
    try r.setTarget(target);
    r.clear(.{ .r = 0, .g = 0, .b = 0, .a = 255 });

    // Um triângulo gigante longe da câmera: descartado pelo frustum.
    const far_away = [_]Vec3{
        Vec3.init(1000, 1000, -1000),
        Vec3.init(1010, 1000, -1000),
        Vec3.init(1000, 1010, -1000),
    };
    const cam = camera_mod.Camera{ .distance = 5.0, .yaw = 0.6, .pitch = 0.4 };
    r.drawMesh(
        .{ .positions = &far_away, .indices = &.{ 0, 1, 2 } },
        Mat4.identity(),
        cam,
        1.0,
        .{ .color = .{ .r = 255, .g = 0, .b = 0, .a = 255 } },
    );
    // Nada foi desenhado (o fundo intacto).
    var y: u32 = 0;
    while (y < 64) : (y += 1) {
        var x: u32 = 0;
        while (x < 64) : (x += 1) {
            try stdt.testing.expectEqual(@as(u8, 0), buf[(y * 64 + x) * 4]);
        }
    }
}
