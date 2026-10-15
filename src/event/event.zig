//! ZyntraUI — entrada normalizada (event/event).
//!
//! Ownership: eventos por valor, sem alocação.
//! Lifetime: válidos apenas no frame em que foram enfileirados;
//! `EventQueue.clear` no `beginFrame` invalida slices anteriores.
//! Segurança: valida codepoints e tamanhos; adaptadores externos
//! devem filtrar dados não confiáveis antes de `push`.
//! ABI C: enums com tag explícita (`u8`/`u32`) e payloads
//! `extern struct`; a `union(enum)` em si ganhará projeção
//! plana na futura camada C-ABI (M5).

const std = @import("std");
const types = @import("../core/types.zig");

/// Botões de mouse normalizados.
pub const MouseButton = enum(u8) {
    left = 0,
    right = 1,
    middle = 2,
};

/// Teclas normalizadas (subseto inicial; `_` reserva extensão).
/// Representação `u32` para futura compatibilidade C e códigos físicos.
pub const Key = enum(u32) {
    unknown = 0,
    escape = 1,
    enter = 2,
    tab = 3,
    space = 4,
    backspace = 5,
    left = 6,
    right = 7,
    up = 8,
    down = 9,
    a = 10,
    c = 11,
    v = 12,
    x = 13,
    z = 14,
    delete = 15,
    home = 16,
    end = 17,
    y = 18,
    page_up = 19,
    page_down = 20,
    _,
};

/// Modificadores como bitflags (bit 0=shift, 1=ctrl, 2=alt, 3=super).
pub const Modifiers = packed struct(u8) {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    super: bool = false,
    _reserved: u4 = 0,
};

/// Evento único de entrada ou janela.
pub const Event = union(enum) {
    mouse_move: extern struct { pos: types.Vec2 },
    mouse_button: extern struct {
        button: MouseButton,
        pressed: bool,
        pos: types.Vec2,
    },
    mouse_wheel: extern struct {
        dx: f32,
        dy: f32,
        pos: types.Vec2,
    },
    key: extern struct {
        key: Key,
        pressed: bool,
        modifiers: Modifiers,
    },
    text: extern struct {
        /// Codepoint Unicode como u32 (extern-compatível).
        /// Válido: 0..0x10FFFF exceto 0xD800..0xDFFF.
        codepoint: u32,
    },
    resize: extern struct { size: types.Size },
    focus: extern struct { gained: bool },
    quit,

    /// Valida invariantes do evento (para dados de adaptadores).
    /// Posições de mouse não-finitas são rejeitadas: NaN envenenaria
    /// `mouse_pos` retido e cálculos de widgets (ex.: drag do slider).
    pub fn isValid(self: Event) bool {
        switch (self) {
            .text => |t| {
                if (t.codepoint > 0x10FFFF) return false;
                if (t.codepoint >= 0xD800 and t.codepoint <= 0xDFFF) return false;
                return true;
            },
            .mouse_move => |m| {
                return std.math.isFinite(m.pos.x) and std.math.isFinite(m.pos.y);
            },
            .mouse_button => |b| {
                return std.math.isFinite(b.pos.x) and std.math.isFinite(b.pos.y);
            },
            .mouse_wheel => |w| {
                return std.math.isFinite(w.dx) and std.math.isFinite(w.dy) and
                    std.math.isFinite(w.pos.x) and std.math.isFinite(w.pos.y);
            },
            else => return true,
        }
    }
};

/// Fila de eventos do frame. Ownership: a fila detém o buffer;
/// o alocador continua do chamador. `clear` retém capacidade.
pub const EventQueue = struct {
    list: std.ArrayList(Event),

    const Self = @This();

    pub fn initEmpty() Self {
        return .{ .list = .empty };
    }

    pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
        self.list.deinit(gpa);
    }

    pub fn clearRetainingCapacity(self: *Self) void {
        self.list.clearRetainingCapacity();
    }

    pub fn len(self: *const Self) usize {
        return self.list.items.len;
    }

    pub fn items(self: *const Self) []const Event {
        return self.list.items;
    }

    /// Enfileira um evento já validado. Retorna `OutOfMemory` ou
    /// `InvalidEvent` se `!ev.isValid()`.
    pub fn push(self: *Self, gpa: std.mem.Allocator, ev: Event) !void {
        if (!ev.isValid()) return error.InvalidEvent;
        try self.list.append(gpa, ev);
    }
};

test "Event.isValid rejeita codepoint inválido" {
    const stdt = @import("std");
    const ok: Event = .{ .text = .{ .codepoint = 'A' } };
    try stdt.testing.expect(ok.isValid());
    const surrogate: Event = .{ .text = .{ .codepoint = 0xD800 } };
    try stdt.testing.expect(!surrogate.isValid());
    const too_big: Event = .{ .text = .{ .codepoint = 0x110000 } };
    try stdt.testing.expect(!too_big.isValid());
    const nan_wheel: Event = .{
        .mouse_wheel = .{ .dx = std.math.nan(f32), .dy = 0, .pos = .{} },
    };
    try stdt.testing.expect(!nan_wheel.isValid());
    const nan_move: Event = .{ .mouse_move = .{ .pos = types.Vec2.init(std.math.inf(f32), 0) } };
    try stdt.testing.expect(!nan_move.isValid());
    const nan_button: Event = .{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(0, std.math.nan(f32)) },
    };
    try stdt.testing.expect(!nan_button.isValid());
    const nan_wheel_pos: Event = .{
        .mouse_wheel = .{ .dx = 0, .dy = 1, .pos = types.Vec2.init(0, std.math.inf(f32)) },
    };
    try stdt.testing.expect(!nan_wheel_pos.isValid());
    const ok_move: Event = .{ .mouse_move = .{ .pos = types.Vec2.init(1, 2) } };
    try stdt.testing.expect(ok_move.isValid());
}

test "EventQueue push/clear retém capacidade" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var q = EventQueue.initEmpty();
    defer q.deinit(gpa);
    try q.push(gpa, .{ .mouse_move = .{ .pos = types.Vec2.init(1, 2) } });
    try q.push(gpa, .quit);
    try stdt.testing.expectEqual(@as(usize, 2), q.len());
    const cap = q.list.capacity;
    q.clearRetainingCapacity();
    try stdt.testing.expectEqual(@as(usize, 0), q.len());
    try stdt.testing.expect(q.list.capacity >= cap);
    try stdt.testing.expectError(error.InvalidEvent, q.push(gpa, .{
        .text = .{ .codepoint = 0x110000 },
    }));
}
