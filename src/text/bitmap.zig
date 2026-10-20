//! ZyntraUI — fonte de bitmap global (text/bitmap).
//!
//! Escopo M142: um atlas MONOESPAÇADO aplicado a TODOS os widgets de
//! uma vez. O app registra a fonte no `Context` (`Context.setBitmapFont`)
//! e todo texto desenhado pelos widgets passa a sair do atlas (blits),
//! visível até no rasterizador de referência.
//!
//! Por que monoespaçado: os widgets medem o texto com as
//! `FontMetrics` que recebem (avanço uniforme). Para que a medida e o
//! desenho coincidam — e o cursor, a seleção e o corte de texto fiquem
//! no lugar — o avanço de TODOS os glifos do atlas precisa ser igual ao
//! avanço das métricas usadas pelos widgets. Se não for, o app pode
//! trocar `FontMetrics` por outra de mesmo avanço.
//!
//! Ownership: o atlas é emprestado pelo chamador e precisa viver
//! enquanto estiver registrado.

const std = @import("std");
const metrics_mod = @import("metrics.zig");
const atlas_mod = @import("atlas.zig");
const image_mod = @import("../draw/image.zig");

/// Erros da fonte de bitmap.
pub const Error = error{
    /// Atlas vazio ou sem glifos.
    InvalidGlyph,
    /// Avanço inválido (não-finito ou ≤ 0).
    InvalidMetrics,
    /// Os glifos do atlas não têm o mesmo avanço (fonte não monoespaçada).
    NotMonospace,
};

/// Fonte de bitmap monoespaçada (atlas + avanço lógico por glifo).
pub const BitmapFont = struct {
    /// Atlas de glifos (emprestado).
    atlas: *const atlas_mod.FontAtlas,
    /// Avanço horizontal de cada glifo, em pixels lógicos.
    advance: f32 = 0,

    /// Valida o atlas e deriva o avanço (comum a todos os glifos).
    /// `NotMonospace` quando os glifos têm avanços diferentes.
    pub fn init(atlas: *const atlas_mod.FontAtlas) Error!BitmapFont {
        if (atlas.glyphs.len == 0) return error.InvalidGlyph;
        const first = atlas.glyphs[0].metrics.advance;
        if (!std.math.isFinite(first) or first <= 0) return error.InvalidMetrics;
        for (atlas.glyphs) |g| {
            if (g.metrics.advance != first) return error.NotMonospace;
        }
        return .{ .atlas = atlas, .advance = first };
    }

    /// True quando a fonte serve as métricas dadas (mesmo avanço).
    pub fn matches(self: BitmapFont, font: metrics_mod.FontMetrics) bool {
        return std.math.isFinite(font.advance) and font.advance == self.advance;
    }

    /// True quando o atlas tem o glifo.
    pub fn hasGlyph(self: BitmapFont, codepoint: u21) bool {
        return self.atlas.glyph(codepoint) != null;
    }
};

test "BitmapFont deriva o avanço e exige monoespaçada" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;

    var b = atlas_mod.Builder.init(64, 64, 1);
    defer b.deinit(gpa);
    _ = try b.addGlyph(gpa, 'A', 4, 8, .{ .advance = 6, .bearing_y = -8, .height = 8 });
    _ = try b.addGlyph(gpa, 'B', 4, 8, .{ .advance = 6, .bearing_y = -8, .height = 8 });
    var bytes: [64 * 64 * 4]u8 = undefined;
    for (&bytes, 0..) |*p, i| p.* = @truncate(i);
    const img = try image_mod.Image.init(64, 64, &bytes);
    var atlas = try b.finish(gpa, img);
    defer atlas.deinit(gpa);

    const font = try BitmapFont.init(&atlas);
    try stdt.testing.expectEqual(@as(f32, 6), font.advance);
    try stdt.testing.expect(font.matches(metrics_mod.FontMetrics.withSize(10))); // advance 6
    try stdt.testing.expect(!font.matches(metrics_mod.FontMetrics.withSize(16))); // advance 9.6
    try stdt.testing.expect(font.hasGlyph('A'));
    try stdt.testing.expect(!font.hasGlyph('Z'));

    // Fonte proporcional é recusada.
    var b2 = atlas_mod.Builder.init(64, 64, 1);
    defer b2.deinit(gpa);
    _ = try b2.addGlyph(gpa, 'A', 4, 8, .{ .advance = 6, .bearing_y = -8, .height = 8 });
    _ = try b2.addGlyph(gpa, 'B', 4, 8, .{ .advance = 3, .bearing_y = -8, .height = 8 });
    var atlas2 = try b2.finish(gpa, img);
    defer atlas2.deinit(gpa);
    try stdt.testing.expectError(error.NotMonospace, BitmapFont.init(&atlas2));
}

test "fuzz BitmapFont: monoespaçada ou recusada, nunca incoerente" {
    try std.testing.fuzz({}, fuzzBitmapFont, .{});
}

fn fuzzBitmapFont(_: void, smith: *std.testing.Smith) !void {
    var bytes: [32]u8 = undefined;
    smith.bytes(&bytes);
    const gpa = std.testing.allocator;

    var b = atlas_mod.Builder.init(32, 32, 1);
    defer b.deinit(gpa);
    const adv_a = @as(f32, @floatFromInt(bytes[0] % 16)) + 1.0;
    const adv_b = @as(f32, @floatFromInt(bytes[1] % 16)) + 1.0;
    _ = b.addGlyph(gpa, 'A', 4, 8, .{ .advance = adv_a, .bearing_y = -8, .height = 8 }) catch return;
    _ = b.addGlyph(gpa, 'B', 4, 8, .{ .advance = adv_b, .bearing_y = -8, .height = 8 }) catch return;
    var img_bytes: [32 * 32 * 4]u8 = undefined;
    for (&img_bytes, 0..) |*p, i| p.* = @truncate(i);
    const img = image_mod.Image.init(32, 32, &img_bytes) catch return;
    var atlas = b.finish(gpa, img) catch return;
    defer atlas.deinit(gpa);

    const font = BitmapFont.init(&atlas) catch |err| switch (err) {
        // Fonte proporcional ⇒ recusada (e o atlas segue intacto).
        error.NotMonospace => {
            try std.testing.expect(atlas.glyphs.len == 2);
            return;
        },
        error.InvalidGlyph => return,
        error.InvalidMetrics => return,
    };
    // Monoespaçada: o avanço é o do primeiro glifo e casa com as métricas
    // do mesmo avanço.
    try std.testing.expectEqual(atlas.glyphs[0].metrics.advance, font.advance);
    try std.testing.expect(font.hasGlyph('A'));
}
