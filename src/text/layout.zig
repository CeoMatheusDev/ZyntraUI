//! ZyntraUI — layout de texto com fonte real ou fallback (text/layout).
//!
//! Escopo M132: uma única API de medição/desenho para texto, usada
//! tanto pelas métricas de fallback (monospace) quanto por um atlas de
//! glifos (fonte real). Medir e desenhar SEMPRE com a mesma fonte evita
//! o desvio clássico entre a largura medida e a desenhada.
//! - `Source.metrics`: métricas de fallback (`text/metrics`).
//! - `Source.atlas`: atlas de glifos (`text/atlas`) — os avanços e a
//!   altura de linha vêm dos glifos reais.
//!
//! Ownership: nada é copiado; o atlas é emprestado.
//! Validação: métricas/atlas válidos e texto UTF-8 bem formado.

const std = @import("std");
const types = @import("../core/types.zig");
const metrics_mod = @import("metrics.zig");
const atlas_mod = @import("atlas.zig");
const image_mod = @import("../draw/image.zig");
const commands = @import("../draw/commands.zig");

/// Erros do layout de texto.
pub const Error = error{
    /// Texto malformado (UTF-8 inválido).
    InvalidUtf8,
    /// Métricas de fonte inválidas.
    InvalidMetrics,
    /// Atlas vazio/inválido.
    InvalidGlyph,
    /// Largura máxima negativa ou não-finita.
    InvalidArgument,
    /// Falta de memória.
    OutOfMemory,
    /// Comando de desenho inválido.
    InvalidCommand,
};

/// Traduz os erros do atlas para os do layout.
fn mapAtlasErr(err: atlas_mod.Error) Error {
    return switch (err) {
        error.InvalidUtf8 => error.InvalidUtf8,
        error.InvalidMetrics => error.InvalidMetrics,
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidGlyph,
        error.DuplicateGlyph,
        error.AtlasFull,
        error.InvalidCommand,
        => error.InvalidGlyph,
    };
}

/// Fonte usada para medir e desenhar texto.
pub const Source = union(enum) {
    /// Métricas de fallback (avanço uniforme por glifo).
    metrics: metrics_mod.FontMetrics,
    /// Atlas de glifos (fonte real, largura proporcional).
    atlas: *const atlas_mod.FontAtlas,

    pub fn lineHeight(self: Source) f32 {
        return switch (self) {
            .metrics => |m| m.lineHeight(),
            .atlas => |a| if (a.glyphs.len == 0) 0 else @max(a.lineHeight(), 1),
        };
    }

    pub fn isValid(self: Source) bool {
        return switch (self) {
            .metrics => |m| m.isValid(),
            .atlas => |a| a.glyphs.len > 0,
        };
    }
};

