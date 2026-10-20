//! ZyntraUI — grid e eixos do viewport 3D (viewport3d/grid).
//!
//! Escopo M157: recursos visuais de apoio — o plano de grade (XZ) e os
//! eixos X/Y/Z, desenhados como segmentos finos pelo mesmo pipeline do
//! rasterizador (recorte, projeção e depth test inclusos).
//!
//! Nada aqui é obrigatório: o app escolhe o que desenhar.

const std = @import("std");
const types = @import("../core/types.zig");
const math = @import("math.zig");
const camera_mod = @import("camera.zig");
const raster_mod = @import("raster.zig");

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Color = types.Color;

/// Opções do plano de grade.
pub const GridOptions = struct {
    /// Espaçamento entre linhas (unidades de mundo).
    spacing: f32 = 1.0,
    /// Número de linhas de cada lado da origem (total = 2*extent+1).
    extent: i32 = 8,
    /// Cor das linhas da grade.
    color: Color = .{ .r = 64, .g = 68, .b = 78, .a = 255 },
    /// Cor dos eixos (X, Y, Z) destacados.
    axis_color: Color = .{ .r = 130, .g = 140, .b = 160, .a = 255 },
    /// Espessura das linhas (unidades de mundo).
    thickness: f32 = 0.02,
};

/// Opções dos eixos XYZ.
pub const AxisOptions = struct {
    /// Comprimento de cada eixo (unidades de mundo).
    length: f32 = 1.0,
    /// Espessura dos eixos.
    thickness: f32 = 0.03,
    x_color: Color = .{ .r = 220, .g = 90, .b = 90, .a = 255 },
    y_color: Color = .{ .r = 120, .g = 210, .b = 120, .a = 255 },
    z_color: Color = .{ .r = 100, .g = 140, .b = 230, .a = 255 },
};

/// Desenha o plano de grade (XZ) com os eixos destacados.
pub fn drawGrid(
    r: *raster_mod.Rasterizer,
    cam: camera_mod.Camera,
    aspect: f32,
    opts: GridOptions,
) void {
    if (!std.math.isFinite(opts.spacing) or opts.spacing <= 0) return;
    if (!std.math.isFinite(opts.thickness) or opts.thickness <= 0) return;
    const extent: i32 = @max(0, @min(opts.extent, 4096));
    const span = @as(f32, @floatFromInt(extent)) * opts.spacing;
    const model = Mat4.identity();

    var i: i32 = -extent;
    while (i <= extent) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) * opts.spacing;
        const is_axis = (i == 0);
        const color = if (is_axis) opts.axis_color else opts.color;
        const thick = if (is_axis) opts.thickness * 2 else opts.thickness;
        // Linhas paralelas a X (z constante) e a Z (x constante).
        r.drawSegment(
            Vec3.init(-span, 0, t),
            Vec3.init(span, 0, t),
            thick,
            color,
            model,
            cam,
            aspect,
        );
        r.drawSegment(
            Vec3.init(t, 0, -span),
            Vec3.init(t, 0, span),
            thick,
            color,
            model,
            cam,
            aspect,
        );
    }
}

/// Desenha os eixos X, Y e Z a partir da origem.
pub fn drawAxes(
    r: *raster_mod.Rasterizer,
    cam: camera_mod.Camera,
    aspect: f32,
    opts: AxisOptions,
) void {
    if (!std.math.isFinite(opts.length) or opts.length <= 0) return;
    if (!std.math.isFinite(opts.thickness) or opts.thickness <= 0) return;
    const model = Mat4.identity();
    const l = opts.length;
    r.drawSegment(Vec3.splat(0), Vec3.init(l, 0, 0), opts.thickness, opts.x_color, model, cam, aspect);
    r.drawSegment(Vec3.splat(0), Vec3.init(0, l, 0), opts.thickness, opts.y_color, model, cam, aspect);
    r.drawSegment(Vec3.splat(0), Vec3.init(0, 0, l), opts.thickness, opts.z_color, model, cam, aspect);
}

test "grid: desenha linhas e eixos sem crash" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var buf: [64 * 64 * 4]u8 = undefined;
    @memset(&buf, 0);
    const target = raster_mod.Target{ .pixels = &buf, .width = 64, .height = 64, .stride = 64 * 4 };

    var r = try raster_mod.Rasterizer.init(gpa, 64, 64);
    defer r.deinit();
    try r.setTarget(target);
    r.clear(.{ .r = 0, .g = 0, .b = 0, .a = 255 });

    const cam = camera_mod.Camera{ .distance = 8.0, .yaw = 0.7, .pitch = 0.5 };
    drawGrid(&r, cam, 1.0, .{ .spacing = 1.0, .extent = 3 });
    drawAxes(&r, cam, 1.0, .{ .length = 1.0 });

    // Algo foi desenhado.
    var lit: u32 = 0;
    var y: u32 = 0;
    while (y < 64) : (y += 1) {
        var x: u32 = 0;
        while (x < 64) : (x += 1) {
            if (buf[(y * 64 + x) * 4] > 0) lit += 1;
        }
    }
    try stdt.testing.expect(lit > 10);

    // Opções degeneradas: nada acontece (sem crash).
    drawGrid(&r, cam, 1.0, .{ .spacing = 0 });
    drawGrid(&r, cam, 1.0, .{ .thickness = -1 });
    drawAxes(&r, cam, 1.0, .{ .length = 0 });
}
