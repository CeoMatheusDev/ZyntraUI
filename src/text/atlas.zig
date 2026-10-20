//! ZyntraUI — atlas de glifos (text/atlas).
//!
//! Escopo M124: modelo de atlas de fonte para a UI (sem rasterizar
//! fonte: o host rasteriza os glifos e o atlas guarda onde eles
//! ficaram).
//! - `Builder`: empacotamento "shelf" determinístico que diz onde cada
//!   bitmap de glifo cabe no atlas (região em pixels).
//! - `FontAtlas`: imagem emprestada + glifos ordenados por codepoint,
//!   com busca binária e métricas lógicas (avanço/bearing).
//! - `drawRun`: desenha um trecho de texto blitando cada glifo do
//!   atlas (reaproveita o comando de imagem).
//! Ownership: o atlas empresta a imagem (o chamador a rasteriza) e
//! possui a tabela de glifos. Nenhuma alocação por frame no desenho.
//! Validação: dimensões finitas e positivas, `advance >= 0`, sem
//! codepoints duplicados e capacidade do atlas respeitada.

const std = @import("std");
const types = @import("../core/types.zig");
const metrics_mod = @import("metrics.zig");
const image_mod = @import("../draw/image.zig");
const commands = @import("../draw/commands.zig");

/// Métricas de um glifo, em pixels LÓGICOS (independentes da escala do
/// atlas).
pub const GlyphMetrics = extern struct {
    /// Avanço horizontal do glifo.
    advance: f32 = 0,
    /// Deslocamento horizontal do bitmap em relação à origem do glifo.
    bearing_x: f32 = 0,
    /// Deslocamento vertical do bitmap em relação à linha de base
    /// (negativo = acima da base).
    bearing_y: f32 = 0,
    /// Largura/altura do bitmap em pixels lógicos (informativo).
    width: f32 = 0,
    height: f32 = 0,

    pub fn isValid(self: GlyphMetrics) bool {
        return std.math.isFinite(self.advance) and self.advance >= 0 and
            std.math.isFinite(self.bearing_x) and
            std.math.isFinite(self.bearing_y) and
            std.math.isFinite(self.width) and self.width >= 0 and
            std.math.isFinite(self.height) and self.height >= 0;
    }
};

/// Glifo posicionado no atlas.
pub const Glyph = struct {
    codepoint: u21 = 0,
    /// Região do bitmap dentro da imagem do atlas (pixels do atlas).
    region: image_mod.Region = .{},
    metrics: GlyphMetrics = .{},

    pub fn isValid(self: Glyph) bool {
        return self.metrics.isValid() and
            self.region.w > 0 and self.region.h > 0;
    }
};

/// Erros do empacotador/atlas.
pub const Error = error{
    /// O glifo não cabe no atlas (capacidade esgotada).
    AtlasFull,
    /// Métricas inválidas (advance/bearing não-finitos ou negativos).
    InvalidMetrics,
    /// Glifo com bitmap vazio ou atlas inconsistente.
    InvalidGlyph,
    /// Codepoint já presente no atlas.
    DuplicateGlyph,
    /// Texto malformado (UTF-8 inválido).
    InvalidUtf8,
    /// Falta de memória ao growar a tabela de glifos.
    OutOfMemory,
};

