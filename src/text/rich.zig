//! ZyntraUI — texto rico: trechos com estilos diferentes (text/rich).
//!
//! Escopo M165: o mesmo texto com MAIS DE UM estilo (cor, negrito,
//! itálico, tag) — o caso do rótulo com ênfase, do link embutido ou do
//! texto de erro.
//! - `Style`: o estilo de um trecho (cor + flags + tag).
//! - `Span`: uma faixa do texto com um estilo (bytes do texto original).
//! - `Run`: um trecho PRONTO para desenhar (faixa + posição + estilo).
//! - `layoutRuns`: quebra o texto (pela largura), aplica as spans e
//!   devolve os trechos com a posição de cada um.
//! - `drawRuns`: desenha os trechos (um comando por trecho).
//!
//! Sem alocação: os trechos vão para um buffer do CHAMADOR. As spans
//! são do app (o texto é do app).
//!
//! Regras determinísticas:
//! - As spans são aplicadas na ORDEM: uma span posterior sobrescreve a
//!   anterior nos bytes em comum.
//! - Os limites dos trechos ficam em fronteiras de codepoint (UTF-8).
//! - O texto é quebrado pela largura (as palavras não separtem; a
//!   quebra usa a mesma fonte da medição).

const std = @import("std");
const types = @import("../core/types.zig");
const layout_mod = @import("layout.zig");
const wrap_mod = @import("wrap.zig");

/// Erros do texto rico.
pub const Error = error{
    /// Texto malformado (UTF-8 inválido).
    InvalidUtf8,
    /// Métricas/atlas inválidos.
    InvalidMetrics,
    /// Argumento inválido (largura negativa, span fora do texto).
    InvalidArgument,
    /// O buffer de trechos do chamador não coube.
    NoSpaceLeft,
    /// Falta de memória.
    OutOfMemory,
    /// Comando de desenho inválido.
    InvalidCommand,
};

/// Estilo de um trecho de texto.
pub const Style = struct {
    /// Cor do texto.
    color: types.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    /// Negrito (o app decide: outra fonte, outra cor...).
    bold: bool = false,
    /// Itálico.
    italic: bool = false,
    /// Etiqueta do estilo — o app usa para escolher o atlas ou o efeito.
    tag: u32 = 0,
};

/// Uma faixa do texto com um estilo (bytes do texto original).
pub const Span = struct {
    /// Primeiro byte da faixa.
    start: u32 = 0,
    /// Comprimento da faixa em bytes.
    len: u32 = 0,
    /// Estilo da faixa.
    style: Style = .{},
};

/// Alinhamento horizontal das linhas (dentro da largura dada).
pub const Align = enum {
    /// Alinha à esquerda.
    start,
    /// Centraliza.
    center,
    /// Alinha à direita.
    end,
};

/// Um trecho pronto para desenhar.
pub const Run = struct {
    /// Primeiro byte do trecho no texto original.
    start: u32 = 0,
    /// Comprimento do trecho em bytes.
    len: u32 = 0,
    /// Posição (canto superior-esquerdo) do trecho.
    x: f32 = 0,
    /// Posição (canto superior-esquerdo) do trecho.
    y: f32 = 0,
    /// Estilo do trecho.
    style: Style = .{},
};

/// O estilo que cobre o byte `offset` (a ÚLTIMA span que cobre vence;
/// sem span ⇒ o estilo padrão).
pub fn styleAt(spans: []const Span, offset: u32) Style {
    var out = Style{};
    for (spans) |s| {
        if (offset < s.start or offset - s.start >= s.len) continue;
        out = s.style;
    }
    return out;
}

/// Move `offset` para o início do codepoint (para trás).
///
/// Um limite no meio de um codepoint UTF-8 é empurrado para o início
/// do caractere (os trechos nunca partem um glifo).
fn snapToCodepoint(text: []const u8, offset: u32) u32 {
    var o = @min(offset, @as(u32, @intCast(text.len)));
    while (o > 0 and o < text.len) {
        const b = text[o];
        // Byte de continuação UTF-8 (10xxxxxx): volta até o início.
        if ((b & 0xC0) != 0x80) break;
        o -= 1;
    }
    return o;
}

