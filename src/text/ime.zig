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
    /// Estado inconsistente (cursor/âncora fora do buffer editado ou
    /// pré-edit sobreposto ao buffer editado).
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
    /// O texto pode se sobrepor ao buffer da composição.
    pub fn update(self: *Self, text: []const u8, cursor: usize) Error!void {
        if (!isValidUtf8(text)) return error.InvalidUtf8;
        if (text.len > self.buf.len) return error.BufferTooSmall;
        @memmove(self.buf[0..text.len], text);
        self.len = text.len;
        // A origem pode ter sido alterada pela cópia sobreposta.
        self.cursor = clampToBoundary(self.buf[0..self.len], cursor);
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
    /// Os bytes do pré-edit não podem se sobrepor a `buf`: nesse caso
    /// retorna `InvalidState` sem alterar o texto ou a composição.
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
        // O deslocamento da cauda poderia sobrescrever o pré-edit antes
        // de inseri-lo. Recusa a sobreposição antes de tocar nos buffers.
        if (slicesOverlap(text, buf)) return error.InvalidState;
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

fn slicesOverlap(a: []const u8, b: []const u8) bool {
    if (a.len == 0 or b.len == 0) return false;
    const a_start = @intFromPtr(a.ptr);
    const b_start = @intFromPtr(b.ptr);
    // Subtração em vez de endereços finais evita overflow aritmético.
    return if (a_start <= b_start) b_start - a_start < a.len else a_start - b_start < b.len;
}

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

test "fuzz IME: sem crash, pré-edit sempre UTF-8 e coerente" {
    try std.testing.fuzz({}, fuzzIme, .{});
}

fn fuzzIme(_: void, smith: *std.testing.Smith) !void {
    var buf: [64]u8 = undefined;
    smith.bytes(&buf);
    var c = Composition.init(&buf);

    // Sequência aleatória de operações.
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        const op = buf[i] % 4;
        const n = @as(usize, buf[(i + 1) % buf.len]) % 32;
        const cursor = @as(usize, buf[(i + 2) % buf.len]) % 64;
        switch (op) {
            0 => c.update("abc", cursor) catch |err| switch (err) {
                error.InvalidUtf8 => {},
                error.BufferTooSmall => {},
                else => return err,
            },
            1 => {
                // Bytes arbitrários: UTF-8 inválido é recusado.
                c.update(buf[0..n], cursor) catch |err| switch (err) {
                    error.InvalidUtf8 => {},
                    error.BufferTooSmall => {},
                    else => return err,
                };
            },
            2 => c.commit(),
            else => c.cancel(),
        }
        // Invariantes: o pré-edit é UTF-8 válido, o cursor está dentro
        // dele e o estado é coerente.
        const pre = c.preedit();
        var k: usize = 0;
        while (k < pre.len) {
            const d = metrics_mod.decodeOne(pre[k..]) catch return error.TestUnexpectedResult;
            k += d.len;
        }
        try std.testing.expect(c.cursor <= c.len);
        try std.testing.expect(c.len <= buf.len);
        if (!c.committed) try std.testing.expect(c.len == 0 or c.active);
    }
}

test "Composition.update aceita texto sobreposto ao buffer" {
    var storage: [16]u8 = undefined;
    var c = Composition.init(&storage);
    try c.update("a\xc3\xa9z", 4);
    const same = c.preedit();
    try c.update(same, 2);
    try std.testing.expectEqualStrings("a\xc3\xa9z", c.preedit());
    try std.testing.expectEqual(@as(usize, 1), c.cursor);

    // Origem antes do destino: move bytes para a direita.
    @memcpy(storage[0..4], "a\xc3\xa9z");
    c = Composition.init(storage[2..]);
    try c.update(storage[0..4], 2);
    try std.testing.expectEqualStrings("a\xc3\xa9z", c.preedit());
    try std.testing.expectEqual(@as(usize, 1), c.cursor);

    // Origem depois do destino: move bytes para a esquerda.
    @memcpy(storage[2..6], "a\xc3\xa9z");
    c = Composition.init(&storage);
    try c.update(storage[2..6], 2);
    try std.testing.expectEqualStrings("a\xc3\xa9z", c.preedit());
    try std.testing.expectEqual(@as(usize, 1), c.cursor);
}

test "applyCommit recusa sobreposição sem alterar texto ou composição" {
    var storage: [16]u8 = "abcdefgh........".*;
    var c = Composition.init(storage[4..12]);
    try c.update("XY", 2);
    c.commit();
    var len: usize = 8;
    var cursor: usize = 2;
    var anchor: usize = 2;
    const before = storage;
    try std.testing.expectError(error.InvalidState, c.applyCommit(storage[0..10], &len, &cursor, &anchor));
    try std.testing.expectEqual(before, storage);
    try std.testing.expectEqual(@as(usize, 8), len);
    try std.testing.expectEqual(@as(usize, 2), cursor);
    try std.testing.expectEqual(@as(usize, 2), anchor);
    try std.testing.expect(c.committed);
    try std.testing.expectEqualStrings("XY", c.preedit());

    // A outra direção de sobreposição também deve ser recusada.
    c = Composition.init(storage[0..4]);
    try c.update("XY", 2);
    c.commit();
    len = 6;
    cursor = 0;
    anchor = 0;
    const before_other = storage;
    try std.testing.expectError(error.InvalidState, c.applyCommit(storage[1..12], &len, &cursor, &anchor));
    try std.testing.expectEqual(before_other, storage);
    try std.testing.expect(c.committed);
}

test "applyCommit aceita partes disjuntas do mesmo array e pré-edit vazio" {
    var storage: [16]u8 = "................".*;
    var c = Composition.init(storage[0..4]);
    try c.update("XY", 2);
    @memcpy(storage[8..10], "ok");
    c.commit();
    var len: usize = 2;
    var cursor: usize = 2;
    var anchor: usize = 2;
    try c.applyCommit(storage[8..16], &len, &cursor, &anchor);
    try std.testing.expectEqualStrings("okXY", storage[8..][0..len]);

    // Pré-edit vazio pode remover uma seleção, pois não há bytes de
    // origem para se sobrepor ao texto editado.
    c = Composition.init(storage[0..4]);
    try c.update("", 0);
    c.commit();
    len = 4;
    cursor = 3;
    anchor = 1;
    try c.applyCommit(&storage, &len, &cursor, &anchor);
    try std.testing.expectEqual(@as(usize, 2), len);
    try std.testing.expectEqualStrings("X.", storage[0..len]);
    try std.testing.expectEqual(@as(usize, 1), cursor);
    try std.testing.expectEqual(@as(usize, 1), anchor);
    try std.testing.expect(!c.committed);
}

test "fuzz IME: atualização com origem no próprio buffer é reproduzível" {
    var input: [64]u8 = @splat(0);
    input[0] = 1; // update com buf[0..n]
    input[1] = 2; // n = 2, ambos os bytes são UTF-8 válido
    var smith = std.testing.Smith{ .in = &input };
    try fuzzIme({}, &smith);
}