/// Empacotador de glifos ("shelf"): linhas horizontais empilhadas.
///
/// O builder não rasteriza nem aloca a imagem do atlas — ele só
/// reserva regiões. O host desenha cada bitmap na região devolvida.
pub const Builder = struct {
    /// Dimensões do atlas em pixels do atlas.
    width: u32 = 0,
    height: u32 = 0,
    /// Espaçamento (em pixels) entre glifos e entre prateleiras.
    padding: u32 = 1,
    /// Pixels do atlas por pixel lógico (1 = 1:1, 2 = retina).
    scale: f32 = 1.0,
    shelf_x: u32 = 0,
    shelf_y: u32 = 0,
    shelf_height: u32 = 0,
    entries: std.ArrayList(Glyph) = .empty,

    const Self = @This();

    pub fn init(width: u32, height: u32, padding: u32) Self {
        return .{ .width = width, .height = height, .padding = padding };
    }

    pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
        self.entries.deinit(gpa);
        self.entries = .empty;
    }

    /// Reserva espaço para um bitmap `w`×`h` (pixels do atlas) e devolve
    /// o glifo com a região reservada.
    pub fn addGlyph(
        self: *Self,
        gpa: std.mem.Allocator,
        codepoint: u21,
        w: u32,
        h: u32,
        metrics: GlyphMetrics,
    ) Error!Glyph {
        if (w == 0 or h == 0) return error.InvalidGlyph;
        if (!metrics.isValid()) return error.InvalidMetrics;
        for (self.entries.items) |e| {
            if (e.codepoint == codepoint) return error.DuplicateGlyph;
        }
        // A prateleira atual não comporta o glifo: abre a próxima.
        if (self.shelf_x > 0 and self.shelf_x + w + self.padding > self.width) {
            self.shelf_y += self.shelf_height + self.padding;
            self.shelf_x = 0;
            self.shelf_height = 0;
        }
        if (self.shelf_x + w > self.width) return error.AtlasFull;
        if (self.shelf_y + h > self.height) return error.AtlasFull;

        const glyph = Glyph{
            .codepoint = codepoint,
            .region = image_mod.Region.init(self.shelf_x, self.shelf_y, w, h),
            .metrics = metrics,
        };
        try self.entries.append(gpa, glyph);
        self.shelf_x += w + self.padding;
        self.shelf_height = @max(self.shelf_height, h);
        return glyph;
    }

    /// Altura ocupada pelo atlas até agora (pixels).
    pub fn usedHeight(self: *const Self) u32 {
        return self.shelf_y + self.shelf_height;
    }

    pub fn count(self: *const Self) usize {
        return self.entries.items.len;
    }

    /// Produz o atlas final: copia os glifos, ordena por codepoint e
    /// devolve a estrutura (a imagem é emprestada do chamador).
    pub fn finish(
        self: *Self,
        gpa: std.mem.Allocator,
        image: image_mod.Image,
    ) Error!FontAtlas {
        const n = self.entries.items.len;
        const glyphs = try gpa.alloc(Glyph, n);
        errdefer gpa.free(glyphs);
        @memcpy(glyphs, self.entries.items);
        std.mem.sort(Glyph, glyphs, {}, glyphLessThan);
        return .{
            .image = image,
            .glyphs = glyphs,
            .scale = self.scale,
        };
    }
};

fn glyphLessThan(_: void, a: Glyph, b: Glyph) bool {
    return a.codepoint < b.codepoint;
}

/// Atlas de fonte pronto para desenho.
pub const FontAtlas = struct {
    /// Imagem do atlas (emprestada pelo chamador).
    image: image_mod.Image = .{},
    /// Glifos ordenados por codepoint (possuídos).
    glyphs: []Glyph = &.{},
    /// Pixels do atlas por pixel lógico.
    scale: f32 = 1.0,

    pub fn deinit(self: *FontAtlas, gpa: std.mem.Allocator) void {
        gpa.free(self.glyphs);
        self.glyphs = &.{};
    }

    /// Busca binária pelo codepoint.
    pub fn glyph(self: *const FontAtlas, codepoint: u21) ?Glyph {
        var lo: usize = 0;
        var hi: usize = self.glyphs.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            const g = self.glyphs[mid];
            if (g.codepoint == codepoint) return g;
            if (g.codepoint < codepoint) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        return null;
    }

    /// Largura lógica do trecho (soma dos avanços dos glifos
    /// conhecidos; glifos ausentes não avançam).
    pub fn measure(self: *const FontAtlas, text: []const u8) Error!f32 {
        var width: f32 = 0;
        var i: usize = 0;
        while (i < text.len) {
            const d = metrics_mod.decodeOne(text[i..]) catch return error.InvalidUtf8;
            if (self.glyph(d.codepoint)) |g| width += g.metrics.advance;
            i += d.len;
        }
        return width;
    }

    /// Altura de linha do atlas: maior (ascente + descida) dos glifos.
    /// A ascente vem do `bearing_y` (negativo = acima da base) e a
    /// descida do que sobra abaixo da base.
    pub fn lineHeight(self: *const FontAtlas) f32 {
        var max_h: f32 = 0;
        for (self.glyphs) |g| {
            const ascent = @max(0, -g.metrics.bearing_y);
            const descent = @max(0, g.metrics.bearing_y + g.metrics.height);
            const h = ascent + descent;
            if (h > max_h) max_h = h;
        }
        return max_h;
    }
};