/// O fim do trecho que começa em `pos` (o próximo limite de span: o
/// início ou o fim de uma span), sempre numa fronteira de codepoint.
fn runEnd(text: []const u8, spans: []const Span, pos: u32, line_end: u32) u32 {
    var end = line_end;
    for (spans) |s| {
        if (s.start > pos and s.start < end) end = s.start;
        const s_end = s.start + s.len;
        if (s_end > pos and s_end < end) end = s_end;
    }
    end = snapToCodepoint(text, end);
    if (end <= pos) {
        // Limite dentro do mesmo glifo: avança um codepoint.
        const d: u32 = std.unicode.utf8ByteSequenceLength(text[pos]) catch {
            return @min(pos + 1, line_end);
        };
        end = @min(pos + d, line_end);
    }
    return end;
}

/// Calcula os trechos do texto rico.
///
/// `max_width` 0 = sem quebra (só as '\n' quebram); > 0 = quebra pela
/// largura (as palavras não separam). `origin` é o canto
/// superior-esquerdo do texto.
///
/// Devolve a quantidade de trechos escritos em `out` (o buffer é do
/// chamador; se não couber ⇒ `NoSpaceLeft`).
pub fn layoutRuns(
    layout: layout_mod.Layout,
    text: []const u8,
    spans: []const Span,
    max_width: f32,
    origin: types.Vec2,
    alignment: Align,
    out: []Run,
) Error!usize {
    if (!std.math.isFinite(max_width) or max_width < 0) return error.InvalidArgument;
    if (!std.math.isFinite(origin.x) or !std.math.isFinite(origin.y)) return error.InvalidArgument;
    for (spans) |s| {
        if (s.start > text.len or s.len > text.len - s.start) return error.InvalidArgument;
    }

    // 1) As linhas (a quebra usa a mesma fonte da medição).
    var line_buf: [256]wrap_mod.LineRange = undefined;
    const width = if (max_width > 0) max_width else @as(f32, @floatFromInt(text.len + 1)) * 1000.0;
    const n_lines = wrap_mod.wrapLinesLayout(text, &layout, width, line_buf[0..]) catch |err| return switch (err) {
        error.NoSpaceLeft => error.NoSpaceLeft,
        error.InvalidUtf8 => error.InvalidUtf8,
        error.InvalidMetrics => error.InvalidMetrics,
        error.InvalidGlyph => error.InvalidMetrics,
        error.InvalidArgument => error.InvalidArgument,
        error.InvalidCommand => error.InvalidCommand,
        error.OutOfMemory => error.OutOfMemory,
    };

    // 2) Cada linha vira trechos: as spans cortam a linha.
    var count: usize = 0;
    const line_h = layout.lineHeight();
    var li: usize = 0;
    while (li < n_lines) : (li += 1) {
        const line = line_buf[li];
        const y = origin.y + @as(f32, @floatFromInt(li)) * line_h;
        // O alinhamento depende da largura da LINHA (a soma dos
        // trechos): primeiro mede, depois posiciona.
        var line_w: f32 = 0;
        {
            var p = line.start;
            const line_end = line.start + line.len;
            while (p < line_end) {
                const e = runEnd(text, spans, p, line_end);
                line_w += layout.advance(text[p..e]) catch return error.InvalidMetrics;
                p = e;
            }
        }
        const offset: f32 = switch (alignment) {
            .start => 0,
            .center => if (max_width > 0) @max(0, (max_width - line_w) / 2) else 0,
            .end => if (max_width > 0) @max(0, max_width - line_w) else 0,
        };
        var x = origin.x + offset;
        var pos = line.start;
        const line_end = line.start + line.len;
        while (pos < line_end) {
            // O estilo do byte corrente.
            const style = styleAt(spans, pos);
            const end = runEnd(text, spans, pos, line_end);
            const slice = text[pos..end];
            const w = layout.advance(slice) catch return error.InvalidMetrics;
            if (count >= out.len) return error.NoSpaceLeft;
            out[count] = .{
                .start = pos,
                .len = end - pos,
                .x = x,
                .y = y,
                .style = style,
            };
            count += 1;
            x += w;
            pos = end;
        }
    }
    return count;
}

