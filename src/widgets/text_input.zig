//! ZyntraUI — campo de texto (widgets/text_input).
//!
//! Modelo M13 (foco + buffer do chamador + seleção):
//! - `buffer`/`len`/`cursor` (+ `anchor` em `textInputSelected`):
//!   buffer UTF-8 de tamanho fixo do CHAMADOR (zero alocação na lib);
//!   `len.*` = bytes usados, `cursor.*`/`anchor.*` = offsets de byte
//!   (sempre fronteira UTF-8, 0..len). Seleção = [min,max); iguais = nada.
//! - `textInput` (1.0.0, preservado): sem seleção; setas colapsam.
//! - `textInputSelected` (1.1.0, aditivo): `Shift`+navegação estende a
//!   seleção; digitar/backspace/`Delete` substituem a faixa; `Tab`,
//!   `Enter`, `Escape` como antes.
//! - Click dentro assume o foco; `Escape`/`clearFocus` liberam.
//! - `Ctrl+A` seleciona tudo (só com âncora); `Ctrl+C/X/V` internos;
//!   `Ctrl+Z/Y` undo/redo com histórico do chamador.
//! - `Ctrl+Backspace`/`Ctrl+Delete` apagam por palavra (só `' '` separa).
//! Desenho: caixa com destaque + highlight da seleção + texto + caret.
//! `id` não-nulo obrigatório.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const metrics_mod = @import("../text/metrics.zig");
const input = @import("input.zig");

pub const TextInputResult = struct {
    focused: bool = false,
    changed: bool = false,
    submitted: bool = false,
    overflowed: bool = false,
    /// True quando há faixa selecionada (só em `textInputSelected`+).
    selected: bool = false,
    /// Undo (`Ctrl+Z`) / redo (`Ctrl+Y` ou `Ctrl+Shift+Z`) aplicados
    /// nesta chamada (só em `textInputHistory`).
    undone: bool = false,
    redone: bool = false,
    len: usize = 0,
};

/// Área de transferência INTERNA (sem OS): o chamador detém `buf` e
/// `len` (bytes válidos). Copiar/colar nunca alocam; conteúdo maior
/// que `buf` não é copiado (tudo-ou-nada, sem truncar).
pub const Clipboard = struct {
    buf: []u8,
    len: usize = 0,
};

/// Histórico de undo/redo com pilhas de snapshots em buffers do
/// CHAMADOR (zero alocação na lib). `S` = passos guardados, `B` = bytes
/// por snapshot (deve cobrir `buffer.len` do campo, senão
/// `InvalidArgument`). Redo esvazia a cada nova mutação.
pub fn TextHistory(comptime S: usize, comptime B: usize) type {
    return struct {
        undo_bytes: [S][B]u8 = undefined,
        undo_len: [S]usize = std.mem.zeroes([S]usize),
        undo_cursor: [S]usize = std.mem.zeroes([S]usize),
        undo_top: usize = 0,
        redo_bytes: [S][B]u8 = undefined,
        redo_len: [S]usize = std.mem.zeroes([S]usize),
        redo_cursor: [S]usize = std.mem.zeroes([S]usize),
        redo_top: usize = 0,
        group_open: bool = false,

        const Self = @This();

        fn snapshot(
            stack_b: *[S][B]u8,
            stack_l: *[S]usize,
            stack_c: *[S]usize,
            top: *usize,
            buf: []const u8,
            len: usize,
            cursor: usize,
        ) void {
            if (S == 0) return; // histórico desabilitado: sem passos
            if (top.* >= S) {
                // Desloca (descarta o mais antigo); S pequeno, O(S·B).
                std.mem.copyForwards([B]u8, stack_b[0 .. S - 1], stack_b[1..S]);
                std.mem.copyForwards(usize, stack_l[0 .. S - 1], stack_l[1..S]);
                std.mem.copyForwards(usize, stack_c[0 .. S - 1], stack_c[1..S]);
                top.* = S - 1;
            }
            const n = @min(len, B);
            @memcpy(stack_b[top.*][0..n], buf[0..n]);
            stack_l[top.*] = n;
            stack_c[top.*] = @min(cursor, n);
            top.* += 1;
        }

        pub fn checkpoint(self: *Self, buf: []const u8, len: usize, cursor: usize) void {
            // Grupo de digitação: um snapshot por rajada.
            if (self.group_open) return;
            snapshot(&self.undo_bytes, &self.undo_len, &self.undo_cursor, &self.undo_top, buf, len, cursor);
            self.redo_top = 0;
            self.group_open = true;
        }

        pub fn checkpointBreak(self: *Self, buf: []const u8, len: usize, cursor: usize) void {
            // Mutação isolada (sempre novo passo).
            snapshot(&self.undo_bytes, &self.undo_len, &self.undo_cursor, &self.undo_top, buf, len, cursor);
            self.redo_top = 0;
            self.group_open = false;
        }

        pub fn closeGroup(self: *Self) void {
            self.group_open = false;
        }

        /// Reabre a rajada sem novo snapshot (substituição por faixa +
        /// digitação contam como um passo).
        pub fn markGrouped(self: *Self) void {
            self.group_open = true;
        }

        pub fn undo(self: *Self, buf: []u8, len: *usize, cursor: *usize, anchor: ?*usize) bool {
            if (self.undo_top == 0) return false;
            self.undo_top -= 1;
            snapshot(&self.redo_bytes, &self.redo_len, &self.redo_cursor, &self.redo_top, buf[0..len.*], len.*, cursor.*);
            const n = self.undo_len[self.undo_top];
            @memcpy(buf[0..n], self.undo_bytes[self.undo_top][0..n]);
            len.* = n;
            cursor.* = self.undo_cursor[self.undo_top];
            if (anchor) |a| a.* = cursor.*;
            self.group_open = false;
            return true;
        }

        pub fn redo(self: *Self, buf: []u8, len: *usize, cursor: *usize, anchor: ?*usize) bool {
            if (self.redo_top == 0) return false;
            self.redo_top -= 1;
            snapshot(&self.undo_bytes, &self.undo_len, &self.undo_cursor, &self.undo_top, buf[0..len.*], len.*, cursor.*);
            const n = self.redo_len[self.redo_top];
            @memcpy(buf[0..n], self.redo_bytes[self.redo_top][0..n]);
            len.* = n;
            cursor.* = self.redo_cursor[self.redo_top];
            if (anchor) |a| a.* = cursor.*;
            self.group_open = false;
            return true;
        }
    };
}

