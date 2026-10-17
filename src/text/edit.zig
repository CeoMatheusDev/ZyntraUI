//! ZyntraUI — utilidades de edição de texto (text/edit).
//!
//! Helpers **puros** compartilhados pelos widgets de texto
//! (`widgets/text_input` e `widgets/textarea`): a área de transferência
//! interna e o histórico de undo/redo. Sem alocação — todo o armazenamento
//! vive em buffers do CHAMADOR.
//!
//! - `Clipboard` — área de transferência INTERNA (sem OS): `buf`/`len` do
//!   chamador; copiar/colar nunca alocam e conteúdo maior que `buf` não é
//!   copiado (tudo-ou-nada, sem truncar).
//! - `TextHistory(S, B)` — pilhas de snapshots do chamador (`S` passos de
//!   `B` bytes); `checkpoint` agrupa rajadas de digitação e `checkpointBreak`
//!   isola mutações grandes (colar/recortar/apagar faixa); `undo`/`redo`
//!   restauram buffer/len/cursor (e a âncora opcional). `S == 0` desabilita
//!   o histórico.
//!
//! Os mesmos tipos são re-exportados por `widgets/text_input`
//! (`text_input.Clipboard` é `edit.Clipboard`) para que um mesmo buffer
//! sirva campos de uma linha e áreas multilinha.

const std = @import("std");

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

test "Clipboard guarda bytes; TextHistory undo/redo restaura buffer/len/cursor" {
    const stdt = @import("std");

    // Clipboard: copiar é tudo-ou-nada (cabe no buffer).
    var mem: [8]u8 = undefined;
    var clip = Clipboard{ .buf = &mem };
    @memcpy(clip.buf[0..2], "xy");
    clip.len = 2;
    try stdt.testing.expectEqualStrings("xy", clip.buf[0..clip.len]);

    const H = TextHistory(4, 16);
    var h = H{};
    var buf: [16]u8 = undefined;
    var len: usize = 0;
    var cursor: usize = 0;
    var anchor: usize = 0;

    // Rajada de digitação: um único passo (o 2º checkpoint é no-op).
    const a = "ab";
    @memcpy(buf[0..a.len], a);
    h.checkpoint(buf[0..0], 0, 0);
    len = a.len;
    cursor = a.len;
    h.checkpoint(buf[0..len], len, cursor);
    try stdt.testing.expectEqual(@as(usize, 1), h.undo_top);

    // Mutação isolada abre um novo passo.
    const b = "abcd";
    @memcpy(buf[0..b.len], b);
    h.checkpointBreak(buf[0..len], len, cursor);
    len = b.len;
    cursor = b.len;
    try stdt.testing.expectEqual(@as(usize, 2), h.undo_top);

    // undo volta ao estado anterior; redo retorna ao atual.
    try stdt.testing.expect(h.undo(&buf, &len, &cursor, &anchor));
    try stdt.testing.expectEqual(@as(usize, 2), len);
    try stdt.testing.expectEqualStrings("ab", buf[0..len]);
    try stdt.testing.expectEqual(@as(usize, 2), cursor);
    try stdt.testing.expectEqual(@as(usize, 2), anchor);
    try stdt.testing.expect(h.redo(&buf, &len, &cursor, &anchor));
    try stdt.testing.expectEqual(@as(usize, 4), len);
    try stdt.testing.expectEqualStrings("abcd", buf[0..len]);

    // Pilha vazia: undo/redo são no-op.
    var empty = H{};
    try stdt.testing.expect(!empty.undo(&buf, &len, &cursor, &anchor));
    try stdt.testing.expect(!empty.redo(&buf, &len, &cursor, &anchor));
}