/// Desenha os trechos (um comando por trecho, na cor do seu estilo).
pub fn drawRuns(
    layout: layout_mod.Layout,
    dl: *@import("../draw/commands.zig").DrawList,
    gpa: std.mem.Allocator,
    text: []const u8,
    runs: []const Run,
) Error!void {
    // Valida todas as faixas antes de desenhar: runs também podem ser
    // construídos diretamente pelo chamador, sem passar pelo layout.
    for (runs) |r| {
        if (r.start > text.len or r.len > text.len - r.start) return error.InvalidArgument;
    }
    for (runs) |r| {
        const slice = text[r.start..][0..r.len];
        layout.draw(dl, gpa, slice, types.Vec2.init(r.x, r.y), r.style.color) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidCommand => error.InvalidCommand,
            error.InvalidUtf8 => error.InvalidUtf8,
            error.InvalidMetrics => error.InvalidMetrics,
            error.InvalidGlyph => error.InvalidMetrics,
            error.InvalidArgument => error.InvalidArgument,
        };
    }
}

// ---------------------------------------------------------------------------
// Testes
// ---------------------------------------------------------------------------

test "rich: um texto sem spans vira um trecho por linha" {
    const stdt = @import("std");
    const font = @import("metrics.zig").FontMetrics.withSize(10);
    const layout = try layout_mod.Layout.fromMetrics(font);
    var runs: [8]Run = undefined;
    const n = try layoutRuns(layout, "ab\ncd", &.{}, 0, types.Vec2.init(0, 0), .start, &runs);
    try stdt.testing.expectEqual(@as(usize, 2), n);
    try stdt.testing.expectEqual(@as(u32, 2), runs[0].len);
    // A segunda linha começa depois do '\n' (byte 3).
    try stdt.testing.expectEqual(@as(u32, 3), runs[1].start);
    try stdt.testing.expectEqual(@as(u32, 2), runs[1].len);
    // A segunda linha fica uma altura abaixo.
    try stdt.testing.expectApproxEqAbs(font.lineHeight(), runs[1].y, 0.001);
}

test "rich: a span divide o trecho e a cor segue o estilo" {
    const stdt = @import("std");
    const font = @import("metrics.zig").FontMetrics.withSize(10);
    const layout = try layout_mod.Layout.fromMetrics(font);
    const red = types.Color.rgb(255, 0, 0);
    const spans = [_]Span{.{ .start = 2, .len = 2, .style = .{ .color = red, .bold = true } }};
    var runs: [8]Run = undefined;
    const n = try layoutRuns(layout, "abcdef", &spans, 0, types.Vec2.init(0, 0), .start, &runs);
    // Três trechos: o de antes da span, o da span e o de depois (o
    // estilo volta ao padrão).
    try stdt.testing.expectEqual(@as(usize, 3), n);
    try stdt.testing.expectEqual(@as(u32, 0), runs[0].start);
    try stdt.testing.expectEqual(@as(u32, 2), runs[0].len);
    try stdt.testing.expectEqual(@as(u32, 2), runs[1].start);
    try stdt.testing.expectEqual(@as(u32, 2), runs[1].len);
    try stdt.testing.expectEqual(red, runs[1].style.color);
    try stdt.testing.expect(runs[1].style.bold);
    try stdt.testing.expectEqual(@as(u32, 4), runs[2].start);
    // O trecho estilizado fica depois do primeiro (avanço 6 por glifo).
    try stdt.testing.expectApproxEqAbs(@as(f32, 12), runs[1].x, 0.001);
}