/// Codifica `codepoint` (0..0x10FFFF, sem surrogates) em UTF-8.
/// Chamar só após validar a faixa; fora dela retorna erro.
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

/// Início da palavra anterior a `pos` (pula espaços e depois a palavra).
/// Opera em bytes; recua só por fronteiras já válidas (buffer validado
/// na entrada, só ASCII ` ` separa — resto é "palavra").
fn wordStartBack(buf: []const u8, pos: usize) usize {
    var i = pos;
    while (i > 0 and buf[i - 1] == ' ') : (i -= 1) {}
    while (i > 0 and buf[i - 1] != ' ') {
        // Recua por codepoints (multibyte-safe).
        var j = i - 1;
        while (j > 0 and buf[j] & 0xC0 == 0x80) : (j -= 1) {}
        i = j;
    }
    return i;
}

/// Fim da próxima palavra a partir de `pos` (pula espaços e a palavra).
fn wordEndFwd(buf: []const u8, len: usize, pos: usize) usize {
    var i = pos;
    while (i < len and buf[i] == ' ') : (i += 1) {}
    while (i < len and buf[i] != ' ') {
        const d = metrics_mod.decodeOne(buf[i..len]) catch break; // defensivo
        i += d.len;
    }
    return i;
}

/// Remove o último codepoint de `buf[0..len]`. Retorna o novo `len`.
fn popCodepoint(buf: []u8, len: usize) usize {
    var i = len;
    if (i == 0) return 0;
    i -= 1;
    // Recua sobre bytes de continuação (10xxxxxx).
    while (i > 0 and buf[i] & 0xC0 == 0x80) : (i -= 1) {}
    return i;
}

/// Campo de texto clássico (1.0.0, preservado): sem seleção e sem
/// histórico; setas colapsam. Para seleção, `textInputSelected`; para
/// undo/redo, `textInputHistory` (ambos aditivos).
pub fn textInput(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    buffer: []u8,
    len: *usize,
    cursor: *usize,
    font: metrics_mod.FontMetrics,
    style: style_mod.TextInputStyle,
) context_mod.ContextError!TextInputResult {
    return textInputInner(ctx, id, bounds, buffer, len, cursor, null, font, style, void, {}, null);
}

/// Campo de texto com seleção (1.1.0): `anchor` persiste entre frames
/// (chamador detém). `Shift`+navegação estende a faixa [min,max);
/// digitar/backspace/`Delete` a substituem; setas simples colapsam.
pub fn textInputSelected(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    buffer: []u8,
    len: *usize,
    cursor: *usize,
    anchor: *usize,
    font: metrics_mod.FontMetrics,
    style: style_mod.TextInputStyle,
) context_mod.ContextError!TextInputResult {
    if (anchor.* > len.*) return error.InvalidArgument;
    return textInputInner(ctx, id, bounds, buffer, len, cursor, anchor, font, style, void, {}, null);
}

/// Campo de texto completo (1.5.0, aditivo): seleção + undo/redo +
/// área de transferência interna (`Ctrl+C/X/V`, tudo-ou-nada, sem OS).
/// `clip` é `*Clipboard` do chamador (pode ser menor que o texto; nesse
/// caso copiar/colar além da capacidade são ignorados com `overflowed`).
pub fn textInputClipboard(
    comptime S: usize,
    comptime B: usize,
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    buffer: []u8,
    len: *usize,
    cursor: *usize,
    anchor: *usize,
    hist: *TextHistory(S, B),
    clip: *Clipboard,
    font: metrics_mod.FontMetrics,
    style: style_mod.TextInputStyle,
) context_mod.ContextError!TextInputResult {
    if (buffer.len > B) return error.InvalidArgument;
    if (anchor.* > len.*) return error.InvalidArgument;
    if (clip.len > clip.buf.len) return error.InvalidArgument;
    return textInputInner(ctx, id, bounds, buffer, len, cursor, anchor, font, style, *TextHistory(S, B), hist, clip);
}

/// Campo de texto com undo/redo (1.5.0, aditivo): `Ctrl+Z` desfaz,
/// `Ctrl+Y` ou `Ctrl+Shift+Z` refazem; rajadas de digitação agrupam em
/// um passo. `hist` é `*TextHistory(S, B)` do chamador com `B` cobrindo
/// `buffer.len` (senão `InvalidArgument`).
pub fn textInputHistory(
    comptime S: usize,
    comptime B: usize,
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    buffer: []u8,
    len: *usize,
    cursor: *usize,
    anchor: *usize,
    hist: *TextHistory(S, B),
    font: metrics_mod.FontMetrics,
    style: style_mod.TextInputStyle,
) context_mod.ContextError!TextInputResult {
    if (buffer.len > B) return error.InvalidArgument;
    if (anchor.* > len.*) return error.InvalidArgument;
    return textInputInner(ctx, id, bounds, buffer, len, cursor, anchor, font, style, *TextHistory(S, B), hist, null);
}