/// Desenha um trecho de texto usando o atlas: cada glifo vira um blit
/// da sua região na imagem do atlas. `baseline` é a origem da linha de
/// base. Glifos ausentes são ignorados.
pub fn drawRun(
    dl: *commands.DrawList,
    gpa: std.mem.Allocator,
    atlas: *const FontAtlas,
    text: []const u8,
    baseline: types.Vec2,
    tint: types.Color,
) Error!void {
    const scale = if (atlas.scale > 0) atlas.scale else 1.0;
    var pen: f32 = 0;
    var i: usize = 0;
    while (i < text.len) {
        const d = metrics_mod.decodeOne(text[i..]) catch return error.InvalidUtf8;
        if (atlas.glyph(d.codepoint)) |g| {
            const w = @as(f32, @floatFromInt(g.region.w)) / scale;
            const h = @as(f32, @floatFromInt(g.region.h)) / scale;
            const dest = types.Rect.init(
                baseline.x + pen + g.metrics.bearing_x,
                baseline.y + g.metrics.bearing_y,
                w,
                h,
            );
            dl.imageRegion(gpa, dest, atlas.image, g.region, tint) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidCommand => return error.InvalidGlyph,
            };
            pen += g.metrics.advance;
        }
        i += d.len;
    }
}

test "Builder empacota glifos em prateleiras" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var b = Builder.init(16, 16, 1);
    defer b.deinit(gpa);

    const a = try b.addGlyph(gpa, 'A', 4, 6, .{ .advance = 5, .bearing_x = 0, .bearing_y = -6, .width = 4, .height = 6 });
    const c = try b.addGlyph(gpa, 'B', 4, 6, .{ .advance = 5, .bearing_x = 0, .bearing_y = -6, .width = 4, .height = 6 });
    // 4+1+4+1 = 10 <= 16: mesma prateleira.
    try stdt.testing.expectEqual(image_mod.Region.init(0, 0, 4, 6), a.region);
    try stdt.testing.expectEqual(image_mod.Region.init(5, 0, 4, 6), c.region);
    try stdt.testing.expectEqual(@as(u32, 6), b.usedHeight());

    // Glifo largo não cabe na linha: abre a próxima prateleira.
    const d = try b.addGlyph(gpa, 'C', 10, 3, .{ .advance = 6 });
    try stdt.testing.expectEqual(image_mod.Region.init(0, 7, 10, 3), d.region);
    try stdt.testing.expectEqual(@as(u32, 10), b.usedHeight());
    try stdt.testing.expectEqual(@as(usize, 3), b.count());
}

test "Builder recusa overflow, duplicatas e métricas inválidas" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var b = Builder.init(8, 4, 1);
    defer b.deinit(gpa);

    try stdt.testing.expectError(error.InvalidGlyph, b.addGlyph(gpa, 'A', 0, 4, .{ .advance = 1 }));
    try stdt.testing.expectError(error.InvalidMetrics, b.addGlyph(gpa, 'A', 2, 2, .{ .advance = -1 }));
    try stdt.testing.expectError(error.InvalidMetrics, b.addGlyph(gpa, 'A', 2, 2, .{ .advance = std.math.nan(f32) }));
    // Mais largo que o atlas.
    try stdt.testing.expectError(error.AtlasFull, b.addGlyph(gpa, 'A', 9, 2, .{ .advance = 1 }));
    // Mais alto que o atlas.
    try stdt.testing.expectError(error.AtlasFull, b.addGlyph(gpa, 'A', 2, 5, .{ .advance = 1 }));
    try stdt.testing.expectEqual(@as(usize, 0), b.count());

    _ = try b.addGlyph(gpa, 'A', 2, 2, .{ .advance = 1 });
    try stdt.testing.expectError(error.DuplicateGlyph, b.addGlyph(gpa, 'A', 2, 2, .{ .advance = 1 }));
}