test "rich: a span posterior sobrescreve a anterior" {
    const stdt = @import("std");
    const font = @import("metrics.zig").FontMetrics.withSize(10);
    const layout = try layout_mod.Layout.fromMetrics(font);
    const red = types.Color.rgb(255, 0, 0);
    const blue = types.Color.rgb(0, 0, 255);
    const spans = [_]Span{
        .{ .start = 0, .len = 6, .style = .{ .color = red } },
        .{ .start = 3, .len = 2, .style = .{ .color = blue } },
    };
    var runs: [8]Run = undefined;
    const n = try layoutRuns(layout, "abcdef", &spans, 0, types.Vec2.init(0, 0), .start, &runs);
    // Três trechos: [0,3) vermelho, [3,5) azul (a span posterior
    // vence), [5,6) vermelho de novo.
    try stdt.testing.expectEqual(@as(usize, 3), n);
    try stdt.testing.expectEqual(red, runs[0].style.color);
    try stdt.testing.expectEqual(@as(u32, 0), runs[0].start);
    try stdt.testing.expectEqual(@as(u32, 3), runs[0].len);
    try stdt.testing.expectEqual(blue, runs[1].style.color);
    try stdt.testing.expectEqual(@as(u32, 3), runs[1].start);
    try stdt.testing.expectEqual(@as(u32, 2), runs[1].len);
    try stdt.testing.expectEqual(red, runs[2].style.color);
    try stdt.testing.expectEqual(@as(u32, 5), runs[2].start);
    try stdt.testing.expectEqual(@as(u32, 1), runs[2].len);
}

test "rich: a quebra por largura respeita as spans" {
    const stdt = @import("std");
    const font = @import("metrics.zig").FontMetrics.withSize(10); // avanço 6
    const layout = try layout_mod.Layout.fromMetrics(font);
    const red = types.Color.rgb(255, 0, 0);
    const spans = [_]Span{.{ .start = 4, .len = 2, .style = .{ .color = red } }};
    var runs: [16]Run = undefined;
    // Largura 18 ⇒ "aaa bbb" não cabe (24) ⇒ 2 linhas.
    const n = try layoutRuns(layout, "aaa bbb", &spans, 18, types.Vec2.init(0, 0), .start, &runs);
    try stdt.testing.expect(n >= 2);
    // A span (bytes 4..6 = "bb") aparece em algum trecho.
    var found = false;
    for (runs[0..n]) |r| {
        if (r.style.color.r == 255 and r.style.color.g == 0) found = true;
    }
    try stdt.testing.expect(found);
}

test "rich: os limites ficam em fronteiras de codepoint" {
    const stdt = @import("std");
    const font = @import("metrics.zig").FontMetrics.withSize(10);
    const layout = try layout_mod.Layout.fromMetrics(font);
    // "aé" = 3 bytes (a=1, é=2). A span começa no meio do 'é'.
    const red = types.Color.rgb(255, 0, 0);
    const spans = [_]Span{.{ .start = 2, .len = 1, .style = .{ .color = red } }};
    var runs: [8]Run = undefined;
    const n = try layoutRuns(layout, "aé", &spans, 0, types.Vec2.init(0, 0), .start, &runs);
    try stdt.testing.expectEqual(@as(usize, 2), n);
    // O segundo trecho começa no início do 'é' (byte 1), não no meio.
    try stdt.testing.expectEqual(@as(u32, 1), runs[1].start);
    try stdt.testing.expectEqual(@as(u32, 2), runs[1].len);
}

test "rich: o alinhamento posiciona a linha" {
    const stdt = @import("std");
    const font = @import("metrics.zig").FontMetrics.withSize(10); // avanço 6
    const layout = try layout_mod.Layout.fromMetrics(font);
    var runs: [8]Run = undefined;
    // "ab" (12 px) numa caixa de 60: start x=0, center x=24, end x=48.
    const n = try layoutRuns(layout, "ab", &.{}, 60, types.Vec2.init(0, 0), .start, &runs);
    try stdt.testing.expectEqual(@as(usize, 1), n);
    try stdt.testing.expectApproxEqAbs(@as(f32, 0), runs[0].x, 0.001);
    const n2 = try layoutRuns(layout, "ab", &.{}, 60, types.Vec2.init(0, 0), .center, &runs);
    try stdt.testing.expectEqual(@as(usize, 1), n2);
    try stdt.testing.expectApproxEqAbs(@as(f32, 24), runs[0].x, 0.001);
    const n3 = try layoutRuns(layout, "ab", &.{}, 60, types.Vec2.init(0, 0), .end, &runs);
    try stdt.testing.expectEqual(@as(usize, 1), n3);
    try stdt.testing.expectApproxEqAbs(@as(f32, 48), runs[0].x, 0.001);
}