fn textInputInner(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    buffer: []u8,
    len: *usize,
    cursor: *usize,
    anchor: ?*usize,
    font: metrics_mod.FontMetrics,
    style: style_mod.TextInputStyle,
    Hist: type,
    hist: Hist,
    clip: ?*Clipboard,
) context_mod.ContextError!TextInputResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid() or !font.isValid()) return error.InvalidArgument;
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;
    if (len.* > buffer.len or cursor.* > len.*) return error.InvalidArgument;
    if (anchor) |a| {
        if (a.* > len.*) return error.InvalidArgument;
    }
    const use_hist = Hist != void;

    var res = TextInputResult{ .len = len.* };
    const fm = input.FrameMouse.scan(ctx.pendingEvents());

    // Todo text-input é focável (registrado mesmo sem foco, para o Tab).
    try ctx.registerFocusable(id);

    // Click dentro assume o foco (independe de captura de press).
    // Troca de foco quebra rajada de digitação do histórico.
    const had_focus = ctx.hasFocus(id);
    if (fm.pressedInside(bounds)) {
        ctx.focus_owner = id;
        if (use_hist and !had_focus) hist.closeGroup();
    }
    const focused = ctx.hasFocus(id);
    res.focused = focused;

    // Apaga a faixa [lo,hi), colapsa cursor e âncora em lo.
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

    if (focused) {
        for (ctx.pendingEvents()) |ev| {
            switch (ev) {
                .text => |t| {
                    var snapped = false;
                    if (anchor) |a| {
                        if (a.* != cursor.*) {
                            if (use_hist) hist.checkpointBreak(buffer[0..len.*], len.*, cursor.*);
                            deleteSelection(buffer, len, cursor, a);
                            res.changed = true;
                            snapped = true;
                        }
                    }
                    var enc: [4]u8 = undefined;
                    const n = encodeUtf8(t.codepoint, &enc) catch continue; // defensivo; fila já valida
                    if (len.* + n <= buffer.len) {
                        // Rajada de digitação agrupa (sem checkpoint se a
                        // exclusão acima já abriu o passo; reabre a rajada).
                        if (use_hist) {
                            if (snapped) {
                                hist.markGrouped();
                            } else {
                                hist.checkpoint(buffer[0..len.*], len.*, cursor.*);
                            }
                        }
                        // Insere no cursor (desloca o sufixo para a direita).
                        std.mem.copyBackwards(u8, buffer[cursor.* + n .. len.* + n], buffer[cursor.*..len.*]);
                        @memcpy(buffer[cursor.*..][0..n], enc[0..n]);
                        cursor.* += n;
                        len.* += n;
                        if (anchor) |a| a.* = cursor.*;
                        res.changed = true;
                    } else {
                        res.overflowed = true;
                    }
                },
                .key => |k| {
                    if (!k.pressed) continue;
                    // Undo/redo consomem o evento antes de todo o resto.
                    if (use_hist and k.key == .z and k.modifiers.ctrl and !k.modifiers.shift) {
                        if (hist.undo(buffer, len, cursor, anchor)) {
                            res.undone = true;
                            res.changed = true;
                        }
                        continue;
                    }
                    if (use_hist and ((k.key == .y and k.modifiers.ctrl) or
                        (k.key == .z and k.modifiers.ctrl and k.modifiers.shift)))
                    {
                        if (hist.redo(buffer, len, cursor, anchor)) {
                            res.redone = true;
                            res.changed = true;
                        }
                        continue;
                    }
                    // Área de transferência interna (só com clip + âncora).
                    if (clip) |cp| {
                        if (k.key == .c and k.modifiers.ctrl and !k.modifiers.shift) {
                            if (anchor) |a| {
                                const lo = @min(a.*, cursor.*);
                                const hi = @max(a.*, cursor.*);
                                if (hi > lo) {
                                    if (hi - lo <= cp.buf.len) {
                                        @memcpy(cp.buf[0 .. hi - lo], buffer[lo..hi]);
                                        cp.len = hi - lo;
                                    } else {
                                        res.overflowed = true;
                                    }
                                }
                            }
                            continue;
                        }
                        if (k.key == .x and k.modifiers.ctrl and !k.modifiers.shift) {
                            if (anchor) |a| {
                                const lo = @min(a.*, cursor.*);
                                const hi = @max(a.*, cursor.*);
                                if (hi > lo) {
                                    if (hi - lo <= cp.buf.len) {
                                        @memcpy(cp.buf[0 .. hi - lo], buffer[lo..hi]);
                                        cp.len = hi - lo;
                                    } else {
                                        res.overflowed = true;
                                    }
                                    if (use_hist) hist.checkpointBreak(buffer[0..len.*], len.*, cursor.*);
                                    deleteSelection(buffer, len, cursor, a);
                                    res.changed = true;
                                }
                            }
                            continue;
                        }
                        if (k.key == .v and k.modifiers.ctrl and !k.modifiers.shift) {
                            var snapped = false;
                            if (anchor) |a| {
                                if (a.* != cursor.*) {
                                    if (use_hist) hist.checkpointBreak(buffer[0..len.*], len.*, cursor.*);
                                    deleteSelection(buffer, len, cursor, a);
                                    res.changed = true;
                                    snapped = true;
                                }
                            }
                            const n = cp.len;
                            if (n > 0) {
                                if (len.* + n <= buffer.len) {
                                    // Um passo de undo por colagem: se já
                                    // houve exclusão acima, sem novo checkpoint.
                                    if (use_hist and !snapped) hist.checkpointBreak(buffer[0..len.*], len.*, cursor.*);
                                    std.mem.copyBackwards(u8, buffer[cursor.* + n .. len.* + n], buffer[cursor.*..len.*]);
                                    @memcpy(buffer[cursor.*..][0..n], cp.buf[0..n]);
                                    cursor.* += n;
                                    len.* += n;
                                    if (anchor) |a| a.* = cursor.*;
                                    res.changed = true;
                                } else {
                                    res.overflowed = true;
                                }
                            }
                            continue;
                        }
                    }
                    const extend = anchor != null and k.modifiers.shift;
                    switch (k.key) {
                        .backspace => {
                            if (anchor) |a| {
                                if (a.* != cursor.*) {
                                    if (use_hist) hist.checkpointBreak(buffer[0..len.*], len.*, cursor.*);
                                    deleteSelection(buffer, len, cursor, a);
                                    res.changed = true;
                                    continue;
                                }
                            }
                            // Ctrl+Backspace apaga a palavra anterior.
                            if (k.modifiers.ctrl and !k.modifiers.shift) {
                                const at = wordStartBack(buffer, cursor.*);
                                if (at != cursor.*) {
                                    if (use_hist) hist.checkpointBreak(buffer[0..len.*], len.*, cursor.*);
                                    const n = cursor.* - at;
                                    std.mem.copyForwards(u8, buffer[at .. len.* - n], buffer[cursor.*..len.*]);
                                    cursor.* = at;
                                    len.* -= n;
                                    if (anchor) |a| a.* = cursor.*;
                                    res.changed = true;
                                }
                                continue;
                            }
                            if (cursor.* > 0) {
                                if (use_hist) hist.checkpointBreak(buffer[0..len.*], len.*, cursor.*);
                                const at = popCodepoint(buffer, cursor.*);
                                const n = cursor.* - at;
                                std.mem.copyForwards(u8, buffer[at .. len.* - n], buffer[cursor.*..len.*]);
                                cursor.* = at;
                                len.* -= n;
                                if (anchor) |a| a.* = cursor.*;
                                res.changed = true;
                            }
                        },
                        .delete => {
                            if (anchor) |a| {
                                if (a.* != cursor.*) {
                                    if (use_hist) hist.checkpointBreak(buffer[0..len.*], len.*, cursor.*);
                                    deleteSelection(buffer, len, cursor, a);
                                    res.changed = true;
                                    continue;
                                }
                            }
                            // Ctrl+Delete apaga a próxima palavra.
                            if (k.modifiers.ctrl and !k.modifiers.shift) {
                                const to = wordEndFwd(buffer, len.*, cursor.*);
                                if (to != cursor.*) {
                                    if (use_hist) hist.checkpointBreak(buffer[0..len.*], len.*, cursor.*);
                                    const n = to - cursor.*;
                                    std.mem.copyForwards(u8, buffer[cursor.* .. len.* - n], buffer[to..len.*]);
                                    len.* -= n;
                                    if (anchor) |a| a.* = cursor.*;
                                    res.changed = true;
                                }
                                continue;
                            }
                            if (cursor.* < len.*) {
                                if (use_hist) hist.checkpointBreak(buffer[0..len.*], len.*, cursor.*);
                                const d = metrics_mod.decodeOne(buffer[cursor.*..len.*]) catch {
                                    return error.InvalidArgument; // buffer do chamador corrompido
                                };
                                std.mem.copyForwards(u8, buffer[cursor.* .. len.* - d.len], buffer[cursor.* + d.len .. len.*]);
                                len.* -= d.len;
                                res.changed = true;
                            }
                        },
                        .left => {
                            if (use_hist) hist.closeGroup();
                            if (cursor.* > 0) cursor.* = popCodepoint(buffer, cursor.*);
                            if (!extend) {
                                if (anchor) |a| a.* = cursor.*;
                            }
                        },
                        .right => {
                            if (use_hist) hist.closeGroup();
                            if (cursor.* < len.*) {
                                const d = metrics_mod.decodeOne(buffer[cursor.*..len.*]) catch {
                                    return error.InvalidArgument;
                                };
                                cursor.* += d.len;
                            }
                            if (!extend) {
                                if (anchor) |a| a.* = cursor.*;
                            }
                        },
                        .home => {
                            if (use_hist) hist.closeGroup();
                            cursor.* = 0;
                            if (!extend) {
                                if (anchor) |a| a.* = cursor.*;
                            }
                        },
                        .end => {
                            if (use_hist) hist.closeGroup();
                            cursor.* = len.*;
                            if (!extend) {
                                if (anchor) |a| a.* = cursor.*;
                            }
                        },
                        .a => {
                            // Ctrl+A seleciona tudo (só com âncora; sem
                            // âncora não há onde representar a faixa).
                            // Não toca no histórico (não muta).
                            if (k.modifiers.ctrl and !k.modifiers.shift) {
                                if (anchor) |a| {
                                    a.* = 0;
                                    cursor.* = len.*;
                                }
                            }
                        },
                        .enter => {
                            if (use_hist) hist.closeGroup();
                            res.submitted = true;
                        },
                        .tab => {
                            if (use_hist) hist.closeGroup();
                            // Tab nunca vira texto: agenda avanço sobre o
                            // registro completo (aplicado no beginFrame).
                            ctx.requestFocusAdvance(if (k.modifiers.shift) .prev else .next);
                        },
                        .escape => {
                            if (use_hist) hist.closeGroup();
                            ctx.focus_owner = null;
                            if (anchor) |a| a.* = cursor.*;
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
    // Seleção só existe com foco; sem foco, widgets veem `selected=false`
    // e nenhum highlight (evita faixa fantasma com estado retido).
    if (anchor) |a| res.selected = res.focused and a.* != cursor.*;

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
    if (res.selected) {
        // Highlight sob o texto, entre os offsets ordenados.
        const a = anchor.?;
        const lo = @min(a.*, cursor.*);
        const hi = @max(a.*, cursor.*);
        const m0 = metrics_mod.measure(buffer[0..lo], font) catch {
            return error.InvalidArgument;
        };
        const m1 = metrics_mod.measure(buffer[0..hi], font) catch {
            return error.InvalidArgument;
        };
        const hy = bounds.y + 2;
        const hh = bounds.h - 4;
        if (hh > 0) {
            ctx.draw.rectFilled(ctx.allocator, .{
                .x = bounds.x + 4 + m0.width,
                .y = hy,
                .w = @max(0, m1.width - m0.width),
                .h = hh,
            }, style.selection) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidCommand => return error.InvalidCommand,
            };
        }
    }
    if (len.* > 0) {
        ctx.draw.pushText(
            ctx.allocator,
            .{ .x = bounds.x + 4, .y = bounds.y + (bounds.h - font.lineHeight()) / 2 },
            style.text,
            font,
            buffer[0..len.*],
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
            error.InvalidUtf8 => return error.InvalidArgument, // buffer do chamador corrompido
            error.InvalidMetrics => return error.InvalidArgument,
        };
    }
    if (res.focused) {
        // Caret na posição do cursor (mede o prefixo + padding).
        const m = metrics_mod.measure(buffer[0..cursor.*], font) catch {
            return error.InvalidArgument;
        };
        const cx = bounds.x + 4 + m.width;
        const top = bounds.y + 4;
        const bottom = bounds.y + bounds.h - 4;
        if (bottom > top) {
            ctx.draw.line(
                ctx.allocator,
                .{ .x = cx, .y = top },
                .{ .x = cx, .y = bottom },
                style.caret,
                1.0,
            ) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidCommand => return error.InvalidCommand,
            };
        }
    }
    return res;
}

test "text_input foco, digita, backspace multibyte, submit, escape" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().textInputStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 30);
    const id = id_mod.Id.fromString("test:ti");
    var buf: [16]u8 = undefined;
    var len: usize = 0;
    var cursor: usize = 0;

    // Sem foco: teclas ignoradas, 2 draws (caixa).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'A' } });
    const r0 = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expect(!r0.focused and !r0.changed);
    try stdt.testing.expectEqual(@as(usize, 0), len);
    try stdt.testing.expectEqual(@as(usize, 2), ctx.drawCommands().len);
    ctx.endFrame();

    // Click foca; digita "A€" (1 + 3 bytes).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'A' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 0x20AC } });
    const r1 = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expect(r1.focused and r1.changed);
    try stdt.testing.expectEqual(@as(usize, 4), len);
    try stdt.testing.expectEqualStrings("A€", buf[0..len]);
    ctx.endFrame();

    // Backspace remove o codepoint inteiro (€ = 3 bytes).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .backspace, .pressed = true, .modifiers = .{} } });
    const r2 = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expect(r2.changed);
    try stdt.testing.expectEqualStrings("A", buf[0..len]);
    // Backspace solto (pressed=false) não repete.
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .backspace, .pressed = false, .modifiers = .{} } });
    const r2b = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expect(!r2b.changed);
    try stdt.testing.expectEqualStrings("A", buf[0..len]);
    ctx.endFrame();

    // Enter submete; Escape desfoca.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .enter, .pressed = true, .modifiers = .{} } });
    const r3 = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expect(r3.submitted and r3.focused);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .escape, .pressed = true, .modifiers = .{} } });
    const r4 = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expect(!r4.focused);
    try stdt.testing.expect(ctx.focus_owner == null);
    ctx.endFrame();

    // Buffer cheio: descarta sem corromper, sinaliza overflow.
    var tiny: [1]u8 = undefined;
    var tlen: usize = 0;
    var tcursor: usize = 0;
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'A' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'B' } });
    const r5 = try textInput(&ctx, id, bounds, &tiny, &tlen, &tcursor, font, style);
    try stdt.testing.expect(r5.overflowed);
    try stdt.testing.expectEqualStrings("A", tiny[0..tlen]);
    ctx.endFrame();

    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, textInput(&ctx, .null, bounds, &buf, &len, &cursor, font, style));
    var badlen: usize = 99;
    try stdt.testing.expectError(error.InvalidArgument, textInput(&ctx, id, bounds, &buf, &badlen, &cursor, font, style));
    var badcur: usize = 50;
    var oklen: usize = 1;
    try stdt.testing.expectError(error.InvalidArgument, textInput(&ctx, id, bounds, &buf, &oklen, &badcur, font, style));
    ctx.endFrame();
}

