//! ZyntraUI — exemplo: viewport 3D (exemplo, não parte da lib).
//!
//! Demonstra o viewport 3D modular (M156–M157) do começo ao fim:
//! 1. Um renderizador EXTERNO (o rasterizador em software da biblioteca)
//!    produz uma imagem RGBA8.
//! 2. O WIDGET do viewport recebe essa imagem (sem conhecer o
//!    rasterizador) e a apresenta.
//! 3. Cubo 3D em wireframe e preenchido (com depth buffer).
//! 4. Câmera com órbita/pan/zoom (o estado é do app).
//! 5. Grid e eixos XYZ.

const std = @import("std");
const zyntra_ui = @import("zyntra_ui");

const WIDTH = 240;
const HEIGHT = 180;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // 1) O app aloca o framebuffer (o renderizador escreve nele).
    var pixels: [WIDTH * HEIGHT * 4]u8 = undefined;
    @memset(&pixels, 0);

    var raster = try zyntra_ui.viewport3d.raster.Rasterizer.init(allocator, WIDTH, HEIGHT);
    defer raster.deinit();
    try raster.setTarget(.{
        .pixels = &pixels,
        .width = WIDTH,
        .height = HEIGHT,
        .stride = WIDTH * 4,
    });

    // 4) A câmera (dados do app) e o cubo.
    var cam = zyntra_ui.viewport3d.camera.Camera{
        .distance = 5.0,
        .yaw = 0.7,
        .pitch = 0.45,
    };
    var cube = zyntra_ui.viewport3d.mesh.CubeMesh.init(1.6);
    const aspect = @as(f32, @floatFromInt(WIDTH)) / @as(f32, @floatFromInt(HEIGHT));

    // 3a) Cubo PREENCHIDO (com depth buffer) + grid + eixos.
    raster.clear(.{ .r = 12, .g = 14, .b = 20, .a = 255 });
    zyntra_ui.viewport3d.grid.drawGrid(&raster, cam, aspect, .{ .spacing = 1.0, .extent = 4 });
    zyntra_ui.viewport3d.grid.drawAxes(&raster, cam, aspect, .{ .length = 1.5 });
    raster.drawMesh(
        cube.mesh(),
        zyntra_ui.viewport3d.math.Mat4.identity(),
        cam,
        aspect,
        .{ .color = .{ .r = 210, .g = 200, .b = 120, .a = 255 }, .backface_culling = true },
    );
    const filled_lit = countLit(&pixels);

    // 3b) Cubo em WIREFRAME (as arestas como segmentos finos).
    raster.clear(.{ .r = 12, .g = 14, .b = 20, .a = 255 });
    zyntra_ui.viewport3d.grid.drawGrid(&raster, cam, aspect, .{ .spacing = 1.0, .extent = 4 });
    zyntra_ui.viewport3d.grid.drawAxes(&raster, cam, aspect, .{ .length = 1.5 });
    drawWireframeCube(&raster, &cam, aspect, &cube);
    const wire_lit = countLit(&pixels);

    // 3c) SELEÇÃO: o clique no centro da tela vira um raio que acerta o
    // cubo (o objeto mais próximo).
    const mvp = zyntra_ui.viewport3d.math.Mat4.mul(
        cam.projectionMatrix(aspect).?,
        cam.view().?,
    );
    var picked: ?zyntra_ui.viewport3d.pick.Hit = null;
    if (zyntra_ui.viewport3d.pick.screenRay(mvp, WIDTH / 2, HEIGHT / 2, WIDTH, HEIGHT)) |ray| {
        picked = zyntra_ui.viewport3d.pick.pickMesh(
            ray,
            cube.mesh(),
            zyntra_ui.viewport3d.math.Mat4.identity(),
            1,
            false,
        );
    }
    // O triângulo atingido é redesenhado com a cor de destaque.
    if (picked) |hit| {
        const hl = zyntra_ui.viewport3d.mesh.Mesh{
            .positions = &cube.positions,
            .indices = &[_]u32{
                cube.indices[hit.triangle * 3],
                cube.indices[hit.triangle * 3 + 1],
                cube.indices[hit.triangle * 3 + 2],
            },
        };
        raster.clear(.{ .r = 12, .g = 14, .b = 20, .a = 255 });
        raster.drawMesh(
            hl,
            zyntra_ui.viewport3d.math.Mat4.identity(),
            cam,
            aspect,
            .{ .color = .{ .r = 255, .g = 120, .b = 60, .a = 255 } },
        );
    }
    const pick_lit = countLit(&pixels);

    // 4b) Órbita: a câmera gira e o render muda.
    cam.orbit(0.4, 0.1);
    raster.clear(.{ .r = 12, .g = 14, .b = 20, .a = 255 });
    raster.drawMesh(
        cube.mesh(),
        zyntra_ui.viewport3d.math.Mat4.identity(),
        cam,
        aspect,
        .{ .color = .{ .r = 120, .g = 200, .b = 255, .a = 255 } },
    );
    const orbit_lit = countLit(&pixels);

    // 5) O widget recebe a imagem PRONTA (desacoplado do rasterizador).
    var ctx = try zyntra_ui.Context.init(allocator, .{
        .viewport = zyntra_ui.Rect.init(0, 0, 640, 480),
    });
    defer ctx.deinit();
    var state = zyntra_ui.viewport3d.viewport.State{
        .yaw = cam.yaw,
        .pitch = cam.pitch,
        .distance = cam.distance,
    };
    const source = zyntra_ui.viewport3d.viewport.ImageSource{
        .pixels = &pixels,
        .width = WIDTH,
        .height = HEIGHT,
        .stride = WIDTH * 4,
    };

    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = zyntra_ui.Vec2.init(120, 90),
    } });
    const res = try zyntra_ui.viewport3d.viewport.viewport3d(
        &ctx,
        zyntra_ui.Id.fromString("vp3d:widget"),
        zyntra_ui.Rect.init(10, 10, WIDTH, HEIGHT),
        source,
        &state,
        .{},
    );
    const cmds = ctx.drawCommands().len;
    ctx.endFrame();

    std.debug.print(
        "viewport3d filled={d} wire={d} orbit={d} pick={d} widget_cmds={d} focused={} dragging={} yaw={d:.3}\n",
        .{ filled_lit, wire_lit, orbit_lit, pick_lit, cmds, res.focused, res.dragging, state.yaw },
    );
    std.debug.assert(filled_lit > 0);
    std.debug.assert(wire_lit > 0);
    std.debug.assert(orbit_lit > 0);
    std.debug.assert(pick_lit > 0); // o clique no centro acerta o cubo
    std.debug.assert(res.focused);
}