/// Layout de texto: mede e desenha com a mesma fonte.
pub const Layout = struct {
    source: Source,

    pub fn init(source: Source) Error!Layout {
        if (!source.isValid()) return error.InvalidMetrics;
        return .{ .source = source };
    }

    /// Layout com as métricas de fallback.
    pub fn fromMetrics(font: metrics_mod.FontMetrics) Error!Layout {
        if (!font.isValid()) return error.InvalidMetrics;
        return .{ .source = .{ .metrics = font } };
    }

    /// Layout com um atlas de glifos.
    pub fn fromAtlas(atlas: *const atlas_mod.FontAtlas) Error!Layout {
        if (atlas.glyphs.len == 0) return error.InvalidGlyph;
        return .{ .source = .{ .atlas = atlas } };
    }

    pub fn lineHeight(self: Layout) f32 {
        return self.source.lineHeight();
    }

    /// Largura total do texto (soma dos avanços dos glifos conhecidos).
    pub fn advance(self: Layout, text: []const u8) Error!f32 {
        return switch (self.source) {
            .metrics => |m| (try metrics_mod.measure(text, m)).width,
            .atlas => |a| a.measure(text) catch |err| return mapAtlasErr(err),
        };
    }

    /// Medição completa (largura, altura, linhas e glifos).
    pub fn measure(self: Layout, text: []const u8) Error!metrics_mod.TextMetrics {
        return switch (self.source) {
            .metrics => |m| metrics_mod.measure(text, m) catch |err| return switch (err) {
                error.InvalidUtf8 => error.InvalidUtf8,
                error.InvalidMetrics => error.InvalidMetrics,
            },
            .atlas => |a| blk: {
                const width = a.measure(text) catch |err| return mapAtlasErr(err);
                var lines: u32 = 1;
                var glyphs: u32 = 0;
                var i: usize = 0;
                while (i < text.len) {
                    const d = metrics_mod.decodeOne(text[i..]) catch return error.InvalidUtf8;
                    if (d.codepoint == '\n') {
                        lines += 1;
                    } else {
                        glyphs += 1;
                    }
                    i += d.len;
                }
                break :blk .{
                    .width = width,
                    .height = @as(f32, @floatFromInt(lines)) * self.lineHeight(),
                    .lines = lines,
                    .glyphs = glyphs,
                };
            },
        };
    }

    /// Quantos bytes iniciais cabem em `max_width` (fronteira de
    /// codepoint). `'\n'` interrompe a medição.
    pub fn truncateToWidth(self: Layout, text: []const u8, max_width: f32) Error!usize {
        if (!std.math.isFinite(max_width) or max_width < 0) return error.InvalidArgument;
        return switch (self.source) {
            .metrics => |m| metrics_mod.truncateToWidth(text, m, max_width) catch |err| return switch (err) {
                error.InvalidUtf8 => error.InvalidUtf8,
                error.InvalidMetrics => error.InvalidMetrics,
                error.InvalidArgument => error.InvalidArgument,
            },
            .atlas => |a| blk: {
                var cur: f32 = 0;
                var i: usize = 0;
                while (i < text.len) {
                    const d = metrics_mod.decodeOne(text[i..]) catch return error.InvalidUtf8;
                    if (d.codepoint == '\n') break;
                    const adv = if (a.glyph(d.codepoint)) |g| g.metrics.advance else 0;
                    if (cur + adv > max_width) break;
                    cur += adv;
                    i += d.len;
                }
                break :blk i;
            },
        };
    }

    /// Desenha o texto com o canto superior-esquerdo em `pos` (mesma
    /// convenção dos widgets) e a cor `color`.
    ///
    /// Com o atlas, cada glifo vira um blit da sua região (o texto fica
    /// visível até no rasterizador de referência, que não desenha
    /// glifos); com o fallback, emite o comando `.text` de sempre.
    pub fn draw(
        self: Layout,
        dl: *commands.DrawList,
        gpa: std.mem.Allocator,
        text: []const u8,
        pos: types.Vec2,
        color: types.Color,
    ) Error!void {
        switch (self.source) {
            .metrics => |m| {
                dl.pushText(gpa, pos, color, m, text) catch |err| return switch (err) {
                    error.OutOfMemory => error.OutOfMemory,
                    error.InvalidCommand => error.InvalidCommand,
                    error.InvalidUtf8 => error.InvalidUtf8,
                    error.InvalidMetrics => error.InvalidMetrics,
                };
            },
            .atlas => |a| {
                // A linha de base fica na ascente do atlas: o topo do
                // glifo alinha com o topo de `pos`.
                const baseline = types.Vec2.init(pos.x, pos.y + a.ascent());
                atlas_mod.drawRun(dl, gpa, a, text, baseline, color) catch |err| return switch (err) {
                    error.OutOfMemory => error.OutOfMemory,
                    error.InvalidUtf8 => error.InvalidUtf8,
                    error.InvalidMetrics => error.InvalidMetrics,
                    error.InvalidGlyph => error.InvalidGlyph,
                    error.DuplicateGlyph => error.InvalidGlyph,
                    error.AtlasFull => error.InvalidGlyph,
                    error.InvalidCommand => error.InvalidCommand,
                };
            },
        }
    }
    /// Offset de byte do glifo cujo "anel" contém `x` (relativo à
    /// origem do texto). Multibyte-safe; `x <= 0` ⇒ 0; além do texto ⇒
    /// o fim. Metade do avanço do glifo decide a fronteira (mesma
    /// regra do fallback monospace).
    pub fn offsetAtX(self: Layout, text: []const u8, x: f32) usize {
        if (!std.math.isFinite(x) or x <= 0 or text.len == 0) return 0;
        var acc: f32 = 0;
        var i: usize = 0;
        while (i < text.len) {
            const d = metrics_mod.decodeOne(text[i..]) catch return i;
            const adv = self.advanceOf(d.codepoint);
            if (x < acc + adv / 2) return i;
            acc += adv;
            i += d.len;
        }
        return i;
    }

    /// Avanço de UM glifo (0 quando o glifo não existe no atlas).
    pub fn advanceOf(self: Layout, codepoint: u21) f32 {
        return switch (self.source) {
            .metrics => |m| m.advance,
            .atlas => |a| if (a.glyph(codepoint)) |g| g.metrics.advance else 0,
        };
    }

    /// Deslocamento horizontal para manter o caret visível (0 quando o
    /// texto cabe). Puro e derivado — mesma fórmula do desenho.
    pub fn visibleOffset(self: Layout, text: []const u8, len: usize, cursor: usize, vis_w: f32) f32 {
        if (vis_w <= 0 or len == 0) return 0;
        const full = self.advance(text[0..len]) catch return 0;
        if (full <= vis_w) return 0;
        const pre = self.advance(text[0..@min(cursor, len)]) catch return 0;
        return std.math.clamp(pre - vis_w, 0, full - vis_w);
    }
};