test "text_input Tab circula foco entre campos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().textInputStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const b1 = types.Rect.init(0, 0, 200, 30);
    const b2 = types.Rect.init(0, 40, 200, 30);
    const id1 = id_mod.Id.fromString("test:ti1");
    const id2 = id_mod.Id.fromString("test:ti2");
    var buf1: [8]u8 = undefined;
    var len1: usize = 0;
    var cur1: usize = 0;
    var buf2: [8]u8 = undefined;
    var len2: usize = 0;
    var cur2: usize = 0;

    // F1: click no campo 1 foca; ambos registrados.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    const f1a = try textInput(&ctx, id1, b1, &buf1, &len1, &cur1, font, style);
    _ = try textInput(&ctx, id2, b2, &buf2, &len2, &cur2, font, style);
    try stdt.testing.expect(f1a.focused);
    try stdt.testing.expect(ctx.hasFocus(id1));
    ctx.endFrame();

    // F2: Tab no campo 1 agenda; aplicado no F3 → campo 2.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .tab, .pressed = true, .modifiers = .{} } });
    _ = try textInput(&ctx, id1, b1, &buf1, &len1, &cur1, font, style);
    _ = try textInput(&ctx, id2, b2, &buf2, &len2, &cur2, font, style);
    try stdt.testing.expect(ctx.hasFocus(id1)); // ainda 1 neste frame
    ctx.endFrame();
    ctx.beginFrame();
    const f3a = try textInput(&ctx, id1, b1, &buf1, &len1, &cur1, font, style);
    const f3b = try textInput(&ctx, id2, b2, &buf2, &len2, &cur2, font, style);
    try stdt.testing.expect(!f3a.focused and f3b.focused);
    // Tab nunca virou texto em nenhum campo:
    try stdt.testing.expectEqual(@as(usize, 0), len1);
    try stdt.testing.expectEqual(@as(usize, 0), len2);
    ctx.endFrame();

    // F4: Shift+Tab no campo 2 volta ao 1 (aplicado no F5).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .tab, .pressed = true, .modifiers = .{ .shift = true } } });
    _ = try textInput(&ctx, id1, b1, &buf1, &len1, &cur1, font, style);
    _ = try textInput(&ctx, id2, b2, &buf2, &len2, &cur2, font, style);
    ctx.endFrame();
    ctx.beginFrame();
    const f5a = try textInput(&ctx, id1, b1, &buf1, &len1, &cur1, font, style);
    const f5b = try textInput(&ctx, id2, b2, &buf2, &len2, &cur2, font, style);
    try stdt.testing.expect(f5a.focused and !f5b.focused);
    ctx.endFrame();
}

