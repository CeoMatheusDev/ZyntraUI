//! ZyntraUI — composição de IME / texto pré-editado (text/ime).
//!
//! Escopo M126: o estado de composição de um IME (o "pré-edit" que o
//! usuário ainda está escrevendo), com buffer do CHAMADOR e sem
//! alocação dentro da biblioteca.
//! - `Composition`: guarda o pré-edit, o cursor dentro dele e o texto
//!   confirmado pendente.
//! - `applyCommit`: insere o texto confirmado no buffer editado,
//!   substituindo a seleção selecionada.
//!
//! Ownership: o pré-edit vive no buffer do chamador (`buf`); a
//! biblioteca só copia bytes para lá e nunca libera nada.
//! Validação: pré-edit UTF-8 válido, cursor sempre em fronteira de
//! codepoint e inserts que não cabem no buffer editado são recusados
//! (`OutOfSpace`) sem tocar no buffer.

const std = @import("std");
const metrics_mod = @import("metrics.zig");

/// Erros da composição de IME.
pub const Error = error{
    /// Pré-edit malformado (UTF-8 inválido).
    InvalidUtf8,
    /// Pré-edit maior que o buffer do chamador.
    BufferTooSmall,
    /// Texto confirmado não cabe no buffer editado.
    OutOfSpace,
    /// Estado inconsistente (cursor/âncora fora do buffer editado).
    InvalidState,
};

/// Estado de composição de IME (pré-edição).
///
/// O app atualiza a composição a partir do callback de IME da
/// plataforma (`update`/`commit`/`cancel`) e entrega o estado ao
/// widget, que aplica o texto confirmado no buffer editado.
pub const Composition = struct {
    /// Buffer do chamador para o pré-edit (emprestado).
    buf: []u8 = &.{},
    /// Bytes válidos do pré-edit.
    len: usize = 0,
    /// Cursor dentro do pré-edit (offset de byte, fronteira UTF-8).
    cursor: usize = 0,
    /// Composição em andamento (pré-edit visível).
    active: bool = false,
    /// Texto confirmado aguardando aplicação no buffer editado.
    committed: bool = false,

    const Self = @This();

    pub fn init(buf: []u8) Self {
        return .{ .buf = buf };
    }

    /// Inicia uma composição (pré-edit vazio).
    pub fn begin(self: *Self) void {
        self.len = 0;
        self.cursor = 0;
        self.active = true;
        self.committed = false;
    }

    /// Substitui o pré-edit por `text` e posiciona o cursor em
    /// `cursor` (offset de byte; clampado numa fronteira UTF-8).
    pub fn update(self: *Self, text: []const u8, cursor: usize) Error!void {
        if (!isValidUtf8(text)) return error.InvalidUtf8;
        if (text.len > self.buf.len) return error.BufferTooSmall;
        @memcpy(self.buf[0..text.len], text);
        self.len = text.len;
        self.cursor = clampToBoundary(text, cursor);
        self.active = true;
        self.committed = false;
    }

    /// Confirma o pré-edit: o texto fica marcado como confirmado e a
    /// composição termina (o widget aplica no buffer editado).
    pub fn commit(self: *Self) void {
        self.committed = true;
        self.active = false;
    }

    /// Cancela a composição (descarta o pré-edit).
    pub fn cancel(self: *Self) void {
        self.len = 0;
        self.cursor = 0;
        self.active = false;
        self.committed = false;
    }

    /// Pré-edit atual (bytes válidos).
    pub fn preedit(self: *const Self) []const u8 {
        return self.buf[0..self.len];
    }

    /// Aplica o texto confirmado no buffer editado, substituindo a faixa
    /// [min(anchor,cursor), max(anchor,cursor)) e movendo o cursor para
    /// o fim do texto inserido. Limpa a composição em caso de sucesso.
    pub fn applyCommit(
        self: *Self,
        buf: []u8,
        len: *usize,
        cursor: *usize,
        anchor: ?*usize,
    ) Error!void {
        if (!self.committed) return;
        if (cursor.* > len.* or len.* > buf.len) return error.InvalidState;
        var lo = cursor.*;
        var hi = cursor.*;
        if (anchor) |a| {
            if (a.* > len.*) return error.InvalidState;
            lo = @min(a.*, cursor.*);
            hi = @max(a.*, cursor.*);
        }
        const text = self.preedit();
        const remove = hi - lo;
        const need = len.* - remove + text.len;
        if (need > buf.len) return error.OutOfSpace;
        if (text.len <= remove) {
            std.mem.copyForwards(u8, buf[lo + text.len .. need], buf[hi..len.*]);
        } else {
            std.mem.copyBackwards(u8, buf[lo + text.len .. need], buf[hi..len.*]);
        }
        @memcpy(buf[lo..][0..text.len], text);
        len.* = need;
        cursor.* = lo + text.len;
        if (anchor) |a| a.* = cursor.*;
        self.cancel();
    }
};

