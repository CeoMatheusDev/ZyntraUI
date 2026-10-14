//! ZyntraUI — métricas de texto (text/metrics).
//!
//! Escopo M4: medição determinística sem backend de rasterização.
//! - Decodificador UTF-8 próprio (RFC 3629) para não depender de APIs
//!   do std cuja estabilidade não é garantida aqui.
//! - `FontMetrics` descreve uma fonte monospace-fallback; backends
//!   reais substituem `advance` por shaping próprio (M5+).
//! - Tudo por valor, sem alocação. Textos inválidos retornam erro,
//!   nunca substituem silenciosamente.
//! Segurança: rejeita overlong, surrogates, > U+10FFFF e truncamentos.

const std = @import("std");

/// Métricas de fonte (pixels lógicos).
pub const FontMetrics = extern struct {
    /// Tamanho nominal (altura EM). Deve ser finito e > 0.
    size: f32 = 16,
    ascent: f32 = 13,
    descent: f32 = 4,
    line_gap: f32 = 0,
    /// Avanço horizontal médio por glifo (fallback monospace).
    advance: f32 = 9.6,

    pub fn withSize(size: f32) FontMetrics {
        return .{
            .size = size,
            .ascent = size * 0.8125,
            .descent = size * 0.25,
            .line_gap = 0,
            .advance = size * 0.6,
        };
    }

    pub fn isValid(self: FontMetrics) bool {
        return std.math.isFinite(self.size) and self.size > 0 and
            std.math.isFinite(self.ascent) and self.ascent >= 0 and
            std.math.isFinite(self.descent) and self.descent >= 0 and
            std.math.isFinite(self.line_gap) and self.line_gap >= 0 and
            std.math.isFinite(self.advance) and self.advance > 0;
    }

    pub fn lineHeight(self: FontMetrics) f32 {
        return self.ascent + self.descent + self.line_gap;
    }
};

/// Resultado de medição.
pub const TextMetrics = extern struct {
    width: f32 = 0,
    height: f32 = 0,
    lines: u32 = 1,
    /// Glifos contados (exclui '\n').
    glyphs: u32 = 0,
};

/// Decodifica um codepoint em `s[0..]`. Retorna codepoint + bytes.
/// Erros: `InvalidUtf8` em sequência malformada, overlong, surrogate,
/// truncada ou > U+10FFFF. Nunca lê além de `s.len`.
pub fn decodeOne(s: []const u8) !struct { codepoint: u21, len: u3 } {
    if (s.len == 0) return error.InvalidUtf8;
    const b0 = s[0];
    if (b0 < 0x80) return .{ .codepoint = b0, .len = 1 };
    if (b0 < 0xC2) return error.InvalidUtf8; // continuação isolada ou overlong C0/C1
    if (b0 < 0xE0) {
        if (s.len < 2) return error.InvalidUtf8;
        const b1 = s[1];
        if (b1 < 0x80 or b1 > 0xBF) return error.InvalidUtf8;
        const cp: u21 = (@as(u21, b0 & 0x1F) << 6) | (b1 & 0x3F);
        return .{ .codepoint = cp, .len = 2 };
    }
    if (b0 < 0xF0) {
        if (s.len < 3) return error.InvalidUtf8;
        const b1 = s[1];
        const b2 = s[2];
        if (b0 == 0xE0 and (b1 < 0xA0 or b1 > 0xBF)) return error.InvalidUtf8;
        if (b0 == 0xED and (b1 < 0x80 or b1 > 0x9F)) return error.InvalidUtf8; // surrogates
        if (b1 < 0x80 or b1 > 0xBF) return error.InvalidUtf8;
        if (b2 < 0x80 or b2 > 0xBF) return error.InvalidUtf8;
        const cp: u21 = (@as(u21, b0 & 0x0F) << 12) | (@as(u21, b1 & 0x3F) << 6) | (b2 & 0x3F);
        if (cp >= 0xD800 and cp <= 0xDFFF) return error.InvalidUtf8;
        return .{ .codepoint = cp, .len = 3 };
    }
    if (b0 < 0xF5) {
        if (s.len < 4) return error.InvalidUtf8;
        const b1 = s[1];
        const b2 = s[2];
        const b3 = s[3];
        if (b0 == 0xF0 and (b1 < 0x90 or b1 > 0xBF)) return error.InvalidUtf8;
        if (b0 == 0xF4 and (b1 < 0x80 or b1 > 0x8F)) return error.InvalidUtf8;
        if (b1 < 0x80 or b1 > 0xBF) return error.InvalidUtf8;
        if (b2 < 0x80 or b2 > 0xBF) return error.InvalidUtf8;
        if (b3 < 0x80 or b3 > 0xBF) return error.InvalidUtf8;
        const cp32: u32 = (@as(u32, b0 & 0x07) << 18) | (@as(u32, b1 & 0x3F) << 12) |
            (@as(u32, b2 & 0x3F) << 6) | (b3 & 0x3F);
        if (cp32 > 0x10FFFF) return error.InvalidUtf8;
        return .{ .codepoint = @intCast(cp32), .len = 4 };
    }
    return error.InvalidUtf8;
}