test "textInputSelected Shift+setas, substitui e destaca" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10); // advance=6
    const style = style_mod.Theme.darkDefault().textInputStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 30);
    const id = id_mod.Id.fromString("test:ti-sel");
    var buf: [16]u8 = undefined;
    var len: usize = 0;
    var cursor: usize = 0;
    var anchor: usize = 0;

    // Foca e digita "ABC" (sem seleção; 4 draws: caixa×2+texto+caret).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'A' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'B' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'C' } });
    const r0 = try textInputSelected(&ctx, id, bounds, &buf, &len, &cursor, &anchor, font, style);
    try stdt.testing.expect(!r0.selected);
    try stdt.testing.expectEqual(@as(usize, 4), ctx.drawCommands().len);
    ctx.endFrame();

    // Shift+Left ×2 seleciona "BC" (+1 draw de highlight).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{ .shift = true } } });
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{} } });
    // ^ segundo Left é simples: colapsa em 1, sem seleção.
    const r1 = try textInputSelected(&ctx, id, bounds, &buf, &len, &cursor, &anchor, font, style);
    try stdt.testing.expect(!r1.selected);
    try stdt.testing.expectEqual(@as(usize, 1), cursor);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{ .shift = true } } });
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{ .shift = true } } });
    const r2 = try textInputSelected(&ctx, id, bounds, &buf, &len, &cursor, &anchor, font, style);
    try stdt.testing.expect(r2.selected);
    try stdt.testing.expectEqual(@as(usize, 1), cursor);
    try stdt.testing.expectEqual(@as(usize, 3), anchor);
    try stdt.testing.expectEqual(@as(usize, 5), ctx.drawCommands().len); // caixa×2+highlight+texto+caret
    ctx.endFrame();

    // Digitar substitui a faixa: "AX".
    ctx.beginFrame();
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'X' } });
    const r3 = try textInputSelected(&ctx, id, bounds, &buf, &len, &cursor, &anchor, font, style);
    try stdt.testing.expect(r3.changed and !r3.selected);
    try stdt.testing.expectEqualStrings("AX", buf[0..len]);
    try stdt.testing.expectEqual(@as(usize, 2), cursor);
    ctx.endFrame();

    // Seleciona tudo (Home + Shift+End: cursor vai ao fim, âncora no 0).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{ .shift = true } } });
    _ = try textInputSelected(&ctx, id, bounds, &buf, &len, &cursor, &anchor, font, style);
    try stdt.testing.expectEqual(@as(usize, 2), cursor);
    try stdt.testing.expectEqual(@as(usize, 0), anchor);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .backspace, .pressed = true, .modifiers = .{} } });
    const r4 = try textInputSelected(&ctx, id, bounds, &buf, &len, &cursor, &anchor, font, style);
    try stdt.testing.expect(r4.changed and !r4.selected);
    try stdt.testing.expectEqual(@as(usize, 0), len);
    ctx.endFrame();

    // Âncora inválida rejeitada; legado preservado (sem selected).
    ctx.beginFrame();
    var badanchor: usize = 99;
    try stdt.testing.expectError(error.InvalidArgument, textInputSelected(&ctx, id, bounds, &buf, &len, &cursor, &badanchor, font, style));
    const rl = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expect(!rl.selected);
    ctx.endFrame();

    // Sem foco: âncora/cursor divergentes não geram faixa fantasma.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'A' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'B' } });
    _ = try textInputSelected(&ctx, id, bounds, &buf, &len, &cursor, &anchor, font, style);
    try stdt.testing.expectEqualStrings("AB", buf[0..len]);
    ctx.endFrame();
    ctx.clearFocus();
    cursor = 0; // âncora retida em 2: faixa [0,2) só vale com foco
    ctx.beginFrame();
    const ru = try textInputSelected(&ctx, id, bounds, &buf, &len, &cursor, &anchor, font, style);
    try stdt.testing.expect(!ru.focused and !ru.selected);
    try stdt.testing.expectEqual(@as(usize, 3), ctx.drawCommands().len); // caixa×2+texto, sem highlight/caret
    ctx.endFrame();
}

