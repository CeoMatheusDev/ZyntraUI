//! ZyntraUI — área de texto multilinha (widgets/textarea).
//!
//! Modelo M65 (baseline, aditivo): complementa `text_input` (uma linha)
//! com edição em **múltiplas linhas** separadas por `'\n'`.
//! - Memória no CHAMADOR (zero alocação na lib): `buffer`/`len` (bytes),
//!   `cursor`/`anchor` (offsets de byte, sempre fronteira UTF-8) e
//!   `scroll_y` (px, clampado). Seleção = `[min(cursor,anchor), max)`.
//! - Foco: click dentro foca; `Escape`/`clearFocus` liberam; `Tab`
//!   circula o foco (Shift volta).
//! - Edição: texto (inclui `\n`), `Enter` insere quebra de linha,
//!   `Backspace`/`Delete` apagam por codepoint ou a seleção.
//! - Navegação: ←/→ (codepoint), ↑/↓ (linha, mesma coluna), `Home`/`End`
//!   (linha; com Ctrl = início/fim do texto), `PageUp`/`PageDown`.
//!   `Shift`+navegação estende a seleção; `Ctrl+A` seleciona tudo.
//! - Undo/redo e área de transferência (M88, aditivo): `Ctrl+Z`/`Ctrl+Y`
//!   (ou `Ctrl+Shift+Z`) desfazem/refazem rajadas de digitação e
//!   operações isoladas; `Ctrl+C/X/V` copiam/recortam/colam texto
//!   multilinha (`\n` inclusive). Só nas variantes `textAreaHistory` e
//!   `textAreaClipboard` (histórico e `Clipboard` em buffers do
//!   CHAMADOR, zero alocação; tipos em `text/edit.zig`).
//! - Rolagem: vertical em `scroll_y` (chamador), acompanhando o caret;
//!   horizontal automática e derivada (sem estado) para manter o caret
//!   visível na linha corrente.
//! - Desenho: caixa (`TextInputStyle`) + seleção por linha + textos +
//!   caret, com clip pareado na área útil.
//! Escopo v1: **sem quebra suave** (linhas longas sofrem rolagem
//! horizontal derivada, não wrap). Reusa `TextInputStyle` (mesma
//! linguagem visual de `text_input`) — sem alterar `text_input.zig`.
//! `id` não-nulo obrigatório.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const metrics_mod = @import("../text/metrics.zig");
const edit = @import("../text/edit.zig");
const input = @import("input.zig");

/// Área de transferência INTERNA e histórico de undo/redo (definidos em
/// `text/edit.zig`): re-exportados para o chamador não precisar importar
/// `widgets/text_input`. O `Clipboard` é o MESMO tipo das duas famílias,
/// então um único buffer serve `text_input` e `textarea`.
pub const Clipboard = edit.Clipboard;
pub const TextHistory = edit.TextHistory;

/// Padding interno (px) da área útil (mesmo valor de `text_input`).
const pad: f32 = 4.0;

pub const TextAreaResult = struct {
    focused: bool = false,
    changed: bool = false,
    overflowed: bool = false,
    selected: bool = false,
    /// Undo (`Ctrl+Z`) / redo (`Ctrl+Y` ou `Ctrl+Shift+Z`) aplicados
    /// nesta chamada (só nas variantes com histórico).
    undone: bool = false,
    redone: bool = false,
    len: usize = 0,
};

/// Número de linhas lógicas (separadas por `'\n'`); buffer vazio = 1.
pub fn textAreaLineCount(buf: []const u8, len: usize) usize {
    var n: usize = 1;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        if (buf[i] == '\n') n += 1;
    }
    return n;
}

/// Altura total do conteúdo (px) para `len` bytes.
pub fn textAreaContentHeight(buf: []const u8, len: usize, font: metrics_mod.FontMetrics) f32 {
    return @as(f32, @floatFromInt(textAreaLineCount(buf, len))) * font.lineHeight();
}

/// Offset máximo de rolagem vertical (0 quando o conteúdo cabe).
pub fn textAreaMaxScroll(buf: []const u8, len: usize, view_h: f32, font: metrics_mod.FontMetrics) f32 {
    return @max(0, textAreaContentHeight(buf, len, font) - view_h);
}

// ---- Helpers puros (internos) -------------------------------------------

fn lineStart(buf: []const u8, len: usize, line: usize) usize {
    if (line == 0) return 0;
    var count: usize = 0;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        if (buf[i] == '\n') {
            count += 1;
            if (count == line) return i + 1;
        }
    }
    return len;
}

fn lineEnd(buf: []const u8, len: usize, line: usize) usize {
    var l: usize = 0;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        if (buf[i] == '\n') {
            if (l == line) return i;
            l += 1;
        }
    }
    return len;
}

fn lineOfOffset(buf: []const u8, offset: usize) usize {
    var line: usize = 0;
    var i: usize = 0;
    while (i < offset) : (i += 1) {
        if (buf[i] == '\n') line += 1;
    }
    return line;
}

fn offsetForLineCol(buf: []const u8, len: usize, line: usize, col: usize) usize {
    const ls = lineStart(buf, len, line);
    const le = lineEnd(buf, len, line);
    return ls + @min(col, le - ls);
}

fn prevCodepoint(buf: []const u8, pos: usize) usize {
    var i = pos;
    if (i == 0) return 0;
    i -= 1;
    while (i > 0 and buf[i] & 0xC0 == 0x80) : (i -= 1) {}
    return i;
}

fn nextCodepoint(buf: []const u8, len: usize, pos: usize) usize {
    if (pos >= len) return pos;
    const d = metrics_mod.decodeOne(buf[pos..len]) catch return len;
    return pos + d.len;
}

fn encodeUtf8(codepoint: u32, out: *[4]u8) !u3 {
    if (codepoint > 0x10FFFF) return error.InvalidUtf8;
    if (codepoint >= 0xD800 and codepoint <= 0xDFFF) return error.InvalidUtf8;
    if (codepoint < 0x80) {
        out[0] = @intCast(codepoint);
        return 1;
    } else if (codepoint < 0x800) {
        out[0] = @intCast(0xC0 | (codepoint >> 6));
        out[1] = @intCast(0x80 | (codepoint & 0x3F));
        return 2;
    } else if (codepoint < 0x10000) {
        out[0] = @intCast(0xE0 | (codepoint >> 12));
        out[1] = @intCast(0x80 | ((codepoint >> 6) & 0x3F));
        out[2] = @intCast(0x80 | (codepoint & 0x3F));
        return 3;
    } else {
        out[0] = @intCast(0xF0 | (codepoint >> 18));
        out[1] = @intCast(0x80 | ((codepoint >> 12) & 0x3F));
        out[2] = @intCast(0x80 | ((codepoint >> 6) & 0x3F));
        out[3] = @intCast(0x80 | (codepoint & 0x3F));
        return 4;
    }
}