/// Mede `text` com avanço fixo. `'\n'` quebra linha (largura por linha
/// = glyphs_na_linha * advance). Retorna `InvalidUtf8` se malformado.
pub fn measure(text: []const u8, metrics: FontMetrics) !TextMetrics {
    if (!metrics.isValid()) return error.InvalidMetrics;
    var width: f32 = 0;
    var cur: f32 = 0;
    var lines: u32 = 1;
    var glyphs: u32 = 0;
    var i: usize = 0;
    // Texto vazio: 1 linha vazia com altura de linha.
    if (text.len == 0) {
        return .{ .width = 0, .height = metrics.lineHeight(), .lines = 1, .glyphs = 0 };
    }
    while (i < text.len) {
        const d = try decodeOne(text[i..]);
        if (d.codepoint == '\n') {
            width = @max(width, cur);
            cur = 0;
            lines += 1;
        } else {
            cur += metrics.advance;
            glyphs += 1;
        }
        i += d.len;
    }
    width = @max(width, cur);
    return .{
        .width = width,
        .height = @as(f32, @floatFromInt(lines)) * metrics.lineHeight(),
        .lines = lines,
        .glyphs = glyphs,
    };
}

/// Retorna o índice de byte (fronteira UTF-8) até onde o texto cabe em
/// `max_width`, sem contar quebras de linha como largura. `'\n'`
/// interrompe a medição (retorna offset até ele). `max_width < 0` é
/// `InvalidArgument`.
pub fn truncateToWidth(text: []const u8, metrics: FontMetrics, max_width: f32) !usize {
    if (!metrics.isValid()) return error.InvalidMetrics;
    if (!std.math.isFinite(max_width)) return error.InvalidArgument;
    if (max_width < 0) return error.InvalidArgument;
    var cur: f32 = 0;
    var i: usize = 0;
    while (i < text.len) {
        const d = try decodeOne(text[i..]);
        if (d.codepoint == '\n') break;
        if (cur + metrics.advance > max_width) break;
        cur += metrics.advance;
        i += d.len;
    }
    return i;
}

test "decodeOne ASCII + multibyte + rejeições" {
    const stdt = @import("std");
    try stdt.testing.expectEqual(@as(u21, 'A'), (try decodeOne("A")).codepoint);
    // 'é' U+00E9 = 0xC3 0xA9
    const e = try decodeOne("\xc3\xa9");
    try stdt.testing.expectEqual(@as(u21, 0xE9), e.codepoint);
    try stdt.testing.expectEqual(@as(u3, 2), e.len);
    // '€' U+20AC = 0xE2 0x82 0xAC
    const euro = try decodeOne("\xe2\x82\xacrest");
    try stdt.testing.expectEqual(@as(u21, 0x20AC), euro.codepoint);
    try stdt.testing.expectEqual(@as(u3, 3), euro.len);
    // overlong '/', surrogate, truncado, >10FFFF
    try stdt.testing.expectError(error.InvalidUtf8, decodeOne("\xc0\xaf"));
    try stdt.testing.expectError(error.InvalidUtf8, decodeOne("\xed\xa0\x80"));
    try stdt.testing.expectError(error.InvalidUtf8, decodeOne("\xe2\x82"));
    try stdt.testing.expectError(error.InvalidUtf8, decodeOne("\xf4\x90\x80\x80"));
    try stdt.testing.expectError(error.InvalidUtf8, decodeOne(""));
}

test "measure linhas e larguras" {
    const stdt = @import("std");
    const m = FontMetrics.withSize(10); // advance=6
    const a = try measure("AB", m);
    try stdt.testing.expectEqual(@as(f32, 12), a.width);
    try stdt.testing.expectEqual(@as(u32, 2), a.glyphs);
    try stdt.testing.expectEqual(@as(u32, 1), a.lines);
    const multi = try measure("A\nBCD", m);
    try stdt.testing.expectEqual(@as(f32, 18), multi.width);
    try stdt.testing.expectEqual(@as(u32, 2), multi.lines);
    try stdt.testing.expectEqual(@as(u32, 4), multi.glyphs);
    const empty = try measure("", m);
    try stdt.testing.expectEqual(@as(f32, 0), empty.width);
    try stdt.testing.expectError(error.InvalidUtf8, measure("\xff", m));
}

test "truncateToWidth respeita fronteira UTF-8" {
    const stdt = @import("std");
    const m = FontMetrics.withSize(10); // advance=6
    try stdt.testing.expectEqual(@as(usize, 1), try truncateToWidth("AB", m, 6));
    try stdt.testing.expectEqual(@as(usize, 2), try truncateToWidth("AB", m, 12));
    // "A€" = 1 + 3 bytes; larguras 6 e 12
    try stdt.testing.expectEqual(@as(usize, 1), try truncateToWidth("A\xe2\x82\xac", m, 6));
    try stdt.testing.expectEqual(@as(usize, 4), try truncateToWidth("A\xe2\x82\xac", m, 12));
    try stdt.testing.expectError(error.InvalidArgument, truncateToWidth("A", m, -1));
}