test "textInputHistory undo agrupa, redo refaz, mutação limpa redo" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().textInputStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 30);
    const id = id_mod.Id.fromString("test:ti-hist");
    var buf: [16]u8 = undefined;
    var len: usize = 0;
    var cursor: usize = 0;
    var anchor: usize = 0;
    var hist = TextHistory(8, 16){};

    const H = struct {
        fn call(
            c: *context_mod.Context,
            i: id_mod.Id,
            b: types.Rect,
            bf: []u8,
            l: *usize,
            cu: *usize,
            a: *usize,
            h: *@TypeOf(hist),
            f: metrics_mod.FontMetrics,
            s: style_mod.TextInputStyle,
        ) !TextInputResult {
            return textInputHistory(8, 16, c, i, b, bf, l, cu, a, h, f, s);
        }
    }.call;

    // Foca e digita "ABC" numa rajada (um passo de undo).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'A' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'B' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'C' } });
    _ = try H(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &hist, font, style);
    try stdt.testing.expectEqualStrings("ABC", buf[0..len]);
    ctx.endFrame();

    // Ctrl+Z desfaz a rajada inteira; Ctrl+Y refaz.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .z, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const ru = try H(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &hist, font, style);
    try stdt.testing.expect(ru.undone and !ru.redone);
    try stdt.testing.expectEqual(@as(usize, 0), len);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .y, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const rr = try H(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &hist, font, style);
    try stdt.testing.expect(rr.redone and !rr.undone);
    try stdt.testing.expectEqualStrings("ABC", buf[0..len]);
    ctx.endFrame();

    // Nova mutação limpa o redo: desfaz, digita, redo falha.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .z, .pressed = true, .modifiers = .{ .ctrl = true } } });
    _ = try H(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &hist, font, style);
    try stdt.testing.expectEqual(@as(usize, 0), len);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'Q' } });
    _ = try H(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &hist, font, style);
    try stdt.testing.expectEqualStrings("Q", buf[0..len]);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .y, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const rn = try H(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &hist, font, style);
    try stdt.testing.expect(!rn.redone);
    try stdt.testing.expectEqualStrings("Q", buf[0..len]);
    ctx.endFrame();

    // Backspace é passo isolado: desfaz sozinho...
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .backspace, .pressed = true, .modifiers = .{} } });
    _ = try H(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &hist, font, style);
    try stdt.testing.expectEqual(@as(usize, 0), len);
    ctx.endFrame();
    // ...Ctrl+Z restaura "Q"; Ctrl+Shift+Z (alias de redo) reapaga.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .z, .pressed = true, .modifiers = .{ .ctrl = true } } });
    _ = try H(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &hist, font, style);
    try stdt.testing.expectEqualStrings("Q", buf[0..len]);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .z, .pressed = true, .modifiers = .{ .ctrl = true, .shift = true } } });
    const rs = try H(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &hist, font, style);
    try stdt.testing.expect(rs.redone);
    try stdt.testing.expectEqual(@as(usize, 0), len);
    ctx.endFrame();

    // Pilha vazia: undo é no-op; buffer maior que B rejeitado.
    ctx.beginFrame();
    var fresh = TextHistory(8, 16){};
    try ctx.pushEvent(.{ .key = .{ .key = .z, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const re = try H(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &fresh, font, style);
    try stdt.testing.expect(!re.undone);
    var big: [17]u8 = undefined;
    var biglen: usize = 0;
    var bigcur: usize = 0;
    var biganc: usize = 0;
    try stdt.testing.expectError(
        error.InvalidArgument,
        textInputHistory(8, 16, &ctx, id, bounds, &big, &biglen, &bigcur, &biganc, &hist, font, style),
    );
    ctx.endFrame();
}

test "textInputClipboard copia, recorta, cola e desfaz" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().textInputStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 30);
    const id = id_mod.Id.fromString("test:ti-clip");
    var buf: [16]u8 = undefined;
    var len: usize = 0;
    var cursor: usize = 0;
    var anchor: usize = 0;
    var hist = TextHistory(8, 16){};
    var clipmem: [16]u8 = undefined;
    var clip = Clipboard{ .buf = &clipmem };

    const H = struct {
        fn call(
            c: *context_mod.Context,
            i: id_mod.Id,
            b: types.Rect,
            bf: []u8,
            l: *usize,
            cu: *usize,
            a: *usize,
            h: *@TypeOf(hist),
            cp: *Clipboard,
            f: metrics_mod.FontMetrics,
            s: style_mod.TextInputStyle,
        ) !TextInputResult {
            return textInputClipboard(8, 16, c, i, b, bf, l, cu, a, h, cp, f, s);
        }
    }.call;

    // Foca e digita "ABCD".
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    for ("ABCD") |ch| try ctx.pushEvent(.{ .text = .{ .codepoint = ch } });
    _ = try H(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &hist, &clip, font, style);
    try stdt.testing.expectEqualStrings("ABCD", buf[0..len]);
    ctx.endFrame();

    // Sem seleção: Ctrl+C não faz nada.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .c, .pressed = true, .modifiers = .{ .ctrl = true } } });
    _ = try H(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &hist, &clip, font, style);
    try stdt.testing.expectEqual(@as(usize, 0), clip.len);
    ctx.endFrame();

    // Shift+Home seleciona tudo; Ctrl+C copia; Ctrl+X recorta.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{ .shift = true } } });
    _ = try H(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &hist, &clip, font, style);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .c, .pressed = true, .modifiers = .{ .ctrl = true } } });
    _ = try H(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &hist, &clip, font, style);
    try stdt.testing.expectEqualStrings("ABCD", clip.buf[0..clip.len]);
    try stdt.testing.expectEqualStrings("ABCD", buf[0..len]); // copiar não altera
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .x, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const rx = try H(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &hist, &clip, font, style);
    try stdt.testing.expect(rx.changed);
    try stdt.testing.expectEqual(@as(usize, 0), len);
    ctx.endFrame();

    // Ctrl+V cola; Ctrl+Z desfaz a colagem (um passo).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .v, .pressed = true, .modifiers = .{ .ctrl = true } } });
    _ = try H(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &hist, &clip, font, style);
    try stdt.testing.expectEqualStrings("ABCD", buf[0..len]);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .z, .pressed = true, .modifiers = .{ .ctrl = true } } });
    _ = try H(&ctx, id, bounds, &buf, &len, &cursor, &anchor, &hist, &clip, font, style);
    try stdt.testing.expectEqual(@as(usize, 0), len);
    ctx.endFrame();

    // Colar além da capacidade: tudo-ou-nada + overflowed.
    var small: [2]u8 = undefined;
    var slen: usize = 0;
    var scur: usize = 0;
    var sanc: usize = 0;
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .v, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const ro = try textInputClipboard(8, 16, &ctx, id, bounds, &small, &slen, &scur, &sanc, &hist, &clip, font, style);
    try stdt.testing.expect(ro.overflowed);
    try stdt.testing.expectEqual(@as(usize, 0), slen);
    ctx.endFrame();
}