/// Remove `[a,b)` deslocando o sufixo para a esquerda.
fn deleteRange(buf: []u8, len: *usize, a: usize, b: usize) void {
    std.mem.copyForwards(u8, buf[a .. len.* - (b - a)], buf[b..len.*]);
    len.* -= b - a;
}

/// Insere `bytes` em `at`; falso (sem alterar) se não couber.
fn insertBytes(buf: []u8, len: *usize, at: usize, bytes: []const u8) bool {
    if (len.* + bytes.len > buf.len) return false;
    std.mem.copyBackwards(u8, buf[at + bytes.len .. len.* + bytes.len], buf[at..len.*]);
    @memcpy(buf[at..][0..bytes.len], bytes);
    len.* += bytes.len;
    return true;
}

/// Linha sob `y` (clampada a `[0, nlines)`); `rel <= 0` → primeira.
/// Nunca converte `f32 → usize` fora da faixa: `y` finito extremo
/// (ex.: arrasto longe da área) satura na última linha em vez de
/// estourar `@intFromFloat`.
fn lineAtY(y: f32, top: f32, line_h: f32, nlines: usize) usize {
    if (line_h <= 0 or nlines == 0) return 0;
    const rel = y - top;
    if (!std.math.isFinite(rel) or rel <= 0) return 0;
    const f = @floor(rel / line_h);
    if (f >= @as(f32, @floatFromInt(nlines))) return nlines - 1;
    const idx: usize = @intFromFloat(f);
    return @min(idx, nlines - 1);
}

/// Offset de byte na linha cujo glifo contém `x` (relativo à origem do
/// texto da linha). Negativo/0 → 0; além do fim → fim.
fn colAtX(font: metrics_mod.FontMetrics, line_text: []const u8, x: f32) usize {
    if (!std.math.isFinite(x) or x <= 0 or line_text.len == 0) return 0;
    var acc: f32 = 0;
    var i: usize = 0;
    while (i < line_text.len) {
        if (x < acc + font.advance / 2) return i;
        const d = metrics_mod.decodeOne(line_text[i..]) catch return i;
        acc += font.advance;
        i += d.len;
    }
    return i;
}

/// Área de texto multilinha (M65): seleção e navegação, sem histórico.
pub fn textArea(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    buffer: []u8,
    len: *usize,
    cursor: *usize,
    anchor: *usize,
    scroll_y: *f32,
    font: metrics_mod.FontMetrics,
    style: style_mod.TextInputStyle,
) context_mod.ContextError!TextAreaResult {
    return textAreaInner(ctx, id, bounds, buffer, len, cursor, anchor, scroll_y, font, style, void, {}, null);
}

/// Área de texto com undo/redo (M88, aditivo): `Ctrl+Z` desfaz, `Ctrl+Y`
/// ou `Ctrl+Shift+Z` refazem; rajadas de digitação agrupam em um passo.
/// `hist` é `*TextHistory(S, B)` do chamador com `B` cobrindo
/// `buffer.len` (senão `InvalidArgument`).
pub fn textAreaHistory(
    comptime S: usize,
    comptime B: usize,
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    buffer: []u8,
    len: *usize,
    cursor: *usize,
    anchor: *usize,
    scroll_y: *f32,
    hist: *TextHistory(S, B),
    font: metrics_mod.FontMetrics,
    style: style_mod.TextInputStyle,
) context_mod.ContextError!TextAreaResult {
    if (buffer.len > B) return error.InvalidArgument;
    if (anchor.* > len.*) return error.InvalidArgument;
    return textAreaInner(ctx, id, bounds, buffer, len, cursor, anchor, scroll_y, font, style, *TextHistory(S, B), hist, null);
}

/// Área de texto completa (M88, aditivo): undo/redo + área de
/// transferência interna (`Ctrl+C/X/V`, tudo-ou-nada, sem OS). `clip` é
/// `*Clipboard` do chamador (pode ser menor que o texto; copiar/colar
/// além da capacidade são ignorados com `overflowed`).
pub fn textAreaClipboard(
    comptime S: usize,
    comptime B: usize,
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    buffer: []u8,
    len: *usize,
    cursor: *usize,
    anchor: *usize,
    scroll_y: *f32,
    hist: *TextHistory(S, B),
    clip: *Clipboard,
    font: metrics_mod.FontMetrics,
    style: style_mod.TextInputStyle,
) context_mod.ContextError!TextAreaResult {
    if (buffer.len > B) return error.InvalidArgument;
    if (anchor.* > len.*) return error.InvalidArgument;
    if (clip.len > clip.buf.len) return error.InvalidArgument;
    return textAreaInner(ctx, id, bounds, buffer, len, cursor, anchor, scroll_y, font, style, *TextHistory(S, B), hist, clip);
}

