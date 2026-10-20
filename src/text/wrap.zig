//! ZyntraUI — quebra de linha para text-runs (text/wrap).
//!
//! Backends precisam fatiar textos multilinha para posicionar cada run;
//! este módulo faz o layout ganancioso (greedy word wrap) de forma pura:
//! - `wrapLines`: escreve faixas de byte em `out` (sem alocação).
//! - `countLines`: conta sem escrever (para dimensionar `out`).
//! Regras (documentadas, determinísticas):
//! - `'\n'` força quebra; parágrafo vazio gera linha vazia (len 0);
//!   `'\n'` final também gera linha vazia (split fiel).
//! - Palavras = runs de não-espaço (`' '`, `'\t'`, `'\r'` separam).
//! - A faixa vai do início da 1ª palavra ao fim da última (espaçamento
//!   interior preservado verbatim); laterais nunca entram.
//! - Para MEDIDA, espaços colapsam (1 espaço entre palavras).
//! - Palavra mais larga que `max_width` quebra no meio por codepoints
//!   (≥1 codepoint por linha garante progresso).
//! - UTF-8 malformado → `InvalidUtf8`; `max_width` <= 0 ou não-finito →
//!   `InvalidArgument`; `out` curto → `NoSpaceLeft` (parcial preenchido).
//! Offsets `u32` (mesma convenção de `DrawCommand.text`).

const std = @import("std");
const metrics = @import("metrics.zig");
const layout_mod = @import("layout.zig");
const atlas_mod = @import("atlas.zig");
const image_mod = @import("../draw/image.zig");

/// Faixa de bytes [start, start+len) dentro do texto original.
pub const LineRange = extern struct {
    start: u32 = 0,
    len: u32 = 0,
};

fn isSpace(cp: u21) bool {
    return cp == ' ' or cp == '\t' or cp == '\r';
}

/// Medidor das métricas de fallback (avanço uniforme).
const MetricsMeasurer = struct {
    m: metrics.FontMetrics,
    fn word(self: @This(), text: []const u8) !f32 {
        var n: u32 = 0;
        var i: usize = 0;
        while (i < text.len) {
            const d = try metrics.decodeOne(text[i..]);
            i += d.len;
            n += 1;
        }
        return @as(f32, @floatFromInt(n)) * self.m.advance;
    }
    fn space(self: @This()) f32 {
        return self.m.advance;
    }
    fn cp(self: @This(), codepoint: u21) f32 {
        _ = codepoint;
        return self.m.advance;
    }
};

/// Medidor de um atlas de glifos (larguras reais da fonte).
const LayoutMeasurer = struct {
    l: *const layout_mod.Layout,
    fn word(self: @This(), text: []const u8) !f32 {
        return self.l.advance(text);
    }
    fn space(self: @This()) f32 {
        return self.l.advanceOf(' ');
    }
    fn cp(self: @This(), codepoint: u21) f32 {
        return self.l.advanceOf(codepoint);
    }
};