test "text_input caret navega, insere no meio e deleta" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().textInputStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 30);
    const id = id_mod.Id.fromString("test:ti-nav");
    var buf: [16]u8 = undefined;
    var len: usize = 0;
    var cursor: usize = 0;

    // Foca e digita "AC" (cursor acompanha o fim).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'A' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'C' } });
    _ = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expectEqualStrings("AC", buf[0..len]);
    try stdt.testing.expectEqual(@as(usize, 2), cursor);
    ctx.endFrame();

    // Left + "B" insere no meio: "ABC".
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'B' } });
    _ = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expectEqualStrings("ABC", buf[0..len]);
    try stdt.testing.expectEqual(@as(usize, 2), cursor);
    ctx.endFrame();

    // Left no início não sai de 0; right avança por codepoint.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{} } });
    _ = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expectEqual(@as(usize, 0), cursor);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    _ = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expectEqual(@as(usize, 3), cursor);
    ctx.endFrame();

    // Delete no meio remove "B": "AC". Backspace no início é no-op.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{} } });
    _ = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expectEqual(@as(usize, 1), cursor);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .delete, .pressed = true, .modifiers = .{} } });
    const rd = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expect(rd.changed);
    try stdt.testing.expectEqualStrings("AC", buf[0..len]);
    try stdt.testing.expectEqual(@as(usize, 1), cursor);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .backspace, .pressed = true, .modifiers = .{} } });
    const rb = try textInput(&ctx, id, bounds, &buf, &len, &cursor, font, style);
    try stdt.testing.expect(!rb.changed);
    try stdt.testing.expectEqualStrings("AC", buf[0..len]);
    ctx.endFrame();
}