test "FontAtlas ordena, busca e mede" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var b = Builder.init(32, 32, 1);
    defer b.deinit(gpa);

    _ = try b.addGlyph(gpa, 'C', 4, 6, .{ .advance = 3, .bearing_y = -6, .height = 6 });
    _ = try b.addGlyph(gpa, 'A', 4, 6, .{ .advance = 2, .bearing_y = -6, .height = 6 });
    _ = try b.addGlyph(gpa, 'B', 4, 6, .{ .advance = 1, .bearing_y = -6, .height = 6 });

    var bytes: [16 * 16 * 4]u8 = undefined;
    for (&bytes, 0..) |*b2, i| b2.* = @truncate(i);
    const img = try image_mod.Image.init(16, 16, &bytes);

    var atlas = try b.finish(gpa, img);
    defer atlas.deinit(gpa);

    // Ordenado por codepoint.
    try stdt.testing.expectEqual(@as(u21, 'A'), atlas.glyphs[0].codepoint);
    try stdt.testing.expectEqual(@as(u21, 'B'), atlas.glyphs[1].codepoint);
    try stdt.testing.expectEqual(@as(u21, 'C'), atlas.glyphs[2].codepoint);

    try stdt.testing.expectEqual(@as(f32, 2), atlas.glyph('A').?.metrics.advance);
    try stdt.testing.expectEqual(@as(f32, 3), atlas.glyph('C').?.metrics.advance);
    try stdt.testing.expect(atlas.glyph('Z') == null);

    // Medição: soma dos avanços; glifo ausente não avança.
    try stdt.testing.expectEqual(@as(f32, 6), try atlas.measure("ABC"));
    try stdt.testing.expectEqual(@as(f32, 2), try atlas.measure("AZ"));
    try stdt.testing.expectEqual(@as(f32, 0), try atlas.measure(""));
    try stdt.testing.expectError(error.InvalidUtf8, atlas.measure("\xff"));
    try stdt.testing.expectEqual(@as(f32, 6), atlas.lineHeight());
}

test "drawRun blita cada glifo na posição do avanço" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var b = Builder.init(32, 32, 1);
    defer b.deinit(gpa);

    _ = try b.addGlyph(gpa, 'A', 2, 4, .{ .advance = 3, .bearing_y = -4, .height = 4 });
    _ = try b.addGlyph(gpa, 'B', 2, 4, .{ .advance = 5, .bearing_y = -4, .height = 4 });

    var bytes: [16 * 16 * 4]u8 = undefined;
    for (&bytes, 0..) |*b2, i| b2.* = @truncate(i);
    const img = try image_mod.Image.init(16, 16, &bytes);
    var atlas = try b.finish(gpa, img);
    defer atlas.deinit(gpa);

    var dl = commands.DrawList.initEmpty();
    defer dl.deinit(gpa);
    try drawRun(&dl, gpa, &atlas, "AB", types.Vec2.init(10, 20), types.Color.rgb(255, 255, 255));

    try stdt.testing.expectEqual(@as(usize, 2), dl.len());
    try stdt.testing.expectEqual(types.Rect.init(10, 16, 2, 4), dl.items()[0].image.rect);
    try stdt.testing.expectEqual(types.Rect.init(13, 16, 2, 4), dl.items()[1].image.rect);
    try stdt.testing.expectEqual(atlas.glyph('A').?.region, dl.items()[0].image.src);

    // Texto inválido não enfileira nada.
    try stdt.testing.expectError(error.InvalidUtf8, drawRun(
        &dl,
        gpa,
        &atlas,
        "\xff",
        types.Vec2.init(0, 0),
        types.Color.rgb(255, 255, 255),
    ));
    try stdt.testing.expectEqual(@as(usize, 2), dl.len());
}

test "drawRun respeita a escala do atlas" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var b = Builder.init(32, 32, 1);
    b.scale = 2.0;
    defer b.deinit(gpa);

    _ = try b.addGlyph(gpa, 'A', 4, 8, .{ .advance = 3, .bearing_y = -4, .height = 4 });

    var bytes: [16 * 16 * 4]u8 = undefined;
    for (&bytes, 0..) |*b2, i| b2.* = @truncate(i);
    const img = try image_mod.Image.init(16, 16, &bytes);
    var atlas = try b.finish(gpa, img);
    defer atlas.deinit(gpa);

    var dl = commands.DrawList.initEmpty();
    defer dl.deinit(gpa);
    try drawRun(&dl, gpa, &atlas, "A", types.Vec2.init(0, 0), types.Color.rgb(255, 255, 255));
    // 4x8 pixels do atlas a 2x => 2x4 pixels lógicos.
    try stdt.testing.expectEqual(types.Rect.init(0, -4, 2, 4), dl.items()[0].image.rect);
}