test "Layout com métricas de fallback mede como o text/metrics" {
    const stdt = @import("std");
    const m = metrics_mod.FontMetrics.withSize(10); // advance 6
    const l = try Layout.fromMetrics(m);
    try stdt.testing.expectEqual(@as(f32, 12), try l.advance("AB"));
    const tm = try l.measure("AB");
    try stdt.testing.expectEqual(@as(f32, 12), tm.width);
    try stdt.testing.expectEqual(@as(u32, 2), tm.glyphs);
    try stdt.testing.expectEqual(@as(usize, 1), try l.truncateToWidth("AB", 6));
    try stdt.testing.expectError(error.InvalidUtf8, l.measure("\xff"));
    try stdt.testing.expectError(error.InvalidMetrics, Layout.fromMetrics(.{ .size = 0 }));
}

test "Layout com atlas mede pelos avanços dos glifos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var b = atlas_mod.Builder.init(64, 64, 1);
    defer b.deinit(gpa);
    _ = try b.addGlyph(gpa, 'A', 4, 8, .{ .advance = 5, .bearing_y = -8, .height = 8 });
    _ = try b.addGlyph(gpa, 'B', 4, 8, .{ .advance = 3, .bearing_y = -8, .height = 8 });
    _ = try b.addGlyph(gpa, '\n', 1, 1, .{ .advance = 0, .bearing_y = 0, .height = 1 });

    var bytes: [64 * 64 * 4]u8 = undefined;
    for (&bytes, 0..) |*b2, i| b2.* = @truncate(i);
    const img = try image_mod.Image.init(64, 64, &bytes);
    var atlas = try b.finish(gpa, img);
    defer atlas.deinit(gpa);

    const l = try Layout.fromAtlas(&atlas);
    // Avanços reais: A=5, B=3 (o fallback monospace daria 6 por glifo).
    try stdt.testing.expectEqual(@as(f32, 8), try l.advance("AB"));
    const tm = try l.measure("AB");
    try stdt.testing.expectEqual(@as(f32, 8), tm.width);
    try stdt.testing.expectEqual(@as(u32, 2), tm.glyphs);
    try stdt.testing.expectEqual(@as(u32, 1), tm.lines);
    // Corte na largura: A(5) cabe, B(3) não (5+3 > 6).
    try stdt.testing.expectEqual(@as(usize, 1), try l.truncateToWidth("AB", 6));
    // Linhas: '\n' conta como linha.
    const multi = try l.measure("A\nB");
    try stdt.testing.expectEqual(@as(u32, 2), multi.lines);
    try stdt.testing.expectError(error.InvalidUtf8, l.measure("\xff"));
}