fn textAreaInner(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    buffer: []u8,
    len: *usize,
    cursor: *usize,
    anchor: *usize,
    scroll_y: *f32,
    font: metrics_mod.FontMetrics,
    style: style_mod.TextInputStyle,
    Hist: type,
    hist: Hist,
    clip: ?*Clipboard,
) context_mod.ContextError!TextAreaResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid() or !font.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;
    if (len.* > buffer.len or cursor.* > len.* or anchor.* > len.*) return error.InvalidArgument;
    if (!std.math.isFinite(scroll_y.*)) return error.InvalidArgument;
    const use_hist = Hist != void;

    var res = TextAreaResult{ .len = len.* };
    const fm = input.FrameMouse.scan(ctx.pendingEvents());
    const line_h = font.lineHeight();
    const view_h = @max(0, bounds.h - pad * 2);
    const vis_w = @max(0, bounds.w - pad * 2);

    // Todo text-area é focável (registrado mesmo sem foco, para o Tab).
    try ctx.registerFocusable(id);

    // Enquanto não houver atividade de mouse neste frame, a posição
    // retida sozinha não reposiciona o caret (espelha text_input).
    var mouse_fresh = false;
    for (ctx.pendingEvents()) |ev| {
        switch (ev) {
            .mouse_move, .mouse_button, .mouse_wheel => mouse_fresh = true,
            else => {},
        }
    }

    // Offset horizontal derivado (mantém o caret visível) — usado no
    // desenho e no mapeamento do ponto de clique.
    const nlines0 = textAreaLineCount(buffer, len.*);
    const caret_line0 = lineOfOffset(buffer, @min(cursor.*, len.*));
    const caret_ls0 = lineStart(buffer, len.*, caret_line0);
    const caret_le0 = lineEnd(buffer, len.*, caret_line0);
    const caret_pre_w = (metrics_mod.measure(buffer[caret_ls0..@min(cursor.*, caret_le0)], font) catch metrics_mod.TextMetrics{}).width;
    const caret_full_w = (metrics_mod.measure(buffer[caret_ls0..caret_le0], font) catch metrics_mod.TextMetrics{}).width;
    const xoff: f32 = if (caret_full_w <= vis_w) 0 else std.math.clamp(caret_pre_w - vis_w, 0, caret_full_w - vis_w);
    const text_x = bounds.x + pad - xoff;
    const text_top = bounds.y + pad;

    var moved = false;

    // Click dentro: foca e posiciona o caret (âncora colapsa; captura
    // para arrasto de seleção). Troca de foco quebra a rajada do histórico.
    const had_focus = ctx.hasFocus(id);
    if (fm.pressedInside(bounds)) {
        ctx.focus_owner = id;
        if (use_hist and !had_focus) hist.closeGroup();
        if (ctx.press_owner == null) {
            if (fm.pressed_pos) |pp| {
                const line = lineAtY(pp.y, text_top, line_h, nlines0);
                const ls = lineStart(buffer, len.*, line);
                const le = lineEnd(buffer, len.*, line);
                const col = colAtX(font, buffer[ls..le], pp.x - text_x);
                const at = @min(ls + col, len.*);
                cursor.* = at;
                anchor.* = at;
                moved = true;
            }
            ctx.press_owner = id;
        }
    }
    // Arrasto: o cursor segue o mouse; a âncora fica (extende a seleção).
    if (ctx.press_owner == id and ctx.mouse_down_left and mouse_fresh) {
        if (ctx.mouse_pos) |mp| {
            const line = lineAtY(mp.y, text_top, line_h, nlines0);
            const ls = lineStart(buffer, len.*, line);
            const le = lineEnd(buffer, len.*, line);
            const col = colAtX(font, buffer[ls..le], mp.x - text_x);
            cursor.* = @min(ls + col, len.*);
            moved = true;
        }
    }
    if (ctx.press_owner == id and fm.released_pos != null) {
        ctx.press_owner = null;
    }

    const focused = ctx.hasFocus(id);
    res.focused = focused;

    if (focused) {
        // Apaga a faixa [lo,hi), colapsa cursor e âncora em lo (o
        // checkpoint do histórico é feito antes da chamada).
        const deleteSelection = struct {
            fn f(buf: []u8, l: *usize, c: *usize, a: *usize) void {
                const lo = @min(a.*, c.*);
                const hi = @max(a.*, c.*);
                std.mem.copyForwards(u8, buf[lo .. l.* - (hi - lo)], buf[hi..l.*]);
                l.* -= hi - lo;
                c.* = lo;
                a.* = lo;
            }
        }.f;

        for (ctx.pendingEvents()) |ev| {
            switch (ev) {
                .text => |t| {
                    if (t.codepoint == '\r') continue;
                    var enc: [4]u8 = undefined;
                    const n = encodeUtf8(t.codepoint, &enc) catch continue;
                    var snapped = false;
                    if (anchor.* != cursor.*) {
                        if (use_hist) hist.checkpointBreak(buffer[0..len.*], len.*, cursor.*);
                        deleteSelection(buffer, len, cursor, anchor);
                        res.changed = true;
                        snapped = true;
                        moved = true;
                    }
                    if (len.* + n <= buffer.len) {
                        // Rajada de digitação agrupa em um único passo.
                        if (use_hist) {
                            if (snapped) hist.markGrouped() else hist.checkpoint(buffer[0..len.*], len.*, cursor.*);
                        }
                        std.mem.copyBackwards(u8, buffer[cursor.* + n .. len.* + n], buffer[cursor.*..len.*]);
                        @memcpy(buffer[cursor.*..][0..n], enc[0..n]);
                        cursor.* += n;
                        len.* += n;
                        anchor.* = cursor.*;
                        res.changed = true;
                        moved = true;
                    } else {
                        res.overflowed = true;
                    }
                },
                .key => |k| {
                    if (!k.pressed) continue;
                    // Undo/redo consomem o evento antes de todo o resto.
                    if (use_hist and k.modifiers.ctrl and !k.modifiers.shift and k.key == .z) {
                        if (hist.undo(buffer, len, cursor, anchor)) {
                            res.undone = true;
                            res.changed = true;
                            moved = true;
                        }
                        continue;
                    }
                    if (use_hist and k.modifiers.ctrl and
                        ((!k.modifiers.shift and k.key == .y) or (k.modifiers.shift and k.key == .z)))
                    {
                        if (hist.redo(buffer, len, cursor, anchor)) {
                            res.redone = true;
                            res.changed = true;
                            moved = true;
                        }
                        continue;
                    }
                    // Área de transferência interna (só com clip).
                    if (clip) |cp| {
                        if (k.modifiers.ctrl and !k.modifiers.shift and
                            (k.key == .c or k.key == .x or k.key == .v))
                        {
                            if (k.key == .c) {
                                const lo = @min(anchor.*, cursor.*);
                                const hi = @max(anchor.*, cursor.*);
                                if (hi > lo) {
                                    if (hi - lo <= cp.buf.len) {
                                        @memcpy(cp.buf[0 .. hi - lo], buffer[lo..hi]);
                                        cp.len = hi - lo;
                                    } else {
                                        res.overflowed = true;
                                    }
                                }
                                continue;
                            }
                            if (k.key == .x) {
                                const lo = @min(anchor.*, cursor.*);
                                const hi = @max(anchor.*, cursor.*);
                                if (hi > lo) {
                                    if (hi - lo <= cp.buf.len) {
                                        @memcpy(cp.buf[0 .. hi - lo], buffer[lo..hi]);
                                        cp.len = hi - lo;
                                    } else {
                                        res.overflowed = true;
                                    }
                                    if (use_hist) hist.checkpointBreak(buffer[0..len.*], len.*, cursor.*);
                                    deleteSelection(buffer, len, cursor, anchor);
                                    res.changed = true;
                                    moved = true;
                                }
                                continue;
                            }
                            // Colar: substitui a faixa (se houver) e insere.
                            var snapped = false;
                            if (anchor.* != cursor.*) {
                                if (use_hist) hist.checkpointBreak(buffer[0..len.*], len.*, cursor.*);
                                deleteSelection(buffer, len, cursor, anchor);
                                res.changed = true;
                                snapped = true;
                            }
                            const n = cp.len;
                            if (n > 0) {
                                if (len.* + n <= buffer.len) {
                                    if (use_hist and !snapped) hist.checkpointBreak(buffer[0..len.*], len.*, cursor.*);
                                    std.mem.copyBackwards(u8, buffer[cursor.* + n .. len.* + n], buffer[cursor.*..len.*]);
                                    @memcpy(buffer[cursor.*..][0..n], cp.buf[0..n]);
                                    cursor.* += n;
                                    len.* += n;
                                    anchor.* = cursor.*;
                                    res.changed = true;
                                    moved = true;
                                } else {
                                    res.overflowed = true;
                                }
                            }
                            continue;
                        }
                    }
                    const extend = k.modifiers.shift;
                    // Colapsa a seleção para edições destrutivas.
                    if (anchor.* != cursor.* and (k.key == .backspace or k.key == .delete)) {
                        if (use_hist) hist.checkpointBreak(buffer[0..len.*], len.*, cursor.*);
                        deleteSelection(buffer, len, cursor, anchor);
                        res.changed = true;
                        moved = true;
                        continue;
                    }
                    switch (k.key) {
                        .backspace => {
                            if (use_hist) hist.closeGroup();
                            if (cursor.* > 0) {
                                if (use_hist) hist.checkpointBreak(buffer[0..len.*], len.*, cursor.*);
                                const at = prevCodepoint(buffer, cursor.*);
                                deleteRange(buffer, len, at, cursor.*);
                                cursor.* = at;
                                anchor.* = at;
                                res.changed = true;
                                moved = true;
                            }
                        },
                        .delete => {
                            if (use_hist) hist.closeGroup();
                            if (cursor.* < len.*) {
                                if (use_hist) hist.checkpointBreak(buffer[0..len.*], len.*, cursor.*);
                                const to = nextCodepoint(buffer, len.*, cursor.*);
                                deleteRange(buffer, len, cursor.*, to);
                                anchor.* = cursor.*;
                                res.changed = true;
                                moved = true;
                            }
                        },
                        .enter => {
                            // Insere após o checkpoint (snapshot do estado
                            // anterior); quebra de linha continua a rajada.
                            if (len.* + 1 <= buffer.len) {
                                if (use_hist) hist.checkpoint(buffer[0..len.*], len.*, cursor.*);
                                _ = insertBytes(buffer, len, cursor.*, "\n");
                                cursor.* += 1;
                                anchor.* = cursor.*;
                                res.changed = true;
                                moved = true;
                            } else {
                                res.overflowed = true;
                            }
                        },
                        .left => {
                            if (use_hist) hist.closeGroup();
                            cursor.* = prevCodepoint(buffer, cursor.*);
                            if (!extend) anchor.* = cursor.*;
                            moved = true;
                        },
                        .right => {
                            if (use_hist) hist.closeGroup();
                            cursor.* = nextCodepoint(buffer, len.*, cursor.*);
                            if (!extend) anchor.* = cursor.*;
                            moved = true;
                        },
                        .up, .down => {
                            if (use_hist) hist.closeGroup();
                            const cur_line = lineOfOffset(buffer, cursor.*);
                            const cur_col = cursor.* - lineStart(buffer, len.*, cur_line);
                            var target = cur_line;
                            if (k.key == .up and cur_line > 0) {
                                target = cur_line - 1;
                            } else if (k.key == .down and cur_line + 1 < textAreaLineCount(buffer, len.*)) {
                                target = cur_line + 1;
                            }
                            cursor.* = offsetForLineCol(buffer, len.*, target, cur_col);
                            if (!extend) anchor.* = cursor.*;
                            moved = true;
                        },
                        .page_up, .page_down => {
                            if (use_hist) hist.closeGroup();
                            const page: usize = if (line_h > 0)
                                @max(1, @as(usize, @intFromFloat(@floor(view_h / line_h))))
                            else
                                1;
                            const cur_line = lineOfOffset(buffer, cursor.*);
                            const cur_col = cursor.* - lineStart(buffer, len.*, cur_line);
                            const total = textAreaLineCount(buffer, len.*);
                            var target = cur_line;
                            if (k.key == .page_up) {
                                target = if (cur_line > page) cur_line - page else 0;
                            } else {
                                target = @min(total - 1, cur_line + page);
                            }
                            cursor.* = offsetForLineCol(buffer, len.*, target, cur_col);
                            if (!extend) anchor.* = cursor.*;
                            moved = true;
                        },
                        .home => {
                            if (use_hist) hist.closeGroup();
                            if (k.modifiers.ctrl) {
                                cursor.* = 0;
                            } else {
                                const line = lineOfOffset(buffer, cursor.*);
                                cursor.* = lineStart(buffer, len.*, line);
                            }
                            if (!extend) anchor.* = cursor.*;
                            moved = true;
                        },
                        .end => {
                            if (use_hist) hist.closeGroup();
                            if (k.modifiers.ctrl) {
                                cursor.* = len.*;
                            } else {
                                const line = lineOfOffset(buffer, cursor.*);
                                cursor.* = lineEnd(buffer, len.*, line);
                            }
                            if (!extend) anchor.* = cursor.*;
                            moved = true;
                        },
                        .a => {
                            if (k.modifiers.ctrl and !k.modifiers.shift) {
                                anchor.* = 0;
                                cursor.* = len.*;
                            }
                        },
                        .tab => {
                            if (use_hist) hist.closeGroup();
                            ctx.requestFocusAdvance(if (k.modifiers.shift) .prev else .next);
                        },
                        .escape => {
                            if (use_hist) hist.closeGroup();
                            ctx.focus_owner = null;
                            anchor.* = cursor.*;
                            res.focused = false;
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }
    }

    res.len = len.*;
    if (!ctx.hasFocus(id)) res.focused = false;
    res.selected = res.focused and anchor.* != cursor.*;

    // Rolagem vertical: clampa e acompanha o caret quando houve movimento.
    const nlines = textAreaLineCount(buffer, len.*);
    const content_h = @as(f32, @floatFromInt(nlines)) * line_h;
    const max_scroll = @max(0, content_h - view_h);
    scroll_y.* = std.math.clamp(scroll_y.*, 0, max_scroll);
    if (moved and focused and line_h > 0) {
        const cl = lineOfOffset(buffer, cursor.*);
        const c_top = @as(f32, @floatFromInt(cl)) * line_h;
        const c_bottom = c_top + line_h;
        if (c_top < scroll_y.*) {
            scroll_y.* = c_top;
        } else if (c_bottom > scroll_y.* + view_h) {
            scroll_y.* = c_bottom - view_h;
        }
        scroll_y.* = std.math.clamp(scroll_y.*, 0, max_scroll);
    }

    // ---- Desenho ---------------------------------------------------------
    const bg = if (res.focused) style.bg_focus else style.bg;
    const border = if (res.focused) style.border_focus else style.border;
    ctx.draw.rectFilled(ctx.allocator, bounds, bg) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    ctx.draw.rectOutline(ctx.allocator, bounds, border, @max(1.0, style.border_width)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };

    // Clip pareado na caixa (conteúdo nunca vaza para fora).
    ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = bounds, .null_rect = false } }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };
    try drawTextAreaContent(ctx, buffer, len.*, cursor.*, anchor.*, res.selected, res.focused, bounds, scroll_y.*, text_top, text_x, line_h, font, style);
    ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = .{}, .null_rect = true } }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };

    return res;
}