test "textInputSelected Ctrl+A seleciona tudo" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().textInputStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 30);
    const id = id_mod.Id.fromString("test:ti-alla");
    var buf: [16]u8 = undefined;
    var len: usize = 0;
    var cursor: usize = 0;
    var anchor: usize = 0;

    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'H' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'i' } });
    _ = try textInputSelected(&ctx, id, bounds, &buf, &len, &cursor, &anchor, font, style);
    ctx.endFrame();

    // Ctrl+A: âncora no 0, cursor no fim, nada muda no texto.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .a, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const r = try textInputSelected(&ctx, id, bounds, &buf, &len, &cursor, &anchor, font, style);
    try stdt.testing.expect(r.selected);
    try stdt.testing.expectEqual(@as(usize, 0), anchor);
    try stdt.testing.expectEqual(@as(usize, 2), cursor);
    try stdt.testing.expectEqualStrings("Hi", buf[0..len]);
    ctx.endFrame();

    // 'a' sem Ctrl não seleciona (cai no else, sem efeito em tecla).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .a, .pressed = true, .modifiers = .{} } });
    const r2 = try textInputSelected(&ctx, id, bounds, &buf, &len, &cursor, &anchor, font, style);
    try stdt.testing.expect(r2.selected); // seleção anterior preservada
    try stdt.testing.expectEqualStrings("Hi", buf[0..len]);
    ctx.endFrame();
}

test "textInput Ctrl+Backspace/Delete por palavra" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const style = style_mod.Theme.darkDefault().textInputStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const bounds = types.Rect.init(0, 0, 200, 30);
    const id = id_mod.Id.fromString("test:ti-word");
    var buf: [32]u8 = undefined;
    var len: usize = 0;
    var cursor: usize = 0;
    var anchor: usize = 0;
    var hist = TextHistory(8, 32){};

    // Digita "foo bar" (foca antes).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(5, 5) },
    });
    for ("foo bar") |ch| try ctx.pushEvent(.{ .text = .{ .codepoint = ch } });
    _ = try textInputHistory(8, 32, &ctx, id, bounds, &buf, &len, &cursor, &anchor, &hist, font, style);
    try stdt.testing.expectEqualStrings("foo bar", buf[0..len]);
    ctx.endFrame();

    // Ctrl+Backspace apaga "bar" (cursor no fim).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .backspace, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const r1 = try textInputHistory(8, 32, &ctx, id, bounds, &buf, &len, &cursor, &anchor, &hist, font, style);
    try stdt.testing.expect(r1.changed);
    try stdt.testing.expectEqualStrings("foo ", buf[0..len]);
    ctx.endFrame();

    // Home + Ctrl+Delete apaga "foo" (para no espaço seguinte).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .delete, .pressed = true, .modifiers = .{ .ctrl = true } } });
    _ = try textInputHistory(8, 32, &ctx, id, bounds, &buf, &len, &cursor, &anchor, &hist, font, style);
    try stdt.testing.expectEqualStrings(" ", buf[0..len]);
    ctx.endFrame();

    // Ctrl+Z desfaz a exclusão por palavra (passo isolado).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .z, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const r2 = try textInputHistory(8, 32, &ctx, id, bounds, &buf, &len, &cursor, &anchor, &hist, font, style);
    try stdt.testing.expect(r2.undone);
    try stdt.testing.expectEqualStrings("foo ", buf[0..len]);
    ctx.endFrame();

    // Com cursor no 0 ("foo " restaurado): exclusões são no-op seguro.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .backspace, .pressed = true, .modifiers = .{ .ctrl = true } } });
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .backspace, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const r3 = try textInputHistory(8, 32, &ctx, id, bounds, &buf, &len, &cursor, &anchor, &hist, font, style);
    try stdt.testing.expect(!r3.changed);
    try stdt.testing.expectEqualStrings("foo ", buf[0..len]);
    ctx.endFrame();
}
