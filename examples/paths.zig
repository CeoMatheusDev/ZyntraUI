//! ZyntraUI — exemplo: caminhos vetoriais (exemplo, não parte da lib).
//!
//! Demonstra o caminho vetorial (M158–M160) do começo ao fim:
//! 1. Um path SVG é ANALISADO (`draw.svg`) em segmentos.
//! 2. Os segmentos são ACHATADOS em polilinhas (`draw.path`).
//! 3. O caminho é desenhado no framebuffer de software: preenchimento
//!    (nonzero e evenodd) e traço (com junta e ponta).
//! 4. Um ícone é montado com curvas (círculo + quadrado arredondado) e
//!    entra na UI como comando de desenho.

const std = @import("std");
const zyntra_ui = @import("zyntra_ui");

const WIDTH = 200;
const HEIGHT = 120;

/// Path SVG de um ícone (um "estrela" de 5 pontas simplificada).
const icon_svg = "M 50 10 L 61 38 L 92 38 L 67 56 L 76 86 L 50 67 L 24 86 L 33 56 L 8 38 L 39 38 Z";

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var fb = try zyntra_ui.software.raster.SoftwareFramebuffer.init(allocator, WIDTH, HEIGHT);
    defer fb.deinit(allocator);

    // 1) O path SVG vira segmentos.
    var segs: [64]zyntra_ui.PathSegment = undefined;
    const builder = try zyntra_ui.svg.parsePath(icon_svg, &segs);
    std.debug.assert(builder.len > 0);

    // 2) Os segmentos viram polilinhas.
    var points: [256]zyntra_ui.Vec2 = undefined;
    var contours: [16]zyntra_ui.PathContourRange = undefined;
    const flattened = try zyntra_ui.draw.path.flatten(builder.segments(), 0.25, &points, &contours);
    std.debug.assert(flattened.contourCount() == 1);

    // 3) O caminho é desenhado: preenchimento + traço.
    var dl = zyntra_ui.DrawList.initEmpty();
    defer dl.deinit(allocator);
    try dl.path(
        allocator,
        flattened,
        zyntra_ui.Color.rgb(240, 200, 90),
        0,
        .nonzero,
        .round,
        .butt,
    );
    try dl.path(
        allocator,
        flattened,
        zyntra_ui.Color.rgb(30, 30, 40),
        2,
        .nonzero,
        .round,
        .round,
    );

    // Um anel: dois círculos concêntricos (o de dentro no sentido
    // oposto) — a regra evenodd deixa o miolo vazado.
    var ring_segs: [128]zyntra_ui.PathSegment = undefined;
    var ring = zyntra_ui.PathBuilder.init(&ring_segs);
    try ring.circle(.{ .x = 140, .y = 60 }, 40);
    try ring.circle(.{ .x = 140, .y = 60 }, 22);
    var ring_points: [512]zyntra_ui.Vec2 = undefined;
    var ring_contours: [16]zyntra_ui.PathContourRange = undefined;
    const ring_flat = try zyntra_ui.draw.path.flatten(ring.segments(), 0.2, &ring_points, &ring_contours);
    try dl.path(
        allocator,
        ring_flat,
        zyntra_ui.Color.rgb(120, 200, 240),
        0,
        .evenodd,
        .round,
        .butt,
    );

    fb.clear(zyntra_ui.Color.rgb(10, 10, 14));
    const stats = try zyntra_ui.software.raster.render(&fb, dl.items(), zyntra_ui.Rect.init(0, 0, WIDTH, HEIGHT));
    const lit = countLit(fb.pixels);
    std.debug.assert(lit > 100);
    std.debug.assert(stats.drawn == 3);

    // O miolo do anel está vazado (o fundo aparece no centro).
    const hole = fb.get(140, 60);
    std.debug.assert(hole[0] < 40);

    // 4) Um ícone (path SVG) entra na UI pelo WIDGET de ícone: o cache
    //    analisa o SVG uma vez e o widget encaixa o caminho no rect.
    var ctx = try zyntra_ui.Context.init(allocator, .{
        .viewport = zyntra_ui.Rect.init(0, 0, WIDTH, HEIGHT),
    });
    defer ctx.deinit();
    ctx.beginFrame();

    var icons = zyntra_ui.widgets.icon.Cache.init(allocator);
    defer icons.deinit();
    const star = (try icons.get(icon_svg)).?;
    try zyntra_ui.widgets.icon.drawIcon(
        &ctx,
        zyntra_ui.Rect.init(4, 4, 48, 48),
        star,
        .{ .fit = .contain, .color = zyntra_ui.Color.rgb(120, 220, 160) },
    );

    // Um ícone de curvas (círculo + retângulo arredondado).
    var icon_segs: [64]zyntra_ui.PathSegment = undefined;
    var icon = zyntra_ui.PathBuilder.init(&icon_segs);
    try icon.circle(.{ .x = 24, .y = 24 }, 18);
    try icon.roundRect(.{ .x = 40, .y = 8, .w = 40, .h = 32 }, 8);
    var icon_points: [256]zyntra_ui.Vec2 = undefined;
    var icon_contours: [16]zyntra_ui.PathContourRange = undefined;
    const icon_flat = try zyntra_ui.draw.path.flatten(icon.segments(), 0.2, &icon_points, &icon_contours);
    try zyntra_ui.widgets.icon.drawIcon(
        &ctx,
        zyntra_ui.Rect.init(60, 4, 48, 48),
        icon_flat,
        .{ .fit = .contain, .color = zyntra_ui.Color.rgb(120, 220, 160) },
    );
    const cmds = ctx.drawCommands().len;
    ctx.endFrame();

    std.debug.print(
        "paths segments={d} points={d} contours={d} lit={d} drawn={d} cmds={d} cached={d}\n",
        .{
            builder.len, flattened.pointCount(), flattened.contourCount(),
            lit,         stats.drawn,            cmds,
            icons.count,
        },
    );
    std.debug.assert(cmds == 2);
}

/// Conta os pixels que não são o fundo (o fundo é preto).
fn countLit(pixels: []const u8) u32 {
    var lit: u32 = 0;
    var i: usize = 0;
    while (i + 3 < pixels.len) : (i += 4) {
        if (pixels[i] > 30 or pixels[i + 1] > 30 or pixels[i + 2] > 30) lit += 1;
    }
    return lit;
}