fn drawTextAreaContent(
    ctx: *context_mod.Context,
    buffer: []const u8,
    len: usize,
    cursor: usize,
    anchor: usize,
    selected: bool,
    focused: bool,
    bounds: types.Rect,
    scroll_y: f32,
    text_top: f32,
    text_x: f32,
    line_h: f32,
    font: metrics_mod.FontMetrics,
    style: style_mod.TextInputStyle,
) context_mod.ContextError!void {
    const nlines = textAreaLineCount(buffer, len);
    const view_h = @max(0, bounds.h - pad * 2);
    const vis_w = @max(0, bounds.w - pad * 2);
    if (line_h <= 0) return;

    const first: usize = @min(nlines, @as(usize, @intFromFloat(@max(0, @floor(scroll_y / line_h)))));
    const span: usize = if (line_h > 0) @max(1, @as(usize, @intFromFloat(@floor(view_h / line_h))) + 1) else 1;
    const last = @min(nlines, first + span + 1);

    const lo = @min(anchor, cursor);
    const hi = @max(anchor, cursor);

    var i = first;
    while (i < last) : (i += 1) {
        const ls = lineStart(buffer, len, i);
        const le = lineEnd(buffer, len, i);
        const y = text_top + @as(f32, @floatFromInt(i)) * line_h - scroll_y;

        if (selected and lo < hi) {
            const s = @max(lo, ls);
            const e = @min(hi, le);
            if (s < e) {
                const m0 = metrics_mod.measure(buffer[ls..s], font) catch return error.InvalidArgument;
                const m1 = metrics_mod.measure(buffer[ls..e], font) catch return error.InvalidArgument;
                ctx.draw.rectFilled(ctx.allocator, .{
                    .x = text_x + m0.width,
                    .y = y,
                    .w = @max(0, m1.width - m0.width),
                    .h = line_h,
                }, style.selection) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InvalidCommand => return error.InvalidCommand,
                };
            }
        }

        if (le > ls) {
            ctx.draw.pushText(
                ctx.allocator,
                .{ .x = text_x, .y = y },
                style.text,
                font,
                buffer[ls..le],
            ) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidCommand => return error.InvalidCommand,
                error.InvalidUtf8 => return error.InvalidArgument,
                error.InvalidMetrics => return error.InvalidArgument,
            };
        }
    }

    if (focused and vis_w > 0) {
        const cl = lineOfOffset(buffer, @min(cursor, len));
        const cls = lineStart(buffer, len, cl);
        const cle = lineEnd(buffer, len, cl);
        const m = metrics_mod.measure(buffer[cls..@min(cursor, cle)], font) catch return error.InvalidArgument;
        const cx = text_x + m.width;
        const cy = text_top + @as(f32, @floatFromInt(cl)) * line_h - scroll_y;
        ctx.draw.line(
            ctx.allocator,
            .{ .x = cx, .y = cy },
            .{ .x = cx, .y = cy + line_h },
            style.caret,
            1.0,
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
        };
    }
}