fn isValidUtf8(text: []const u8) bool {
    var i: usize = 0;
    while (i < text.len) {
        const d = metrics_mod.decodeOne(text[i..]) catch return false;
        i += d.len;
    }
    return true;
}

/// Ajusta `cursor` para a maior fronteira de codepoint ≤ `cursor`.
fn clampToBoundary(text: []const u8, cursor: usize) usize {
    const target = @min(cursor, text.len);
    var last: usize = 0;
    var i: usize = 0;
    while (i < text.len) {
        const d = metrics_mod.decodeOne(text[i..]) catch break;
        const next = i + d.len;
        if (next > target) break;
        last = next;
        i = next;
    }
    return last;
}

test "Composition atualiza, confirma e cancela" {
    const stdt = @import("std");
    var buf: [32]u8 = undefined;
    var c = Composition.init(&buf);

    c.begin();
    try stdt.testing.expect(c.active);
    try stdt.testing.expectEqualStrings("", c.preedit());

    try c.update("ni", 2);
    try stdt.testing.expect(c.active);
    try stdt.testing.expectEqualStrings("ni", c.preedit());
    try stdt.testing.expectEqual(@as(usize, 2), c.cursor);

    // Cursor no meio de um caractere multibyte volta à fronteira.
    try c.update("\xc3\xa9x", 1);
    try stdt.testing.expectEqual(@as(usize, 0), c.cursor);
    try c.update("\xc3\xa9x", 2);
    try stdt.testing.expectEqual(@as(usize, 2), c.cursor);
    try c.update("\xc3\xa9x", 99);
    try stdt.testing.expectEqual(@as(usize, 3), c.cursor);

    // Pré-edit grande demais para o buffer é recusado.
    try stdt.testing.expectError(error.BufferTooSmall, c.update("0123456789abcdef0123456789abcdef0", 0));
    // UTF-8 inválido é recusado.
    try stdt.testing.expectError(error.InvalidUtf8, c.update("\xff", 0));

    c.commit();
    try stdt.testing.expect(!c.active);
    try stdt.testing.expect(c.committed);
    try stdt.testing.expectEqualStrings("\xc3\xa9x", c.preedit());

    c.cancel();
    try stdt.testing.expect(!c.committed);
    try stdt.testing.expectEqualStrings("", c.preedit());
}

test "applyCommit insere no cursor e substitui a seleção" {
    const stdt = @import("std");
    var pre: [16]u8 = undefined;
    var c = Composition.init(&pre);

    var text: [16]u8 = undefined;
    @memcpy(text[0..5], "hello");
    var len: usize = 5;
    var cursor: usize = 5;
    var anchor: usize = 5;

    // Sem confirmação: nada acontece.
    try c.applyCommit(&text, &len, &cursor, &anchor);
    try stdt.testing.expectEqual(@as(usize, 5), len);

    try c.update("!", 1);
    c.commit();
    try c.applyCommit(&text, &len, &cursor, &anchor);
    try stdt.testing.expectEqual(@as(usize, 6), len);
    try stdt.testing.expectEqualStrings("hello!", text[0..len]);
    try stdt.testing.expectEqual(@as(usize, 6), cursor);
    try stdt.testing.expectEqual(@as(usize, 6), anchor);
    // A composição é limpa depois do commit.
    try stdt.testing.expect(!c.committed);
    try stdt.testing.expectEqualStrings("", c.preedit());

    // Com seleção: o texto confirmado substitui a faixa.
    @memcpy(text[0..3], "abc");
    len = 3;
    cursor = 3;
    anchor = 0;
    try c.update("XY", 2);
    c.commit();
    try c.applyCommit(&text, &len, &cursor, &anchor);
    try stdt.testing.expectEqual(@as(usize, 2), len);
    try stdt.testing.expectEqualStrings("XY", text[0..len]);
    try stdt.testing.expectEqual(@as(usize, 2), cursor);
    try stdt.testing.expectEqual(@as(usize, 2), anchor);
}

test "applyCommit recusa insert que não cabe" {
    const stdt = @import("std");
    var pre: [8]u8 = undefined;
    var c = Composition.init(&pre);
    var text: [4]u8 = undefined;
    var len: usize = 3;
    var cursor: usize = 3;
    var anchor: usize = 3;

    try c.update("ab", 2);
    c.commit();
    try stdt.testing.expectError(error.OutOfSpace, c.applyCommit(&text, &len, &cursor, &anchor));
    // O buffer não foi tocado e a composição continua pendente.
    try stdt.testing.expectEqual(@as(usize, 3), len);
    try stdt.testing.expect(c.committed);
}
