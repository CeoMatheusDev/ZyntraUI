//! ZyntraUI — identificadores estáveis de widgets (core/id).
//!
//! Contrato:
//! - `Id` é um `u64` opaco e estável dentro de um processo.
//! - Derivação determinística (FNV-1a 64) para não depender de
//!   APIs de hash do std cuja estabilidade entre versões não é
//!   garantida para IDs persistentes.
//! - `fromString` nunca falha; string vazia retorna `empty`.
//! - Sem alocação, sem I/O.

pub const Id = enum(u64) {
    null = 0,
    _,

    pub fn fromU64(v: u64) Id {
        if (v == 0) return .null;
        return @fromBackingInt(@intCast(v));
    }

    pub fn value(self: Id) u64 {
        return @backingInt(self);
    }

    pub fn isNull(self: Id) bool {
        return self == .null;
    }

    /// Hash FNV-1a 64 de uma string (offset basis + prime padrão).
    pub fn fromString(s: []const u8) Id {
        if (s.len == 0) return .null;
        var h: u64 = 0xcbf29ce484222325;
        for (s) |byte| {
            h ^= byte;
            h *%= 0x100000001b3;
        }
        if (h == 0) h = 1; // reserva 0 para .null
        return @fromBackingInt(@intCast(h));
    }

    /// Combina um id pai com um índice filho (para listas/árvores).
    pub fn child(self: Id, index: u32) Id {
        var h: u64 = self.value() ^ 0x9e3779b97f4a7c15;
        h *%= 0x100000001b3;
        h ^= index;
        h *%= 0x100000001b3;
        if (h == 0) h = 1;
        return @fromBackingInt(@intCast(h));
    }
};

test "Id.fromString determinístico e não-nulo" {
    const std = @import("std");
    const a = Id.fromString("button/ok");
    const b = Id.fromString("button/ok");
    const c = Id.fromString("button/cancel");
    try std.testing.expect(!a.isNull());
    try std.testing.expectEqual(a.value(), b.value());
    try std.testing.expect(a.value() != c.value());
    try std.testing.expect(Id.fromString("").isNull());
    try std.testing.expect(Id.fromU64(0).isNull());
}

test "Id.child deriva ids distintos" {
    const std = @import("std");
    const parent = Id.fromString("list");
    const c0 = parent.child(0);
    const c1 = parent.child(1);
    try std.testing.expect(!c0.isNull());
    try std.testing.expect(!c1.isNull());
    try std.testing.expect(c0.value() != c1.value());
}