test "TextArea digita, Enter cria linha, Backspace junta linhas" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().textInputStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 60);
    const id = id_mod.Id.fromString("test:ta");
    var buf: [32]u8 = undefined;
    var len: usize = 0;
    var cursor: usize = 0;
    var anchor: usize = 0;
    var scroll: f32 = 0;

    // Sem foco: teclas ignoradas; caixa + clip (4 comandos).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'x' } });
    const r0 = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expect(!r0.focused and !r0.changed and len == 0);
    try stdt.testing.expectEqual(@as(usize, 4), ctx.drawCommands().len);
    ctx.endFrame();

    // Click foca; digita "ab" + Enter + "cd".
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'a' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'b' } });
    try ctx.pushEvent(.{ .key = .{ .key = .enter, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'c' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'd' } });
    const r1 = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expect(r1.focused and r1.changed);
    try stdt.testing.expectEqualStrings("ab\ncd", buf[0..len]);
    try stdt.testing.expectEqual(@as(usize, 5), cursor);
    try stdt.testing.expectEqual(@as(usize, 2), textAreaLineCount(&buf, len));
    ctx.endFrame();

    // Backspace apaga 'd','c' e depois o '\n' (junta as linhas).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .backspace, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .backspace, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .backspace, .pressed = true, .modifiers = .{} } });
    const r2 = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expect(r2.changed);
    try stdt.testing.expectEqualStrings("ab", buf[0..len]);
    try stdt.testing.expectEqual(@as(usize, 1), textAreaLineCount(&buf, len));
    ctx.endFrame();
}