test "rich: erros" {
    const stdt = @import("std");
    const font = @import("metrics.zig").FontMetrics.withSize(10);
    const layout = try layout_mod.Layout.fromMetrics(font);
    var runs: [2]Run = undefined;
    try stdt.testing.expectError(Error.InvalidArgument, layoutRuns(layout, "abc", &.{}, -1, types.Vec2.init(0, 0), .start, &runs));
    const bad = [_]Span{.{ .start = 0, .len = 99 }};
    try stdt.testing.expectError(Error.InvalidArgument, layoutRuns(layout, "abc", &bad, 0, types.Vec2.init(0, 0), .start, &runs));
    // Buffer pequeno (duas linhas ⇒ dois trechos).
    try stdt.testing.expectError(Error.NoSpaceLeft, layoutRuns(layout, "ab\ncd", &.{}, 0, types.Vec2.init(0, 0), .start, runs[0..1]));
}

test "rich: desenhar um trecho por comando" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = @import("metrics.zig").FontMetrics.withSize(10);
    const layout = try layout_mod.Layout.fromMetrics(font);
    const red = types.Color.rgb(255, 0, 0);
    const spans = [_]Span{.{ .start = 2, .len = 2, .style = .{ .color = red } }};
    var runs: [8]Run = undefined;
    const n = try layoutRuns(layout, "abcdef", &spans, 0, types.Vec2.init(0, 0), .start, &runs);

    var dl = @import("../draw/commands.zig").DrawList.initEmpty();
    defer dl.deinit(gpa);
    try drawRuns(layout, &dl, gpa, "abcdef", runs[0..n]);
    // Um comando por trecho (o estilo volta ao padrão depois da span).
    try stdt.testing.expectEqual(@as(usize, 3), dl.len());
    try stdt.testing.expectEqualStrings("ab", dl.textOf(dl.items()[0]));
    try stdt.testing.expectEqualStrings("cd", dl.textOf(dl.items()[1]));
    try stdt.testing.expectEqual(red, dl.items()[1].text.color);
    try stdt.testing.expectEqualStrings("ef", dl.textOf(dl.items()[2]));
}

test "rich: spans com overflow são rejeitadas sem trap" {
    const layout = try layout_mod.Layout.fromMetrics(@import("metrics.zig").FontMetrics.withSize(10));
    var runs: [2]Run = undefined;
    const bad = [_]Span{.{ .start = 1, .len = std.math.maxInt(u32) }};
    try std.testing.expectError(error.InvalidArgument, layoutRuns(layout, "abc", &bad, 0, .{}, .start, &runs));
    const outside = [_]Span{.{ .start = std.math.maxInt(u32), .len = 2 }};
    try std.testing.expectError(error.InvalidArgument, layoutRuns(layout, "abc", &outside, 0, .{}, .start, &runs));
}

test "rich: styleAt compara faixas sem overflow" {
    const spans = [_]Span{.{ .start = 2, .len = std.math.maxInt(u32), .style = .{ .tag = 42 } }};
    try std.testing.expectEqual(@as(u32, 0), styleAt(&spans, 1).tag);
    try std.testing.expectEqual(@as(u32, 42), styleAt(&spans, 2).tag);
    try std.testing.expectEqual(@as(u32, 42), styleAt(&spans, std.math.maxInt(u32)).tag);
    try std.testing.expectEqual(@as(u32, 0), styleAt(&.{.{ .start = 2, .len = 0 }}, 2).tag);
}

test "rich: drawRuns rejeita faixas inválidas antes de emitir comandos" {
    const gpa = std.testing.allocator;
    const layout = try layout_mod.Layout.fromMetrics(@import("metrics.zig").FontMetrics.withSize(10));
    var dl = @import("../draw/commands.zig").DrawList.initEmpty();
    defer dl.deinit(gpa);
    const invalid = [_]Run{
        .{ .start = 0, .len = 1 },
        .{ .start = 1, .len = std.math.maxInt(u32) },
    };
    try std.testing.expectError(error.InvalidArgument, drawRuns(layout, &dl, gpa, "abc", &invalid));
    try std.testing.expectEqual(@as(usize, 0), dl.len());
    try std.testing.expectError(error.InvalidArgument, drawRuns(layout, &dl, gpa, "abc", &.{.{ .start = 4 }}));
    try drawRuns(layout, &dl, gpa, "abc", &.{.{ .start = 3, .len = 0 }});
}