/// Núcleo compartilhado: `out == null` só conta.
fn layoutGeneric(
    comptime M: type,
    text: []const u8,
    measurer: M,
    max_width: f32,
    out: ?[]LineRange,
) !usize {
    if (!std.math.isFinite(max_width) or max_width <= 0) return error.InvalidArgument;
    // Offsets u32 abaixo: texto além de 4 GiB não é endereçável aqui.
    if (text.len > std.math.maxInt(u32)) return error.OutOfMemory;
    if (text.len == 0) return 0;

    var nlines: usize = 0;
    const emit = struct {
        fn f(o: ?[]LineRange, idx: *usize, start: usize, len: usize) !void {
            if (o) |oo| {
                if (idx.* >= oo.len) return error.NoSpaceLeft;
                oo[idx.*] = .{ .start = @intCast(start), .len = @intCast(len) };
            }
            idx.* += 1;
        }
    }.f;

    var i: usize = 0;
    var line_start: ?usize = null; // byte offset da 1ª palavra da linha
    var line_end: usize = 0; // fim da última palavra (exclusivo)
    var line_w: f32 = 0; // largura medida (palavras + espaços simples)
    var spaced = false; // espaços pendentes desde a última palavra

    // Descarrega a linha atual (mesmo vazia: parágrafo vazio).
    const flush = struct {
        fn f(
            o: ?[]LineRange,
            nl: *usize,
            ls: *?usize,
            le: *usize,
            at: usize,
        ) !void {
            if (ls.*) |s| {
                try emit(o, nl, s, le.* - s);
            } else {
                try emit(o, nl, at, 0);
            }
            ls.* = null;
        }
    }.f;

    while (i < text.len) {
        const d = try metrics.decodeOne(text[i..]);
        const cp = d.codepoint;
        if (cp == '\n') {
            try flush(out, &nlines, &line_start, &line_end, i);
            line_w = 0;
            spaced = false;
            i += d.len;
            continue;
        }
        if (isSpace(cp)) {
            spaced = true;
            i += d.len;
            continue;
        }
        // Palavra: [i, wend).
        var wend = i;
        while (wend < text.len) {
            const dd = try metrics.decodeOne(text[wend..]);
            if (dd.codepoint == '\n' or isSpace(dd.codepoint)) break;
            wend += dd.len;
        }
        const ww = try M.word(measurer, text[i..wend]);
        if (line_start == null) {
            if (ww <= max_width) {
                line_start = i;
                line_end = wend;
                line_w = ww;
            } else {
                // Palavra longa com linha vazia: fatia por codepoints.
                var p = i;
                while (p < wend) {
                    var pw: f32 = 0;
                    var q = p;
                    while (q < wend) {
                        const dd = try metrics.decodeOne(text[q..]);
                        const w = M.cp(measurer, dd.codepoint);
                        if (pw > 0 and pw + w > max_width) break;
                        pw += w;
                        q += dd.len;
                    }
                    try emit(out, &nlines, p, q - p);
                    p = q;
                }
            }
            spaced = false;
            i = wend;
            continue;
        }
        // Linha com conteúdo.
        const need = (if (spaced) M.space(measurer) else 0) + ww;
        if (line_w + need <= max_width) {
            line_end = wend;
            line_w += need;
        } else {
            try flush(out, &nlines, &line_start, &line_end, i);
            line_w = 0;
            // Recoloca a palavra na linha nova (pode fatiar se longa).
            if (ww <= max_width) {
                line_start = i;
                line_end = wend;
                line_w = ww;
            } else {
                var p = i;
                while (p < wend) {
                    var pw: f32 = 0;
                    var q = p;
                    while (q < wend) {
                        const dd = try metrics.decodeOne(text[q..]);
                        const w = M.cp(measurer, dd.codepoint);
                        if (pw > 0 and pw + w > max_width) break;
                        pw += w;
                        q += dd.len;
                    }
                    try emit(out, &nlines, p, q - p);
                    p = q;
                }
            }
        }
        spaced = false;
        i = wend;
    }
    // Linha final (inclui vazia após '\n' final: split fiel).
    // Texto só-espaços sem '\n' não gera linha (sem palavras).
    if (line_start != null or (text.len > 0 and text[text.len - 1] == '\n')) {
        try flush(out, &nlines, &line_start, &line_end, text.len);
    }
    return nlines;
}

/// Núcleo com as métricas de fallback (comportamento histórico).
fn layout(text: []const u8, m: metrics.FontMetrics, max_width: f32, out: ?[]LineRange) !usize {
    if (!m.isValid()) return error.InvalidMetrics;
    return layoutGeneric(MetricsMeasurer, text, MetricsMeasurer{ .m = m }, max_width, out);
}

/// Escreve até `out.len` faixas; retorna a quantidade escrita.
pub fn wrapLines(text: []const u8, m: metrics.FontMetrics, max_width: f32, out: []LineRange) !usize {
    // Conta primeiro? Não — escreve direto; NoSpaceLeft se curto.
    // (Duas passagens seriam O(2n); uma passagem com erro é suficiente.)
    return layout(text, m, max_width, out);
}

/// Conta as linhas sem escrever.
pub fn countLines(text: []const u8, m: metrics.FontMetrics, max_width: f32) !usize {
    return layout(text, m, max_width, null);
}

/// Quebra de linha com fonte real (atlas de glifos): as larguras vêm
/// dos AVANÇOS dos glifos, então a quebra respeita a fonte
/// proporcional. Mesmas regras do `wrapLines` (palavras, espaços
/// colapsados na medida, palavra longa fatiada por codepoint).
pub fn wrapLinesLayout(
    text: []const u8,
    l: *const layout_mod.Layout,
    max_width: f32,
    out: []LineRange,
) !usize {
    return layoutGeneric(LayoutMeasurer, text, LayoutMeasurer{ .l = l }, max_width, out);
}

/// Conta as linhas de uma quebra com fonte real (sem escrever).
pub fn countLinesLayout(
    text: []const u8,
    l: *const layout_mod.Layout,
    max_width: f32,
) !usize {
    return layoutGeneric(LayoutMeasurer, text, LayoutMeasurer{ .l = l }, max_width, null);
}