test "TextArea navegação vertical preserva coluna; Home/End/Ctrl+End" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().textInputStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 60);
    const id = id_mod.Id.fromString("test:ta-nav");
    var buf: [32]u8 = undefined;
    const text = "l1\nlonger\nl3";
    @memcpy(buf[0..text.len], text);
    var len: usize = text.len;
    var cursor: usize = 2; // fim de "l1"
    var anchor: usize = 2;
    var scroll: f32 = 0;

    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(15, 5) },
    });
    _ = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expect(ctx.hasFocus(id));
    ctx.endFrame();

    // Down: linha 1, coluna 2 → offset 3 + 2 = 5.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    _ = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expectEqual(@as(usize, 5), cursor);
    ctx.endFrame();

    // End: fim da linha 1 ("longer") → offset 3+6 = 9.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{} } });
    _ = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expectEqual(@as(usize, 9), cursor);
    ctx.endFrame();

    // Home: início da linha 1 → 3.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    _ = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expectEqual(@as(usize, 3), cursor);
    ctx.endFrame();

    // Ctrl+End → fim do texto.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{ .ctrl = true } } });
    _ = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expectEqual(@as(usize, len), cursor);
    ctx.endFrame();
}

test "TextArea seleção por Shift, Ctrl+A e clip; contrato inválidos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().textInputStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:ta-sel");

    // Bounds pequenos para forçar rolagem vertical.
    const bounds = types.Rect.init(0, 0, 60, 24);
    var buf: [64]u8 = undefined;
    const text = "one\ntwo\nthree\nfour";
    @memcpy(buf[0..text.len], text);
    var len: usize = text.len;
    var cursor: usize = 0;
    var anchor: usize = 0;
    var scroll: f32 = 0;

    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    _ = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    ctx.endFrame();

    // Shift+Down estende a seleção (não colapsa a âncora).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{ .shift = true } } });
    const rs = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expect(rs.selected);
    try stdt.testing.expect(anchor == 0 and cursor > 0);
    ctx.endFrame();

    // Ctrl+A seleciona tudo.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .a, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const ra = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expect(ra.selected and anchor == 0 and cursor == len);
    ctx.endFrame();

    // PageDown rola e mantém o caret visível (scroll_y > 0).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .page_down, .pressed = true, .modifiers = .{} } });
    _ = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expect(scroll > 0);
    ctx.endFrame();

    // Contratos inválidos.
    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, textArea(&ctx, .null, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style));
    try stdt.testing.expectError(error.InvalidArgument, textArea(&ctx, id, types.Rect.init(0, 0, 0, 0), &buf, &len, &cursor, &anchor, &scroll, font, style));
    var bad_len: usize = buf.len + 1;
    try stdt.testing.expectError(error.InvalidArgument, textArea(&ctx, id, bounds, &buf, &bad_len, &cursor, &anchor, &scroll, font, style));
    var bad_cur: usize = len + 1;
    try stdt.testing.expectError(error.InvalidArgument, textArea(&ctx, id, bounds, &buf, &len, &bad_cur, &anchor, &scroll, font, style));
    var bad_anchor: usize = len + 1;
    try stdt.testing.expectError(error.InvalidArgument, textArea(&ctx, id, bounds, &buf, &len, &cursor, &bad_anchor, &scroll, font, style));
    var bad_scroll: f32 = std.math.nan(f32);
    try stdt.testing.expectError(error.InvalidArgument, textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &bad_scroll, font, style));
    ctx.endFrame();
}

test "TextArea multibyte: Backspace/Delete por codepoint" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().textInputStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 120, 40);
    const id = id_mod.Id.fromString("test:ta-mb");
    var buf: [32]u8 = undefined;
    const text = "A€\nB"; // '€' = 3 bytes
    @memcpy(buf[0..text.len], text);
    var len: usize = text.len;
    var cursor: usize = 0;
    var anchor: usize = 0;
    var scroll: f32 = 0;

    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    _ = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    ctx.endFrame();

    // Vai ao fim do texto (Ctrl+End) e apaga 'B'.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{ .ctrl = true } } });
    try ctx.pushEvent(.{ .key = .{ .key = .backspace, .pressed = true, .modifiers = .{} } });
    _ = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expectEqualStrings("A€\n", buf[0..len]);
    ctx.endFrame();

    // Apaga o '\n' (junta) e depois o '€' inteiro (3 bytes).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .backspace, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .backspace, .pressed = true, .modifiers = .{} } });
    _ = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expectEqualStrings("A", buf[0..len]);
    ctx.endFrame();
}

test "TextArea buffer cheio e capacidade zero: overflow sem corrupção" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().textInputStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 120, 40);
    const id = id_mod.Id.fromString("test:ta-full");
    var buf: [3]u8 = undefined;
    var len: usize = 0;
    var cursor: usize = 0;
    var anchor: usize = 0;
    var scroll: f32 = 0;

    // Enche o buffer "abc".
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'a' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'b' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'c' } });
    _ = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expectEqualStrings("abc", buf[0..len]);
    ctx.endFrame();

    // Digitar além da capacidade: overflow, estado intacto.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'd' } });
    const rf = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expect(rf.overflowed and !rf.changed);
    try stdt.testing.expectEqualStrings("abc", buf[0..len]);
    try stdt.testing.expectEqual(@as(usize, 3), cursor);
    // Enter também não cabe.
    try ctx.pushEvent(.{ .key = .{ .key = .enter, .pressed = true, .modifiers = .{} } });
    const re = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expect(re.overflowed and !re.changed);
    try stdt.testing.expectEqualStrings("abc", buf[0..len]);
    ctx.endFrame();

    // Backspace libera espaço e a inserção volta a funcionar.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .backspace, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'z' } });
    _ = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expectEqualStrings("abz", buf[0..len]);
    ctx.endFrame();

    // Capacidade zero: qualquer inserção é overflow.
    var zlen: usize = 0;
    var zcur: usize = 0;
    var zanch: usize = 0;
    var zscr: f32 = 0;
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'x' } });
    const rz = try textArea(&ctx, id, bounds, &.{}, &zlen, &zcur, &zanch, &zscr, font, style);
    try stdt.testing.expect(rz.overflowed and zlen == 0);
    ctx.endFrame();
}