/// Desenha as arestas de um cubo como segmentos finos.
fn drawWireframeCube(
    raster: *zyntra_ui.viewport3d.raster.Rasterizer,
    cam: *const zyntra_ui.viewport3d.camera.Camera,
    aspect: f32,
    cube: *const zyntra_ui.viewport3d.mesh.CubeMesh,
) void {
    const v = cube.positions;
    const edges = [_][2]u8{
        .{ 0, 1 }, .{ 1, 2 }, .{ 2, 3 }, .{ 3, 0 },
        .{ 4, 5 }, .{ 5, 6 }, .{ 6, 7 }, .{ 7, 4 },
        .{ 0, 4 }, .{ 1, 5 }, .{ 2, 6 }, .{ 3, 7 },
    };
    for (edges) |e| {
        raster.drawSegment(
            v[e[0]],
            v[e[1]],
            0.02,
            .{ .r = 255, .g = 230, .b = 120, .a = 255 },
            zyntra_ui.viewport3d.math.Mat4.identity(),
            cam.*,
            aspect,
        );
    }
}

/// Conta os pixels que NÃO são o fundo (o fundo é escuro: 12/14/20).
fn countLit(pixels: []const u8) u32 {
    var lit: u32 = 0;
    var i: usize = 0;
    while (i + 3 < pixels.len) : (i += 4) {
        if (pixels[i] > 40 or pixels[i + 1] > 40 or pixels[i + 2] > 40) lit += 1;
    }
    return lit;
}