test "wrap básico, newline e vazio" {
    const stdt = @import("std");
    const m = metrics.FontMetrics.withSize(10); // advance=6
    var out: [8]LineRange = undefined;

    // "aaa bbb" (18+6+18): 18+6+18=42 > 20 → quebra.
    const n = try wrapLines("aaa bbb", m, 20, &out);
    try stdt.testing.expectEqual(@as(usize, 2), n);
    try stdt.testing.expectEqualStrings("aaa", "aaa bbb"[out[0].start..][0..out[0].len]);
    try stdt.testing.expectEqualStrings("bbb", "aaa bbb"[out[1].start..][0..out[1].len]);

    // Cabe tudo: 1 linha.
    const n1 = try wrapLines("ab cd", m, 100, &out);
    try stdt.testing.expectEqual(@as(usize, 1), n1);
    try stdt.testing.expectEqualStrings("ab cd", "ab cd"[out[0].start..][0..out[0].len]);

    // '\n' força; parágrafo vazio gera linha vazia.
    const n2 = try wrapLines("a\n\nb", m, 100, &out);
    try stdt.testing.expectEqual(@as(usize, 3), n2);
    try stdt.testing.expectEqual(@as(u32, 0), out[1].len);

    // Vazio e só-espaços: zero linhas.
    try stdt.testing.expectEqual(@as(usize, 0), try wrapLines("", m, 100, &out));
    try stdt.testing.expectEqual(@as(usize, 0), try wrapLines("   ", m, 100, &out));

    // countLines concorda.
    try stdt.testing.expectEqual(n, try countLines("aaa bbb", m, 20));
    try stdt.testing.expectEqual(n2, try countLines("a\n\nb", m, 100));
}

test "wrap palavra longa, erros e out curto" {
    const stdt = @import("std");
    const m = metrics.FontMetrics.withSize(10); // advance=6
    var out: [8]LineRange = undefined;

    // "abcdef" (36px) em largura 20 → fatias "abc"(18) + "def".
    const t = "abcdef";
    const n = try wrapLines(t, m, 20, &out);
    try stdt.testing.expectEqual(@as(usize, 2), n);
    try stdt.testing.expectEqualStrings("abc", t[out[0].start..][0..out[0].len]);
    try stdt.testing.expectEqualStrings("def", t[out[1].start..][0..out[1].len]);

    // Multibyte não quebra no meio do codepoint: "A€B" (€=3B).
    const u = "A€B";
    const nu = try wrapLines(u, m, 12, &out);
    try stdt.testing.expectEqual(@as(usize, 2), nu);
    try stdt.testing.expectEqualStrings("A€", u[out[0].start..][0..out[0].len]);
    try stdt.testing.expectEqualStrings("B", u[out[1].start..][0..out[1].len]);

    // Erros.
    try stdt.testing.expectError(error.InvalidUtf8, wrapLines("\xff", m, 100, &out));
    try stdt.testing.expectError(error.InvalidArgument, wrapLines("a", m, 0, &out));
    try stdt.testing.expectError(error.InvalidArgument, wrapLines("a", m, -5, &out));
    var tiny: [1]LineRange = undefined;
    try stdt.testing.expectError(error.NoSpaceLeft, wrapLines("aaa bbb", m, 20, &tiny));
}

test "fuzz decodeOne: sem crash, faixas válidas, len coerente" {
    try std.testing.fuzz({}, fuzzDecode, .{});
}

fn fuzzDecode(_: void, smith: *std.testing.Smith) !void {
    var buf: [32]u8 = undefined;
    smith.bytes(&buf);
    const n: usize = smith.valueRangeAtMost(u8, 0, 32);
    const input = buf[0..n];
    if (input.len == 0) {
        try std.testing.expectError(error.InvalidUtf8, metrics.decodeOne(input));
        return;
    }
    if (metrics.decodeOne(input)) |d| {
        // Codepoint sempre representável e fora de surrogates.
        try std.testing.expect(d.codepoint <= 0x10FFFF);
        try std.testing.expect(d.codepoint < 0xD800 or d.codepoint > 0xDFFF);
        try std.testing.expect(d.len >= 1 and d.len <= 4);
        try std.testing.expect(d.len <= input.len);
        // Lead byte determina o comprimento (overlong/continuação caem aqui).
        const b0 = input[0];
        if (b0 < 0x80) {
            try std.testing.expectEqual(@as(u3, 1), d.len);
        } else if (b0 < 0xC2) {
            return error.TestUnexpectedResult; // deve ter falhado
        } else if (b0 < 0xE0) {
            try std.testing.expectEqual(@as(u3, 2), d.len);
        } else if (b0 < 0xF0) {
            try std.testing.expectEqual(@as(u3, 3), d.len);
        } else if (b0 < 0xF5) {
            try std.testing.expectEqual(@as(u3, 4), d.len);
        } else {
            return error.TestUnexpectedResult; // deve ter falhado
        }
    } else |err| {
        try std.testing.expectEqual(error.InvalidUtf8, err);
    }
}