test "TextArea coluna clampa em linha curta; Delete sobre '\\n' junta" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().textInputStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 60);
    const id = id_mod.Id.fromString("test:ta-clamp");
    var buf: [32]u8 = undefined;
    const text = "longer\nl3";
    @memcpy(buf[0..text.len], text);
    var len: usize = text.len;
    var cursor: usize = 6; // fim de "longer"
    var anchor: usize = 6;
    var scroll: f32 = 0;

    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    _ = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expect(ctx.hasFocus(id));
    ctx.endFrame();

    // Down para "l3" (col 2 < 6): clampa na coluna 2 → offset 7 + 2 = 9.
    cursor = 6;
    anchor = 6;
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    _ = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expectEqual(@as(usize, 9), cursor);
    ctx.endFrame();

    // Up de volta: coluna 2 em "longer" → offset 2.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .up, .pressed = true, .modifiers = .{} } });
    _ = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expectEqual(@as(usize, 2), cursor);
    ctx.endFrame();

    // Delete sobre o '\n' (offset 6) junta as linhas.
    cursor = 6;
    anchor = 6;
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .delete, .pressed = true, .modifiers = .{} } });
    const rd = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expect(rd.changed);
    try stdt.testing.expectEqualStrings("longerl3", buf[0..len]);
    try stdt.testing.expectEqual(@as(usize, 8), len);
    ctx.endFrame();
}

test "TextArea seleção multilinha apaga faixa; scroll clampa nos limites" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().textInputStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 60, 20); // view pequena → rolagem
    const id = id_mod.Id.fromString("test:ta-mlsel");
    var buf: [32]u8 = undefined;
    const text = "aa\nbb\ncc\ndd\nee";
    @memcpy(buf[0..text.len], text);
    var len: usize = text.len;
    var cursor: usize = 0;
    var anchor: usize = 0;
    var scroll: f32 = 0;

    // Rolagem: acima do máximo e abaixo do zero são clampadas.
    scroll = 9999;
    ctx.beginFrame();
    _ = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expectApproxEqAbs(textAreaMaxScroll(&buf, len, bounds.h - 8, font), scroll, 0.001);
    ctx.endFrame();
    scroll = -5;
    ctx.beginFrame();
    _ = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expectEqual(@as(f32, 0), scroll);
    ctx.endFrame();

    // Foca e seleciona 2 linhas (offset 0 → início da 2ª linha = 6).
    scroll = 0;
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    _ = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{ .shift = true } } });
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{ .shift = true } } });
    const rs = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expect(rs.selected and anchor == 0 and cursor == 6);
    ctx.endFrame();

    // Backspace apaga a faixa multilinha → resta "cc\ndd\nee".
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .backspace, .pressed = true, .modifiers = .{} } });
    const rd = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expect(rd.changed and !rd.selected);
    try stdt.testing.expectEqualStrings("cc\ndd\nee", buf[0..len]);
    try stdt.testing.expectEqual(@as(usize, 0), cursor);
    ctx.endFrame();

    // Contratos inválidos não corrompem o estado (len/cursor intactos).
    ctx.beginFrame();
    var bad_cur: usize = len + 1;
    try stdt.testing.expectError(error.InvalidArgument, textArea(&ctx, id, bounds, &buf, &len, &bad_cur, &anchor, &scroll, font, style));
    var bad_anchor: usize = len + 1;
    try stdt.testing.expectError(error.InvalidArgument, textArea(&ctx, id, bounds, &buf, &len, &cursor, &bad_anchor, &scroll, font, style));
    var bad_scroll: f32 = std.math.nan(f32);
    try stdt.testing.expectError(error.InvalidArgument, textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &bad_scroll, font, style));
    try stdt.testing.expectEqualStrings("cc\ndd\nee", buf[0..len]);
    try stdt.testing.expectEqual(@as(usize, 0), cursor);
    ctx.endFrame();
}

test "TextArea arrasto fora da área clampa; y extremo não estoura" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().textInputStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 60, 20);
    const id = id_mod.Id.fromString("test:ta-drag");
    var buf: [32]u8 = undefined;
    const text = "l0\nl1\nl2\nl3";
    @memcpy(buf[0..text.len], text);
    var len: usize = text.len;
    var cursor: usize = 0;
    var anchor: usize = 0;
    var scroll: f32 = 0;

    // Press no topo (âncora na linha 0).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    _ = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expectEqual(@as(usize, 0), anchor);
    ctx.endFrame();

    // Arrasta bem abaixo da área visível: cursor clampa na última linha.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(5, 1000) } });
    const rd = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expect(rd.selected);
    try stdt.testing.expect(cursor <= len);
    try stdt.testing.expectEqual(@as(usize, 9), cursor); // início da linha 3
    ctx.endFrame();

    // y finito absurdo (1e30): não deve estourar @intFromFloat; clampa.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(5, 1e30) } });
    const rx = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expect(rx.selected and cursor <= len);
    try stdt.testing.expectEqual(@as(usize, 9), cursor);
    ctx.endFrame();

    // Arrasta acima do topo: cursor clampa na primeira linha (offset 0).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(5, -1000) } });
    _ = try textArea(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, font, style);
    try stdt.testing.expectEqual(@as(usize, 0), cursor);
    ctx.endFrame();
}

test "textArea rejeita bounds não-finitos sem tocar o estado" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().textInputStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:ta-nan");
    var buf: [16]u8 = undefined;
    var len: usize = 0;
    var cursor: usize = 0;
    var anchor: usize = 0;
    var scroll: f32 = 0;
    const nan_bounds = types.Rect.init(0, 0, 200, std.math.nan(f32));
    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, textArea(&ctx, id, nan_bounds, &buf, &len, &cursor, &anchor, &scroll, font, style));
    try stdt.testing.expectEqual(@as(usize, 0), len);
    try stdt.testing.expectEqual(@as(f32, 0), scroll);
    ctx.endFrame();
}

