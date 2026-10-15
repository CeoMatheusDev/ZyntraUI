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

/// Faixa de bytes [start, start+len) dentro do texto original.
pub const LineRange = extern struct {
    start: u32 = 0,
    len: u32 = 0,
};

fn isSpace(cp: u21) bool {
    return cp == ' ' or cp == '\t' or cp == '\r';
}

/// Núcleo compartilhado: `out == null` só conta.
fn layout(text: []const u8, m: metrics.FontMetrics, max_width: f32, out: ?[]LineRange) !usize {
    if (!m.isValid()) return error.InvalidMetrics;
    if (!std.math.isFinite(max_width) or max_width <= 0) return error.InvalidArgument;
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
        // Palavra: [i, wend), conta glifos.
        var wend = i;
        var glyphs: u32 = 0;
        while (wend < text.len) {
            const dd = try metrics.decodeOne(text[wend..]);
            if (dd.codepoint == '\n' or isSpace(dd.codepoint)) break;
            wend += dd.len;
            glyphs += 1;
        }
        const ww = @as(f32, @floatFromInt(glyphs)) * m.advance;
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
                        if (pw > 0 and pw + m.advance > max_width) break;
                        pw += m.advance;
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
        const need = (if (spaced) m.advance else 0) + ww;
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
                        if (pw > 0 and pw + m.advance > max_width) break;
                        pw += m.advance;
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