test "fuzz wrap/measure: faixas contidas, contagens coerentes" {
    try std.testing.fuzz({}, fuzzWrap, .{});
}

fn fuzzWrap(_: void, smith: *std.testing.Smith) !void {
    var buf: [48]u8 = undefined;
    smith.bytes(&buf);
    const n: usize = smith.valueRangeAtMost(u8, 0, 48);
    const text = buf[0..n];
    const m = metrics.FontMetrics.withSize(10);
    const widths = [_]f32{ 1, 6, 12, 30, 1000 };
    const max_width = widths[smith.value(u8) % widths.len];

    var out: [32]LineRange = undefined;
    const counted = countLines(text, m, max_width) catch |err| {
        // Únicos erros possíveis aqui (métricas válidas, largura válida).
        try std.testing.expectEqual(error.InvalidUtf8, err);
        // wrapLines deve concordar no erro.
        var out2: [1]LineRange = undefined;
        try std.testing.expectError(error.InvalidUtf8, wrapLines(text, m, max_width, &out2));
        return;
    };
    // Texto válido: wrap escreve o mesmo tanto que conta (ou NoSpaceLeft).
    const written = wrapLines(text, m, max_width, &out) catch |err| {
        try std.testing.expectEqual(error.NoSpaceLeft, err);
        return; // parcial preenchido; nada mais a afirmar sem realloc
    };
    try std.testing.expectEqual(counted, written);
    for (out[0..written]) |r| {
        const start: usize = r.start;
        const end: usize = start + r.len;
        try std.testing.expect(end <= text.len);
        // Faixa sempre decodifica limpa (fronteira de codepoint).
        var p = start;
        while (p < end) {
            const d = try metrics.decodeOne(text[p..end]);
            p += d.len;
        }
        try std.testing.expectEqual(end, p);
    }
    // Medição coerente no mesmo texto.
    const tm = try metrics.measure(text, m);
    try std.testing.expect(tm.width <= @as(f32, @floatFromInt(tm.glyphs)) * m.advance + 0.001);
    try std.testing.expectEqual(@as(f32, @floatFromInt(tm.lines)) * m.lineHeight(), tm.height);
}

test "wrap com fonte real (atlas) respeita os avanços dos glifos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var b = atlas_mod.Builder.init(64, 64, 1);
    defer b.deinit(gpa);
    _ = try b.addGlyph(gpa, 'A', 4, 8, .{ .advance = 5, .bearing_y = -8, .height = 8 });
    _ = try b.addGlyph(gpa, 'B', 4, 8, .{ .advance = 3, .bearing_y = -8, .height = 8 });
    _ = try b.addGlyph(gpa, ' ', 1, 1, .{ .advance = 2 });
    var bytes: [64 * 64 * 4]u8 = undefined;
    for (&bytes, 0..) |*p, i| p.* = @truncate(i);
    const img = try image_mod.Image.init(64, 64, &bytes);
    var atlas = try b.finish(gpa, img);
    defer atlas.deinit(gpa);

    const l = try layout_mod.Layout.fromAtlas(&atlas);
    var out: [8]LineRange = undefined;

    // "AB" = 8 px, "AB" = 8 px, espaço = 2 px ⇒ largura 11 não comporta
    // as duas palavras na mesma linha.
    const n = try wrapLinesLayout("AB AB", &l, 11, &out);
    try stdt.testing.expectEqual(@as(usize, 2), n);
    try stdt.testing.expectEqual(@as(usize, 0), out[0].start);
    try stdt.testing.expectEqual(@as(usize, 2), out[0].len);
    try stdt.testing.expectEqual(@as(usize, 3), out[1].start);
    try stdt.testing.expectEqual(@as(usize, 2), out[1].len);

    // Largura 18 comporta as duas palavras.
    const n2 = try wrapLinesLayout("AB AB", &l, 18, &out);
    try stdt.testing.expectEqual(@as(usize, 1), n2);
    try stdt.testing.expectEqual(@as(usize, 5), out[0].len);

    // Contagem sem escrita bate com a escrita.
    try stdt.testing.expectEqual(@as(usize, 2), try countLinesLayout("AB AB", &l, 11));

    // Palavra maior que a linha é fatiada por codepoint.
    const n3 = try wrapLinesLayout("AB", &l, 4, &out);
    try stdt.testing.expectEqual(@as(usize, 2), n3);
    try stdt.testing.expectEqual(@as(usize, 1), out[0].len);
    try stdt.testing.expectEqual(@as(usize, 1), out[1].len);

    // Contratos.
    try stdt.testing.expectError(error.InvalidArgument, wrapLinesLayout("A", &l, 0, &out));
    try stdt.testing.expectError(error.InvalidUtf8, wrapLinesLayout("\xff", &l, 10, &out));
}