test "TextArea undo/redo (Ctrl+Z/Y) agrupa rajada e restaura" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().textInputStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 60);
    const id = id_mod.Id.fromString("test:ta-hist");
    var buf: [32]u8 = undefined;
    var len: usize = 0;
    var cursor: usize = 0;
    var anchor: usize = 0;
    var scroll: f32 = 0;
    var hist = TextHistory(8, 32){};

    // Foca (troca de foco quebra a rajada).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    _ = try textAreaHistory(8, 32, &ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, &hist, font, style);
    ctx.endFrame();

    // Rajada "ab" + Enter + "cd" → um único passo de undo.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'a' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'b' } });
    try ctx.pushEvent(.{ .key = .{ .key = .enter, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'c' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'd' } });
    const r1 = try textAreaHistory(8, 32, &ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, &hist, font, style);
    try stdt.testing.expect(r1.changed and !r1.undone and !r1.redone);
    try stdt.testing.expectEqualStrings("ab\ncd", buf[0..len]);
    try stdt.testing.expectEqual(@as(usize, 1), hist.undo_top);
    ctx.endFrame();

    // Ctrl+Z desfaz a rajada inteira.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .z, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const ru = try textAreaHistory(8, 32, &ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, &hist, font, style);
    try stdt.testing.expect(ru.undone and ru.changed and !ru.redone);
    try stdt.testing.expectEqual(@as(usize, 0), len);
    try stdt.testing.expectEqual(@as(usize, 0), cursor);
    ctx.endFrame();

    // Ctrl+Shift+Z refaz.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .z, .pressed = true, .modifiers = .{ .ctrl = true, .shift = true } } });
    const rr = try textAreaHistory(8, 32, &ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, &hist, font, style);
    try stdt.testing.expect(rr.redone and rr.changed and !rr.undone);
    try stdt.testing.expectEqualStrings("ab\ncd", buf[0..len]);
    try stdt.testing.expectEqual(@as(usize, 5), cursor);
    ctx.endFrame();

    // Ctrl+Y também refaz (após novo undo).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .z, .pressed = true, .modifiers = .{ .ctrl = true } } });
    _ = try textAreaHistory(8, 32, &ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, &hist, font, style);
    try stdt.testing.expectEqual(@as(usize, 0), len);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .y, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const ry = try textAreaHistory(8, 32, &ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, &hist, font, style);
    try stdt.testing.expect(ry.redone);
    try stdt.testing.expectEqualStrings("ab\ncd", buf[0..len]);
    ctx.endFrame();

    // `B` menor que o buffer é recusado (snapshot não cobriria o campo).
    var small_hist = TextHistory(2, 4){};
    var big: [8]u8 = undefined;
    var blen: usize = 0;
    var bcur: usize = 0;
    var banch: usize = 0;
    var bscr: f32 = 0;
    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, textAreaHistory(2, 4, &ctx, id, bounds, &big, &blen, &bcur, &banch, &bscr, &small_hist, font, style));
    ctx.endFrame();
}

test "TextArea clipboard (Ctrl+A/C/X/V) multilinha, overflow e tipo compartilhado" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().textInputStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 60);
    const id = id_mod.Id.fromString("test:ta-clip");
    var buf: [64]u8 = undefined;
    const text = "aa\nbb\ncc";
    @memcpy(buf[0..text.len], text);
    var len: usize = text.len;
    var cursor: usize = 0;
    var anchor: usize = 0;
    var scroll: f32 = 0;
    var hist = TextHistory(8, 64){};
    var clipmem: [16]u8 = undefined;
    var clip = Clipboard{ .buf = &clipmem };

    // O `Clipboard` de `textarea` é o MESMO tipo de `text_input`.
    comptime {
        if (Clipboard != @import("../widgets/text_input.zig").Clipboard)
            @compileError("Clipboard deve ser compartilhado entre text_input e textarea");
    }

    // Foca.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    _ = try textAreaClipboard(8, 64, &ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, &hist, &clip, font, style);
    ctx.endFrame();

    // Ctrl+A + Ctrl+C copia o texto inteiro (com '\n'), sem alterar.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .a, .pressed = true, .modifiers = .{ .ctrl = true } } });
    try ctx.pushEvent(.{ .key = .{ .key = .c, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const rc = try textAreaClipboard(8, 64, &ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, &hist, &clip, font, style);
    try stdt.testing.expect(!rc.changed and !rc.overflowed);
    try stdt.testing.expectEqual(@as(usize, text.len), clip.len);
    try stdt.testing.expectEqualStrings(text, clip.buf[0..clip.len]);
    try stdt.testing.expect(anchor == 0 and cursor == len);
    ctx.endFrame();

    // Colapsa no fim e cola: o texto dobra.
    cursor = len;
    anchor = len;
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .v, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const rv = try textAreaClipboard(8, 64, &ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, &hist, &clip, font, style);
    try stdt.testing.expect(rv.changed and len == text.len * 2);
    try stdt.testing.expectEqualStrings("aa\nbb\nccaa\nbb\ncc", buf[0..len]);
    try stdt.testing.expectEqual(len, cursor);
    ctx.endFrame();

    // Ctrl+Z desfaz a colagem (passo isolado).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .z, .pressed = true, .modifiers = .{ .ctrl = true } } });
    _ = try textAreaClipboard(8, 64, &ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, &hist, &clip, font, style);
    try stdt.testing.expectEqual(@as(usize, text.len), len);
    try stdt.testing.expectEqualStrings(text, buf[0..len]);
    ctx.endFrame();

    // Ctrl+X sobre uma faixa multilinha copia e remove.
    anchor = 0;
    cursor = 5; // "aa\nbb"
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .x, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const rx = try textAreaClipboard(8, 64, &ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, &hist, &clip, font, style);
    try stdt.testing.expect(rx.changed and !rx.selected);
    try stdt.testing.expectEqualStrings("aa\nbb", clip.buf[0..clip.len]);
    try stdt.testing.expectEqualStrings("\ncc", buf[0..len]);
    try stdt.testing.expectEqual(@as(usize, 0), cursor);
    ctx.endFrame();

    // Copiar faixa maior que a área de transferência: overflow, sem mudança.
    anchor = 0;
    cursor = len; // "\ncc" (3 bytes) cabe; força overflow com faixa maior
    clip.len = 0;
    var tiny: [1]u8 = undefined;
    var tiny_clip = Clipboard{ .buf = &tiny };
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .c, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const ro = try textAreaClipboard(8, 64, &ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, &hist, &tiny_clip, font, style);
    try stdt.testing.expect(ro.overflowed and !ro.changed);
    try stdt.testing.expectEqual(@as(usize, 0), tiny_clip.len);
    ctx.endFrame();

    // Contratos inválidos: clip.len > clip.buf.len.
    var bad_clip = Clipboard{ .buf = &clipmem, .len = clipmem.len + 1 };
    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, textAreaClipboard(8, 64, &ctx, id, bounds, &buf, &len, &cursor, &anchor, &scroll, &hist, &bad_clip, font, style));
    ctx.endFrame();
}
