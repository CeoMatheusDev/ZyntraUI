//! ZyntraUI — estatísticas estendidas de frame (draw/stats).
//!
//! Escopo M153: observabilidade do pipeline sem alterar os contratos
//! existentes. `renderer.FrameStats` é um `extern struct` PÚBLICO (o
//! backend da C-ABI depende do layout dele), então as métricas novas
//! moram aqui, num tipo independente.
//!
//! - `FrameMetrics`: contadores por frame (comandos por tipo, bytes de
//!   texto, glifos, regiões sujas, crescimentos de buffer).
//! - `frameMetrics`: varre a `DrawList` **sem alocar** (uso diagnóstico,
//!   fora da hot path).
//!
//! Ownership: nada é alocado; as métricas são um retrato do frame.

const std = @import("std");
const types = @import("../core/types.zig");
const commands = @import("commands.zig");
const renderer = @import("renderer.zig");

/// Métricas estendidas de um frame (independentes de `FrameStats`).
pub const FrameMetrics = extern struct {
    /// Comandos na lista (todos os tipos).
    commands_total: u32 = 0,
    /// Comandos dentro do viewport (após culling).
    commands_visible: u32 = 0,
    /// Comandos descartados pelo culling.
    commands_culled: u32 = 0,
    /// Retângulos preenchidos/contornados/arredondados.
    rects: u32 = 0,
    /// Comandos de texto (runs de bytes UTF-8).
    texts: u32 = 0,
    /// Bytes de texto copiados para a arena.
    text_bytes: u32 = 0,
    /// Comandos de imagem.
    images: u32 = 0,
    /// Comandos de imagem com região de origem (sprites/atlas).
    image_regions: u32 = 0,
    /// Comandos de run de glifos.
    glyph_runs: u32 = 0,
    /// Glifos somados de todos os runs.
    glyphs_total: u32 = 0,
    /// Chamadas de `mark_dirty` no frame (regiões sujas acumuladas).
    dirty_rects: u32 = 0,
    /// Crescimentos (realocações) dos buffers da lista no frame.
    buffer_growths: u32 = 0,
};

/// Calcula as métricas do frame a partir da lista (sem alocar).
/// `dirty_rects` e `buffer_growths` vêm do contexto (o chamador
/// completa com `Context.frameMetrics`).
pub fn frameMetrics(list: *const commands.DrawList, viewport: types.Rect) FrameMetrics {
    var out = FrameMetrics{ .commands_total = @intCast(list.items().len) };
    const culled = renderer.cull(list.items(), viewport);
    out.commands_visible = culled.visible;
    out.commands_culled = culled.culled;
    out.text_bytes = @intCast(list.text_bytes.items.len);
    for (list.items()) |cmd| {
        switch (cmd) {
            .rect_filled, .rect_outline, .rect_rounded, .rect_gradient, .rect_gradient_radial, .rect_gradient_conic => out.rects += 1,
            .text => out.texts += 1,
            .image => out.images += 1,
            .glyph_run => |g| {
                out.glyph_runs += 1;
                out.glyphs_total += g.count;
            },
            else => {},
        }
    }
    return out;
}

test "frameMetrics conta por tipo sem alocar" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var dl = commands.DrawList.initEmpty();
    defer dl.deinit(gpa);

    const font = @import("../text/metrics.zig").FontMetrics.withSize(10);
    try dl.rectFilled(gpa, types.Rect.init(0, 0, 10, 10), types.Color.rgb(1, 2, 3));
    try dl.rectOutline(gpa, types.Rect.init(0, 0, 10, 10), types.Color.rgb(1, 2, 3), 1.0);
    try dl.pushText(gpa, types.Vec2.init(0, 0), types.Color.rgb(1, 2, 3), font, "abc");
    try dl.image(gpa, types.Rect.init(0, 0, 4, 4), image_for_test(), types.Color.rgb(1, 2, 3));

    const m = frameMetrics(&dl, types.Rect.init(0, 0, 100, 100));
    try stdt.testing.expectEqual(@as(u32, 4), m.commands_total);
    try stdt.testing.expectEqual(@as(u32, 4), m.commands_visible);
    try stdt.testing.expectEqual(@as(u32, 0), m.commands_culled);
    try stdt.testing.expectEqual(@as(u32, 2), m.rects);
    try stdt.testing.expectEqual(@as(u32, 1), m.texts);
    try stdt.testing.expectEqual(@as(u32, 3), m.text_bytes);
    try stdt.testing.expectEqual(@as(u32, 1), m.images);

    // Fora do viewport, o comando é descartado.
    const m2 = frameMetrics(&dl, types.Rect.init(1000, 1000, 10, 10));
    try stdt.testing.expectEqual(@as(u32, 4), m2.commands_culled);
}

fn image_for_test() @import("image.zig").Image {
    var bytes: [16]u8 = undefined;
    for (&bytes, 0..) |*b, i| b.* = @intCast(i);
    return @import("image.zig").Image.init(2, 2, &bytes) catch unreachable;
}