test "Layout.draw usa o atlas (blits) ou o fallback (comando de texto)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var dl = commands.DrawList.initEmpty();
    defer dl.deinit(gpa);

    // Fallback: um comando `.text`.
    const m = metrics_mod.FontMetrics.withSize(10);
    const l = try Layout.fromMetrics(m);
    try l.draw(&dl, gpa, "AB", types.Vec2.init(1, 2), types.Color.rgb(255, 255, 255));
    try stdt.testing.expectEqual(@as(usize, 1), dl.len());
    try stdt.testing.expect(dl.items()[0] == .text);

    // Atlas: um blit por glifo.
    var b = atlas_mod.Builder.init(64, 64, 1);
    defer b.deinit(gpa);
    _ = try b.addGlyph(gpa, 'A', 4, 8, .{ .advance = 5, .bearing_y = -8, .height = 8 });
    _ = try b.addGlyph(gpa, 'B', 4, 8, .{ .advance = 3, .bearing_y = -8, .height = 8 });
    var bytes: [64 * 64 * 4]u8 = undefined;
    for (&bytes, 0..) |*b2, i| b2.* = @truncate(i);
    const img = try image_mod.Image.init(64, 64, &bytes);
    var atlas = try b.finish(gpa, img);
    defer atlas.deinit(gpa);

    var dl2 = commands.DrawList.initEmpty();
    defer dl2.deinit(gpa);
    const l2 = try Layout.fromAtlas(&atlas);
    try l2.draw(&dl2, gpa, "AB", types.Vec2.init(0, 0), types.Color.rgb(255, 255, 255));
    // Um único comando de run com os dois glifos.
    try stdt.testing.expectEqual(@as(usize, 1), dl2.len());
    try stdt.testing.expect(dl2.items()[0] == .glyph_run);
    const refs = dl2.glyphsOf(dl2.items()[0]);
    try stdt.testing.expectEqual(@as(usize, 2), refs.len);
    // O segundo glifo avança pelo avanço real (5 px).
    try stdt.testing.expectEqual(@as(f32, 5), refs[1].dx);
}

test "fuzz layout: sem crash e coerente com o atlas" {
    try std.testing.fuzz({}, fuzzLayoutAtlas, .{});
}

fn fuzzLayoutAtlas(_: void, smith: *std.testing.Smith) !void {
    var bytes: [64]u8 = undefined;
    smith.bytes(&bytes);
    const gpa = std.testing.allocator;

    // Atlas com 2 glifos de avanço arbitrário (finito e > 0).
    const adv_a = @as(f32, @floatFromInt(bytes[0] % 16)) + 1.0;
    const adv_b = @as(f32, @floatFromInt(bytes[1] % 16)) + 1.0;
    var b = atlas_mod.Builder.init(32, 32, 1);
    defer b.deinit(gpa);
    _ = b.addGlyph(gpa, 'A', 4, 8, .{ .advance = adv_a, .bearing_y = -8, .height = 8 }) catch return;
    _ = b.addGlyph(gpa, 'B', 4, 8, .{ .advance = adv_b, .bearing_y = -8, .height = 8 }) catch return;
    var img_bytes: [32 * 32 * 4]u8 = undefined;
    for (&img_bytes, 0..) |*p, i| p.* = @truncate(i);
    const img = image_mod.Image.init(32, 32, &img_bytes) catch return;
    var atlas = b.finish(gpa, img) catch return;
    defer atlas.deinit(gpa);

    const l = Layout.fromAtlas(&atlas) catch return;
    // Texto ASCII aleatório (UTF-8 válido).
    var text: [32]u8 = undefined;
    const n = bytes[2] % 32;
    for (0..n) |i| text[i] = 'A' + (bytes[3 + i] % 2); // 'A' ou 'B'
    const slice = text[0..n];

    const w = l.advance(slice) catch |err| switch (err) {
        error.InvalidUtf8 => return,
        else => return err,
    };
    try std.testing.expect(w >= 0);
    const m = l.measure(slice) catch return;
    try std.testing.expect(m.width >= 0);
    try std.testing.expect(m.lines >= 1);
    // O corte respeita a largura e a fronteira de codepoint.
    const cut = l.truncateToWidth(slice, w) catch return;
    try std.testing.expect(cut <= slice.len);
    // O offset do clique é coerente com o texto.
    const off = l.offsetAtX(slice, w * 0.5);
    try std.testing.expect(off <= slice.len);
}
