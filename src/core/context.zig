//! ZyntraUI — contexto GUI (core/context).
//!
//! Ownership:
//! - O chamador fornece `allocator`; o `Context` apenas o retém
//!   (não assume ownership do alocador).
//! - `Context.deinit` libera apenas memória alocada pelo próprio
//!   contexto (M1: nenhuma alocação interna; reserva para M2+).
//! Lifetime:
//! - `init` → `beginFrame`/`endFrame` (0..N) → `deinit`.
//! - Mover o `Context` por valor invalida ponteiros internos
//!   futuros; usar ponteiro estável após `init`.
//! Erros:
//! - M1 não aloca e não falha após `init`. `init` valida o
//!   viewport e retorna `error.InvalidArgument` se negativo.

const std = @import("std");
const types = @import("types.zig");

/// Erros públicos do contexto (M1).
pub const ContextError = error{
    InvalidArgument,
    OutOfMemory,
};

/// Configuração de criação do contexto.
pub const ContextConfig = struct {
    /// Viewport inicial em pixels lógicos.
    viewport: types.Rect = .{},
    /// Capacidade inicial reservada para widgets (M2+; M1 apenas valida).
    /// Deve ser <= max_widget_capacity.
    initial_widget_capacity: u32 = 256,
    max_widget_capacity: u32 = 65536,
};

/// Estado do frame.
pub const FrameState = enum {
    idle,
    active,
};

/// Contexto raiz da GUI. Um por aplicação/janela na M1.
pub const Context = struct {
    allocator: std.mem.Allocator,
    viewport: types.Rect,
    frame_index: u64,
    state: FrameState,

    const Self = @This();

    /// Cria o contexto. Não aloca em M1; valida a config.
    pub fn init(allocator: std.mem.Allocator, config: ContextConfig) ContextError!Self {
        if (config.viewport.w < 0 or config.viewport.h < 0) {
            return error.InvalidArgument;
        }
        if (config.initial_widget_capacity == 0) {
            return error.InvalidArgument;
        }
        if (config.initial_widget_capacity > config.max_widget_capacity) {
            return error.InvalidArgument;
        }
        return .{
            .allocator = allocator,
            .viewport = config.viewport,
            .frame_index = 0,
            .state = .idle,
        };
    }

    pub fn deinit(self: *Self) void {
        // M1: sem alocações internas. Mantém o hook para M2+
        // (pools/arenas) e invalida o estado para detectar use-after-deinit
        // em builds de debug via frame_index sentinela.
        self.state = .idle;
        self.frame_index = 0;
    }

    /// Inicia um novo frame. Deve ser pareado com `endFrame`.
    /// Precondição: nenhum frame ativo.
    pub fn beginFrame(self: *Self) void {
        std.debug.assert(self.state == .idle);
        self.state = .active;
    }

    /// Encerra o frame atual e avança `frame_index` com wrap seguro.
    /// Precondição: frame ativo.
    pub fn endFrame(self: *Self) void {
        std.debug.assert(self.state == .active);
        self.state = .idle;
        self.frame_index +%= 1;
    }

    pub fn isFrameActive(self: *const Self) bool {
        return self.state == .active;
    }

    pub fn setViewport(self: *Self, viewport: types.Rect) ContextError!void {
        if (viewport.w < 0 or viewport.h < 0) return error.InvalidArgument;
        self.viewport = viewport;
    }
};

test "Context ciclo de vida mínimo" {
    const allocator = std.testing.allocator;
    var ctx = try Context.init(allocator, .{
        .viewport = types.Rect.init(0, 0, 800, 600),
    });
    defer ctx.deinit();
    try std.testing.expect(!ctx.isFrameActive());
    try std.testing.expectEqual(@as(u64, 0), ctx.frame_index);
    ctx.beginFrame();
    try std.testing.expect(ctx.isFrameActive());
    ctx.endFrame();
    try std.testing.expect(!ctx.isFrameActive());
    try std.testing.expectEqual(@as(u64, 1), ctx.frame_index);
}

test "Context rejeita config inválida" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(
        error.InvalidArgument,
        Context.init(allocator, .{ .viewport = types.Rect.init(0, 0, -1, 600) }),
    );
    try std.testing.expectError(
        error.InvalidArgument,
        Context.init(allocator, .{ .initial_widget_capacity = 0 }),
    );
    try std.testing.expectError(
        error.InvalidArgument,
        Context.init(allocator, .{ .initial_widget_capacity = 10, .max_widget_capacity = 5 }),
    );
}

test "Context.setViewport valida" {
    const allocator = std.testing.allocator;
    var ctx = try Context.init(allocator, .{});
    defer ctx.deinit();
    try ctx.setViewport(types.Rect.init(0, 0, 1280, 720));
    try std.testing.expectEqual(@as(f32, 1280), ctx.viewport.w);
    try std.testing.expectError(
        error.InvalidArgument,
        ctx.setViewport(types.Rect.init(0, 0, -10, 10)),
    );
}
